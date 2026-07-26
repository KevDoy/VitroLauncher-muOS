-- Persistent launcher state, stored at <appdir>/data/state.json.
-- Tracks last-played order so the most recently played title is always
-- the first tile.

local json = require("src.lib.json")
local Platform = require("src.platform")

local State = {}

State.lastPlayed = {} -- list of game ids, most recent first
State.bookmarks = {}  -- set: game id -> true

local function statePath()
    return Platform.appDir() .. "/data/state.json"
end

function State.load()
    local raw = Platform.readFile(statePath())
    if raw then
        local ok, parsed = pcall(json.decode, raw)
        if ok and type(parsed) == "table" then
            if type(parsed.lastPlayed) == "table" then
                State.lastPlayed = parsed.lastPlayed
            end
            if type(parsed.bookmarks) == "table" then
                State.bookmarks = parsed.bookmarks
            end
        end
    end
end

function State.save()
    Platform.mkdir(Platform.appDir() .. "/data")
    Platform.writeFile(statePath(), json.encode({
        lastPlayed = State.lastPlayed,
        bookmarks = State.bookmarks,
    }))
end

function State.isBookmarked(gameId)
    return State.bookmarks[gameId] == true
end

function State.toggleBookmark(gameId)
    State.bookmarks[gameId] = not State.bookmarks[gameId] or nil
    State.save()
    return State.bookmarks[gameId] == true
end

function State.markPlayed(gameId)
    local list = { gameId }
    for _, id in ipairs(State.lastPlayed) do
        if id ~= gameId then table.insert(list, id) end
    end
    -- Keep the list bounded
    while #list > 100 do table.remove(list) end
    State.lastPlayed = list
    State.save()
end

-- Sort games: last-played first (most recent leading), then the rest A-Z.
function State.sortGames(games)
    local rank = {}
    for i, id in ipairs(State.lastPlayed) do rank[id] = i end

    table.sort(games, function(a, b)
        local ra, rb = rank[a.id], rank[b.id]
        if ra and rb then return ra < rb end
        if ra then return true end
        if rb then return false end
        return a.name:lower() < b.name:lower()
    end)
    return games
end

return State
