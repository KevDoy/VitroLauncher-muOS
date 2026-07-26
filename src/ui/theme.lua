-- Theme router: every background theme implements setColors / getColor /
-- update / draw, and every theme takes the user's chosen color scheme
-- into account. Add new themes to LIST and new colors to COLORS below.

local Wave = require("src.ui.wave")
local Particles = require("src.ui.particles")
local Clouds = require("src.ui.clouds")
local Simple = require("src.ui.simple")
local Draw = require("src.ui.draw")

local Theme = {}

-- Ordered list for the Settings screen. `forceLight` overrides the
-- color scheme's light/dark UI mode (the Simple themes have fixed gray
-- backdrops); `accentBorders` makes selection outlines use the accent
-- color regardless of mode.
Theme.LIST = {
    { key = "waves", name = "Waves", module = Wave },
    { key = "particles", name = "Particles", module = Particles },
    { key = "clouds", name = "Clouds", module = Clouds },
    { key = "simple-dark", name = "Simple Dark", module = Simple.dark,
        forceLight = false, accentBorders = true },
    { key = "simple-light", name = "Simple Light", module = Simple.light,
        forceLight = true, accentBorders = true },
}

-- Color schemes for the Settings "Color" row. `value` is what gets
-- stored in config (wave_color). Single-color entries tint everything;
-- dual-color entries split background and accent, and `light = true`
-- flips the UI foreground to dark for light backgrounds.
Theme.COLORS = {
    { name = "Blue",   value = "#2245cc" },
    { name = "Purple", value = "#7a3fd4" },
    { name = "Red",    value = "#c0264b" },
    { name = "Orange", value = "#d97b1f" },
    { name = "Green",  value = "#1f9e46" },
    { name = "Teal",   value = "#12939c" },
    { name = "Pink",   value = "#d4569b" },
    { name = "Silver", value = "#7f8c9b" },
    { name = "Black",  value = "#101216" },
    -- SteamOS: near-black with bright blue accents
    { name = "Black & Blue", value = "black-blue", bg = "#0e141b", accent = "#1a9fff" },
    -- Wii: white with sky blue accents (light UI foreground mode)
    { name = "White & Blue", value = "white-blue", bg = "#e9edf2", accent = "#20a0d6", light = true },
}

local current = Wave
local currentEntry = Theme.LIST[1]
local schemeLight = false -- light flag from the color scheme

-- The active theme can override the scheme's light/dark UI mode and
-- switch the selection outlines to the accent color.
local function applyMode()
    local l = schemeLight
    if currentEntry.forceLight ~= nil then l = currentEntry.forceLight end
    Draw.setLight(l)
    Draw.setAccentHighlight(currentEntry.accentBorders or false)
end

function Theme.set(key)
    for _, t in ipairs(Theme.LIST) do
        if t.key == key then
            current = t.module
            currentEntry = t
            applyMode()
            return
        end
    end
    current = Wave
    currentEntry = Theme.LIST[1]
    applyMode()
end

function Theme.nameFor(key)
    for _, t in ipairs(Theme.LIST) do
        if t.key == key then return t.name end
    end
    return Theme.LIST[1].name
end

function Theme.schemeFor(value)
    for _, c in ipairs(Theme.COLORS) do
        if c.value == value then return c end
    end
    return nil
end

-- Accepts a "#RRGGBB" hex (single color) or a scheme id like
-- "black-blue". Applies to all themes so switching keeps the choice.
function Theme.setColor(value)
    local scheme = Theme.schemeFor(value)
    local accent, bg, light
    if scheme and scheme.bg then
        accent, bg, light = scheme.accent, scheme.bg, scheme.light and true or false
    else
        -- Single color (palette entry or hand-edited hex): accent and
        -- background are the same, preserving the classic look
        accent = (type(value) == "string" and value:match("^#?%x%x%x%x%x%x$"))
            and value or "#2245cc"
        bg, light = accent, false
    end
    schemeLight = light
    applyMode()
    local ar, ag, ab = accent:gsub("#", ""):match("^(%x%x)(%x%x)(%x%x)$")
    if ar then
        Draw.setAccentColor(tonumber(ar, 16) / 255, tonumber(ag, 16) / 255, tonumber(ab, 16) / 255)
    end
    for _, t in ipairs(Theme.LIST) do
        t.module.setColors(accent, bg, light)
    end
end

function Theme.getColor()
    return current.getColor()
end

function Theme.update(dt)
    current.update(dt)
end

function Theme.draw(w, h)
    current.draw(w, h)
end

return Theme
