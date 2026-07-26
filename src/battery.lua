-- Battery status reader.
-- Device (muOS/Linux): reads the standard sysfs power_supply interface that
--   muOS's own device configs point at, e.g.
--   /sys/class/power_supply/axp2202-battery/capacity  (0-100)
--   The supply name varies per device, so we scan for one that has both a
--   "capacity" file and a battery-ish type.
-- macOS (local testing): parses `pmset -g batt`.
-- Drawing lives in src/ui/statusbar.lua; this module only reads state.

local Platform = require("src.platform")

local Battery = {}

Battery.level = nil      -- 0-100, nil if unknown
Battery.charging = false

local capacityPath = nil
local statusPath = nil
local searched = false

local REFRESH_INTERVAL = 10
local timer = REFRESH_INTERVAL -- force a read on first update

local function readTrimmed(path)
    local data = Platform.readFile(path)
    if not data then return nil end
    return (data:gsub("%s+$", ""))
end

local function findSysfsBattery()
    searched = true
    local h = io.popen("ls -1 /sys/class/power_supply 2>/dev/null")
    if not h then
        print("[Battery] ERROR: could not list /sys/class/power_supply")
        return
    end
    local found = 0
    for name in h:lines() do
        found = found + 1
        local base = "/sys/class/power_supply/" .. name
        local cap = readTrimmed(base .. "/capacity")
        local type_ = readTrimmed(base .. "/type")
        print(string.format("[Battery] candidate: %s (type=%s, capacity=%s)",
            name, tostring(type_), tostring(cap)))
        if cap and tonumber(cap) then
            -- Prefer entries that identify as a battery; accept any
            -- capacity-bearing entry as a fallback.
            if (type_ == "Battery") or name:lower():find("battery") or not capacityPath then
                capacityPath = base .. "/capacity"
                statusPath = base .. "/status"
            end
        end
    end
    h:close()
    if capacityPath then
        print("[Battery] Using " .. capacityPath)
    elseif found == 0 then
        print("[Battery] /sys/class/power_supply is empty or unreadable")
    else
        print("[Battery] No entry with a numeric capacity found")
    end
end

local loggedFirstRead = false
local loggedReadFailure = false

local function readDevice()
    if not searched then findSysfsBattery() end
    if not capacityPath then return end

    local raw = readTrimmed(capacityPath)
    Battery.level = tonumber(raw)
    local status = statusPath and readTrimmed(statusPath)
    Battery.charging = (status == "Charging" or status == "Full")

    if not loggedFirstRead and Battery.level then
        loggedFirstRead = true
        print(string.format("[Battery] First read: %d%% (status=%s)",
            Battery.level, tostring(status)))
    end
    -- Log a read failure once (not every 10s) so the log stays readable
    if not Battery.level and not loggedReadFailure then
        loggedReadFailure = true
        print(string.format("[Battery] Read failed: capacity=%s status=%s from %s",
            tostring(raw), tostring(status), capacityPath))
    elseif Battery.level and loggedReadFailure then
        loggedReadFailure = false
        print("[Battery] Reads recovered: " .. Battery.level .. "%")
    end
end

local function readMac()
    local h = io.popen("pmset -g batt 2>/dev/null")
    if not h then return end
    local out = h:read("*a")
    h:close()
    local pct = out:match("(%d+)%%")
    Battery.level = tonumber(pct)
    Battery.charging = out:find("AC Power") ~= nil

    if not loggedFirstRead then
        loggedFirstRead = true
        print(string.format("[Battery] First read (pmset): %s%% (charging=%s)",
            tostring(Battery.level), tostring(Battery.charging)))
    end
end

function Battery.update(dt)
    timer = timer + dt
    if timer < REFRESH_INTERVAL then return end
    timer = 0

    if Platform.isMac then
        readMac()
    else
        readDevice()
    end
end

return Battery
