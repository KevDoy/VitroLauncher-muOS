-- Platform detection and filesystem helpers.
-- All persistent data is written inside the application folder (never /tmp,
-- never the Love2D save directory) so the app is fully self-contained on muOS.

local Platform = {}

Platform.isMac = (love.system.getOS() == "OS X")
Platform.isDevice = (love.system.getOS() == "Linux")

-- Debug: force device code paths during local testing
if os.getenv("GL_FORCE_DEVICE") == "1" then
    Platform.isDevice = true
    Platform.isMac = false
end

-- Absolute path to the application folder (works when running `love .`
-- from the app dir on device, or `love /path/to/app` locally).
function Platform.appDir()
    local src = love.filesystem.getSource()
    -- If running from a .love file, fall back to its containing directory
    if src:match("%.love$") then
        return src:match("^(.*)/[^/]+$") or "."
    end
    return src
end

local function shellEscape(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end
Platform.shellEscape = shellEscape

function Platform.readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

function Platform.writeFile(path, contents)
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(contents)
    f:close()
    return true
end

function Platform.fileExists(path)
    local f = io.open(path, "rb")
    if f then f:close() return true end
    return false
end

function Platform.mkdir(path)
    os.execute("mkdir -p " .. shellEscape(path))
end

-- List immediate subdirectories of a directory (sorted by name).
-- A single find call (BusyBox-compatible) instead of ls + a test -d
-- per entry: process spawns are expensive on-device and this runs for
-- every library folder across up to three roots.
function Platform.listDirs(path)
    local dirs = {}
    local h = io.popen("find " .. shellEscape(path) ..
        " -mindepth 1 -maxdepth 1 -type d 2>/dev/null")
    if not h then return dirs end
    for line in h:lines() do
        local name = line:match("([^/]+)/*$")
        if name then table.insert(dirs, name) end
    end
    h:close()
    table.sort(dirs)
    return dirs
end

-- Load an image from an absolute path outside the Love2D mount.
-- Mipmaps smooth out the heavy downscaling of large cover art (trilinear
-- filtering); without them distant pixels get skipped and tiles shimmer.
function Platform.loadImage(path)
    local data = Platform.readFile(path)
    if not data then return nil end
    local ok, fileData = pcall(love.filesystem.newFileData, data, path:match("[^/]+$") or "img.png")
    if not ok then return nil end

    local mipOk, img = pcall(function()
        local image = love.graphics.newImage(fileData, { mipmaps = true })
        image:setMipmapFilter("linear", 1)
        return image
    end)
    if mipOk then return img end

    -- Some GLES2 devices can't mipmap non-power-of-two textures;
    -- fall back to a plain (aliased but visible) load.
    local plainOk, plain = pcall(love.graphics.newImage, fileData)
    if plainOk then return plain end
    return nil
end

return Platform
