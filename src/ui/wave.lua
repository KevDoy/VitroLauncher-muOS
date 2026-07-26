-- PSP XMB-style animated wave background.
-- A fullscreen shader draws a vertical color gradient with two
-- translucent wave layers, each filled from its crest to the bottom of
-- the screen so they overlap like the PSP's. Colors come from the theme
-- router: single-color schemes use one tint for everything (the classic
-- look), dual-color schemes split background and ribbon accent, and
-- light schemes (e.g. White & Blue) render the ribbon by darkening
-- toward the accent instead of adding brightness.
-- If shader creation fails (exotic GL driver), falls back to a static
-- gradient so the launcher still works.

local Wave = {}

local shader = nil
local shaderFailed = false
local time = 0
local gradient = nil -- fallback mesh

local SHADER_SRC = [[
    // Animation arrives as four pre-wrapped phases (0..2pi) instead of a
    // raw time value. Device fragment shaders run at mediump (fp16)
    // precision, where a forever-growing time quantizes ever more
    // coarsely and the wave turns choppy after a few minutes. Phases are
    // wrapped CPU-side in doubles, so they stay small and smooth forever.
    extern vec4 phases;
    extern vec3 tint;       // ribbon / accent color
    extern vec3 gradTop;    // background gradient, precomputed CPU-side
    extern vec3 gradBottom;
    extern float lightMode; // 1.0 = light background (mix ribbon in)
    extern vec2 res;

    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        // Untextured primitives carry no texture coordinates, so derive
        // 0..1 UVs from the pixel position instead.
        vec2 uv = sc / res;

        vec3 col = mix(gradTop, gradBottom, uv.y);

        // Two drifting sine crests, PSP style: each wave is a filled
        // surface from its crest down past the bottom of the screen, so
        // there is no visible lower edge. The two translucent layers
        // overlap and compound where they cross. Crests sit low on the
        // screen so they peek out below the tile row.
        float y1 = 0.76 + 0.13 * sin(uv.x * 2.2 + phases.x)
                        + 0.05 * sin(uv.x * 5.0 - phases.y);
        float y2 = 0.92 + 0.12 * sin(uv.x * 2.8 - phases.z)
                        + 0.06 * sin(uv.x * 4.1 + phases.w);

        // Fill everything below each crest (soft top edge only)
        float f1 = smoothstep(y1 - 0.02, y1 + 0.05, uv.y);
        float f2 = smoothstep(y2 - 0.02, y2 + 0.05, uv.y);

        // Bright rim highlight along each crest; visible through the
        // other wave's body like the PSP's translucent layers
        float g1 = exp(-abs(uv.y - y1) * 55.0);
        float g2 = exp(-abs(uv.y - y2) * 55.0);

        if (lightMode > 0.5) {
            // Light background: blend each layer toward the accent and
            // draw crisp accent rim lines (adding white would vanish).
            // Sequential mixes compound where the waves overlap. The
            // front (lower) wave is stronger so it reads as the top layer.
            col = mix(col, tint, f1 * 0.20);
            col = mix(col, tint, f2 * 0.32);
            col = mix(col, tint, (g1 + g2) * 0.45);
        } else {
            // The front (lower) wave is more opaque than the back one
            col += f1 * (tint * 0.45 + vec3(0.05));
            col += f2 * (tint * 0.70 + vec3(0.10));
            col += (g1 + g2) * (tint * 0.6 + vec3(0.4)) * 0.5;
        }

        return vec4(col, 1.0);
    }
]]

-- "#RRGGBB" or "RRGGBB" -> r, g, b in 0..1
local function hexToRGB(hex)
    if type(hex) ~= "string" then return nil end
    local r, g, b = hex:gsub("#", ""):match("^(%x%x)(%x%x)(%x%x)$")
    if not r then return nil end
    return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

local tint = { 0.13, 0.27, 0.80 } -- accent (PSP blue #2245cc)
local bgTint = { 0.13, 0.27, 0.80 }
local lightMode = false

-- accent/bg are hex strings; light flips the ribbon rendering
function Wave.setColors(accent, bg, light)
    local r, g, b = hexToRGB(accent)
    if r then tint = { r, g, b } end
    local br, bgc, bb = hexToRGB(bg)
    if br then bgTint = { br, bgc, bb } end
    lightMode = light and true or false
    gradient = nil -- rebuild fallback with new colors
end

function Wave.getColor()
    return tint[1], tint[2], tint[3]
end

-- Background gradient endpoints. Dark schemes keep the classic
-- dark-at-top ramp; light schemes stay uniformly bright with a gentle
-- deepening toward the bottom.
local function gradientColors()
    if lightMode then
        return { bgTint[1] * 1.04, bgTint[2] * 1.04, bgTint[3] * 1.04 },
            { bgTint[1] * 0.88, bgTint[2] * 0.88, bgTint[3] * 0.92 }
    end
    return { bgTint[1] * 0.20, bgTint[2] * 0.20, bgTint[3] * 0.20 },
        { bgTint[1] * 1.05, bgTint[2] * 1.05, bgTint[3] * 1.05 }
end

local function ensureShader()
    if shader or shaderFailed then return end
    local ok, result = pcall(love.graphics.newShader, SHADER_SRC)
    if ok then
        shader = result
    else
        shaderFailed = true
        print("[Wave] Shader unavailable, using static gradient: " .. tostring(result))
    end
end

function Wave.update(dt)
    time = time + dt
end

function Wave.draw(w, h)
    ensureShader()
    love.graphics.setColor(1, 1, 1, 1)

    if shader then
        local TWO_PI = 2 * math.pi
        shader:send("phases", {
            (time * 0.45) % TWO_PI,
            (time * 0.26) % TWO_PI,
            (time * 0.36) % TWO_PI,
            (time * 0.31) % TWO_PI,
        })
        local top, bottom = gradientColors()
        shader:send("tint", tint)
        shader:send("gradTop", top)
        shader:send("gradBottom", bottom)
        shader:send("lightMode", lightMode and 1 or 0)
        shader:send("res", { w, h })
        love.graphics.setShader(shader)
        love.graphics.rectangle("fill", 0, 0, w, h)
        love.graphics.setShader()
        return
    end

    -- Fallback: static vertical gradient
    if not gradient then
        local top, bottom = gradientColors()
        gradient = love.graphics.newMesh({
            { 0, 0, 0, 0, top[1], top[2], top[3], 1 },
            { 1, 0, 1, 0, top[1], top[2], top[3], 1 },
            { 1, 1, 1, 1, bottom[1], bottom[2], bottom[3], 1 },
            { 0, 1, 0, 1, bottom[1], bottom[2], bottom[3], 1 },
        }, "fan", "static")
    end
    love.graphics.draw(gradient, 0, 0, 0, w, h)
end

return Wave
