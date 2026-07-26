-- Stretchable "glass" pill background, built from three slices:
-- glass-bg-left / -center / -right. The caps keep their aspect ratio and
-- the center stretches horizontally, so the pill fits any content width.
-- Mipmaps keep the thin edge highlight smooth at small draw sizes.

local Draw = require("src.ui.draw")
local Blur = require("src.ui.blur")
local Simple = require("src.ui.simple")

local Glass = {}

-- Solid pill backdrops for Transparency = No: the same gray gradients
-- as the Simple Dark / Simple Light themes, built once per mode.
local opaqueMesh = {}

local function opaqueGradient(lightMode)
    local key = lightMode and "light" or "dark"
    if not opaqueMesh[key] then
        local p = Simple.PALETTE[key]
        opaqueMesh[key] = love.graphics.newMesh({
            { 0, 0, 0, 0, p.top[1], p.top[2], p.top[3], 1 },
            { 1, 0, 1, 0, p.top[1], p.top[2], p.top[3], 1 },
            { 1, 1, 1, 1, p.bottom[1], p.bottom[2], p.bottom[3], 1 },
            { 0, 1, 0, 1, p.bottom[1], p.bottom[2], p.bottom[3], 1 },
        }, "fan", "static")
    end
    return opaqueMesh[key]
end

local slices = nil -- { left, center, right } or false when loading failed

local function load()
    if slices ~= nil then return slices end
    local ok, result = pcall(function()
        local imgs = {}
        for _, name in ipairs({ "left", "center", "right" }) do
            local img = love.graphics.newImage(
                "assets/images/glass-bg-" .. name .. ".png", { mipmaps = true })
            img:setMipmapFilter("linear", 1)
            imgs[name] = img
        end
        return imgs
    end)
    slices = ok and result or false
    if not ok then print("[Glass] Failed to load pill slices: " .. tostring(result)) end
    return slices
end

local function drawSlices(imgs, x, y, w, h)
    -- The slices are translucent, so they must butt exactly: any overlap
    -- doubles the alpha into a visible seam, any gap leaves a hairline.
    -- Snapping the joints to whole pixels keeps the edges clean.
    x = math.floor(x + 0.5)
    y = math.floor(y + 0.5)
    local scale = h / imgs.left:getHeight()
    local capW = math.floor(imgs.left:getWidth() * scale + 0.5)

    -- Short pills: a center sliver squeezed far below its natural width
    -- samples the whole center texture into a few columns and renders as
    -- a visible band, so below that the caps simply meet in the middle
    -- instead (stretched slightly to fill the width). The threshold is
    -- relative to the cap size so it holds at any resolution.
    if w - 2 * capW < capW * 0.5 then
        capW = math.floor(w / 2)
        love.graphics.draw(imgs.left, x, y, 0, capW / imgs.left:getWidth(), scale)
        love.graphics.draw(imgs.right, x + capW, y, 0,
            (w - capW) / imgs.right:getWidth(), scale)
        return
    end

    local rightX = math.floor(x + w - capW + 0.5)
    local centerX = x + capW
    local centerW = rightX - centerX

    love.graphics.draw(imgs.center, centerX, y, 0,
        centerW / imgs.center:getWidth(), scale)
    love.graphics.draw(imgs.left, x, y, 0, capW / imgs.left:getWidth(), scale)
    love.graphics.draw(imgs.right, rightX, y, 0, capW / imgs.right:getWidth(), scale)
end

-- Draws the pill with a drop shadow. (x, y) is the top-left corner.
-- Returns true when the slices are available (false = draw nothing).
function Glass.draw(x, y, w, h, s, alpha)
    alpha = alpha or 1

    -- Transparency off: a solid pill with an outline instead of glass.
    -- Dark gray gradient behind white icons/text, light gray behind
    -- dark ones (the Simple theme gradients).
    if not Draw.isTransparent() then
        local r = h / 2
        love.graphics.stencil(function()
            love.graphics.rectangle("fill", x, y, w, h, r, r)
        end, "replace", 1)
        love.graphics.setStencilTest("greater", 0)
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.draw(opaqueGradient(Draw.isLight()), x, y, 0, w, h)
        love.graphics.setStencilTest()
        Draw.setFG(0.5 * alpha)
        love.graphics.setLineWidth(math.max(1, (s or 1)))
        love.graphics.rectangle("line", x, y, w, h, r, r)
        love.graphics.setColor(1, 1, 1, 1)
        return true
    end

    local imgs = load()
    if not imgs then return false end

    -- On light themes the shadow shows against the pale background and
    -- visually extends the pill downward, making centered content look
    -- shifted up — so it gets much fainter and tighter there.
    local shadowA = Draw.isLight() and 0.10 or 0.35
    local shadowY = Draw.isLight() and 1.5 or 3
    love.graphics.setColor(0, 0, 0, shadowA * alpha)
    drawSlices(imgs, x + 1.5 * (s or 1), y + shadowY * (s or 1), w, h)

    -- Frosted-glass backdrop (Settings: Glass Blur): the blurred scene,
    -- stencil-masked to the pill shape, under the translucent artwork.
    -- Inset by a pixel so the blur never peeks past the art's soft edge.
    if Blur.isActive() and alpha > 0.05 then
        love.graphics.stencil(function()
            local r = (h - 2) / 2
            love.graphics.rectangle("fill", x + 1, y + 1, w - 2, h - 2, r, r)
        end, "replace", 1)
        love.graphics.setStencilTest("greater", 0)
        love.graphics.setColor(1, 1, 1, alpha)
        Blur.patch(x, y, w, h)
        love.graphics.setStencilTest()
    end

    love.graphics.setColor(1, 1, 1, alpha)
    drawSlices(imgs, x, y, w, h)
    love.graphics.setColor(1, 1, 1, 1)
    return true
end

return Glass
