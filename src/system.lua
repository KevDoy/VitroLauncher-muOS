-- System volume and screen brightness control.
-- Device: volume via the first ALSA simple control that amixer reports;
-- brightness through muOS's own bright.sh script and /run/muos var
-- files, so the launcher never fights the OS's settings - we only
-- write when the user changes the row.
-- Desktop: simulated in-memory so the Settings UI is testable.

local Platform = require("src.platform")

local System = {}

-- Desktop simulation state
local simVolume = 50
local simBrightness = 70

-- The Settings screen calls the getters every frame while it renders,
-- so device reads (amixer forks, /run/muos files) go through a short-
-- lived cache instead.
local CACHE_TIME = 1.0

local function runRead(cmd)
    local h = io.popen(cmd .. " 2>/dev/null")
    if not h then return nil end
    local out = h:read("*a")
    h:close()
    return out
end

-- ---------------------------------------------------------------------
-- Volume (ALSA via amixer)
-- ---------------------------------------------------------------------

local mixerCtl = nil -- control name, or false when unavailable

local function findMixer()
    if mixerCtl ~= nil then return mixerCtl end
    mixerCtl = false
    -- First simple control amixer knows about, e.g. "Simple mixer
    -- control 'Master',0". Device mixers vary (Master/Playback/SPK/...).
    local out = runRead("amixer scontrols")
    local name = (out or ""):match("Simple mixer control '([^']+)'")
    if name then
        mixerCtl = name
        print("[System] Mixer control: " .. name)
    end
    return mixerCtl
end

local volCache, volCacheAt = nil, -math.huge

function System.getVolume()
    if not Platform.isDevice then return simVolume end
    local now = love.timer.getTime()
    if now - volCacheAt < CACHE_TIME then return volCache end
    local ctl = findMixer()
    if not ctl then return nil end
    local out = runRead("amixer -M sget '" .. ctl .. "'")
    local pct = out and out:match("%[(%d+)%%%]")
    volCache = pct and tonumber(pct) or nil
    volCacheAt = now
    return volCache
end

function System.setVolume(pct)
    pct = math.max(0, math.min(100, pct))
    if not Platform.isDevice then
        simVolume = pct
        print("[System] (simulated) volume -> " .. pct .. "%")
        return
    end
    local ctl = findMixer()
    if not ctl then return end
    os.execute("amixer -M -q sset '" .. ctl .. "' " .. pct .. "% 2>/dev/null")
    volCache, volCacheAt = pct, love.timer.getTime()
end

-- ---------------------------------------------------------------------
-- Screen brightness (muOS bright.sh)
-- ---------------------------------------------------------------------
-- muOS manages brightness itself: current level lives in
-- /run/muos/config/settings/general/brightness, the device's maximum in
-- /run/muos/device/screen/bright, and /opt/muos/script/device/bright.sh
-- applies changes (handling per-device quirks like inverted panels).
-- We read the var files for display and shell out to bright.sh U / D
-- for changes, so behavior matches the OS's own MENU+VOL hotkeys.

local BRIGHT_SH = "/opt/muos/script/device/bright.sh"
-- bright.sh writes the current level as a percentage here on every
-- change (and recomputes it on demand via its "I" mode).
local PCT_FILE = "/tmp/current_brightness_percent"
-- Raw value + device maximum, fallback for muOS versions whose
-- bright.sh doesn't maintain the percent file.
local CUR_FILE = "/run/muos/config/settings/general/brightness"
local CUR_FILE_LEGACY = "/opt/muos/config/brightness.txt"
local MAX_FILE = "/run/muos/device/screen/bright"

local function readNumber(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local n = tonumber((f:read("*a") or ""):match("%-?%d+"))
    f:close()
    return n
end

local briCache, briCacheAt = nil, -math.huge

-- Returns brightness as a percentage (or nil when unavailable)
function System.getBrightness()
    if not Platform.isDevice then return simBrightness end
    local now = love.timer.getTime()
    if now - briCacheAt < CACHE_TIME then return briCache end

    local pct = readNumber(PCT_FILE)
    if not pct then
        -- Not written yet this boot: ask bright.sh to compute it once
        os.execute("sh " .. BRIGHT_SH .. " I >/dev/null 2>&1")
        pct = readNumber(PCT_FILE)
    end
    if not pct then
        local cur = readNumber(CUR_FILE) or readNumber(CUR_FILE_LEGACY)
        local max = readNumber(MAX_FILE)
        pct = (cur and max and max > 0)
            and math.floor(cur * 100 / max + 0.5) or nil
    end

    briCache = pct and math.max(0, math.min(100, pct)) or nil
    briCacheAt = now
    return briCache
end

-- delta: -1 / +1, stepping by the increment configured in muOS.
-- Never steps down to 0 - bright.sh blanks the panel at 0, which would
-- look like the device died mid-menu.
function System.changeBrightness(delta)
    if not Platform.isDevice then
        simBrightness = math.max(10, math.min(100, simBrightness + delta * 10))
        print("[System] (simulated) brightness -> " .. simBrightness .. "%")
        return
    end
    if delta < 0 then
        local cur = readNumber(CUR_FILE) or readNumber(CUR_FILE_LEGACY)
        if cur and cur <= 1 then return end
        -- No raw value readable: fall back to the percent bright.sh
        -- maintains (one default increment above zero stays safe).
        if not cur then
            local pct = readNumber(PCT_FILE)
            if pct and pct <= 10 then return end
        end
    end
    os.execute("sh " .. BRIGHT_SH .. " " .. (delta > 0 and "U" or "D")
        .. " >/dev/null 2>&1")
    briCacheAt = -math.huge -- reflect the change on the next read
end

return System
