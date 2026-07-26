-- "Particles" theme: PS5 boot-screen style dust motes drifting through a
-- shaft of light. A fake light source sits just above the top-right
-- corner; motes brighten as they pass through its beam and fade into the
-- dark outside it, which is what sells the "dust catching light" look.
-- Depth of field: mid-distance motes are small and bright (in focus),
-- near ones are big dim bokeh blobs, far ones tiny and faint.
--
-- Built to be cheap on handheld GPUs (H700 / Mali-G31): no fragment
-- shader, one small pre-rendered soft dot drawn as ~70 quads, a
-- 4-vertex gradient, and two low-alpha quads for the light glow.

local Particles = {}

local COUNT = 70
local time = 0
local tint = { 0.13, 0.27, 0.80 }   -- accent (default: PSP blue)
local bgTint = { 0.13, 0.27, 0.80 } -- background base
local lightMode = false

local dotImg = nil     -- soft radial dot, generated once
local gradient = nil   -- background mesh, rebuilt when the color changes
local motes = nil      -- particle list, created on first draw

-- Fake light source: sits just off-screen above the top-right corner,
-- beaming down-left. The beam sways very slowly.
local LIGHT_X, LIGHT_Y = 0.82, -0.18
local BEAM_ANGLE = 2.25       -- radians, pointing down-left
local BEAM_SWAY = 0.05
local BEAM_WIDTH = 0.72       -- cone tightness (cos of half-angle)

-- "#RRGGBB" or "RRGGBB" -> r, g, b in 0..1
local function hexToRGB(hex)
    if type(hex) ~= "string" then return nil end
    local r, g, b = hex:gsub("#", ""):match("^(%x%x)(%x%x)(%x%x)$")
    if not r then return nil end
    return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

function Particles.setColors(accent, bg, light)
    local r, g, b = hexToRGB(accent)
    if r then tint = { r, g, b } end
    local br, bgc, bb = hexToRGB(bg)
    if br then bgTint = { br, bgc, bb } end
    lightMode = light and true or false
    gradient = nil -- rebuild with the new colors
end

function Particles.getColor()
    return tint[1], tint[2], tint[3]
end

-- One 48px soft dot with a gaussian falloff; every mote draws this at a
-- different scale/alpha, which reads as depth-of-field blur.
local function ensureDot()
    if dotImg then return end
    local size = 48
    local data = love.image.newImageData(size, size)
    local c = (size - 1) / 2
    data:mapPixel(function(px, py)
        local dx, dy = (px - c) / c, (py - c) / c
        local a = math.exp(-(dx * dx + dy * dy) * 4.5)
        return 1, 1, 1, math.min(1, a)
    end)
    dotImg = love.graphics.newImage(data)
    dotImg:setFilter("linear", "linear")
end

-- Depth 0 = far, 1 = near, biased toward far so most motes are small
local function newMote()
    local z = math.random() ^ 1.4
    return {
        x = math.random() * 1.2 - 0.1,
        y = math.random() * 1.2 - 0.1,
        z = z,
        -- Individual wander: two sine components per axis at different
        -- frequencies make each path curve slowly and independently, so
        -- motes never look like they ride one shared current.
        f1 = 0.05 + 0.20 * math.random(), p1 = math.random() * 6.28,
        f2 = 0.07 + 0.25 * math.random(), p2 = math.random() * 6.28,
        wanderAmp = 0.004 + 0.010 * math.random(),
        -- Base drift scales with depth (parallax); some barely move
        drift = (0.2 + math.random()) * (0.1 + 0.9 * z),
        -- Shimmer: a slow deep pulse plus a faster flicker, at per-mote
        -- speeds so the field sparkles instead of breathing in unison.
        twinkleSpeed = 0.6 + 1.2 * math.random(),
        phase = math.random() * 6.28,
        shimmerSpeed = 4.0 + 5.0 * math.random(),
        shimmerPhase = math.random() * 6.28,
    }
end

local function ensureMotes()
    if motes then return end
    motes = {}
    for i = 1, COUNT do motes[i] = newMote() end
end

function Particles.update(dt)
    time = time + dt
    if not motes then return end
    for _, m in ipairs(motes) do
        -- Gentle shared air movement (right and slightly up), plus the
        -- mote's own wander. Near motes drift faster than far ones.
        local wander = m.wanderAmp
        m.x = m.x + (0.010 * m.drift + wander * math.sin(time * m.f1 + m.p1)) * dt
        m.y = m.y + (-0.003 * m.drift + wander * math.sin(time * m.f2 + m.p2)) * dt
        -- Wrap with margin on both axes (drift direction varies)
        if m.x > 1.1 then m.x = -0.1 elseif m.x < -0.1 then m.x = 1.1 end
        if m.y > 1.1 then m.y = -0.1 elseif m.y < -0.1 then m.y = 1.1 end
    end
end

