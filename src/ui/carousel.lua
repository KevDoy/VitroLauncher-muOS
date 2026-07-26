-- Horizontal tile carousel.
-- Layout is designed on a 480px-tall reference canvas and scales with the
-- actual window height, so 640x480, 720x480 and larger screens all work.

local Draw = require("src.ui.draw")
local Fonts = require("src.ui.fonts")
local ImageCache = require("src.ui.imagecache")
local Rounded = require("src.ui.rounded")
local Stats = require("src.stats")

local Carousel = {}

-- Base (unscaled, 480p reference) metrics
local BASE = {
    tile = 160,          -- unfocused tile height
    tileFocused = 200,   -- focused tile height
    gap = 20,            -- space between tile edges (uniform for all tiles)
    centerXFrac = 0.50,  -- focused tile center (fraction of screen width)
    centerY = 0.44,      -- vertical center line (fraction of screen height)
    cornerRatio = 0.15,  -- corner radius as a fraction of tile size
    borderWidth = 4,     -- focused white border
    borderGap = 3,       -- gap between image edge and border
    titleSize = 21,      -- focused title font size
    titleOffset = 18,    -- distance from tile bottom to title
    playtimeSize = 15,   -- playtime line under the title
    playtimeGap = 8,     -- title -> playtime spacing
}

local ANIM_SPEED = 10 -- exponential smoothing factor

function Carousel.new()
    local self = {
        games = {},
        selected = 1,
        active = true,    -- false while another UI element (bottom bar) has focus
        infinite = false, -- wraparound scrolling (Settings toggle)
        sizeScale = 1,    -- cover tile scale: 1 default, <1 for "small" (Settings)
        aspect = 2 / 3,   -- tile width / height: 2/3 box art or 1 square (config)
        rounded = true,   -- rounded tile corners (config)
        showTitles = false, -- focused game title below the tile (config)
        showPlaytime = true, -- playtime line under the title (config)
        focus = {},   -- per-tile focus animation value (0..1)
        anim = 0,     -- fractional slot offset, eases back to 0 after a move
        images = ImageCache.new(64), -- covers, LRU-bounded GPU memory
        fonts = {},   -- pixel size -> Font
    }
    return setmetatable(self, { __index = Carousel })
end

