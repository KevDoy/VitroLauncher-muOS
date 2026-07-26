-- Settings screen (dedicated page, reached via the bottom nav or SELECT).
-- Controls: up/down select row, left/right change value, A activates
-- (Reset), B/L1 back out to the previous screen (handled in main.lua).

local Config = require("src.config")
local System = require("src.system")
local Theme = require("src.ui.theme")
local Draw = require("src.ui.draw")
local Fonts = require("src.ui.fonts")
local Glass = require("src.ui.glass")
local Icons = require("src.ui.icons")

local Settings = {}

local selected = 1
local scroll = 0 -- first visible row index - 1

-- Color schemes live in Theme.COLORS (single hex or dual bg+accent)
local COLORS = Theme.COLORS

local function hexToRGB(hex)
    local r, g, b = hex:match("#(%x%x)(%x%x)(%x%x)")
    return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

local function colorIndex()
    local current = tostring(Config.values.wave_color or ""):lower()
    for i, c in ipairs(COLORS) do
        if c.value:lower() == current then return i end
    end
    return nil -- user-edited custom hex in config.json
end

local function cycleColor(delta)
    local i = colorIndex()
    i = i and ((i - 1 + delta) % #COLORS) + 1 or 1
    Config.set("wave_color", COLORS[i].value)
    Theme.setColor(COLORS[i].value)
end

-- Generic option cycler: key cycles through the values list
local function cycler(key, values)
    return function(delta)
        local current = Config.values[key]
        local i = 1
        for j, v in ipairs(values) do
            if v == current then i = j break end
        end
        i = ((i - 1 + delta) % #values) + 1
        Config.set(key, values[i])
        print("[Settings] " .. key .. " -> " .. tostring(values[i]))
    end
end

local function toggler(key)
    return function() Config.set(key, not Config.values[key]) end
end

local function yesNo(key)
    return function() return Config.values[key] and "Yes" or "No" end
end

-- Only two options, so either direction toggles
local function toggleButtonStyle()
    local modern = Config.values.button_layout == "modern"
    Config.set("button_layout", modern and "retro" or "modern")
end

-- Confirm/back label pair for prompts, e.g. "A", "B" or "X", "O"
function Settings.buttonLabels()
    if Config.values.button_layout == "modern" then
        return "X", "O"
    end
    return "A", "B"
end

local RESET_KEYS = {
    "wave_color", "theme", "tooltips", "nav_autohide", "infinite_scroll", "button_layout",
    "default_screen", "startup_fade", "show_playtime", "show_titles", "cover_size",
    "recent_limit", "all_icon_size", "all_sort", "all_bookmarks", "transparency",
}

local function resetSettings()
    Config.reset(RESET_KEYS)
    Theme.setColor(Config.values.wave_color)
    print("[Settings] Reset to defaults")
end

-- Draw the current color as a filled dot left of the value text.
-- Dual-color schemes show two half circles (background | accent).
local function drawColorDot(cx, cy, s)
    local radius = 8 * s
    local scheme = Theme.schemeFor(Config.values.wave_color)
    if scheme and scheme.bg then
        local br, bgc, bb = hexToRGB(scheme.bg)
        local ar, ag, ab = hexToRGB(scheme.accent)
        love.graphics.setColor(br, bgc, bb, 1)
        love.graphics.arc("fill", cx, cy, radius, math.pi / 2, math.pi * 1.5)
        love.graphics.setColor(ar, ag, ab, 1)
        love.graphics.arc("fill", cx, cy, radius, -math.pi / 2, math.pi / 2)
    else
        local hex = tostring(Config.values.wave_color or "#2245cc")
        local r, g, b = hexToRGB(hex:match("^#?%x%x%x%x%x%x$") and hex or "#2245cc")
        love.graphics.setColor(r, g, b, 1)
        love.graphics.circle("fill", cx, cy, radius)
    end
    Draw.setFG(0.6)
    love.graphics.setLineWidth(1.2 * s)
    love.graphics.circle("line", cx, cy, radius)
end

local COVER_SIZES = { "small", "medium", "large" }
local COVER_NAMES = { small = "Small", medium = "Medium", large = "Large", default = "Medium" }

local ROWS = {
    {
        label = "Color",
        value = function()
            local i = colorIndex()
            return i and COLORS[i].name or "Custom"
        end,
        change = cycleColor,
        dot = true,
    },
    {
        label = "Theme",
        value = function() return Theme.nameFor(Config.values.theme) end,
        change = cycler("theme", { "waves", "particles", "clouds", "simple-dark", "simple-light" }),
    },
    { label = "Tooltips", value = yesNo("tooltips"), change = toggler("tooltips") },
    {
        label = "Auto-Hide Navigation",
        value = function()
            local v = tonumber(Config.values.nav_autohide) or 0
            return v > 0 and (v .. "s") or "No"
        end,
        change = cycler("nav_autohide", { 0, 3, 5, 10 }),
    },
    { label = "Infinite Scrolling", value = yesNo("infinite_scroll"), change = toggler("infinite_scroll") },
    {
        label = "Button Style",
        value = function()
            return Config.values.button_layout == "modern" and "X / O" or "A / B"
        end,
        change = toggleButtonStyle,
        glyphs = true,
    },
    {
        label = "Default Screen",
        value = function()
            return Config.values.default_screen == "all" and "All Titles" or "Recent"
        end,
        change = cycler("default_screen", { "recent", "all" }),
    },
    { label = "Startup Fade-In", value = yesNo("startup_fade"), change = toggler("startup_fade") },
    { label = "Show Playtime", value = yesNo("show_playtime"), change = toggler("show_playtime") },
    { label = "Show Titles on Recents", value = yesNo("show_titles"), change = toggler("show_titles") },
    {
        label = "Cover Size on Recents",
        value = function() return COVER_NAMES[Config.values.cover_size] or "Large" end,
        change = cycler("cover_size", COVER_SIZES),
    },
    {
        label = "Title Limit on Recents",
        value = function() return tostring(tonumber(Config.values.recent_limit) or 12) end,
        change = cycler("recent_limit", { 4, 8, 12, 16 }),
    },
    {
        label = "Icon Size on All Titles",
        value = function()
            return Config.values.all_icon_size == "small" and "Small (3 Rows)" or "Large (2 Rows)"
        end,
        change = cycler("all_icon_size", { "large", "small" }),
    },
    {
        label = "Sorting on All Titles",
        value = function()
            local names = { recent = "Recent", playtime = "Time Played" }
            return names[Config.values.all_sort] or "A-Z"
        end,
        change = cycler("all_sort", { "az", "recent", "playtime" }),
    },
    {
        label = "Bookmarks on All Titles",
        value = function()
            return Config.values.all_bookmarks == "sorted" and "As Sorted" or "Show First"
        end,
        change = cycler("all_bookmarks", { "first", "sorted" }),
    },
    { label = "Transparency", value = yesNo("transparency"), change = toggler("transparency") },
    {
        label = "Screen Brightness",
        value = function()
            local v = System.getBrightness()
            return v and (v .. "%") or "--"
        end,
        change = function(delta) System.changeBrightness(delta) end,
    },
    {
        label = "System Volume",
        value = function()
            local v = System.getVolume()
            return v and (v .. "%") or "--"
        end,
        change = function(delta)
            local v = System.getVolume()
            if v then System.setVolume(v + delta * 10) end
        end,
    },
    { label = "Reset Settings", value = function() return "" end, activate = resetSettings },
}

local VISIBLE = 7 -- rows on screen at once

-- Consumes an input action while the settings screen is active.
-- Returns true when handled; "back"/screen switching stay in main.lua.
function Settings.handle(action)
    local row = ROWS[selected]
    if action == "up" then
        selected = math.max(1, selected - 1)
    elseif action == "down" then
        selected = math.min(#ROWS, selected + 1)
    elseif action == "left" then
        if row.change then row.change(-1) end
    elseif action == "right" then
        if row.change then row.change(1) end
    elseif action == "launch" then
        if row.activate then row.activate() end
    else
        return false
    end
    -- Keep the selected row inside the visible window
    if selected - 1 < scroll then scroll = selected - 1 end
    if selected > scroll + VISIBLE then scroll = selected - VISIBLE end
    return true
end

function Settings.draw(w, h)
    local s = h / 480

    local titleFont = Fonts.get(30 * s, "bold")
    love.graphics.setFont(titleFont)
    Draw.print("Settings", 40 * s, 26 * s, Draw.fg(1), s)

    local rowH = 42 * s
    local rowsTop = 84 * s
    local rowX = 40 * s
    local rowW = w - rowX * 2
    local labelFont = Fonts.get(19 * s, "bold")
    local valueFont = Fonts.get(15 * s, "bold")

    for vi = 1, math.min(VISIBLE, #ROWS - scroll) do
        local i = scroll + vi
        local row = ROWS[i]
        local ry = rowsTop + (vi - 1) * rowH
        local cy = ry + rowH / 2
        local focused = (i == selected)

        if focused then
            Glass.draw(rowX, ry + 2 * s, rowW, rowH - 4 * s, s)
        end

        love.graphics.setFont(labelFont)
        local alpha = focused and 1 or 0.85
        Draw.print(row.label, rowX + 22 * s, cy - labelFont:getHeight() / 2,
            Draw.fg(alpha), s)

        -- Value block, right-aligned; focused changeable rows get arrows
        love.graphics.setFont(valueFont)
        local rightEdge = rowX + rowW - 22 * s
        local arrowW = 14 * s
        if focused and row.change then
            Icons.drawGlassArrow(rightEdge + 4 * s, cy, 13 * s, 1, 0.9)
            rightEdge = rightEdge - arrowW
        end

        local vx = rightEdge
        if row.glyphs then
            -- A / B or X / O as button images
            local confirm = Icons.button("confirm", Config.values.button_layout)
            local back = Icons.button("back", Config.values.button_layout)
            local gh = 18 * s
            local slashW = valueFont:getWidth(" / ")
            local gw = confirm and (gh / confirm:getHeight() * confirm:getWidth()) or 0
            vx = vx - gw
            if back then Icons.drawAtHeight(back, vx, cy, gh, alpha) end
            vx = vx - slashW
            Draw.print(" / ", vx, cy - valueFont:getHeight() / 2, Draw.fg(alpha), s)
            vx = vx - gw
            if confirm then Icons.drawAtHeight(confirm, vx, cy, gh, alpha) end
        else
            local value = row.value()
            if value ~= "" then
                vx = vx - valueFont:getWidth(value)
                Draw.print(value, vx, cy - valueFont:getHeight() / 2, Draw.fg(alpha), s)
            end
            if row.dot then
                vx = vx - 16 * s
                drawColorDot(vx, cy, s)
                vx = vx - 8 * s
            end
        end

        if focused and row.change then
            Icons.drawGlassArrow(vx - 14 * s, cy, 13 * s, -1, 0.9)
        end
    end

    -- Scroll hints when rows continue off-screen
    local hintFont = Fonts.get(13 * s, "regular")
    love.graphics.setFont(hintFont)
    if scroll + VISIBLE < #ROWS then
        Draw.printf("more", 0, rowsTop + VISIBLE * rowH + 2 * s, w - 44 * s, "right",
            Draw.fg(0.45), s)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return Settings
