-- Bottom navigation pill: Last Played / All Titles / Settings icons on a
-- glass background. The active screen's icon sits on a second, smaller
-- glass pill. L1/R1 glyphs flank the pill as tooltips (hidden when the
-- Tooltips setting is No).

local Glass = require("src.ui.glass")
local Icons = require("src.ui.icons")
local Draw = require("src.ui.draw")

local NavPill = {}

NavPill.SCREENS = { "recent", "all", "settings" }

local ICONS = {
    recent = "icons/lastplayed",
    all = "icons/allTitles",
    settings = "icons/settings",
}

-- The active-item bubble slides between slots instead of jumping.
-- The slide is held briefly after a screen switch so the (possibly
-- laggy) switch frame doesn't swallow the start of the animation.
local SLIDE_DELAY = 0.15
local SLIDE_SPEED = 12 -- exponential smoothing rate (higher = snappier)

local pos = nil    -- animated slot position (1..#SCREENS, fractional)
local target = 1
local movedAt = -1

local function slotIndex(name)
    for i, n in ipairs(NavPill.SCREENS) do
        if n == name then return i end
    end
    return 1
end

-- Call once per frame with a clamped dt (see main.lua).
function NavPill.update(dt, currentScreen)
    local i = slotIndex(currentScreen)
    if pos == nil then -- first frame: snap to the starting screen
        pos = i
        target = i
    end
    if i ~= target then
        target = i
        movedAt = love.timer.getTime()
    end
    if pos == target then return end
    if movedAt >= 0 and love.timer.getTime() - movedAt < SLIDE_DELAY then return end

    -- Ease-out: move a fixed fraction of the remaining distance each frame
    local step = (target - pos) * math.min(1, dt * SLIDE_SPEED)
    pos = pos + step
    if math.abs(target - pos) < 0.005 then pos = target end
end

-- alpha (0..1) drives the auto-hide fade; nil means fully visible.
function NavPill.draw(w, h, s, currentScreen, tooltips, alpha)
    alpha = alpha or 1
    if alpha <= 0.01 then return end
    -- Metrics traced from the mockup (multiply by 0.625 for 480p)
    local pillH = 54 * s
    local iconSize = 27 * s
    local innerH = 46 * s         -- active-item bubble
    local innerW = 70 * s
    -- The bubble fills its slot, and the pill's side padding equals the
    -- bubble's top/bottom gap, so the margin around an edge bubble is
    -- uniform on all sides.
    local slotW = innerW
    local padX = (pillH - innerH) / 2
    local pillW = padX * 2 + slotW * #NavPill.SCREENS
    local px = (w - pillW) / 2
    local py = h - 18 * s - pillH
    local cy = py + pillH / 2

    Glass.draw(px, py, pillW, pillH, s, alpha)

    -- Active-item bubble at its animated (possibly mid-slide) position
    local bubbleCx = px + padX + slotW * ((pos or slotIndex(currentScreen)) - 0.5)
    Glass.draw(bubbleCx - innerW / 2, cy - innerH / 2, innerW, innerH, s, alpha)

    for i, name in ipairs(NavPill.SCREENS) do
        local slotCx = px + padX + slotW * (i - 0.5)
        local active = (name == currentScreen)

        local img = Icons.get(ICONS[name])
        if img then
            local iw, ih = img:getDimensions()
            local scale = iconSize / math.max(iw, ih)
            Draw.setFG((active and 1 or 0.55) * alpha)
            love.graphics.draw(img, slotCx - iw * scale / 2, cy - ih * scale / 2, 0, scale, scale)
        end
    end

    -- L1 / R1 tooltips beside the pill
    if tooltips then
        local glyphH = 22 * s
        local gap = 12 * s
        local l1 = Icons.get("buttons/button_L1")
        local r1 = Icons.get("buttons/button_R1")
        if l1 then
            local gw = glyphH / l1:getHeight() * l1:getWidth()
            Icons.drawAtHeight(l1, px - gap - gw, cy, glyphH, 0.7 * alpha)
        end
        if r1 then
            Icons.drawAtHeight(r1, px + pillW + gap, cy, glyphH, 0.7 * alpha)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return NavPill
