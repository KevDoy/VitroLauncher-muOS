-- Launcher configuration, layered from two files:
--
--   <appdir>/defaults.cfg       - shipped defaults in a hand-editable
--                                 key = value format with comments.
--                                 Users (or themes) can edit this to
--                                 change the launcher's out-of-the-box
--                                 behavior. (A legacy defaults.json is
--                                 still honored when no .cfg exists.)
--   <appdir>/config/config.json - only the settings the user explicitly
--                                 selected (via the Settings panel or by
--                                 hand). Always wins over defaults.cfg.
--
-- Effective values = built-in DEFAULTS <- defaults.cfg <- config.json.

local json = require("src.lib.json")
local Cfg = require("src.lib.cfg")
local Platform = require("src.platform")

local Config = {}

local DEFAULTS = {
    -- Directory that holds one folder per title, each with an info.cfg.
    -- Relative paths are resolved against the application folder.
    games_dir = "GAME",

    -- Additional game library roots, scanned and merged with games_dir.
    -- Defaults cover a GAME folder at the root of either SD card, so
    -- game folders can live on the cards instead of inside the app.
    -- Roots that don't exist are skipped silently. Each root gets a
    -- short prefix (derived from its path) that namespaces its game ids
    -- so same-named folders on different cards don't share bookmarks or
    -- last-played state.
    extra_games_dirs = { "/mnt/mmc/GAME", "/mnt/sdcard/GAME" },

    -- Background wave color (hex). Classic PSP blue by default.
    wave_color = "#2245cc",

    -- Wrap the carousel around: left of the first title is the last one.
    infinite_scroll = false,

    -- Display-only: how button prompts are labelled in the UI.
    -- "retro" shows A/B, "modern" shows X/O (Cross/Circle).
    -- Functionality never changes - muOS always reports A and B.
    button_layout = "retro",

    -- Background theme: "waves" or "particles". Every theme uses the
    -- wave_color selection as its accent color.
    theme = "waves",

    -- Show button-hint icons (L1/R1 next to the nav pill, etc.).
    -- The bookmark hint on the All Titles screen is always shown.
    tooltips = true,

    -- Fade out the bottom navigation pill after this many seconds of
    -- inactivity (0 = never hide). Any input brings it back.
    nav_autohide = 0,

    -- Screen shown when the launcher starts: "recent" or "all".
    default_screen = "recent",

    -- Startup fade-in: background fades in from black, then the UI.
    -- Cover/icon textures preload behind it either way.
    startup_fade = true,

    -- Exit RetroArch games by pressing MENU alone instead of muOS's
    -- MENU+START. Applied only to games launched from this launcher
    -- (via --appendconfig, nothing in muOS is modified). The MENU
    -- button stops acting as the hotkey modifier, so the other stock
    -- hotkeys (MENU+X menu, MENU+L2/R2 state load/save, ...) are
    -- disabled with it. muOS auto save-states preserve progress.
    -- Not in the Settings screen; set it here or in config/config.json.
    ra_menu_exit = true,

    -- Write RetroArch battery saves and save states into the game's own
    -- folder (next to the rom) instead of muOS's central save directory,
    -- so a game folder carries everything - art, stats, saves - when
    -- copied between cards or devices. Applied only to games launched
    -- from this launcher (via --appendconfig, nothing in muOS is
    -- modified). Games launched from the muOS menu keep using the
    -- central location; existing central saves are not moved, copy the
    -- .srm/state files into the folder to migrate them. Standalone
    -- emulators (PSP) and PortMaster titles manage their own saves and
    -- are unaffected. Not in the Settings screen.
    saves_in_game_dir = true,

    -- Show total playtime under the selected title.
    show_playtime = true,

    -- Translucent glass pills with backdrop blur. When off, pills render
    -- as solid gray-gradient surfaces (dark behind white icons, light
    -- behind dark ones) with an outline, and the blur is skipped.
    transparency = true,

    -- How many titles the Last Played carousel shows (4/8/12/16).
    recent_limit = 12,

    -- All Titles screen: icon grid size ("large" = 2 rows, "small" = 3),
    -- sort order ("az" or "recent"), bookmark placement ("first" or "sorted").
    all_icon_size = "small",
    all_sort = "az",
    all_bookmarks = "first",

    -- Game cover tile size: "small", "medium" or "large".
    -- ("default" is accepted as a legacy alias for "medium".)
    cover_size = "large",

    -- Cover tile aspect ratio (width:height): "2:3" box art or "1:1" square.
    cover_aspect = "2:3",

    -- Rounded corners on cover tiles.
    rounded_corners = true,

    -- Show the focused game's title below its tile.
    show_titles = false,

    -- RetroArch invocation on muOS.
    -- cores_dir "auto" resolves on-device: /opt/muos/share/core on current
    -- muOS, falling back to <rom mount>/MUOS/core on older builds. Set an
    -- absolute path here to override.
    retroarch_bin = "retroarch",
    retroarch_args = "-v -f",
    cores_dir = "auto",

    -- Systems that muOS runs via a standalone emulator instead of a
    -- libretro core. The script receives (NAME, CORE, FILE) like muOS's
    -- own content launcher passes.
    ext_launchers = {
        psp = { script = "/opt/muos/script/launch/ext-ppsspp.sh", core = "ppsspp" },
    },

    -- Map info.cfg "system" -> libretro core filename
    cores = {
        gb = "gambatte_libretro.so",
        gbc = "gambatte_libretro.so",
        gba = "mgba_libretro.so",
        nes = "fceumm_libretro.so",
        snes = "snes9x_libretro.so",
        megadrive = "genesis_plus_gx_libretro.so",
        genesis = "genesis_plus_gx_libretro.so",
        psx = "pcsx_rearmed_libretro.so",
        n64 = "mupen64plus_next_libretro.so",
        arcade = "fbneo_libretro.so",
    },
}

