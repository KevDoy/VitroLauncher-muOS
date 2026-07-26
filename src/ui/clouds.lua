-- "Clouds" theme: cotton-candy pixel-art sky modeled on the classic
-- pink-clouds-on-cyan look. Big fluffy clouds fill the whole screen at
-- different depths and drift slowly; everything (sky included) is
-- rendered through a Bayer-dithered palette, which gives the soft
-- "airbrushed pixel art" gradients of the reference.
--
-- The Color setting drives the clouds: their shade ramp is generated
-- from the accent hue (Pink reproduces the reference art exactly).
-- The sky always stays in the blue family - its shade is only nudged
-- per color so it complements the clouds (shifted away from blue
-- accents so they still pop, dimmed to a night sky for dark schemes,
-- lightened for light ones).
--
-- Cloud sprites are generated procedurally on the CPU whenever the
-- color changes: each cloud is a union of elliptical puffs (metaballs)
-- shaded per pixel as lit spheres (sun above), quantized to the
-- palette with ordered dithering. At runtime it's one tiled sky
-- texture and ~8 nearest-filtered quads. No shaders.

local Clouds = {}

local time = 0
local tint = { 212 / 255, 86 / 255, 155 / 255 }   -- accent (default Pink)
local bgTint = { 212 / 255, 86 / 255, 155 / 255 }
local lightMode = false

local sprites = nil
local clouds = nil
local skyImg, skyRows = nil, 0
local skyQuad, skyCols = nil, 0

-- "#RRGGBB" or "RRGGBB" -> r, g, b in 0..1
local function hexToRGB(hex)
    if type(hex) ~= "string" then return nil end
    local r, g, b = hex:gsub("#", ""):match("^(%x%x)(%x%x)(%x%x)$")
    if not r then return nil end
    return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

local function rgbToHSL(r, g, b)
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local l = (mx + mn) / 2
    if mx == mn then return 0, 0, l end
    local d = mx - mn
    local s = l > 0.5 and d / (2 - mx - mn) or d / (mx + mn)
    local h
    if mx == r then
        h = (g - b) / d + (g < b and 6 or 0)
    elseif mx == g then
        h = (b - r) / d + 2
    else
        h = (r - g) / d + 4
    end
    return h / 6, s, l
end

local function hslToRGB(h, s, l)
    if s <= 0 then return l, l, l end
    local function hue(p, q, t)
        t = t % 1
        if t < 1 / 6 then return p + (q - p) * 6 * t end
        if t < 1 / 2 then return q end
        if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
        return p
    end
    local q = l < 0.5 and l * (1 + s) or l + s - l * s
    local p = 2 * l - q
    return hue(p, q, h + 1 / 3), hue(p, q, h), hue(p, q, h - 1 / 3)
end

function Clouds.setColors(accent, bg, light)
    local r, g, b = hexToRGB(accent)
    if r then tint = { r, g, b } end
    local br, bgc, bb = hexToRGB(bg)
    if br then bgTint = { br, bgc, bb } end
    lightMode = light and true or false
    sprites = nil -- regenerate the art with the new palette
    skyImg = nil
end

function Clouds.getColor()
    return tint[1], tint[2], tint[3]
end

