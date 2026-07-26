-- LRU texture cache for cover art and icons, bounded by estimated GPU
-- memory instead of entry count (one oversized cover costs as much as
-- dozens of properly-sized icons). Visible tiles re-request their image
-- every frame, so they always carry the freshest ticks and eviction
-- only ever hits offscreen textures. Missing files are cached as false
-- (free) so they aren't retried every frame.

local Platform = require("src.platform")

local ImageCache = {}
ImageCache.__index = ImageCache

-- Estimated GPU bytes: RGBA plus ~1/3 extra for the mipmap chain
local function costOf(img)
    return img:getWidth() * img:getHeight() * 4 * 1.34
end

function ImageCache.new(budgetMB)
    return setmetatable({
        entries = {}, -- path -> { img = Image|false, tick = n, cost = bytes }
        bytes = 0,
        budget = (budgetMB or 64) * 1024 * 1024,
        tick = 0,
    }, ImageCache)
end

function ImageCache:has(path)
    return self.entries[path] ~= nil
end

-- Insert a preloaded image (or false for a missing file). No-op when
-- the path is already cached.
function ImageCache:put(path, img)
    if self.entries[path] then return end
    self.tick = self.tick + 1
    local cost = img and costOf(img) or 0
    self.entries[path] = { img = img or false, tick = self.tick, cost = cost }
    self.bytes = self.bytes + cost
    self:evict()
end

-- Image for a path, loading it on first use. nil when the file is
-- missing or unreadable.
function ImageCache:get(path)
    local entry = self.entries[path]
    if entry then
        self.tick = self.tick + 1
        entry.tick = self.tick
        return entry.img or nil
    end
    local img = Platform.loadImage(path) or false
    self:put(path, img)
    return img or nil
end

-- Release least-recently-used textures until within budget. The entry
-- with the current (newest) tick is never evicted, so a just-loaded
-- image survives even if it alone exceeds the budget.
function ImageCache:evict()
    while self.bytes > self.budget do
        local oldestPath, oldest
        for path, entry in pairs(self.entries) do
            if entry.img and entry.tick ~= self.tick and
                (not oldest or entry.tick < oldest.tick) then
                oldestPath, oldest = path, entry
            end
        end
        if not oldest then return end
        self.bytes = self.bytes - oldest.cost
        oldest.img:release()
        self.entries[oldestPath] = nil
    end
end

return ImageCache