-- Shipped defaults.cfg, regenerated when the file is missing. Keep it
-- in sync with the DEFAULTS table above (values and keys must match).
local DEFAULTS_CFG = [[
# Vitro Launcher default settings.
#
# Settings are layered: built-in defaults  <  this file  <  config/config.json
# (config/config.json holds only what you pick in the Settings screen
# and always wins over this file.)
#
# Lines starting with # are comments. Leave a value empty to keep the
# built-in default. Delete this file and the launcher regenerates it.

# Directory that holds one folder per title, each with an info.cfg.
# Relative paths are resolved against the application folder.
games_dir = GAME

# Additional game library roots, scanned and merged with games_dir
# (comma-separated). Defaults cover a GAME folder at the root of either
# SD card, so game folders can live on the cards instead of inside the
# app. Roots that don't exist are skipped silently. Set to "none" to
# scan games_dir only.
extra_games_dirs = /mnt/mmc/GAME, /mnt/sdcard/GAME

# Accent color: a #RRGGBB hex (classic PSP blue by default), or a
# dual-color scheme id: black-blue (SteamOS-style dark + blue accents)
# or white-blue (Wii-style light background, dark text).
wave_color = #2245cc

# Background theme: waves, particles, clouds, simple-dark or
# simple-light. Every theme uses wave_color as its accent.
theme = waves

# Wrap the carousel around: left of the first title is the last one.
infinite_scroll = false

# Display-only: how button prompts are labelled in the UI.
# retro shows A/B, modern shows X/O (Cross/Circle).
# Functionality never changes - muOS always reports A and B.
button_layout = retro

# Show button-hint icons (L1/R1 next to the nav pill, etc.).
# The bookmark hint on the All Titles screen is always shown.
tooltips = true

# Fade out the bottom navigation pill after this many seconds of
# inactivity (0 = never hide). Any input brings it back.
nav_autohide = 0

# Screen shown when the launcher starts: recent or all.
default_screen = recent

# Startup fade-in: background fades in from black, then the UI.
startup_fade = true

# Exit RetroArch games by pressing MENU alone instead of muOS's
# MENU+START. Applied only to games launched from this launcher (via
# --appendconfig, nothing in muOS is modified). The MENU button stops
# acting as the hotkey modifier, so the other stock hotkeys (MENU+X
# menu, MENU+L2/R2 state load/save, ...) are disabled with it. muOS
# auto save-states preserve progress. Not in the Settings screen.
ra_menu_exit = true

# Write RetroArch battery saves and save states into the game's own
# folder (next to the rom) instead of muOS's central save directory,
# so a game folder carries everything - art, stats, saves - when
# copied between cards or devices. Applied only to games launched from
# this launcher. Existing central saves are not moved; copy the
# .srm/state files into the folder to migrate them. Standalone
# emulators (PSP) and PortMaster titles manage their own saves and are
# unaffected. Not in the Settings screen.
saves_in_game_dir = true

# Show total playtime under the selected title.
show_playtime = true

# Translucent glass pills with backdrop blur. When off, pills render
# as solid gray-gradient surfaces with an outline, and the blur is
# skipped.
transparency = true

# How many titles the Last Played carousel shows (4/8/12/16).
recent_limit = 12

# All Titles screen: icon grid size (large = 2 rows, small = 3), sort
# order (az, recent or playtime), bookmark placement (first or sorted).
all_icon_size = small
all_sort = az
all_bookmarks = first

# Game cover tile size: small, medium or large.
cover_size = large

# Cover tile aspect ratio (width:height): 2:3 box art or 1:1 square.
cover_aspect = 2:3

# Rounded corners on cover tiles.
rounded_corners = true

# Show the focused game's title below its tile.
show_titles = false

# RetroArch invocation on muOS.
# cores_dir "auto" resolves on-device: /opt/muos/share/core on current
# muOS, falling back to <rom mount>/MUOS/core on older builds. Set an
# absolute path to override.
retroarch_bin = retroarch
retroarch_args = -v -f
cores_dir = auto

# Map info.cfg "system" -> libretro core filename.
[cores]
gb = gambatte_libretro.so
gbc = gambatte_libretro.so
gba = mgba_libretro.so
nes = fceumm_libretro.so
snes = snes9x_libretro.so
megadrive = genesis_plus_gx_libretro.so
genesis = genesis_plus_gx_libretro.so
psx = pcsx_rearmed_libretro.so
n64 = mupen64plus_next_libretro.so
arcade = fbneo_libretro.so

# Systems that muOS runs via a standalone emulator instead of a
# libretro core. One [ext_launchers.<system>] section per system; the
# script receives (NAME, CORE, FILE) like muOS's own content launcher.
[ext_launchers.psp]
script = /opt/muos/script/launch/ext-ppsspp.sh
core = ppsspp
]]

