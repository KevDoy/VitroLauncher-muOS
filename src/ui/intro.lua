-- Startup intro: fades the background in from black, then fades the UI
-- in on top, while the game cover/icon textures preload behind the fade
-- so the first scroll through the library doesn't drop frames.
-- The preload keeps running (with a smaller time budget) even when the
-- fade is disabled or already finished.

local Platform = require("src.platform")

local Intro = {}

local BG_FADE = 0.6  -- seconds: black -> background
local UI_FADE = 0.45 -- seconds: UI fade-in after the background is up

local phase = "done" -- "bg" -> "ui" -> "done"
local t = 0
local canvas = nil
local canvasOk = true
local uiHeld = false -- true while the startup library scan is running

-- Preload queue: { path = ..., cache = <lazy-load cache to fill> }
local queue = nil
local qi = 1
local loaded = {} -- path -> Image/false, shared when caches want the same file

function Intro.start(fade)
    phase = fade and "bg" or "done"
    t = 0
end

function Intro.isActive()
    return phase ~= "done" or uiHeld
end

-- Holds the UI back while the startup library scan is still running:
-- the background (waves) shows and animates, but the UI fade doesn't
-- start until the scan delivers the game list. Works with the fade
-- disabled too - the UI simply appears once the scan finishes.
function Intro.setUIHeld(held)
    uiHeld = held and true or false
end

-- true while the UI must not be drawn at all (background fade phase,
-- or the library scan hasn't finished yet)
function Intro.hideUI()
    return uiHeld or phase == "bg"
end

-- Queues covers/icons into the carousel/grid image caches (ImageCache
-- instances), so their lazy loaders find them already loaded. Callers
-- pass only the titles that will be visible soon (the Last Played row,
-- the first grid pages) - everything else lazy-loads on scroll, and the
-- caches evict old textures instead of growing with the library.
function Intro.preload(carouselGames, carouselCache, gridGames, gridCache)
    queue, qi, loaded = {}, 1, {}
    local queued = {}
    local function add(path, cache)
        if not path then return end
        local key = tostring(cache) .. path
        if queued[key] then return end
        queued[key] = true
        table.insert(queue, { path = path, cache = cache })
    end
    for _, g in ipairs(carouselGames) do
        add(g.imgPath, carouselCache)
    end
    for _, g in ipairs(gridGames) do
        add(g.iconPath or g.imgPath, gridCache)
    end
end

local function smoothstep(x)
    x = math.max(0, math.min(1, x))
    return x * x * (3 - 2 * x)
end

function Intro.update(dt)
    if phase == "bg" then
        t = t + dt
        -- The UI fade waits for the library scan; the background stays
        -- fully faded in (the black overlay's alpha bottoms out at 0)
        if t >= BG_FADE and not uiHeld then phase, t = "ui", 0 end
    elseif phase == "ui" then
        t = t + dt
        if t >= UI_FADE then
            phase, t = "done", 0
            canvas = nil
        end
    end

    if not queue then return end
    -- Time-budgeted loading: generous while the fade hides the cost,
    -- gentle afterwards so a long tail can't cause visible hitches.
    local budget = Intro.isActive() and 0.010 or 0.004
    local start = love.timer.getTime()
    repeat
        local item = queue[qi]
        if not item then
            queue = nil
            print("[Intro] Image preload complete")
            return
        end
        qi = qi + 1
        if not item.cache:has(item.path) then
            if loaded[item.path] == nil then
                loaded[item.path] = Platform.loadImage(item.path) or false
            end
            item.cache:put(item.path, loaded[item.path])
        end
    until love.timer.getTime() - start >= budget
end

-- During the UI fade the interface is drawn into an offscreen canvas
-- and composited with the fade alpha (fading every element in place
-- would mean threading an alpha through every UI module). Returns false
-- when no redirection happened (not fading, or canvases unsupported).
function Intro.beginUI(w, h)
    if phase ~= "ui" or not canvasOk then return false end
    if not canvas or canvas:getWidth() ~= w or canvas:getHeight() ~= h then
        local ok, c = pcall(love.graphics.newCanvas, w, h)
        if not ok then
            canvasOk = false -- fall back to popping the UI in
            print("[Intro] Canvas unavailable, skipping UI fade")
            return false
        end
        canvas = c
    end
    love.graphics.setCanvas({ canvas, stencil = true })
    love.graphics.clear(0, 0, 0, 0)
    return true
end

function Intro.endUI()
    if phase ~= "ui" or not canvas then return end
    love.graphics.setCanvas()
    local a = smoothstep(t / UI_FADE)
    -- Canvas contents are premultiplied; scaling all four channels by
    -- the fade alpha keeps translucent edges free of dark fringes.
    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.setColor(a, a, a, a)
    love.graphics.draw(canvas)
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
end

-- Black overlay while the background fades in from black
function Intro.drawOverlay(w, h)
    if phase ~= "bg" then return end
    love.graphics.setColor(0, 0, 0, 1 - smoothstep(t / BG_FADE))
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1, 1)
end

return Intro
