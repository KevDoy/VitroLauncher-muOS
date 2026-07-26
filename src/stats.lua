-- Per-game play statistics, stored inside each game's folder as
-- stats.json (sibling of info.cfg) so the numbers travel with the game
-- when a folder is copied between cards or devices. Keyed by the entry's
-- rom file, since one folder's info.cfg may define several titles:
--
--   { "Crash Bandicoot.pbp":
--       { "playSeconds": 4260, "playCount": 7, "lastPlayed": 1752771600 } }
--
-- Sessions have to survive the launcher not running while a game plays
-- (on device the launcher quits, the game runs, then the launcher is
-- reopened by mux_launch.sh):
--   * launch  -> playCount/lastPlayed bump in the folder's stats.json,
--               plus an open-session marker at data/session.json
--   * return  -> the next launcher start folds the elapsed time into the
--               folder's stats.json and clears the marker
-- While the game runs, mux_launch.sh stamps runtime/heartbeat every 30s.
-- If the launcher never came back (battery died, hard power-off), the
-- session is closed at the last heartbeat instead of being lost or
-- counting hours of off-time.

local json = require("src.lib.json")
local Platform = require("src.platform")
local Config = require("src.config")

local Stats = {}

-- A heartbeat this much older than "now" means the launcher did NOT
-- come straight back after the game exited; close at the heartbeat.
local STALE_HEARTBEAT = 120

local function sessionPath()
    return Platform.appDir() .. "/data/session.json"
end

local function heartbeatPath()
    return Platform.appDir() .. "/runtime/heartbeat"
end

local function readJson(path)
    local raw = Platform.readFile(path)
    if not raw then return nil end
    local ok, parsed = pcall(json.decode, raw)
    if ok and type(parsed) == "table" then return parsed end
    return nil
end

-- game.id is "<folder>/<file>", optionally namespaced by a library-root
-- prefix ("mmc:<folder>/<file>"); stats.json entries are keyed by <file>
local function splitId(id)
    local folderName, fileName = id:match("^([^/]+)/(.+)$")
    if folderName then
        folderName = folderName:gsub("^[^:]*:", "") -- drop the root prefix
    end
    return folderName, fileName or id
end

local function addToStats(folderPath, fileName, update)
    local path = folderPath .. "/stats.json"
    local all = readJson(path) or {}
    local entry = all[fileName] or { playSeconds = 0, playCount = 0 }
    update(entry)
    all[fileName] = entry
    Platform.writeFile(path, json.encode(all))
    return entry
end

-- Called when a game is launched: bump the folder stats and leave the
-- open-session marker for the next launcher start to close.
function Stats.recordLaunch(game)
    local _, fileName = splitId(game.id)
    addToStats(game.folder, fileName, function(entry)
        entry.playCount = (entry.playCount or 0) + 1
        entry.lastPlayed = os.time()
    end)

    Platform.mkdir(Platform.appDir() .. "/data")
    Platform.writeFile(sessionPath(),
        json.encode({ id = game.id, startedAt = os.time() }))
end

-- Called at launcher startup (and right after a synchronous desktop
-- run): closes any open session and adds the elapsed play time to the
-- game folder's stats.json.
function Stats.finishOpenSession()
    local session = readJson(sessionPath())
    if not session or not session.id or not session.startedAt then return end

    local now = os.time()
    local endTime = now
    local hbRaw = Platform.readFile(heartbeatPath())
    local hb = hbRaw and tonumber(hbRaw:match("%d+"))
    if hb and hb >= session.startedAt and (now - hb) > STALE_HEARTBEAT then
        endTime = hb -- launcher didn't come straight back; trust the heartbeat
    end
    local elapsed = math.max(0, endTime - session.startedAt)

    local folderName, fileName = splitId(session.id)
    -- The id's prefix selects which library root the folder lives in
    local rootDir = Config.rootForId(session.id)
    if folderName and rootDir then
        local entry = addToStats(rootDir .. "/" .. folderName, fileName,
            function(e) e.playSeconds = (e.playSeconds or 0) + elapsed end)
        print(string.format("[Stats] %s: +%ds played (total %ds over %d launches)",
            session.id, elapsed, entry.playSeconds, entry.playCount or 0))
    end

    os.remove(sessionPath())
    os.remove(heartbeatPath())
end

-- Stats for one game (nil when it has never been played), for display.
function Stats.forGame(game)
    local _, fileName = splitId(game.id)
    local all = readJson(game.folder .. "/stats.json")
    return all and all[fileName] or nil
end

-- Compact playtime for the UI: "2h" / "2h 15m" / "45m" / "<1m".
-- Returns nil for zero/unknown so callers can skip the line entirely.
function Stats.formatPlaytime(seconds)
    if not seconds or seconds <= 0 then return nil end
    if seconds < 60 then return "<1m" end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if h == 0 then return m .. "m" end
    if h >= 10 or m == 0 then return h .. "h" end
    return h .. "h " .. m .. "m"
end

return Stats
