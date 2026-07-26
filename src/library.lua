-- Scans the game library roots for titles.
-- Roots are the app's games dir plus a GAME folder at the root of
-- either SD card (Config.gamesRoots()). Every immediate subfolder of a
-- root (any name) may contain an info.cfg describing one or more titles:
--   name = ...  /  system = gba  /  file = rom.gba  /  img = cover.png
-- (one [game] section per title when a folder holds several). Folders
-- with only a legacy info.json keep working.

local json = require("src.lib.json")
local Cfg = require("src.lib.cfg")
local Platform = require("src.platform")
local Config = require("src.config")

local Library = {}

local function entriesFromJson(parsed)
    -- legacy info.json may be a single object or an array of objects
    if type(parsed) ~= "table" then return {} end
    if parsed.name or parsed.file then return { parsed } end
    return parsed
end

-- info.cfg: keys before any section describe the first title; each
-- [game] section describes another one.
local function entriesFromCfg(parsed)
    local entries = {}
    if next(parsed.root) then table.insert(entries, parsed.root) end
    for _, sec in ipairs(parsed.sections) do
        table.insert(entries, sec.values)
    end
    return entries
end

-- Reads a folder's title entries from info.cfg, falling back to a
-- legacy info.json. Returns entries, sourcePath; nil when the folder
-- has neither file or it can't be parsed.
local function readEntries(folderPath)
    local cfgPath = folderPath .. "/info.cfg"
    local raw = Platform.readFile(cfgPath)
    if raw then
        local ok, parsed = pcall(Cfg.parse, raw)
        if not ok then
            print("[Library] Failed to parse " .. cfgPath .. ": " .. tostring(parsed))
            return nil
        end
        return entriesFromCfg(parsed), cfgPath
    end

    local jsonPath = folderPath .. "/info.json"
    raw = Platform.readFile(jsonPath)
    if not raw then
        print("[Library] No info.cfg in " .. folderPath .. ", skipping")
        return nil
    end
    local ok, parsed = pcall(json.decode, raw)
    if not ok then
        print("[Library] Failed to parse " .. jsonPath .. ": " .. tostring(parsed))
        return nil
    end
    return entriesFromJson(parsed), jsonPath
end

-- One library folder -> zero or more games appended to `games`.
-- idPrefix namespaces ids from extra roots ("mmc:folder/file"); the
-- primary root's prefix is "" so legacy ids stay unchanged.
local function scanFolder(games, folderPath, folder, idPrefix)
    local entries, infoPath = readEntries(folderPath)
    if not entries then return end

    -- Play stats written by src/stats.lua (may not exist yet)
    local stats = nil
    local statsRaw = Platform.readFile(folderPath .. "/stats.json")
    if statsRaw then
        local sok, sparsed = pcall(json.decode, statsRaw)
        if sok and type(sparsed) == "table" then stats = sparsed end
    end

    for i, entry in ipairs(entries) do
        if entry.file and entry.name then
            local gameStats = stats and stats[entry.file] or nil
            table.insert(games, {
                id = idPrefix .. folder .. "/" .. entry.file,
                name = entry.name,
                system = entry.system,
                folder = folderPath,
                romPath = folderPath .. "/" .. entry.file,
                imgPath = entry.img and (folderPath .. "/" .. entry.img) or nil,
                iconPath = entry.icon and (folderPath .. "/" .. entry.icon) or nil,
                bgPath = entry.bg and (folderPath .. "/" .. entry.bg) or nil,
                isScript = entry.file:match("%.sh$") ~= nil,
                playSeconds = gameStats and gameStats.playSeconds or 0,
            })
        else
            print("[Library] Skipping entry " .. i .. " in " .. infoPath .. " (missing name/file)")
        end
    end
end

-- Returns a list of games:
-- { id, name, system, romPath, imgPath, iconPath, bgPath, folder,
--   isScript, playSeconds }
-- When `yield` is given it is called after each folder, so the scan can
-- run inside a time-budgeted coroutine (see Library.startScan).
function Library.scan(yield)
    local games = {}
    for _, root in ipairs(Config.gamesRoots()) do
        local folders = Platform.listDirs(root.path)
        if #folders > 0 then
            print("[Library] Scanning " .. root.path .. " (" .. #folders .. " folder(s))")
        end
        for _, folder in ipairs(folders) do
            scanFolder(games, root.path .. "/" .. folder, folder, root.prefix)
            if yield then yield() end
        end
    end
    return games
end

-- Incremental scan for startup: returns a step function that scans a
-- few folders per call (staying within budgetSeconds) and returns the
-- finished game list once done, nil while still scanning. The waves
-- background keeps animating while the library loads.
function Library.startScan(budgetSeconds)
    local co = coroutine.create(function()
        return Library.scan(coroutine.yield)
    end)
    return function()
        local start = love.timer.getTime()
        repeat
            local ok, result = coroutine.resume(co)
            if not ok then
                error("[Library] Scan failed: " .. tostring(result), 0)
            end
            if coroutine.status(co) == "dead" then
                return result
            end
        until love.timer.getTime() - start >= (budgetSeconds or 0.008)
        return nil
    end
end

return Library
