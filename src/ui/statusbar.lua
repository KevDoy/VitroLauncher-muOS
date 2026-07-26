-- Top-right status pill: current time + battery, on a stretchable glass
-- background (src/ui/glass.lua). The pill sizes itself to its contents,
-- so more info can be added later without touching the artwork.

local Battery = require("src.battery")
local Glass = require("src.ui.glass")
local Draw = require("src.ui.draw")

local StatusBar = {}

-- "11:44 PM" style, without a leading zero on the hour
local function timeText()
    local t = os.date("*t")
    local hour = t.hour % 12
    if hour == 0 then hour = 12 end
    return string.format("%d:%02d %s", hour, t.min, t.hour < 12 and "AM" or "PM")
end

local function drawBatteryContent(font, x, cy, s)
    local iconW, iconH = 26 * s, 13 * s
    local capW = 2.5 * s
    local pad = 6 * s
    local text = math.floor(Battery.level) .. "%"
    local textW = font:getWidth(text)

    Draw.print(text, x, cy - font:getHeight() / 2, Draw.fg(0.85), s)

    local bx = x + textW + pad
    local by = cy - iconH / 2
    local r = 3 * s
    local o = math.max(1, 1.5 * s)
    love.graphics.setLineWidth(1.5 * s)

    -- Icon drop shadow (outline + nub, offset)
    love.graphics.setColor(0, 0, 0, Draw.isLight() and 0.12 or 0.45)
    love.graphics.rectangle("line", bx + o, by + o, iconW, iconH, r, r)
    love.graphics.rectangle("fill", bx + iconW + 1 * s + o, cy - 3 * s + o, capW, 6 * s, 1 * s, 1 * s)

    -- Battery outline + cap nub
    Draw.setFG(0.85)
    love.graphics.rectangle("line", bx, by, iconW, iconH, r, r)
    love.graphics.rectangle("fill", bx + iconW + 1 * s, cy - 3 * s, capW, 6 * s, 1 * s, 1 * s)

    -- Fill level
    local inset = 2.5 * s
    local fillW = (iconW - inset * 2) * math.max(0, math.min(1, Battery.level / 100))
    if Battery.charging then
        love.graphics.setColor(0.35, 0.85, 0.35, 0.95)
    elseif Battery.level <= 20 then
        love.graphics.setColor(0.9, 0.25, 0.2, 0.95)
    else
        Draw.setFG(0.85)
    end
    if fillW > 0 then
        love.graphics.rectangle("fill", bx + inset, by + inset, fillW, iconH - inset * 2, 1.5 * s, 1.5 * s)
    end

    love.graphics.setColor(1, 1, 1, 1)
    return textW + pad + iconW + capW
end

local function batteryContentWidth(font, s)
    if not Battery.level then return 0 end
    local text = math.floor(Battery.level) .. "%"
    return font:getWidth(text) + 6 * s + 26 * s + 2.5 * s
end

-- Draws the pill with its top-right corner at (x, y).
function StatusBar.draw(font, x, y, s)
    local padX = 14 * s
    local gap = 12 * s
    local pillH = 34 * s

    local time = timeText()
    local timeW = font:getWidth(time)
    local battW = batteryContentWidth(font, s)

    local contentW = timeW + (battW > 0 and (gap + battW) or 0)
    local pillW = contentW + padX * 2
    local px = x - pillW
    local cy = y + pillH / 2

    love.graphics.setFont(font)
    Glass.draw(px, y, pillW, pillH, s)

    Draw.print(time, px + padX, cy - font:getHeight() / 2, Draw.fg(0.85), s)
    if battW > 0 then
        drawBatteryContent(font, px + padX + timeW + gap, cy, s)
    end
end

return StatusBar
