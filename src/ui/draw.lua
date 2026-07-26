-- Small drawing helpers shared by the UI modules.

local Draw = {}

-- Light color schemes (e.g. White & Blue) flip the UI foreground from
-- white to near-black and soften the text shadow. Set by src/ui/theme.lua.
local light = false
local FG_DARK = { 1, 1, 1 }          -- foreground on dark backgrounds
local FG_LIGHT = { 0.12, 0.14, 0.18 } -- foreground on light backgrounds

function Draw.setLight(isLight)
    light = isLight and true or false
end

function Draw.isLight()
    return light
end

-- Transparency setting (Settings: Transparency, default Yes). When off,
-- the glass surfaces render as solid gray-gradient pills (dark behind
-- white icons, light behind dark ones) with an outline, and backdrop
-- blur is skipped.
local transparent = true

function Draw.setTransparency(on)
    transparent = on and true or false
end

function Draw.isTransparent()
    return transparent
end

-- UI foreground color (text, borders, icon tint) at the given alpha
function Draw.fg(alpha)
    local c = light and FG_LIGHT or FG_DARK
    return { c[1], c[2], c[3], alpha or 1 }
end

-- love.graphics.setColor with the UI foreground at the given alpha
function Draw.setFG(alpha)
    local c = light and FG_LIGHT or FG_DARK
    love.graphics.setColor(c[1], c[2], c[3], alpha or 1)
end

-- Theme accent color, set by src/ui/theme.lua alongside the light flag
local accent = { 1, 1, 1 }

function Draw.setAccentColor(r, g, b)
    accent = { r, g, b }
end

-- Themes with neutral backdrops (Simple Dark/Light) force selection
-- outlines to the accent color in both modes. Set by src/ui/theme.lua.
local accentHighlight = false

function Draw.setAccentHighlight(on)
    accentHighlight = on and true or false
end

-- Accent nudged toward a readable luminance range for the current
-- mode, so e.g. the Black accent stays visible as a selection border
-- on Simple Dark's charcoal backdrop (blended toward mid-gray) and a
-- very bright accent would still read on a pale background.
local function highlightRGB()
    local r, g, b = accent[1], accent[2], accent[3]
    local lum = 0.299 * r + 0.587 * g + 0.114 * b
    if light then
        if lum > 0.72 then
            local t = (lum - 0.72) / lum
            r, g, b = r * (1 - t), g * (1 - t), b * (1 - t)
        end
    elseif lum < 0.35 then
        local t = (0.35 - lum) / (1 - lum)
        r, g, b = r + (1 - r) * t, g + (1 - g) * t, b + (1 - b) * t
    end
    return r, g, b
end

-- Highlight color for selection outlines: white on dark schemes, the
-- theme accent on light ones (a dark outline reads as a shadow there)
-- or whenever the active theme requests accent borders.
function Draw.setHighlight(alpha)
    if light or accentHighlight then
        local r, g, b = highlightRGB()
        love.graphics.setColor(r, g, b, alpha or 1)
    else
        love.graphics.setColor(1, 1, 1, alpha or 1)
    end
end

local function shadowOffset(s)
    return math.max(1, 1.5 * (s or 1))
end

local function shadowAlpha()
    -- Dark text on a light background needs far less shadow
    return light and 0.15 or 0.55
end

-- print/printf with a soft drop shadow so text stays readable on the
-- animated background. `color` is {r, g, b[, a]}; `s` is the UI scale.

function Draw.print(text, x, y, color, s)
    local o = shadowOffset(s)
    local a = color[4] or 1
    love.graphics.setColor(0, 0, 0, shadowAlpha() * a)
    love.graphics.print(text, x + o, y + o)
    love.graphics.setColor(color[1], color[2], color[3], a)
    love.graphics.print(text, x, y)
end

function Draw.printf(text, x, y, limit, align, color, s)
    local o = shadowOffset(s)
    local a = color[4] or 1
    love.graphics.setColor(0, 0, 0, shadowAlpha() * a)
    love.graphics.printf(text, x + o, y + o, limit, align)
    love.graphics.setColor(color[1], color[2], color[3], a)
    love.graphics.printf(text, x, y, limit, align)
end

return Draw
