# Vitro Launcher

> Building your own muOS app? See [docs/BUILDING-MUOS-APPS.md](docs/BUILDING-MUOS-APPS.md),
> [docs/CONTROLS.md](docs/CONTROLS.md) and
> [docs/MUOS-SYSTEM-INTEGRATION.md](docs/MUOS-SYSTEM-INTEGRATION.md)
> for everything learned making this one.

A Love2D home-screen style game launcher for [muOS](https://muos.dev) handhelds.
Three screens on an animated background (PSP-style waves, PS5-style
drifting dust particles, pixel-art clouds, or Switch-style Simple
gray), switched with L1/R1 via the glass navigation pill at the bottom:

- **Last Played** — horizontally scrolling carousel of cover-art tiles
  (2:3 box art by default, 1:1 square optional); the focused tile grows,
  gets a white border and shows its total playtime. The most recently
  played game is always the first tile.
- **All Titles** — paged grid of game icons (cover art fallback) with
  bookmarking (Y), page skipping (X) and its own sorting options.
- **Settings** — full-page settings list (see Controls / Configuration).

Appearance is configurable via `defaults.cfg` (see below).

Targets 640x480 and 720x480, but the layout scales responsively with screen height.

## How it works

- Titles live in folders (any name) inside `GAME/`. Each folder contains an
  `info.cfg`, the rom (or a PortMaster launch script), and a preview image:

```
name = Pokemon: Fire Red
system = gba
file = Pokemon - FireRed Version (USA, Europe) (Rev 1).gba
img = default.png
icon =
bg =
```

- `system` selects the emulator (mapping lives in `defaults.cfg`; override
  per-user in `config/config.json`). If `file` ends in `.sh` it is executed
  directly (PortMaster games). Full format reference, including how to add
  PortMaster titles: [docs/GAME-LIBRARY.md](docs/GAME-LIBRARY.md).
- On device, picking a game writes `runtime/next_launch.sh` and exits; the loop
  in `mux_launch.sh` runs the game (RetroArch with the muOS global config, or
  the `.sh` script) and reopens the launcher when the game exits. Holding
  L1+X+START in the launcher exits back to the muOS menu.
- Everything the app writes stays inside the application folder:
  - `defaults.cfg` — default settings (regenerated if deleted)
  - `config/config.json` — the user's own selections
  - `data/state.json` — last-played order and bookmarks
  - `runtime/` — logs and the generated launch script

## Configuration

Settings are layered from two files in the application folder:

- **`defaults.cfg`** (app root) — the launcher's defaults, in a plain
  `key = value` format with a comment explaining every setting. Edit
  this to change out-of-the-box behavior, or ship it as part of a
  theme. Notable keys:
  - `cover_aspect` — cover tile shape: `2:3` box art (default) or
    `1:1` square
  - `rounded_corners` — `true` (default) or `false`
  - `show_titles` — show the focused game's title under its tile;
    `false` by default
  - `tooltips` — button-hint icons (L1/R1, X) across the UI; `true` by
    default (the bookmark hint on All Titles always shows)
  - `nav_autohide` — fade out the bottom navigation pill after this many
    seconds of inactivity (`0` = never, the default; Settings offers
    3/5/10)
  - `default_screen` — screen shown at startup: `recent` or `all`
  - `startup_fade` — startup fade-in (background from black, then the
    UI); `true` by default. Cover and icon textures preload during the
    fade either way, so first navigation doesn't drop frames
  - `ra_menu_exit` — exit RetroArch games by pressing MENU alone
    instead of muOS's MENU+START; `true` by default. Not shown in the
    Settings screen — set it to `false` here (or in
    `config/config.json`) to keep the stock hotkeys. Applied per
    launch via RetroArch's `--appendconfig` (nothing in muOS is
    modified), so games started from the stock muOS menu keep the
    stock hotkeys either way. Because MENU stops acting as the hotkey
    modifier, the other MENU+button hotkeys (quick menu, save/load
    state, fast forward, ...) are disabled while playing; muOS's
    automatic save-states still preserve progress on exit
  - `saves_in_game_dir` — RetroArch battery saves and save states are
    written into the game's own folder (next to the rom) instead of
    muOS's central save directory, so a game folder carries everything
    with it when copied between cards or devices; `true` by default.
    Applied per launch via `--appendconfig` like `ra_menu_exit`, so
    games started from the stock muOS menu keep saving centrally.
    Existing central saves are not moved — copy the `.srm`/state files
    into the game's folder to migrate them. Standalone emulators (PSP)
    and PortMaster titles manage their own saves and are unaffected
  - `show_playtime` — total playtime under the focused title; `true` by
    default
  - `transparency` — translucent glass pills with a frosted backdrop
    blur; `true` by default. When `false`, pills render as solid
    gray-gradient surfaces (the Simple theme grays: dark behind white
    icons, light behind dark ones) with an outline, and the blur is
    skipped
  - `recent_limit` — how many titles the Last Played carousel shows;
    `12` by default (Settings offers 4/8/12/16)
  - `all_icon_size` (`large` = 2 rows / `small` = 3 rows),
    `all_sort` (`az` / `recent` / `playtime`) and `all_bookmarks`
    (`first` / `sorted`) — All Titles grid options
  - `theme` — background theme: `waves` (default), `particles`,
    `clouds` (pixel-art clouds drifting over a bottom glow),
    `simple-dark` or `simple-light` (Switch-style flat gray
    gradients; the Color setting only shows up as the accent on
    selection borders).
    Every theme picks up `wave_color` (the Color setting) as its accent
  - `wave_color` — a `#RRGGBB` hex, or a dual-color scheme id:
    `black-blue` (SteamOS-style dark + blue accents) or `white-blue`
    (Wii-style light background; the UI text flips to dark automatically)
  - `extra_games_dirs` — additional library roots scanned and merged
    with `games_dir` (comma-separated); defaults to
    `/mnt/mmc/GAME, /mnt/sdcard/GAME`, i.e. a `GAME` folder at the root
    of either SD card. Roots that don't exist are skipped silently, so
    nothing needs configuring — just create the folder on the card
  - plus `wave_color`, `cover_size`, `infinite_scroll`, `button_layout`,
    core mappings and RetroArch paths
