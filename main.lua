-- Vitro Launcher for muOS
-- Horizontally scrolling carousel of game tiles. Most recently played
-- title is always first. Launches games via RetroArch (or PortMaster
-- .sh scripts) and returns here when they exit.

local Platform = require("src.platform")
local Logger = require("src.utils.logger")
local Config = require("src.config")
local Library = require("src.library")
local State = require("src.state")
local Stats = require("src.stats")
local Launcher = require("src.launcher")
local Battery = require("src.battery")
local StatusBar = require("src.ui.statusbar")
local Carousel = require("src.ui.carousel")
local Grid = require("src.ui.grid")
local NavPill = require("src.ui.navpill")
local Theme = require("src.ui.theme")
local Draw = require("src.ui.draw")
local Blur = require("src.ui.blur")
local Settings = require("src.ui.settings")
local Loading = require("src.ui.loading")
local Intro = require("src.ui.intro")

local carousel
local grid
local allGames = {}
local scanStep = nil      -- incremental startup scan (Library.startScan)
local message = nil       -- { text, until }
local ignoreInputUntil = 0

-- Screens: "recent" (Last Played carousel), "all" (All Titles grid),
-- "settings". L1/R1 move between them; SELECT toggles Settings.
local SCREEN_ORDER = { "recent", "all", "settings" }
local screen = "recent"
local contentScreen = "recent" -- last non-settings screen (for backing out)

-- Auto-hide for the bottom nav pill (Settings: No / 3s / 5s / 10s).
-- The pill only reappears when the user switches screens - regular
-- button presses keep it hidden.
local NAV_FADE_TIME = 0.35
-- Switching screens can stall the device for a frame or two (library
-- resort, texture loads). Holding the fade-in briefly lets it start
-- after the stall, so the pill actually fades instead of popping in.
local NAV_REVEAL_DELAY = 0.15
local navAlpha = 1
local navShownAt = 0

-- Input arrives from two possible sources on device: gptokeyb (synthetic
-- keyboard events) and the native SDL gamepad. Either may be dead depending
-- on the muOS build, so we listen to both and de-duplicate by action.
local Input = {
    held = {},        -- merged held state, e.g. held["start"], held["gp_a"]
    lastFire = {},    -- action -> time it last fired (for de-dup)
    repeatDir = nil,  -- gamepad dpad held direction (manual auto-repeat)
    repeatStart = 0,
    lastRepeat = 0,
}
local ACTION_COOLDOWN = 0.12   -- collapses duplicates from the two sources
local REPEAT_DELAY = 0.35
local REPEAT_INTERVAL = 0.15

-- Hold L1 + X + START this long to leave the launcher and land on the
-- muOS home screen (see exitToMuos below).
local EXIT_COMBO_HOLD = 2.0
local exitComboStart = nil

local act -- forward declaration (defined in the input section below)

-- Order for the All Titles grid: A-Z, recent-first or most-played-first,
-- with bookmarked titles optionally pulled to the front (Settings options).
local function sortAllTitles(games)
    local list = {}
    for _, g in ipairs(games) do table.insert(list, g) end
    if Config.values.all_sort == "recent" then
        State.sortGames(list)
    elseif Config.values.all_sort == "playtime" then
        table.sort(list, function(a, b)
            local pa, pb = a.playSeconds or 0, b.playSeconds or 0
            if pa ~= pb then return pa > pb end
            return a.name:lower() < b.name:lower()
        end)
    else
        table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    end
    if Config.values.all_bookmarks ~= "sorted" then
        local marked, rest = {}, {}
        for _, g in ipairs(list) do
            table.insert(State.isBookmarked(g.id) and marked or rest, g)
        end
        for _, g in ipairs(rest) do table.insert(marked, g) end
        list = marked
    end
    return list
end

-- Last Played list: recent-first, capped by the Recent Limit setting
local function recentGames()
    local recent = {}
    for _, g in ipairs(allGames) do table.insert(recent, g) end
    State.sortGames(recent)
    local limit = tonumber(Config.values.recent_limit) or 12
    while #recent > limit do table.remove(recent) end
    return recent
end