local function ensureGradient()
    if gradient then return end
    local br, dk, md
    if lightMode then
        -- Light scheme: bright background, faintest toward the bottom
        br = { bgTint[1] * 1.03, bgTint[2] * 1.03, bgTint[3] * 1.03 }
        md = { bgTint[1] * 0.97, bgTint[2] * 0.97, bgTint[3] * 0.99 }
        dk = { bgTint[1] * 0.90, bgTint[2] * 0.90, bgTint[3] * 0.94 }
    else
        -- Dark wash of the background color; slightly brighter toward
        -- the light corner (top-right) than the opposite one.
        br = { bgTint[1] * 0.16 + 0.02, bgTint[2] * 0.16 + 0.02, bgTint[3] * 0.20 + 0.03 }
        dk = { bgTint[1] * 0.05, bgTint[2] * 0.05, bgTint[3] * 0.07 }
        md = { bgTint[1] * 0.10 + 0.01, bgTint[2] * 0.10 + 0.01, bgTint[3] * 0.13 + 0.01 }
    end
    gradient = love.graphics.newMesh({
        { 0, 0, 0, 0, md[1], md[2], md[3], 1 }, -- top-left
        { 1, 0, 1, 0, br[1], br[2], br[3], 1 }, -- top-right (lit)
        { 1, 1, 1, 1, md[1], md[2], md[3], 1 }, -- bottom-right
        { 0, 1, 0, 1, dk[1], dk[2], dk[3], 1 }, -- bottom-left (darkest)
    }, "fan", "static")
end

-- Light intensity (0..1) at a normalized screen position: a soft cone
-- from the source, fading with distance.
local function lightAt(x, y, axisX, axisY)
    local vx, vy = x - LIGHT_X, y - LIGHT_Y
    local dist = math.sqrt(vx * vx + vy * vy) + 1e-6
    local cosang = (vx * axisX + vy * axisY) / dist
    local cone = (cosang - BEAM_WIDTH) / (1 - BEAM_WIDTH)
    if cone <= 0 then return 0 end
    cone = cone * cone
    return cone * math.exp(-dist * 1.1)
end

function Particles.draw(w, h)
    ensureDot()
    ensureMotes()
    ensureGradient()

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(gradient, 0, 0, 0, w, h)

    -- Beam axis sways slowly so the scene feels alive
    local ang = BEAM_ANGLE + BEAM_SWAY * math.sin(time * 0.07)
    local axisX, axisY = math.cos(ang), math.sin(ang)

    -- Mote color. Dark schemes: mostly white with a whisper of the
    -- accent, drawn additively so overlaps glow. Light schemes: accent-
    -- colored motes with normal blending (Wii-bubble style), because
    -- additive white would vanish on a bright background.
    local cr, cg, cb
    if lightMode then
        cr, cg, cb = tint[1], tint[2], tint[3]
    else
        cr = 1 - (1 - tint[1]) * 0.25
        cg = 1 - (1 - tint[2]) * 0.25
        cb = 1 - (1 - tint[3]) * 0.25
    end

    love.graphics.setBlendMode(lightMode and "alpha" or "add")

    -- The light itself: a soft glow at the source corner and a long
    -- faint streak down the beam axis (two quads of the same dot).
    local dotW = dotImg:getWidth()
    local lx, ly = LIGHT_X * w, LIGHT_Y * h
    love.graphics.setColor(cr, cg, cb, 0.18)
    local glowSize = 1.5 * h
    love.graphics.draw(dotImg, lx - glowSize / 2, ly - glowSize / 2, 0,
        glowSize / dotW, glowSize / dotW)
    love.graphics.setColor(cr, cg, cb, 0.09)
    love.graphics.draw(dotImg, lx, ly, ang,
        3.0 * h / dotW, 1.3 * h / dotW, dotW / 2, dotW / 2)

    for _, m in ipairs(motes) do
        local z = m.z
        local light = lightAt(m.x, m.y, axisX, axisY)
        -- Depth of field: brightest near the focus plane (z ~ 0.6)
        local d = z - 0.6
        local focus = math.exp(-(d * d) / 0.05)
        -- Position in the light dominates; ambient keeps a faint field
        -- visible outside the beam. Twinkle is a subtle modulation.
        local twinkle = 0.72 + 0.28 * math.sin(time * m.twinkleSpeed + m.phase)
            + 0.16 * math.sin(time * m.shimmerSpeed + m.shimmerPhase)
        local alpha = (0.08 + 0.5 * focus) * (0.25 + 1.7 * light) * twinkle
        if alpha > 0.015 then
            -- Size: tiny in the distance, small soft bokeh up close
            local size = (1.5 + 20 * z * z) * (h / 480)
            love.graphics.setColor(cr, cg, cb, math.min(alpha, 0.85))
            local scale = size / dotW
            love.graphics.draw(dotImg, m.x * w - size / 2, m.y * h - size / 2, 0, scale, scale)
        end
    end

    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
end

return Particles