- **`config/config.json`** — only what the user explicitly selected (via
  the Settings panel or by hand). These always take precedence over
  `defaults.cfg`.

## Controls

| Input | Action |
| --- | --- |
| L1 / R1 | Switch screen: Last Played, All Titles, Settings |
| D-pad | Scroll through titles (grid: also up/down; right past the last column turns the page) |
| A | Launch the focused game |
| X | All Titles: skip to the next page |
| Y | All Titles: bookmark / unbookmark the focused game |
| SELECT | Jump to Settings and back |
| B | Leave Settings |
| Power button (hold 2 s) | Screen fades to black, then powers off; release early to cancel |
| Menu/guide button (hold 2 s) | Same fade-to-black shutdown |
| START + SELECT | Exit the launcher back to the muOS menu |
| L1 + X + START (hold 2 s) | Exit the launcher back to the muOS menu (with a progress bar) |

## Local testing (macOS)

Requires LÖVE (`brew install --cask love`).

```bash
./run-mac.sh        # or: love .
love . 720x480      # start at a specific size (window is resizable too)
```

On macOS the keyboard maps directly: arrow keys scroll, `A`/Enter launches
(simulated unless a local `retroarch` is installed), `9` / `0` (or `[` / `]`)
switch screens (L1/R1), `X` skips grid pages, `Y` bookmarks, `S` (or End) jumps
to Settings, `R` rescans `GAME/`, `1`/`2` snap the window to
640x480/720x480, Esc quits.

## Building for muOS

1. Copy ARM64 Love2D binaries into `bin/` (extract from an existing muOS
   Love2D app, e.g. `cp -r .examples/iPod-muOS/ClickWheel/bin .`).
2. Run `./build.sh` — produces `.dist/VitroLauncher_<version>.muxupd`.
3. Copy the `.muxupd` to the device `ARCHIVE/` folder and install via the
   muOS Archive Manager.
4. Copy your `GAME/` folders (roms, `info.cfg`, images) into
   `MUOS/application/Vitro Launcher/GAME/` on the SD card — or into a
   `GAME` folder at the root of either SD card (`/mnt/mmc/GAME`,
   `/mnt/sdcard/GAME`); all of them are scanned and shown as one
   library.

The app appears under **Applications → Vitro Launcher**; the built-in
launch loop keeps you inside this launcher between games.

### Optional: open Vitro Launcher at boot

Vitro Launcher can open automatically on top of the muOS frontend at boot:

1. Copy `vitrolauncher_boot.sh` to `MUOS/init/` on the SD card (the build
   also ships it inside the app folder on device).