function Carousel:setGames(games)
    self.games = games
    self.selected = math.max(1, math.min(self.selected, #games))
    self.focus = {}
    for i = 1, #games do
        self.focus[i] = (i == self.selected) and 1 or 0
    end
    self.anim = 0
    -- self.images is intentionally kept: it's keyed by file path, so a
    -- re-sorted or re-scanned list reuses the already-loaded textures
    -- (screen switches call setGames and reloading here caused hitches).
end

function Carousel:selectedGame()
    return self.games[self.selected]
end

function Carousel:move(delta)
    local n = #self.games
    if n == 0 then return false end
    local target = self.selected + delta
    if self.infinite and n > 1 then
        target = ((target - 1) % n) + 1
    elseif target < 1 or target > n then
        return false
    end
    self.selected = target
    -- Keep the previously-focused tile visually in place, then ease the
    -- row over by one slot. Clamped so held-repeat can't run away.
    self.anim = math.max(-2.5, math.min(2.5, self.anim + delta))
    return true
end

function Carousel:update(dt)
    local k = math.min(1, dt * ANIM_SPEED)
    for i = 1, #self.games do
        local target = (self.active and i == self.selected) and 1 or 0
        self.focus[i] = self.focus[i] + (target - self.focus[i]) * k
    end
    self.anim = self.anim * (1 - k)
    if math.abs(self.anim) < 0.001 then self.anim = 0 end
end

function Carousel:imageFor(game)
    if not game.imgPath then return nil end
    return self.images:get(game.imgPath)
end

function Carousel:fontFor(px)
    return Fonts.get(px, "bold")
end

local function drawCover(img, x, y, w, h, radius)
    Rounded.drawCover(img, x, y, w, h, radius)
end

function Carousel:draw(screenW, screenH)
    local s = screenH / 480 -- responsive scale
    local cy = screenH * BASE.centerY
    local n = #self.games

    if n == 0 then
        local font = self:fontFor(22 * s)
        love.graphics.setFont(font)
        Draw.printf("No games found.\nAdd folders with info.cfg inside the GAME directory.",
            0, cy - font:getHeight(), screenW, "center", Draw.fg(0.8), s)
        return
    end

    -- Tiles sit around the focused tile's center with a uniform edge gap,
    -- so positions are accumulated from each tile's animated size. Slot
    -- offsets are relative to the selected index; with infinite scrolling
    -- they wrap around the list (each game drawn at most once).
    local gap = BASE.gap * s
    local centerX = screenW * BASE.centerXFrac
    local slotEstimate = (BASE.tile * self.aspect * self.sizeScale + BASE.gap) * s
    local maxOff = math.ceil(screenW / slotEstimate) + 1

    local lo, hi
    if self.infinite and n > 1 then
        lo = math.max(-math.floor(n / 2), -maxOff)
        hi = math.min(lo + n - 1, maxOff)
    else
        lo = math.max(1 - self.selected, -maxOff)
        hi = math.min(n - self.selected, maxOff)
    end

    local function indexAt(o)
        return ((self.selected - 1 + o) % n) + 1
    end
    -- Tile height at slot offset o; width is height * aspect
    local function sizeAt(o)
        return (BASE.tile + (BASE.tileFocused - BASE.tile) * self.focus[indexAt(o)])
            * self.sizeScale * s
    end
    local function widthAt(o)
        return sizeAt(o) * self.aspect
    end

    -- Center positions relative to the focused tile
    local centers = { [0] = 0 }
    for o = 1, hi do
        centers[o] = centers[o - 1] + widthAt(o - 1) / 2 + gap + widthAt(o) / 2
    end
    for o = -1, lo, -1 do
        centers[o] = centers[o + 1] - (widthAt(o + 1) / 2 + gap + widthAt(o) / 2)
    end

    local shift = self.anim * slotEstimate

    for o = lo, hi do
        local i = indexAt(o)
        local game = self.games[i]
        local f = self.focus[i]
        local th = sizeAt(o)
        local tw = th * self.aspect
        local cx = centerX + centers[o] + shift
        local x = cx - tw / 2
        local y = cy - th / 2

        if x + tw > 0 and x < screenW then
            local radius = self.rounded and math.min(tw, th) * BASE.cornerRatio or 0
            local img = self:imageFor(game)

            if img then
                drawCover(img, x, y, tw, th, radius)
            else
                -- Placeholder tile
                love.graphics.setColor(0.15, 0.15, 0.15, 1)
                love.graphics.rectangle("fill", x, y, tw, th, radius, radius)
                local font = self:fontFor(th * 0.4)
                love.graphics.setFont(font)
                Draw.setFG(0.35)
                local letter = game.name:sub(1, 1):upper()
                love.graphics.printf(letter, x, y + th / 2 - font:getHeight() / 2, tw, "center")
            end

            -- Subtle border on every tile (readability against the bg)
            Draw.setFG(0.25)
            love.graphics.setLineWidth(BASE.borderWidth / 2 * s)
            love.graphics.rectangle("line", x, y, tw, th, radius, radius)

            -- Focused border: white, or the accent on light schemes
            if f > 0.01 then
                local pad = BASE.borderGap * s
                Draw.setHighlight(f)
                love.graphics.setLineWidth(BASE.borderWidth * s)
                love.graphics.rectangle("line",
                    x - pad, y - pad, tw + pad * 2, th + pad * 2,
                    radius + pad, radius + pad)
            end

            -- Focused title and playtime below the tile
            local alpha = math.max(0, (f - 0.5) * 2)
            if alpha > 0.01 then
                local textY = y + th + BASE.titleOffset * s
                local textW = math.max(tw * 2, 340 * s)
                if self.showTitles then
                    local font = self:fontFor(BASE.titleSize * s)
                    love.graphics.setFont(font)
                    -- Single line only: long names get an ellipsis so the
                    -- title never wraps into the playtime line below.
                    local title = game.name
                    if font:getWidth(title) > textW then
                        repeat
                            title = title:sub(1, -2)
                        until font:getWidth(title .. "...") <= textW or #title == 0
                        title = title .. "..."
                    end
                    Draw.printf(title, cx - textW / 2, textY, textW, "center",
                        Draw.fg(alpha), s)
                    textY = textY + font:getHeight() + BASE.playtimeGap * s
                end
                local played = self.showPlaytime and Stats.formatPlaytime(game.playSeconds)
                if played then
                    local font = Fonts.get(BASE.playtimeSize * s, "regular")
                    love.graphics.setFont(font)
                    Draw.printf(played .. " Played", cx - textW / 2, textY, textW,
                        "center", Draw.fg(alpha * 0.9), s)
                end
            end
        end
    end
end

return Carousel
