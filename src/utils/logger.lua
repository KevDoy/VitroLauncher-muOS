-- Debug logger (pattern borrowed from the ClickWheel example app).
-- Appends to <app root>/debug.log - the same file mux_launch.sh writes -
-- so the shell setup and the Love2D runtime share one debugging trail.
-- Writes immediately (open/append/close) so output survives hard crashes.

local Logger = {}

local originalPrint = print
local logPath = nil

local function writeToLog(message)
    if not logPath then return end
    local f = io.open(logPath, "a")
    if f then
        f:write(message .. "\n")
        f:close()
    end
end

function Logger.init(appDir)
    logPath = appDir .. "/debug.log"

    -- Unbuffer stdout too, so anything printed also reaches the shell
    -- redirect in mux_launch.sh without getting lost in a crash.
    pcall(function() io.stdout:setvbuf("no") end)

    writeToLog("")
    writeToLog("=== Love2D started " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===")
    writeToLog("OS: " .. love.system.getOS())
    writeToLog("Love version: " .. table.concat({ love.getVersion() }, "."))
    writeToLog("App dir: " .. appDir)
    local w, h = love.graphics.getDimensions()
    writeToLog("Window: " .. w .. "x" .. h)

    -- Every print() everywhere now also lands in debug.log
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring(select(i, ...))
        end
        local message = table.concat(parts, "\t")
        originalPrint(...)
        writeToLog(os.date("[%H:%M:%S] ") .. message)
    end

    print("[Logger] Initialized, logging to " .. logPath)
end

-- Log an error with traceback, used by the error handler.
function Logger.logError(msg)
    writeToLog("")
    writeToLog("!!! ERROR " .. os.date("%Y-%m-%d %H:%M:%S"))
    writeToLog(tostring(msg))
    writeToLog(debug.traceback())
end

return Logger
