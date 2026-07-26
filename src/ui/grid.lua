-- All Titles screen: paged grid of game icons (cover art fallback).
-- Bookmarks show a badge in the icon's top-left corner and Y toggles
-- them. Pages advance by pressing right at the rightmost column, or all
-- at once with X. The selected title's name and playtime show below the
-- grid, next to the always-visible bookmark hint.

local State = require("src.state")
local Stats = require("src.stats")
local Draw = require("src.ui.draw")
local Fonts = require("src.ui.fonts")
local Icons = require("src.ui.icons")
local ImageCache = require("src.ui.imagecache")
local Rounded = require("src.ui.rounded")

local Grid = {}

-- 480p reference layouts per Icon Size setting. Total grid width must
-- leave room at 640x480 for the page arrows and X tooltip at the edges
-- (~45px margin each side).
local LAYOUTS = {
    large = { rows = 2, cols = 5, icon = 98, gap = 15 },
    small = { rows = 3, cols = 7, icon = 68, gap = 12 },
}

local GRID_TOP = 70       -- grid area top (below the status pill)
local NAME_Y = 336        -- selected title name baseline area
local CORNER = 0.16       -- icon corner radius ratio
local ZOOM = 0.14         -- focused icon grows to (1 + ZOOM) of its slot
local ANIM_SPEED = 10     -- exponential smoothing factor (matches carousel)

function Grid.new()
    local self = {
        games = {},
        selected = 1,     -- absolute index into games
        sizeMode = "large",
        images = ImageCache.new(64), -- icons/covers, LRU-bounded GPU memory
        focus = {},       -- per-icon focus animation value (0..1)
    }
    return setmetatable(self, { __index = Grid })
end

function Grid:layout()
    return LAYOUTS[self.sizeMode] or LAYOUTS.large
end

function Grid:perPage()
    local l = self:layout()
    return l.rows * l.cols
end

