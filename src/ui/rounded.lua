-- Anti-aliased rounded-corner image drawing.
-- The stencil approach clips per-pixel and leaves jagged corners; this
-- shader instead fades the image's alpha over a ~1px band along a
-- rounded-rectangle signed-distance field, which reads as a smooth edge
-- at any resolution.

local Rounded = {}

local SHADER_SRC = [[
extern vec2 rectPos;    // tile top-left, screen px
extern vec2 rectHalf;   // tile half-size, screen px
extern float radius;    // corner radius, px

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc)
{
    vec4 px = Texel(tex, tc) * color;
    // Signed distance to the rounded rectangle: negative inside
    vec2 d = abs(sc - rectPos - rectHalf) - (rectHalf - vec2(radius));
    float dist = length(max(d, vec2(0.0))) - radius;
    px.a *= clamp(0.5 - dist, 0.0, 1.0);
    return px;
}
]]

local shader = nil -- compiled shader, or false when unsupported

local function getShader()
    if shader == nil then
        local ok, result = pcall(love.graphics.newShader, SHADER_SRC)
        shader = ok and result or false
        if not ok then
            print("[Rounded] Shader unavailable, corners fall back to stencil: "
                .. tostring(result))
        end
    end
    return shader
end

local function drawStencilFallback(img, x, y, w, h, radius, scale, dx, dy)
    love.graphics.stencil(function()
        love.graphics.rectangle("fill", x, y, w, h, radius, radius)
    end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)
    love.graphics.draw(img, dx, dy, 0, scale, scale)
    love.graphics.setStencilTest()
end

-- Draws img center-cropped to fill the (x, y, w, h) rect with smooth
-- rounded corners of the given radius.
function Rounded.drawCover(img, x, y, w, h, radius)
    local iw, ih = img:getDimensions()
    local scale = math.max(w / iw, h / ih)
    local dx = x + (w - iw * scale) / 2
    local dy = y + (h - ih * scale) / 2

    love.graphics.setColor(1, 1, 1, 1)
    local sh = getShader()
    if not sh then
        drawStencilFallback(img, x, y, w, h, radius, scale, dx, dy)
        return
    end

    sh:send("rectPos", { x, y })
    sh:send("rectHalf", { w / 2, h / 2 })
    sh:send("radius", radius)
    love.graphics.setShader(sh)

    -- The cover-crop can spill outside the tile; scissor keeps the
    -- shader's work (and any overdraw) inside the rect.
    love.graphics.intersectScissor(math.floor(x), math.floor(y),
        math.ceil(w) + 1, math.ceil(h) + 1)
    love.graphics.draw(img, dx, dy, 0, scale, scale)
    love.graphics.setScissor()
    love.graphics.setShader()
end

return Rounded