local function applyLibrary(games, selectFirst)
    allGames = games
    carousel:setGames(recentGames())
    if selectFirst then
        carousel.selected = 1
    end
    grid:setGames(sortAllTitles(allGames))
    print("[Main] Loaded " .. #allGames .. " game(s)")
end

-- Synchronous rescan (desktop R key, after a local game run). Startup
-- uses the incremental scan below instead.
local function refreshLibrary(selectFirst)
    applyLibrary(Library.scan(), selectFirst)
end

-- Preload only the textures that will be visible right away: the Last
-- Played row plus the first grid pages. Everything else lazy-loads on
-- scroll, and the caches evict old textures (src/ui/imagecache.lua),
-- so memory no longer grows with the library size.
local GRID_PRELOAD = 24
local function preloadVisible()
    local gridGames = {}
    for i = 1, math.min(GRID_PRELOAD, #grid.games) do
        gridGames[i] = grid.games[i]
    end
    Intro.preload(carousel.games, carousel.images, gridGames, grid.images)
end

local function setScreen(name)
    if name == screen then return end
    screen = name
    navShownAt = love.timer.getTime() -- bring the auto-hidden nav back
    if name ~= "settings" then contentScreen = name end
    -- Re-apply sorting/limits when entering a screen so Settings changes
    -- take effect (the order stays stable while you're on the screen).
    if name == "all" then
        grid:setGames(sortAllTitles(allGames))
    elseif name == "recent" then
        carousel:setGames(recentGames())
    end
    print("[Main] Screen -> " .. name)
end

local function showMessage(text, duration)
    message = { text = text, expires = love.timer.getTime() + (duration or 2) }
end

-- ---------------------------------------------------------------------
-- Exit to the muOS home screen (L1 + X + START held 2 seconds).
-- Quitting without picking a game breaks the loop in mux_launch.sh and
-- returns to the muOS menu. The /tmp/gamelauncher_off flag is only
-- there for devices still carrying the legacy frontend.sh patch from
-- older versions of this project (then named Game Launcher) - it
-- tells that patch to step aside, so it keeps the old name.
-- ---------------------------------------------------------------------

-- Each physical button can arrive under several names depending on the
-- input path: gptokeyb keyboard events (see vitrolauncher.gptk) or native
-- SDL gamepad events.
local function exitComboHeld()
    local l1 = Input.held["pageup"] or Input.held["l1"] or Input.held["gp_leftshoulder"]
    local x = Input.held["x"] or Input.held["gp_x"]
    local start = Input.held["home"] or Input.held["start"] or Input.held["gp_start"]
    return l1 and x and start
end

local function exitToMuos()
    print("[Input] L1+X+START held - exiting to muOS home screen")
    if Platform.isDevice then
        Platform.writeFile("/tmp/gamelauncher_off", "1\n")
    end
    love.event.quit()
end

-- Shut Down button. On device: write runtime/power_off and quit; the
-- loop in mux_launch.sh sees the flag and powers the device off via
-- muOS's own quit script.
local function shutdownDevice()
    if not Platform.isDevice then
        showMessage("Shutdown (simulated on desktop)", 2)
        return
    end
    print("[Main] Shut Down held - powering off")
    Platform.writeFile(Platform.appDir() .. "/runtime/power_off", "1\n")
    love.event.quit()
end

-- Hold-to-shut-down: keeping A pressed on the power button fades the
-- screen to black over SHUTDOWN_HOLD seconds. Fully black = power off.
-- Releasing early fades back in quickly.
local SHUTDOWN_HOLD = 2.0
local SHUTDOWN_FADE_BACK = 0.4
local shutdownFade = 0        -- black overlay alpha (0..1)
local shutdownTriggered = false

-- The hold that arms the shutdown fade: the device's physical power
-- button or the menu/guide button. SDL reports the power key as "power"
-- and the menu button as either the "menu" key or the gamepad "guide"
-- button, depending on the input path. If holding a button does nothing
-- on a device, check debug.log for what it actually sends (every key
-- and gamepad press is logged) and add it here.
local function shutdownHeld()
    return (Input.held["power"] or Input.held["menu"] or Input.held["gp_guide"])
        and true or false
end

local function updateShutdownFade(dt)
    if shutdownHeld() and not shutdownTriggered then
        shutdownFade = math.min(1, shutdownFade + dt / SHUTDOWN_HOLD)
        if shutdownFade >= 1 then
            -- Latch until release so a simulated (desktop) shutdown
            -- doesn't immediately restart the fade.
            shutdownTriggered = true
            shutdownDevice()
        end
    else
        shutdownFade = math.max(0, shutdownFade - dt / SHUTDOWN_FADE_BACK)
        if not shutdownHeld() then shutdownTriggered = false end
    end
end

function love.load(args)
    Logger.init(Platform.appDir())

    -- Optional size argument for local testing, e.g. `love . 720x480`
    for _, a in ipairs(args or {}) do
        local w, h = a:match("^(%d+)x(%d+)$")
        if w then love.window.setMode(tonumber(w), tonumber(h), { resizable = true }) end
    end

    love.graphics.setBackgroundColor(0, 0, 0)
    love.graphics.setDefaultFilter("linear", "linear")
    love.keyboard.setKeyRepeat(true)

    Config.load()
    State.load()
    -- Close the play session left open by the game we just returned from
    Stats.finishOpenSession()
    Theme.setColor(Config.values.wave_color)
    Theme.set(Config.values.theme)

    carousel = Carousel.new()
    grid = Grid.new()

    screen = (Config.values.default_screen == "all") and "all" or "recent"
    contentScreen = screen

    -- The library scan runs incrementally across the first frames (see
    -- love.update), so a large library on slow storage can't freeze the
    -- intro: the waves animate from the first frame, and the UI fades
    -- in once the scan has delivered the game list.
    scanStep = Library.startScan()
    Intro.start(Config.values.startup_fade ~= false)
    Intro.setUIHeld(true)

    -- Log input devices so debug.log shows what we can hear
    local joysticks = love.joystick.getJoysticks()
    print("[Input] Joysticks detected: " .. #joysticks)
    for i, js in ipairs(joysticks) do
        print(string.format("[Input]   %d: %s (gamepad: %s, buttons: %d)",
            i, js:getName(), tostring(js:isGamepad()), js:getButtonCount()))
    end
    print("[Main] Ready")
end

-- Crashes land in debug.log with a traceback, then show the standard
-- Love2D error screen (B/escape exits it on device via gptokeyb).
local defaultErrorHandler = love.errorhandler or love.errhand
function love.errorhandler(msg)
    Logger.logError(msg)
    return defaultErrorHandler(msg)
end

-- Debug: GL_SCREENSHOT=/path/out.png captures a frame ~1.5s in, then quits.
-- GL_AUTOKEYS="right,right,a" simulates key presses at 0.4s intervals first;
-- "hold:a" presses without releasing (for hold-to-confirm testing).
local screenshotPath = os.getenv("GL_SCREENSHOT")
local screenshotDone = false
local autoKeys = {}
local autoKeyIndex = 1
for k in (os.getenv("GL_AUTOKEYS") or ""):gmatch("[^,]+") do
    table.insert(autoKeys, k)
end
-- GL_SCREENSHOT_AT overrides the capture time (e.g. to catch the
-- startup fade mid-animation).
local screenshotAt = tonumber(os.getenv("GL_SCREENSHOT_AT")) or (1.5 + #autoKeys * 0.4)

function love.update(dt)
    -- Incremental startup scan: a slice of folders per frame, then the
    -- UI (held back by Intro) gets the finished list and fades in.
    if scanStep then
        local games = scanStep()
        if games then
            scanStep = nil
            applyLibrary(games, true)
            preloadVisible()
            Intro.setUIHeld(false)
        end
    end

    Theme.set(Config.values.theme) -- cheap sync so the Settings row applies live
    Theme.update(dt)
    Intro.update(dt)
    -- Cheap sync so the Settings toggles apply immediately
    carousel.infinite = Config.values.infinite_scroll and true or false
    -- "default" is a legacy alias for medium; anything unknown gets the
    -- large (default) scale
    carousel.sizeScale = ({ small = 0.75, medium = 1, default = 1 })[Config.values.cover_size] or 1.2
    carousel.aspect = (Config.values.cover_aspect == "1:1") and 1 or (2 / 3)
    carousel.rounded = Config.values.rounded_corners and true or false
    carousel.showTitles = Config.values.show_titles and true or false
    carousel.showPlaytime = Config.values.show_playtime and true or false
    grid.sizeMode = Config.values.all_icon_size or "large"
    carousel:update(dt)
    grid:update(dt)
    Battery.update(dt)
    Loading.update(dt)
    updateShutdownFade(dt)

    local hideAfter = tonumber(Config.values.nav_autohide) or 0
    local now = love.timer.getTime()
    local navTarget = 1
    if hideAfter > 0 and now - navShownAt > hideAfter then
        navTarget = 0
    end
    -- Clamp dt for UI animations: the frame that switches screens can
    -- take long enough on device that a raw dt would complete the whole
    -- fade/slide in one step.
    local uiDt = math.min(dt, 1 / 30)
    if navAlpha < navTarget and now - navShownAt < NAV_REVEAL_DELAY then
        -- hold; the fade-in starts once the new screen has settled
    elseif navAlpha < navTarget then
        navAlpha = math.min(navTarget, navAlpha + uiDt / NAV_FADE_TIME)
    elseif navAlpha > navTarget then
        navAlpha = math.max(navTarget, navAlpha - uiDt / NAV_FADE_TIME)
    end
    NavPill.update(uiDt, screen)
    if message and love.timer.getTime() > message.expires then
        message = nil
    end

    if exitComboHeld() then
        exitComboStart = exitComboStart or love.timer.getTime()
        if love.timer.getTime() - exitComboStart >= EXIT_COMBO_HOLD then
            exitComboStart = nil
            exitToMuos()
        end
    else
        exitComboStart = nil
    end

    -- Manual auto-repeat for held gamepad dpad (keyboard repeat is native)
    if Input.repeatDir then
        local now = love.timer.getTime()
        if now - Input.repeatStart > REPEAT_DELAY and
            now - Input.lastRepeat > REPEAT_INTERVAL then
            Input.lastRepeat = now
            act(Input.repeatDir, true)
        end
    end

    if autoKeys[autoKeyIndex] and love.timer.getTime() > 0.5 + autoKeyIndex * 0.4 then
        local k = autoKeys[autoKeyIndex]
        autoKeyIndex = autoKeyIndex + 1
        local hold = k:match("^hold:(.+)$")
        love.keypressed(hold or k, hold or k, false)
        if not hold then love.keyreleased(k) end
    end

    if screenshotPath and not screenshotDone and love.timer.getTime() > screenshotAt then
        screenshotDone = true
        love.graphics.captureScreenshot(function(imageData)
            local fileData = imageData:encode("png")
            local dir = screenshotPath:match("^(.*)/[^/]+$")
            if dir then Platform.mkdir(dir) end
            Platform.writeFile(screenshotPath, fileData:getString())
            love.event.quit()
        end)
    end
end

function love.draw()
    local w, h = love.graphics.getDimensions()

    -- Glass Blur: render the scene into an offscreen canvas so the
    -- pills can sample a blurred copy of what's behind them. When
    -- transparency is off (or canvases are unavailable) this is a no-op
    -- and everything draws straight to the screen.
    Draw.setTransparency(Config.values.transparency ~= false)
    -- Blur stays off during the startup intro: the UI fades in through
    -- its own canvas there, which the blur pipeline can't sample.
    Blur.setEnabled(Draw.isTransparent() and not Intro.isActive())
    Blur.begin(w, h)

    Theme.draw(w, h)

    -- Readability overlay over the animated background: dark schemes
    -- get a black wash, light schemes a white one (the text is dark).
    if Draw.isLight() then
        love.graphics.setColor(1, 1, 1, 0.25)
    else
        love.graphics.setColor(0, 0, 0, 0.25)
    end
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1, 1)

    local s = h / 480

    -- Startup intro phase 1 hides the UI entirely (background fades in
    -- from black first); phase 2 redirects it into a canvas that gets
    -- composited with the fade alpha.
    if not Intro.hideUI() then
        Intro.beginUI(w, h)

        if screen == "recent" then
            carousel:draw(w, h)
        elseif screen == "all" then
            grid:draw(w, h, {
                showPlaytime = Config.values.show_playtime,
                tooltips = Config.values.tooltips,
                buttonLayout = Config.values.button_layout,
            })
        else
            -- Settings draws glass mid-scene (the row highlight), so its
            -- blur backdrop must be captured now - before rows and text -
            -- or the pill would show a blurred ghost of its own label.
            Blur.snapshot()
            Settings.draw(w, h)
        end

        -- Composite the scene to the screen and refresh the blur copy;
        -- the pills below sample this frame's blurred backdrop.
        Blur.finish()

        -- Status pill (time + battery), equal top and right margins
        local statusMargin = 12 * s
        StatusBar.draw(carousel:fontFor(16 * s), w - statusMargin, statusMargin, s)

        NavPill.draw(w, h, s, screen, Config.values.tooltips, navAlpha)

        Intro.endUI()
    else
        Blur.finish()
    end

    Intro.drawOverlay(w, h)

    Loading.draw(w, h, function(px) return carousel:fontFor(px) end)

    if message then
        local s = h / 480
        local font = carousel:fontFor(18 * s)
        love.graphics.setFont(font)
        love.graphics.setColor(0, 0, 0, 0.75)
        local th = font:getHeight() + 20 * s
        love.graphics.rectangle("fill", 0, h - th, w, th)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(message.text, 0, h - th + 10 * s, w, "center")
    end

    -- Exit-combo hold progress (L1+X+START)
    if exitComboStart then
        local s = h / 480
        local progress = math.min(
            (love.timer.getTime() - exitComboStart) / EXIT_COMBO_HOLD, 1)
        local font = carousel:fontFor(18 * s)
        love.graphics.setFont(font)
        local th = font:getHeight() + 34 * s
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.rectangle("fill", 0, h - th, w, th)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("Keep holding to exit to muOS...", 0, h - th + 8 * s, w, "center")
        local bw, bh = w * 0.5, 6 * s
        local bx, by = (w - bw) / 2, h - 12 * s
        love.graphics.setColor(1, 1, 1, 0.25)
        love.graphics.rectangle("fill", bx, by, bw, bh, bh / 2)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", bx, by, bw * progress, bh, bh / 2)
    end

    -- Shutdown fade: black overlay on top of everything
    if shutdownFade > 0 then
        love.graphics.setColor(0, 0, 0, shutdownFade)
        love.graphics.rectangle("fill", 0, 0, w, h)
    end
end

local function launchGame(game)
    if not game then return end

    -- The loading screen fades in first; the launch itself runs once the
    -- screen is fully covered (see src/ui/loading.lua).
    Loading.start(game, function()
        local result, err = Launcher.launch(game)
        if not result then
            showMessage(err or "Failed to launch", 3)
        elseif result == "ran" then
            -- Local (macOS) run finished or was simulated: the played game
            -- moves to the front, mirroring what happens on device relaunch.
            refreshLibrary(true)
            ignoreInputUntil = love.timer.getTime() + 0.4
        end
        return result
    end)
end

-- ---------------------------------------------------------------------
-- Unified input: keyboard events (gptokeyb / desktop) and native SDL
-- gamepad events both funnel into act(). A short cooldown per action
-- prevents double-firing when both sources deliver the same press.
-- ---------------------------------------------------------------------

function act(action, allowRepeat)
    local now = love.timer.getTime()
    if now < ignoreInputUntil then return end
    if not allowRepeat then
        local last = Input.lastFire[action]
        if last and now - last < ACTION_COOLDOWN then return end
    end
    Input.lastFire[action] = now

    -- No input while the loading screen is covering a launch
    if Loading.isActive() then return end

    -- Global actions: screen switching and settings
    if action == "prevscreen" or action == "nextscreen" then
        local i
        for j, name in ipairs(SCREEN_ORDER) do
            if name == screen then i = j end
        end
        local target = SCREEN_ORDER[i + (action == "nextscreen" and 1 or -1)]
        if target then setScreen(target) end
        return
    elseif action == "settings" then
        -- SELECT toggles Settings and back
        setScreen(screen == "settings" and contentScreen or "settings")
        return
    end

    if screen == "settings" then
        if Settings.handle(action) then return end
        if action == "back" then setScreen(contentScreen) end
    elseif screen == "all" then
        if action == "left" then
            grid:move(-1, 0)
        elseif action == "right" then
            grid:move(1, 0)
        elseif action == "up" then
            grid:move(0, -1)
        elseif action == "down" then
            grid:move(0, 1)
        elseif action == "launch" then
            launchGame(grid:selectedGame())
        elseif action == "skip" then
            grid:skipPage()
        elseif action == "bookmark" then
            grid:toggleBookmark()
        end
    else -- recent
        if action == "left" then
            carousel:move(-1)
        elseif action == "right" then
            carousel:move(1)
        elseif action == "launch" then
            launchGame(carousel:selectedGame())
        end
    end
end

-- Keyboard (gptokeyb on device, real keyboard on desktop)

function love.keypressed(key, scancode, isrepeat)
    if not isrepeat then
        -- Log every key so debug.log reveals what unusual buttons send
        -- (e.g. the physical power button on different devices).
        print("[Input] key: " .. key .. " (scancode: " .. tostring(scancode) .. ")")
        Input.held[key] = true
    end

    if key == "left" then
        act("left", isrepeat)
    elseif key == "right" then
        act("right", isrepeat)
    elseif key == "down" then
        act("down", isrepeat)
    elseif key == "up" then
        act("up", isrepeat)
    elseif (key == "a" or key == "return") and not isrepeat then
        act("launch")
    elseif key == "b" and not isrepeat then
        act("back")
    elseif key == "x" and not isrepeat then
        act("skip")
    elseif key == "y" and not isrepeat then
        act("bookmark")
    elseif (key == "pageup" or key == "[" or key == "9") and not isrepeat then
        -- L1 arrives as "pageup" via gptokeyb; "[" / "9" are desktop aliases
        act("prevscreen")
    elseif (key == "pagedown" or key == "]" or key == "0") and not isrepeat then
        -- R1 arrives as "pagedown"; "]" / "0" are desktop aliases
        act("nextscreen")
    elseif (key == "end" or key == "s") and not isrepeat then
        -- SELECT arrives as "end" via gptokeyb; "s" is the desktop alias
        act("settings")
    elseif key == "escape" and Platform.isMac then
        love.event.quit()
    elseif key == "r" and Platform.isMac and not isrepeat then
        refreshLibrary(false)
        showMessage("Library reloaded", 1)
    elseif key == "1" and Platform.isMac then
        love.window.setMode(640, 480, { resizable = true })
    elseif key == "2" and Platform.isMac then
        love.window.setMode(720, 480, { resizable = true })
    end
end

function love.keyreleased(key)
    Input.held[key] = nil
end

-- Native SDL gamepad (works even when gptokeyb isn't running)

function love.gamepadpressed(joystick, button)
    print("[Input] gamepad: " .. button)
    Input.held["gp_" .. button] = true

    if button == "dpleft" then
        Input.repeatDir, Input.repeatStart = "left", love.timer.getTime()
        act("left")
    elseif button == "dpright" then
        Input.repeatDir, Input.repeatStart = "right", love.timer.getTime()
        act("right")
    elseif button == "dpdown" then
        Input.repeatDir, Input.repeatStart = "down", love.timer.getTime()
        act("down")
    elseif button == "dpup" then
        Input.repeatDir, Input.repeatStart = "up", love.timer.getTime()
        act("up")
    elseif button == "a" then
        act("launch")
    elseif button == "b" then
        act("back")
    elseif button == "x" then
        act("skip")
    elseif button == "y" then
        act("bookmark")
    elseif button == "leftshoulder" then
        act("prevscreen")
    elseif button == "rightshoulder" then
        act("nextscreen")
    elseif button == "back" then -- SELECT on the native SDL gamepad path
        act("settings")
    end
end

function love.gamepadreleased(joystick, button)
    Input.held["gp_" .. button] = nil
    if (button == "dpleft" and Input.repeatDir == "left") or
        (button == "dpright" and Input.repeatDir == "right") or
        (button == "dpdown" and Input.repeatDir == "down") or
        (button == "dpup" and Input.repeatDir == "up") then
        Input.repeatDir = nil
    end
end

-- Raw joystick fallback for pads without a gamepad mapping: hat = dpad.

function love.joystickhat(joystick, hat, direction)
    if joystick:isGamepad() then return end
    print("[Input] hat: " .. direction)
    if direction == "l" then
        Input.repeatDir, Input.repeatStart = "left", love.timer.getTime()
        act("left")
    elseif direction == "r" then
        Input.repeatDir, Input.repeatStart = "right", love.timer.getTime()
        act("right")
    elseif direction == "d" then
        Input.repeatDir, Input.repeatStart = "down", love.timer.getTime()
        act("down")
    elseif direction == "u" then
        Input.repeatDir, Input.repeatStart = "up", love.timer.getTime()
        act("up")
    elseif direction == "c" then
        Input.repeatDir = nil
    end
end

function love.joystickpressed(joystick, button)
    if joystick:isGamepad() then return end
    -- Button indices vary by device; log them so debug.log reveals the
    -- mapping if we ever need a per-device override.
    print("[Input] raw joystick button: " .. button)
end