function Grid:pageCount()
    return math.max(1, math.ceil(#self.games / self:perPage()))
end

function Grid:setGames(games)
    self.games = games
    self.selected = math.max(1, math.min(self.selected, #games))
    self.focus = {}
    for i = 1, #games do
        self.focus[i] = (i == self.selected) and 1 or 0
    end
    -- self.images is intentionally kept: it's keyed by file path, so a
    -- re-sorted or re-scanned list reuses the already-loaded textures
    -- (screen switches call setGames and reloading here caused hitches).
end

-- Ease each icon's focus toward selected/unselected, like the carousel
function Grid:update(dt)
    local k = math.min(1, dt * ANIM_SPEED)
    for i = 1, #self.games do
        local target = (i == self.selected) and 1 or 0
        self.focus[i] = (self.focus[i] or 0) + (target - (self.focus[i] or 0)) * k
    end
end

function Grid:selectedGame()
    return self.games[self.selected]
end

-- dx/dy in {-1, 0, 1}. Pressing right past the last column moves to the
-- next page (same row); left past the first column to the previous page.
function Grid:move(dx, dy)
    local n = #self.games
    if n == 0 then return end
    local per = self:perPage()
    local cols = self:layout().cols
    local idx = self.selected - 1
    local page = math.floor(idx / per)
    local slot = idx % per
    local row, col = math.floor(slot / cols), slot % cols

    if dx ~= 0 then
        col = col + dx
        if col >= cols then
            if (page + 1) * per < n then page, col = page + 1, 0 else col = cols - 1 end
        elseif col < 0 then
            if page > 0 then page, col = page - 1, cols - 1 else col = 0 end
        end
    end
    if dy ~= 0 then
        row = math.max(0, math.min(self:layout().rows - 1, row + dy))
    end

    local target = page * per + row * cols + col
    -- Clamp into the page's real items (last page may be partial)
    self.selected = math.min(target, n - 1) + 1
end

function Grid:skipPage()
    local n = #self.games
    if n == 0 then return end
    local per = self:perPage()
    local page = math.floor((self.selected - 1) / per)
    local slot = (self.selected - 1) % per
    page = (page + 1) % self:pageCount()
    self.selected = math.min(page * per + slot, n - 1) + 1
end

function Grid:toggleBookmark()
    local game = self:selectedGame()
    if not game then return end
    local on = State.toggleBookmark(game.id)
    print("[Grid] Bookmark " .. (on and "added" or "removed") .. ": " .. game.id)
end

function Grid:imageFor(game)
    local path = game.iconPath or game.imgPath
    if not path then return nil end
    return self.images:get(path)
end

-- f is the 0..1 focus animation value: the icon zooms around its center
-- and gets the strong highlight border as it approaches 1.
local function drawIconTile(self, game, x, y, size, s, f)
    -- Zoom around the slot center
    local zoomed = size * (1 + ZOOM * f)
    x = x - (zoomed - size) / 2
    y = y - (zoomed - size) / 2
    size = zoomed

    local radius = size * CORNER
    local img = self:imageFor(game)

    if img then
        Rounded.drawCover(img, x, y, size, size, radius)
    else
        love.graphics.setColor(0.15, 0.15, 0.15, 1)
        love.graphics.rectangle("fill", x, y, size, size, radius, radius)
        local font = Fonts.get(size * 0.4, "bold")
        love.graphics.setFont(font)
        Draw.setFG(0.35)
        love.graphics.printf(game.name:sub(1, 1):upper(), x, y + size / 2 - font:getHeight() / 2, size, "center")
    end

    -- Subtle border on all icons; strong border fades in with focus
    Draw.setFG(0.25)
    love.graphics.setLineWidth(2 * s)
    love.graphics.rectangle("line", x, y, size, size, radius, radius)
    if f > 0.01 then
        local pad = 3 * s
        Draw.setHighlight(f)
        love.graphics.setLineWidth(4 * s)
        love.graphics.rectangle("line", x - pad, y - pad, size + pad * 2, size + pad * 2,
            radius + pad, radius + pad)
    end

    -- Bookmark badge, top-left
    if State.isBookmarked(game.id) then
        local badge = Icons.get("bookmark")
        if badge then
            local bh = size * 0.30
            local bw = bh / badge:getHeight() * badge:getWidth()
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(badge, x + size * 0.08, y - 2 * s, 0,
                bw / badge:getWidth(), bh / badge:getHeight())
        end
    end
end

-- opts: { showPlaytime, tooltips, buttonLayout }
function Grid:draw(w, h, opts)
    local s = h / 480
    local n = #self.games

    if n == 0 then
        local font = Fonts.get(22 * s, "bold")
        love.graphics.setFont(font)
        Draw.printf("No games found.\nAdd folders with info.cfg inside the GAME directory.",
            0, h * 0.4, w, "center", Draw.fg(0.8), s)
        return
    end

    local l = self:layout()
    local icon = l.icon * s
    local gap = l.gap * s
    local per = self:perPage()
    local page = math.floor((self.selected - 1) / per)
    local first = page * per + 1
    local last = math.min(first + per - 1, n)

    local gridW = l.cols * icon + (l.cols - 1) * gap
    local gridH = l.rows * icon + (l.rows - 1) * gap
    local x0 = (w - gridW) / 2
    local y0 = GRID_TOP * s + (LAYOUTS.large.rows * (LAYOUTS.large.icon + LAYOUTS.large.gap) * s - gridH) / 2

    -- Zoomed icons overlap their neighbors, so draw in two passes:
    -- resting icons first, then anything mid-animation on top.
    local function tileAt(i)
        local slot = i - first
        local row, col = math.floor(slot / l.cols), slot % l.cols
        return x0 + col * (icon + gap), y0 + row * (icon + gap)
    end
    for i = first, last do
        if (self.focus[i] or 0) <= 0.01 then
            local x, y = tileAt(i)
            drawIconTile(self, self.games[i], x, y, icon, s, 0)
        end
    end
    for i = first, last do
        local f = self.focus[i] or 0
        if f > 0.01 then
            local x, y = tileAt(i)
            drawIconTile(self, self.games[i], x, y, icon, s, f)
        end
    end

    -- Next/previous page arrows at the screen edges (right one carries
    -- the X tooltip, since X skips pages)
    local arrowCy = y0 + gridH / 2
    local function arrow(cx, dir, more)
        if not more then return end
        Icons.drawGlassArrow(cx, arrowCy, 20 * s, dir, 0.9)
    end
    arrow(14 * s, -1, page > 0)
    arrow(w - 14 * s, 1, page < self:pageCount() - 1)
    if opts.tooltips and self:pageCount() > 1 then
        local glyph = Icons.button("skip", opts.buttonLayout)
        if glyph then
            Icons.drawAtHeight(glyph, w - 22 * s, arrowCy + 22 * s, 16 * s, 0.7)
        end
    end

    -- Selected title, then playtime + bookmark hint
    local game = self.games[self.selected]
    local nameFont = Fonts.get(21 * s, "bold")
    love.graphics.setFont(nameFont)
    Draw.printf(game.name, w * 0.1, NAME_Y * s, w * 0.8, "center", Draw.fg(1), s)

    local infoFont = Fonts.get(15 * s, "regular")
    love.graphics.setFont(infoFont)
    local played = opts.showPlaytime and Stats.formatPlaytime(game.playSeconds)
    local glyph = Icons.button("bookmark", opts.buttonLayout)
    local glyphH = 16 * s
    local glyphW = glyph and (glyphH / glyph:getHeight() * glyph:getWidth()) or 0
    local hintText = State.isBookmarked(game.id) and " to Unbookmark" or " to Bookmark"

    -- Compose "2h Played | (Y) to Bookmark" centered as one line.
    -- The bookmark hint stays even when tooltips are off (by design).
    local left = played and (played .. " Played  |  ") or ""
    local totalW = infoFont:getWidth(left) + glyphW + infoFont:getWidth(hintText)
    local tx = w / 2 - totalW / 2
    local ty = (NAME_Y + 30) * s
    local cy = ty + infoFont:getHeight() / 2
    if left ~= "" then
        Draw.print(left, tx, ty, Draw.fg(0.9), s)
        tx = tx + infoFont:getWidth(left)
    end
    if glyph then
        Icons.drawAtHeight(glyph, tx, cy, glyphH, 0.9)
        tx = tx + glyphW
    end
    Draw.print(hintText, tx, ty, Draw.fg(0.9), s)

    love.graphics.setColor(1, 1, 1, 1)
end

return Grid