2. Enable **User Init Scripts** (Configuration → Settings → Advanced).
3. Set muOS's Startup setting to Main Menu (not last/resume).
4. Reboot.

The script waits for the muOS menu to come up, then dispatches into Vitro
Launcher exactly the way selecting it in the Applications menu would. The
frontend keeps running underneath, so nothing in muOS is modified, and
the launch loop still brings the launcher back between games. Exiting the
launcher (holding L1+X+START) drops you on the normal muOS menu until
the next boot.

To disable it, delete `vitrolauncher_boot.sh` from `MUOS/init/` — or run
`vitrolauncher_boot_off.sh` (from a shell, or copy it to `MUOS/task/` and
run it from Applications → Tasks), which also cleans up the frontend
patch left behind by older versions of this project. Both scripts log to
`MUOS/log/vitrolauncher_boot.log`.

### Optional: fast boot (skip the muOS menu entirely)

The init-script route above still starts the muOS menu first and then
dispatches into Vitro Launcher, so a few seconds of muOS menu show
before the launcher appears. Fast boot removes that step: run
`vitrolauncher_fastboot_on.sh` once (from a shell, or from `MUOS/task/`
→ Applications → Tasks where available) and reboot. On muOS versions
without the Tasks folder, copy it to `MUOS/init/` instead (with User
Init Scripts enabled): it installs the patch on the first boot (taking
effect from the next one), exits instantly on every boot after that,
and automatically re-applies the patch when a muOS update reverts it.

It patches the single `FRONTEND start` line in the muOS boot script
(`/opt/muos/script/system/startup.sh` on 2601 "Jacaranda",
`/opt/muos/script/init/S99muos.sh` on newer builds — it finds
whichever exists) — the stock frontend loop is started with Vitro
Launcher as its first action instead of the menu, using muOS's own
startup-module mechanism. The loop's
dispatch logic is untouched, so exiting the launcher (holding
L1+X+START) drops onto the normal muOS menu, and games, power
off, and updates all behave exactly as stock. The original file is
backed up and the patched file must pass a syntax check before it is
installed; on muOS versions without the module mechanism the script
refuses to change anything.

Undo with `vitrolauncher_fastboot_off.sh`. Note that muOS updates
replace `S99muos.sh`, silently reverting fast boot — just re-run the
task afterwards (keeping `vitrolauncher_boot.sh` in `MUOS/init/` as a
fallback is fine; the two coexist, and the init script does nothing
when fast boot already brought the launcher up). Logs go to
`MUOS/log/vitrolauncher_fastboot.log`.

## Project layout

```
main.lua              Entry point, input handling
conf.lua              Love2D window/module config
defaults.cfg          Default settings (user selections in config/ win)
src/platform.lua      OS detection, file/shell helpers
src/config.lua        Layered config: defaults.cfg + config/config.json
src/library.lua       GAME/ folder scanner
src/state.lua         Last-played persistence, bookmarks, sorting
src/launcher.lua      RetroArch/PortMaster command builder
src/system.lua        Screen brightness / system volume control
src/ui/carousel.lua   Responsive tile carousel rendering
src/ui/theme.lua      Background theme router (waves / particles / clouds / simple)
src/ui/wave.lua       PSP-style wave background
src/ui/particles.lua  PS5-style dust particle background
src/ui/clouds.lua     Pixel-art drifting clouds background
src/ui/simple.lua     Switch-style flat gray backgrounds (dark / light)
src/ui/grid.lua       All Titles icon grid (pages, bookmarks)
src/ui/settings.lua   Settings screen
src/ui/navpill.lua    Bottom navigation pill
src/lib/cfg.lua       .cfg reader (defaults.cfg, per-game info.cfg)
src/lib/json.lua      JSON (rxi/json.lua, MIT)
mux_launch.sh         muOS launch script with game/relaunch loop
vitrolauncher.gptk    gptokeyb button mapping
vitrolauncher_boot.sh      Open-at-boot script (copy to MUOS/init)
vitrolauncher_boot_off.sh  Open-at-boot remover / legacy cleanup
vitrolauncher_fastboot_on.sh   Fast boot: boot straight into the launcher
vitrolauncher_fastboot_off.sh  Fast boot remover (restores stock boot)
build.sh              .muxupd packager
run-mac.sh            Local test runner
```

## Credits

UI icons (nav pill glyphs in `assets/images/icons/`) are from
[Google Material Symbols](https://fonts.google.com/icons), used under the
[Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).
