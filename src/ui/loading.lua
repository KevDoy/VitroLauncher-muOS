-- Launch loading screen.
-- Fades in over the launcher after a title is picked; once it fully
-- covers the screen the actual launch runs (on device that quits the app
-- and the loading screen is the last frame shown before the game).
--
-- Two looks:
--   bg.png present  - the background art fades in while slowly zooming.
--   no bg.png       - the waves fade out to a flat wave-colored backdrop
--                     with the title's icon, name and a "Loading..." pulse.

local Platform = require("src.platform")
local Theme = require("src.ui.theme")
local Draw = require("src.ui.draw")

local Loading = {}

local FADE_IN = 1.1    -- seconds to full cover
local HOLD = 0.25      -- fully covered before launching (guarantees a frame)
local FADE_OUT = 0.5   -- desktop only: reveal the launcher again
local ZOOM = 0.14      -- total bg zoom over the fade

local state = nil -- { game, onLaunch, t, phase, bg, icon }

local function smoothstep(p)
    p = math.max(0, math.min(1, p))
    return p * p * (3 - 2 * p)
end

function Loading.isActive()
    return state ~= nil
end

-- onLaunch runs once the screen is fully covered. It should return the
-- Launcher.launch result: "quit" keeps the cover up (device), "ran"
-- fades back out (desktop), nil/false drops the cover immediately.
function Loading.start(game, onLaunch)
    state = {
        game = game,
        onLaunch = onLaunch,
        t = 0,
        phase = "in", -- "in" -> "hold" -> "out"
        bg = game.bgPath and Platform.loadImage(game.bgPath) or nil,
        icon = game.iconPath and Platform.loadImage(game.iconPath) or nil,
    }
end

function Loading.update(dt)
    if not state then return end
    state.t = state.t + dt

    if state.phase == "in" and state.t >= FADE_IN + HOLD then
        local result = state.onLaunch()
        if result == "ran" then
            state.phase = "out"
            state.t = 0
        elseif result == "quit" then
            state.phase = "hold" -- stay covered; the app is quitting
        else
            state = nil -- launch failed, reveal the launcher (and message)
        end
    elseif state.phase == "out" and state.t >= FADE_OUT then
        state = nil
    end
end

local function drawBg(w, h, alpha, zoom)
    love.graphics.setColor(0, 0, 0, alpha)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local img = state.bg
    local iw, ih = img:getDimensions()
    local scale = math.max(w / iw, h / ih) * zoom
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(img, w / 2, h / 2, 0, scale, scale, iw / 2, ih / 2)
end

local function drawGeneric(w, h, alpha, fontFor)
    local s = h / 480
    local r, g, b = Theme.getColor()

    -- Flat backdrop in the wave color, dimmed so the icon pops
    love.graphics.setColor(r * 0.30, g * 0.30, b * 0.30, alpha)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local cy = h * 0.44
    local iconSize = 96 * s

    if state.icon then
        local ix = w / 2 - iconSize / 2
        local iy = cy - iconSize / 2
        local radius = iconSize * 0.15
        love.graphics.stencil(function()
            love.graphics.rectangle("fill", ix, iy, iconSize, iconSize, radius, radius)
        end, "replace", 1)
        love.graphics.setStencilTest("greater", 0)
        local iw, ih = state.icon:getDimensions()
        local scale = math.max(iconSize / iw, iconSize / ih)
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.draw(state.icon,
            ix + (iconSize - iw * scale) / 2, iy + (iconSize - ih * scale) / 2,
            0, scale, scale)
        love.graphics.setStencilTest()
    end

    local nameFont = fontFor(22 * s)
    love.graphics.setFont(nameFont)
    Draw.printf(state.game.name, w * 0.1, cy + iconSize / 2 + 22 * s, w * 0.8,
        "center", { 1, 1, 1, alpha }, s)

    -- Pulsing "Loading..." so the screen reads as busy, not frozen
    local pulse = 0.55 + 0.45 * math.sin(state.t * 4)
    local hintFont = fontFor(15 * s)
    love.graphics.setFont(hintFont)
    Draw.printf("Loading...", 0, h - 56 * s, w, "center",
        { 1, 1, 1, alpha * pulse }, s)
end

function Loading.draw(w, h, fontFor)
    if not state then return end

    local alpha, progress
    if state.phase == "out" then
        alpha = 1 - smoothstep(state.t / FADE_OUT)
        progress = 1
    else
        progress = smoothstep(state.t / FADE_IN)
        alpha = progress
    end

    if state.bg then
        -- Zoom keeps creeping a little past full cover so the shot
        -- never feels like a freeze-frame
        local zoom = 1 + ZOOM * progress + 0.015 * math.max(0, state.t - FADE_IN)
        drawBg(w, h, alpha, zoom)
    else
        drawGeneric(w, h, alpha, fontFor)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return Loading
