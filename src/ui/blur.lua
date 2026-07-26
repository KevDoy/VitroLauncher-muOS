-- Backdrop blur for the glass pills ("frosted glass"). Off by default
-- (Settings: Glass Blur).
--
-- How it works: main.lua renders the whole scene into an offscreen
-- canvas (Blur.begin / Blur.finish). finish() composites that canvas
-- to the screen and keeps a quarter-resolution, gaussian-blurred copy;
-- Glass.draw then samples the blurred copy under each pill
-- (Blur.patch). The blur copy refreshes at 30Hz - behind frosted
-- glass a one-frame-old backdrop is indistinguishable - so the steady
-- GPU cost is one fullscreen composite plus three small quarter-res
-- passes every other frame.
--
-- The blur source is snapshotted *before* any glass or text is drawn
-- on screens that render glass mid-scene (Settings calls
-- Blur.snapshot() right after the background), so pill backdrops never
-- contain a ghost of the content sitting on top of them. Screens whose
-- glass all comes after the scene (carousel/grid) snapshot at finish(),
-- which lets the cover art blur through the nav pill.
--
-- If canvases or the shader are unavailable (old GLES2 driver), the
-- module reports inactive and everything renders exactly as before.

local Blur = {}

local SCALE = 4      -- blur canvases at 1/4 resolution
local UPDATE_EVERY = 2 -- refresh the blurred copy every Nth frame

local enabled = false
local supported = nil -- nil = not probed yet
local scene, blurA, blurB = nil, nil, nil
local shader = nil
local quad = nil
local sw, sh = 0, 0
local frame = 0
local hasBlur = false
local snapped = false -- blur source already captured this frame

-- Classic 9-tap gaussian with linear-sampling offsets; GLES2-safe.
local SHADER_SRC = [[
extern vec2 dir; // (1/texW, 0) for the horizontal pass, (0, 1/texH) vertical
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc)
{
    vec4 sum = Texel(tex, uv) * 0.2270270270;
    vec2 o1 = dir * 1.3846153846;
    vec2 o2 = dir * 3.2307692308;
    sum += (Texel(tex, uv + o1) + Texel(tex, uv - o1)) * 0.3162162162;
    sum += (Texel(tex, uv + o2) + Texel(tex, uv - o2)) * 0.0702702703;
    return sum * color;
}
]]

local function probe(w, h)
    local ok = pcall(function()
        shader = love.graphics.newShader(SHADER_SRC)
        scene = love.graphics.newCanvas(w, h)
        local bw, bh = math.ceil(w / SCALE), math.ceil(h / SCALE)
        blurA = love.graphics.newCanvas(bw, bh)
        blurB = love.graphics.newCanvas(bw, bh)
        blurA:setFilter("linear", "linear")
        blurB:setFilter("linear", "linear")
        quad = love.graphics.newQuad(0, 0, 1, 1, bw, bh)
    end)
    if not ok then
        print("[Blur] Canvases/shader unavailable, glass blur disabled")
        scene, blurA, blurB, shader = nil, nil, nil, nil
    end
    return ok
end

local function ensure(w, h)
    if supported == false then return false end
    if supported and w == sw and h == sh then return true end
    supported = probe(w, h)
    if supported then
        sw, sh = w, h
        hasBlur = false
    end
    return supported
end

function Blur.setEnabled(on)
    enabled = on and true or false
end

-- True when glass should draw blurred backdrops this frame
function Blur.isActive()
    return enabled and supported == true and hasBlur
end

-- Redirect scene rendering into the offscreen canvas. Returns true
-- when active; when false, drawing continues straight to the screen.
function Blur.begin(w, h)
    if not enabled or not ensure(w, h) then return false end
    frame = frame + 1
    snapped = false
    -- The stencil flag keeps Glass/Rounded stencil clipping working
    -- while the canvas is bound.
    love.graphics.setCanvas({ scene, stencil = true })
    love.graphics.clear(0, 0, 0, 1)
    return true
end

-- Downsample + blur the scene canvas as it looks right now.
-- Leaves no canvas bound; callers restore what they need.
local function refreshBlur()
    local bw, bh = blurA:getDimensions()
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setShader()
    love.graphics.setStencilTest()
    -- Downsample the scene to quarter res
    love.graphics.setCanvas(blurA)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(scene, 0, 0, 0, bw / sw, bh / sh)
    -- Separable gaussian: horizontal into B, vertical back into A
    love.graphics.setShader(shader)
    shader:send("dir", { 1 / bw, 0 })
    love.graphics.setCanvas(blurB)
    love.graphics.draw(blurA, 0, 0)
    shader:send("dir", { 0, 1 / bh })
    love.graphics.setCanvas(blurA)
    love.graphics.draw(blurB, 0, 0)
    love.graphics.pop()
    love.graphics.setCanvas()
    hasBlur = true
end

-- Capture the blur source mid-scene, before glass/text is drawn on top
-- of it. Call while the scene is being rendered (after Blur.begin).
function Blur.snapshot()
    if not enabled or supported ~= true or snapped then return end
    snapped = true
    if not hasBlur or frame % UPDATE_EVERY == 0 then
        refreshBlur()
        -- Resume rendering into the scene canvas
        love.graphics.setCanvas({ scene, stencil = true })
    end
end

-- Composite the scene to the screen; if no mid-scene snapshot was
-- taken, refresh the blurred copy from the full scene (at 30Hz).
function Blur.finish()
    if not enabled or supported ~= true then return end
    love.graphics.setCanvas()

    if not snapped then
        snapped = true
        if not hasBlur or frame % UPDATE_EVERY == 0 then
            refreshBlur()
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(scene, 0, 0)
end

-- Draw the blurred backdrop for the screen rectangle (x, y, w, h).
-- The caller is responsible for masking (stencil) and setColor.
function Blur.patch(x, y, w, h)
    if not Blur.isActive() then return end
    quad:setViewport(x / SCALE, y / SCALE, w / SCALE, h / SCALE)
    love.graphics.draw(blurA, quad, x, y, 0, SCALE, SCALE)
end

return Blur