Config.values = nil   -- effective config (defaults + user selections)
Config.defaults = nil -- built-in DEFAULTS merged with defaults.cfg
Config.user = nil     -- only what the user selected (config/config.json)

local function deepMerge(base, override)
    local out = {}
    for k, v in pairs(base) do out[k] = v end
    for k, v in pairs(override or {}) do
        if type(v) == "table" and type(base[k]) == "table" then
            out[k] = deepMerge(base[k], v)
        else
            out[k] = v
        end
    end
    return out
end

local function readJson(path)
    local raw = Platform.readFile(path)
    if not raw then return nil end
    local ok, parsed = pcall(json.decode, raw)
    if ok and type(parsed) == "table" then
        return parsed
    end
    print("[Config] Failed to parse " .. path .. ", ignoring: " .. tostring(parsed))
    return nil
end

-- Everything in a .cfg file parses as a string; coerce each value to
-- the type of the built-in default it overrides ("true" -> boolean,
-- "12" -> number, comma-separated -> list). Unknown keys (extra core
-- mappings, ...) stay strings. Values that don't convert are dropped
-- so the built-in default holds.
local function coerce(value, ref)
    if type(value) == "table" then
        local out = {}
        for k, v in pairs(value) do
            -- explicit if: "and/or" would turn a false reference into nil
            local childRef = nil
            if type(ref) == "table" then childRef = ref[k] end
            out[k] = coerce(v, childRef)
        end
        return out
    end
    if type(ref) == "boolean" then
        if value == "true" then return true end
        if value == "false" then return false end
        return nil
    elseif type(ref) == "number" then
        return tonumber(value)
    elseif type(ref) == "table" then
        if ref[1] ~= nil or next(ref) == nil then
            -- list default: comma-separated value ("none" = empty list)
            local list = {}
            if value:lower() ~= "none" then
                for item in value:gmatch("[^,]+") do
                    item = item:match("^%s*(.-)%s*$")
                    if item ~= "" then table.insert(list, item) end
                end
            end
            return list
        end
        return nil -- plain value where a section was expected
    end
    return value
end

local function readCfg(path, refs)
    local raw = Platform.readFile(path)
    if not raw then return nil end
    local ok, parsed = pcall(Cfg.parse, raw)
    if not ok then
        print("[Config] Failed to parse " .. path .. ", ignoring: " .. tostring(parsed))
        return nil
    end
    return coerce(Cfg.toTable(parsed), refs)
