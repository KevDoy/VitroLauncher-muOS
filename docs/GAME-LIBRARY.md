# Game library: folder structure and info.cfg

The launcher scans its game library roots at startup and merges them
into one library:

- `GAME/` inside the app folder (`games_dir` in `defaults.cfg`);
- a `GAME` folder at the root of either SD card — `/mnt/mmc/GAME` and
  `/mnt/sdcard/GAME` (`extra_games_dirs`). Roots that don't exist are
  skipped, so nothing needs configuring: create the folder on the card
  and drop game folders in.

Every immediate subfolder of a root is one library entry. The folder
name itself doesn't matter — all metadata comes from the `info.cfg`
inside it. (Internally, titles from the card roots get an id prefix
like `mmc:`, so a folder duplicated across cards keeps separate
bookmarks and last-played state.)

The launcher also writes a `stats.json` into each folder as its titles get
played (play count, total play time in seconds, last-played timestamp,
keyed by rom file). It travels with the folder when copied to another
device and is safe to delete — counting simply restarts.

RetroArch saves live in the folder too: battery saves (`.srm`) and save
states are written next to the rom (`saves_in_game_dir` in
`defaults.cfg`, on by default), so a game folder carries its art, stats
and save data with it. Games that already have saves in muOS's central
save directory start fresh until you copy the `.srm`/state files into
the folder. Standalone emulators (PSP → PPSSPP) and PortMaster titles
keep managing their own save locations.

```
GAME/
├── CrashBandicoot/
│   ├── info.cfg
│   ├── default.png                  <- cover art
│   └── Crash Bandicoot.pbp          <- rom
├── sonicmania/
│   ├── info.cfg
│   ├── default.png
│   └── Sonic Mania.sh               <- PortMaster launch script
└── ...
```

Folders without an `info.cfg` are skipped (a note is written to
`debug.log`). Folders with only a legacy `info.json` (the pre-0.3
format) still load.

## info.cfg format

One `key = value` per line — no quotes, no escaping. Lines starting
with `#` are comments; a key left empty (`bg = `) simply means "not
set", so files can list every field:

```
name = Crash Bandicoot
system = psx
file = Crash Bandicoot.pbp
img = default.png
icon =
bg =
```

One folder usually holds one game, but a folder may declare several
titles — start each one with a `[game]` line:

```
[game]
name = Super Mario World
system = snes
file = Super Mario World.sfc
img = default.png

[game]
name = Super Mario World 2: Yoshi's Island
system = snes
file = Yoshis Island.sfc
img = yoshi.png
```

| Field | Required | Meaning |
| --- | --- | --- |
| `name` | yes | Title shown under the tile. |
| `file` | yes | Rom file or launch script, relative to the folder. |
| `system` | for roms | Selects the emulator (see below). Ignored for `.sh` files. |
| `img` | no | Cover image relative to the folder. Tiles are 2:3 box-art shaped by default (`cover_aspect` in `defaults.cfg` switches to 1:1); anything is center-cropped to fill the tile. Omit it for a placeholder tile with the game's first letter. |
| `icon` | no | Small square icon (e.g. `icon.png`). Shown on the generic loading screen when the title has no `bg`. |
| `bg` | no | Fullscreen background art (e.g. `bg.png`). When present, launching the title fades in and slowly zooms this image as the loading screen. Without it a generic loading screen (wave-colored backdrop + icon + name) is used. |

## How `file` decides the launch method

- **`.sh` file (PortMaster)** — executed directly; `system` is not used.
  See the PortMaster section below.
- **Anything else (rom)** — launched through the emulator mapped to
  `system` in `defaults.cfg`:
  - Most systems map to a RetroArch libretro core via the `[cores]`
    section (e.g. `gba = mgba_libretro.so`). Defaults cover gb, gbc, gba,
    nes, snes, megadrive/genesis, psx, n64, and arcade.
  - Systems with an `[ext_launchers.<system>]` section use a standalone
    emulator through muOS's own ext-* launch scripts (default: `psp` →
    PPSSPP).
  - Add or change mappings by editing `defaults.cfg` in the app folder on
    the device, or override them in `config/config.json` (which always wins).

## PortMaster titles

PortMaster games are split in two on the device:

- the **port data folder** (game engine, assets, saves) that PortMaster
  installs into the device's `ports/` directory, e.g. `ports/sonicmania/`;
- the **launch script** (`Sonic Mania.sh`) that PortMaster puts next to it.

To add a PortMaster title to the launcher, install the port with
PortMaster as usual, then put **a copy of just the launch script** in the
game's folder under `GAME/` — do not copy the data folder:

```
GAME/sonicmania/
├── info.cfg           <- file = Sonic Mania.sh
├── default.png
└── Sonic Mania.sh     <- copied from the device's ports/ directory
```

PortMaster scripts locate their data folder from their own file path
(path components 2+3 of `$0` pick the SD card). A script run from inside
the app folder would resolve a bogus card path, so at launch time the
generated launch script finds which card holds `ports/<port>/` and runs
a temporary copy of the script from `<card>/ports/.vitrolauncher/`
(removed after the game exits).

The rom/asset requirements of the port still apply (e.g. Render96
needs `baserom.us.z64` in `ports/render96ex/`) — set the port up so it
runs from the muOS menu first, then wire it into the launcher.

## Where things end up on the device

The build ships `GAME/` with `info.cfg` files only. Roms, covers, and
port scripts are copied manually to the SD card, into any of the
library roots:

```
MUOS/application/Vitro Launcher/GAME/<folder>/...
<SD card root>/GAME/<folder>/...
```

After changing `GAME/` contents, restart the launcher (it scans on
startup; on macOS press `R` to rescan live).

## Image sizes

Tiles display covers at roughly 200px tall, icons at ~100px, and
backgrounds fullscreen (480p), so huge source art only costs memory and
load time on device. [VitroManager](../VitroManager/README.md)
downscales images on import (covers to 480x720, icons to 160x160,
backgrounds to 960x720) and its **Optimize Images** button applies the
same budgets to an existing library in place. Hand-built folders work
with any size — oversized art is simply wasteful, and the launcher
evicts least-recently-shown textures to keep memory bounded.
