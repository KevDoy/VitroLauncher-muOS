-- Cache for the small UI images in assets/images (nav icons, button
-- glyphs, bookmark badge). Mipmapped so they stay smooth at UI sizes.

local Draw = require("src.ui.draw")

local Icons = {}

local cache = {}

-- name is relative to assets/images, without extension: "icons/settings"
function Icons.get(name)
    if cache[name] == nil then
        local ok, img = pcall(function()
            local i = love.graphics.newImage("assets/images/" .. name .. ".png", { mipmaps = true })
            i:setMipmapFilter("linear", 1)
            return i
        end)
        cache[name] = ok and img or false
        if not ok then print("[Icons] Missing image: " .. name) end
    end
    return cache[name] or nil
end

-- Physical-button glyph for the current button style.
-- Roles: confirm (east/A), back (south/B), skip (north/X), bookmark (west/Y).
local GLYPHS = {
    retro = { confirm = "button_A", back = "button_B", skip = "button_X", bookmark = "button_Y" },
    modern = { confirm = "button_Cross", back = "button_Circle", skip = "button_Square", bookmark = "button_Triangle" },
}

function Icons.button(role, layout)
    local map = GLYPHS[layout] or GLYPHS.retro
    return Icons.get("buttons/" .. (map[role] or "button_A"))
end

-- Glass-style directional arrow (assets/images/glass-arrow-right.png),
-- centered on (cx, cy) at the given height. dir 1 = right, -1 = left
-- (mirrored). Drawn untinted like the glass pill, with a soft shadow so
-- it stays visible on light color schemes.
function Icons.drawGlassArrow(cx, cy, height, dir, alpha)
    local img = Icons.get("glass-arrow-right")
    if not img then return end
    alpha = alpha or 1
    local iw, ih = img:getDimensions()
    local scale = height / ih
    local sx = (dir or 1) >= 0 and scale or -scale
    local ox, oy = iw / 2, ih / 2
    -- Transparency off: a solid foreground-colored arrow, no shadow
    if not Draw.isTransparent() then
        Draw.setFG(alpha)
        love.graphics.draw(img, cx, cy, 0, sx, scale, ox, oy)
        love.graphics.setColor(1, 1, 1, 1)
        return
    end

    local shadow = math.max(1.5, height * 0.1)

    -- Two offset passes fake a soft shadow: a wider faint one for the
    -- halo plus a tighter darker one for contact.
    love.graphics.setColor(0, 0, 0, (Draw.isLight() and 0.10 or 0.20) * alpha)
    love.graphics.draw(img, cx + shadow, cy + shadow * 1.6, 0,
        sx * 1.08, scale * 1.08, ox, oy)
    love.graphics.setColor(0, 0, 0, (Draw.isLight() and 0.18 or 0.40) * alpha)
    love.graphics.draw(img, cx + shadow * 0.5, cy + shadow, 0, sx, scale, ox, oy)
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(img, cx, cy, 0, sx, scale, ox, oy)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw an image scaled to a given height, centered vertically on cy,
-- tinted with the UI foreground (assets are white line art, so the tint
-- turns them dark on light color schemes). Returns the drawn width.
function Icons.drawAtHeight(img, x, cy, height, alpha)
    local iw, ih = img:getDimensions()
    local scale = height / ih
    Draw.setFG(alpha or 1)
    love.graphics.draw(img, x, cy - height / 2, 0, scale, scale)
    love.graphics.setColor(1, 1, 1, 1)
    return iw * scale
end

return Icons