-- Cloud shade ramp from the accent hue, dark underside -> sunlit top.
-- The lightness/saturation curve is tuned so Pink (#d4569b) reproduces
-- the reference palette.
local function cloudPalette()
    local h, s = rgbToHSL(tint[1], tint[2], tint[3])
    local sat = math.max(s, 0.25) -- Black/Silver still get a usable hue
    -- k grows toward the light end: in HSL, pale shades need *more*
    -- saturation to keep their hue (these values are read back from
    -- the reference art's pink ramp).
    local levels = {
        { l = 0.60, k = 1.00 }, -- deep shadow (undersides, crevices)
        { l = 0.70, k = 1.17 },
        { l = 0.79, k = 1.27 },
        { l = 0.87, k = 1.32 },
        { l = 0.94, k = 1.36 },
        { l = 0.985, k = 1.65 }, -- sunlit top, near white
    }
    local pal = {}
    for i, lv in ipairs(levels) do
        local r, g, b = hslToRGB(h, math.min(1, sat * lv.k), lv.l)
        pal[i] = { r, g, b }
    end
    return pal
end

-- Sky gradient stops (top -> bottom), always blue/cyan. Tuned so Pink
-- matches the reference: steel blue up high to pale cyan low. The path
-- shifts away from blue-family accents so the clouds keep contrast,
-- darkens to a night sky for dark schemes and lightens for light ones.
local function skyPalette()
    local ch = rgbToHSL(tint[1], tint[2], tint[3])
    local hueShift, lShift = 0, 0
    if ch >= 0.42 and ch <= 0.58 then
        -- Cyan/teal/green-cyan accents: nudge the sky toward deeper
        -- blue so the clouds don't melt into it
        hueShift = 0.06
    elseif ch > 0.58 and ch <= 0.72 then
        -- Blue/indigo accents: keep the sky blue, just a touch deeper -
        -- white cloud tops carry the contrast
        lShift = -0.06
    end
    local lum = 0.299 * bgTint[1] + 0.587 * bgTint[2] + 0.114 * bgTint[3]
    if lightMode then
        lShift = lShift + 0.10
    elseif lum < 0.15 then
        lShift = lShift - 0.22 -- Black / Black & Blue: night sky
    end
    local stops = {}
    for i = 0, 3 do
        local t = i / 3
        local r, g, b = hslToRGB(
            (0.588 - 0.072 * t + hueShift) % 1,
            0.43 + 0.17 * t,
            math.max(0.12, math.min(0.92, 0.48 + 0.24 * t + lShift)))
        stops[i + 1] = { r, g, b }
    end
    return stops
end

-- Bayer 4x4 threshold matrix, the classic ordered-dither pattern
local BAYER = {
    { 0, 8, 2, 10 },
    { 12, 4, 14, 6 },
    { 3, 11, 1, 9 },
    { 15, 7, 13, 5 },
}

local function bayer(x, y)
    return BAYER[y % 4 + 1][x % 4 + 1] / 16
end

-- Tiny deterministic per-pixel noise to break up shading bands
local function hashNoise(x, y)
    local n = math.sin(x * 127.1 + y * 311.7) * 43758.5453
    return n - math.floor(n)
end

-- Cloud sprite generation -------------------------------------------------

-- Build one cloud on a gw x gh cell grid: a wide slab along the
-- baseline fuses puffs into one mass, round puffs on top make the
-- cauliflower silhouette, small low puffs give the lumpy underside.
local function buildSprite(gw, gh, puffN)
    local baseline = gh - 2
    local puffs = {
        { x = gw * 0.5, y = baseline - gh * 0.16, rx = gw * 0.44, ry = gh * 0.30 },
    }
    for i = 1, puffN do
        local r = gh * (0.24 + 0.22 * math.random())
        local t = (i - 0.5) / puffN
        local bulge = 1 - (2 * t - 1) * (2 * t - 1) * 0.55
        local cx = gw * (0.10 + 0.80 * t) + (math.random() - 0.5) * gh * 0.2
        local cy = baseline - gh * 0.32 * bulge - r * 0.45
        table.insert(puffs, { x = cx, y = cy, rx = r, ry = r })
    end
    for _ = 1, math.floor(puffN / 2) do
        local r = gh * (0.13 + 0.10 * math.random())
        table.insert(puffs, {
            x = gw * (0.12 + 0.76 * math.random()),
            y = baseline - r * 0.7,
            rx = r, ry = r,
        })
    end

    local pal = cloudPalette()
    local shades = #pal
    -- Sun above, slightly left and in front (unit vector). The z
    -- component matters: with a true 3D sphere normal the shading is
    -- smooth across each puff, where the old flat radial direction had
    -- discontinuities that rendered as sharp dark points.
    local LX, LY, LZ = -0.24, -0.82, 0.52

    local data = love.image.newImageData(gw, gh)
    for py = 0, gh - 1 do
        for px = 0, gw - 1 do
            local wsum, dsum = 0, 0
            for _, p in ipairs(puffs) do
                local dx, dy = (px - p.x) / p.rx, (py - p.y) / p.ry
                if dy > 0 then dy = dy * 1.2 end -- flatter bottoms
                local d2 = dx * dx + dy * dy
                if d2 < 1 then
                    local w = (1 - d2) * (1 - d2)
                    -- Sphere normal (dx, dy, nz): lambert shading
                    local nz = math.sqrt(1 - d2)
                    local dot = dx * LX + dy * LY + nz * LZ
                    wsum = wsum + w
                    dsum = dsum + w * dot
                end
            end
            if wsum > 0.001 then
                -- Bias bright: most of the cloud is sunlit, the pink
                -- shadow lives in undersides and crevices
                local b = 0.52 + 0.55 * (dsum / wsum)
                b = b + (hashNoise(px, py) - 0.5) * 0.06
                b = math.max(0, math.min(1, b))
                local level = b * (shades - 1)
                local base = math.floor(level)
                if level - base > bayer(px, py) then base = base + 1 end
                local c = pal[math.max(1, math.min(shades, base + 1))]
                data:setPixel(px, py, c[1], c[2], c[3], 1)
            else
                data:setPixel(px, py, 0, 0, 0, 0)
            end
        end
    end
    local img = love.graphics.newImage(data)
    img:setFilter("nearest", "nearest")
    return img
end

local function ensureSprites()
    if sprites then return end
    -- Deterministic shapes so every boot shows the same sky
    math.randomseed(23)
    sprites = {
        buildSprite(150, 60, 8), -- hero cloud
        buildSprite(100, 42, 6),
        buildSprite(64, 26, 5),
        buildSprite(40, 16, 4),  -- small distant cloud
    }
    math.randomseed(os.time())
end

-- Cloud layout: fills the whole screen. x/y are normalized; depth sets
-- both scale of drift speed and draw order (far first).
local function ensureClouds()
    if clouds then return end
    clouds = {
        -- Far, slow layer
        { sprite = 4, x = 0.30, y = 0.06, speed = 0.002 },
        { sprite = 4, x = 0.75, y = 0.50, speed = 0.002 },
        { sprite = 3, x = 0.55, y = 0.28, speed = 0.003 },
        -- Mid layer
        { sprite = 2, x = 0.65, y = -0.04, speed = 0.0045 },
        { sprite = 3, x = 0.05, y = 0.62, speed = 0.004 },
        { sprite = 2, x = 0.25, y = 0.78, speed = 0.005 },
        -- Near, big and fastest
        { sprite = 1, x = -0.10, y = 0.16, speed = 0.007 },
        { sprite = 1, x = 0.55, y = 0.66, speed = 0.008 },
    }
end

function Clouds.update(dt)
    time = time + dt
    if not clouds then return end
    for _, c in ipairs(clouds) do
        c.x = c.x + c.speed * dt
        if c.x > 1.1 then c.x = -0.6 end
    end
end

-- Sky: a dithered vertical gradient through the skyPalette() stops,
-- built as a narrow tile (the Bayer pattern repeats every 4px) and
-- stretched across the screen.
local function ensureSky(rows)
    if skyImg and skyRows == rows then return end
    skyRows = rows
    local SKY = skyPalette()
    local w = 4
    local data = love.image.newImageData(w, rows)
    local segs = #SKY - 1
    for y = 0, rows - 1 do
        local t = y / (rows - 1) * segs
        local i = math.min(segs, math.floor(t) + 1)
        local f = t - (i - 1)
        for x = 0, w - 1 do
            -- Dither the blend between the two neighboring stops
            local j = (f > bayer(x, y)) and (i + 1) or i
            j = math.max(1, math.min(#SKY, j))
            local c = SKY[j]
            data:setPixel(x, y, c[1], c[2], c[3], 1)
        end
    end
    skyImg = love.graphics.newImage(data)
    skyImg:setFilter("nearest", "nearest")
    skyImg:setWrap("repeat", "clamp")
    skyQuad, skyCols = nil, 0
end

function Clouds.draw(w, h)
    -- Integer pixel size keeps the art crisp at any resolution
    local px = math.max(2, math.floor(h / 160 + 0.5))
    local rows = math.ceil(h / px)

    ensureSprites()
    ensureClouds()
    ensureSky(rows)

    love.graphics.setColor(1, 1, 1, 1)
    -- Tile the 4px-wide sky strip across the full width
    local cols = math.ceil(w / px)
    if not skyQuad or skyCols ~= cols then
        skyCols = cols
        skyQuad = love.graphics.newQuad(0, 0, cols, rows,
            skyImg:getWidth(), skyImg:getHeight())
    end
    love.graphics.draw(skyImg, skyQuad, 0, 0, 0, px, px)

    for _, c in ipairs(clouds) do
        local img = sprites[c.sprite]
        -- Smooth scrolling: positions move at screen-pixel resolution
        -- (the art itself stays chunky). Rounding to whole screen
        -- pixels avoids nearest-filter edge jitter at fractional
        -- positions.
        local x = math.floor(c.x * w + 0.5)
        local y = math.floor(c.y * h + 0.5)
        love.graphics.draw(img, x, y, 0, px, px)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return Clouds
