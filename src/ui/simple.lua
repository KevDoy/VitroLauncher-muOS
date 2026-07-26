-- "Simple Dark" / "Simple Light" themes: Nintendo Switch style. A flat,
-- static gray gradient (dark or light) as the backdrop; the user's
-- chosen color only shows up as the accent on selection borders, which
-- src/ui/theme.lua handles by forcing accent highlights for these
-- themes. Essentially free to render: one static 4-vertex mesh.

-- "#RRGGBB" or "RRGGBB" -> r, g, b in 0..1
local function hexToRGB(hex)
    if type(hex) ~= "string" then return nil end
    local r, g, b = hex:gsub("#", ""):match("^(%x%x)(%x%x)(%x%x)$")
    if not r then return nil end
    return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

local function newSimple(top, bottom)
    local M = {}
    local tint = { 0.13, 0.27, 0.80 } -- accent, exposed via getColor
    local gradient = nil

    function M.setColors(accent, _bg, _light)
        local r, g, b = hexToRGB(accent)
        if r then tint = { r, g, b } end
    end

    function M.getColor()
        return tint[1], tint[2], tint[3]
    end

    function M.update(_dt) end

    function M.draw(w, h)
        if not gradient then
            gradient = love.graphics.newMesh({
                { 0, 0, 0, 0, top[1], top[2], top[3], 1 },
                { 1, 0, 1, 0, top[1], top[2], top[3], 1 },
                { 1, 1, 1, 1, bottom[1], bottom[2], bottom[3], 1 },
                { 0, 1, 0, 1, bottom[1], bottom[2], bottom[3], 1 },
            }, "fan", "static")
        end
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(gradient, 0, 0, 0, w, h)
    end

    return M
end

-- Gradient stops, shared with src/ui/glass.lua (the Transparency=No
-- pill backdrops reuse these same grays).
local PALETTE = {
    -- Switch dark: near-flat charcoal, a touch brighter at the top
    dark = { top = { 0.20, 0.20, 0.215 }, bottom = { 0.125, 0.125, 0.135 } },
    -- Switch light: pale gray, faintly darker toward the bottom
    light = { top = { 0.955, 0.955, 0.965 }, bottom = { 0.865, 0.87, 0.885 } },
}

return {
    dark = newSimple(PALETTE.dark.top, PALETTE.dark.bottom),
    light = newSimple(PALETTE.light.top, PALETTE.light.bottom),
    PALETTE = PALETTE,
}
