-- Shared font cache (bold + regular Roboto Condensed).

local Fonts = {}

local FILES = {
    bold = "assets/fonts/RobotoCondensed-Bold.ttf",
    regular = "assets/fonts/RobotoCondensed-Regular.ttf",
}

local cache = {}

function Fonts.get(px, weight)
    weight = FILES[weight] and weight or "bold"
    px = math.max(8, math.floor(px + 0.5))
    local key = weight .. px
    if not cache[key] then
        cache[key] = love.graphics.newFont(FILES[weight], px)
    end
    return cache[key]
end

return Fonts