end

function Config.load()
    local appDir = Platform.appDir()

    -- Shipped defaults. defaults.cfg is the editable, commented file;
    -- a legacy defaults.json is honored when no .cfg exists. The .cfg
    -- is regenerated if neither file is present, so there is always a
    -- file to edit; never overwritten once present.
    local defaultsPath = appDir .. "/defaults.cfg"
    local legacyPath = appDir .. "/defaults.json"
    local fileDefaults = readCfg(defaultsPath, DEFAULTS) or readJson(legacyPath)
    if not Platform.fileExists(defaultsPath) and not Platform.fileExists(legacyPath) then
        Platform.writeFile(defaultsPath, DEFAULTS_CFG)
        print("[Config] Wrote default settings to " .. defaultsPath)
    end
    Config.defaults = deepMerge(DEFAULTS, fileDefaults or {})

    -- User selections: only keys the user actually chose live here, so
    -- everything else keeps following defaults.cfg.
    local userPath = appDir .. "/config/config.json"
    Config.user = readJson(userPath) or {}
    if not Platform.fileExists(userPath) then
        Platform.mkdir(appDir .. "/config")
        Platform.writeFile(userPath, "{}\n")
    end

    Config.values = deepMerge(Config.defaults, Config.user)

    -- Legacy aliases from older configs
    local layoutAliases = { nintendo = "retro", playstation = "modern" }
    Config.values.button_layout = layoutAliases[Config.values.button_layout]
        or Config.values.button_layout

    return Config.values
end

-- Effective default for a key (built-ins overlaid with defaults.cfg)
function Config.defaultFor(key)
    return Config.defaults[key]
end

-- Record a user selection and persist it. Selections always take
-- precedence over defaults.cfg.
function Config.set(key, value)
    Config.user[key] = value
    Config.values[key] = value
    Config.save()
end

-- Drop the user's selections for these keys so defaults apply again.
function Config.reset(keys)
    for _, key in ipairs(keys) do
        Config.user[key] = nil
        Config.values[key] = Config.defaults[key]
    end
    Config.save()
end

-- Persist the user's selections (config/config.json only)
function Config.save()
    local appDir = Platform.appDir()
    Platform.mkdir(appDir .. "/config")
    Platform.writeFile(appDir .. "/config/config.json", json.encode(Config.user))
end

function Config.gamesDir()
    local dir = Config.values.games_dir
    if not dir:match("^/") then
        dir = Platform.appDir() .. "/" .. dir
    end
    return dir
end

-- Library roots to scan: games_dir plus extra_games_dirs, as a list of
-- { path, prefix }. The primary root's prefix is "" so its game ids
-- stay in the legacy "<folder>/<file>" form (existing bookmarks and
-- last-played history keep working). Extra roots get "<name>:" derived
-- from the path's parent directory (/mnt/mmc/GAME -> "mmc:"), which
-- namespaces their ids so same-named folders on different cards don't
-- share state.
function Config.gamesRoots()
    local roots = { { path = Config.gamesDir(), prefix = "" } }
    local seen = { [""] = true }
    for _, dir in ipairs(Config.values.extra_games_dirs or {}) do
        if dir ~= roots[1].path then
            local name = dir:match("([^/]+)/[^/]+/*$") or "root"
            local prefix, n = name .. ":", 2
            while seen[prefix] do
                prefix = name .. n .. ":"
                n = n + 1
            end
            seen[prefix] = true
            table.insert(roots, { path = dir, prefix = prefix })
        end
    end
    return roots
end

-- Root path for a game id's prefix ("mmc:mario64/rom.z64" -> the mmc
-- root path; unprefixed ids -> the primary games dir). nil when the
-- prefix doesn't match any configured root anymore.
function Config.rootForId(id)
    local prefix = id:match("^([^/:]*:)") or ""
    for _, root in ipairs(Config.gamesRoots()) do
        if root.prefix == prefix then return root.path end
    end
    return nil
end

function Config.coreForSystem(system)
    if not system then return nil end
    return Config.values.cores[system:lower()]
end

function Config.extLauncherForSystem(system)
    if not system then return nil end
    return Config.values.ext_launchers[system:lower()]
end

return Config
