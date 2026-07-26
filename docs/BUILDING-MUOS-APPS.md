# Building a Love2D Application for muOS

A practical guide based on building this launcher (Vitro Launcher), the ClickWheel example
app, and muOS's own source (`MustardOS/internal`). Everything here was verified
against a real device or muOS's stock app scripts.

Companion docs: [CONTROLS.md](CONTROLS.md) covers input handling in
depth; [MUOS-SYSTEM-INTEGRATION.md](MUOS-SYSTEM-INTEGRATION.md) covers
talking to the OS at runtime (volume, brightness, battery, time,
power, launching RetroArch/PortMaster content).

---

## 1. The Big Picture

A muOS app is a folder containing:

| Piece | Purpose |
| --- | --- |
| `mux_launch.sh` | Entry point. muOS runs this when the user opens the app |
| `main.lua` + `conf.lua` | Your Love2D application |
| `bin/love` + `bin/libs.aarch64/` | The ARM64 Love2D runtime you bundle yourself |
| `yourapp.gptk` | Button-to-keyboard mapping for gptokeyb (see CONTROLS.md) |

muOS does not ship Love2D as a system framework — every Love2D app carries its
own binary and shared libraries. Extract them from a known-good app (the stock
Bluetooth app, ClickWheel, this project's `bin/`). Verify with:

```bash
file bin/love   # must say: ELF 64-bit ... ARM aarch64
```

The `love` binary is tiny (~10 KB); the engine itself is `libs.aarch64/liblove-11.5.so`.

---

## 2. Project Layout

```
your-app/
├── main.lua              # Love2D entry point
├── conf.lua              # window/module config
├── src/                  # your Lua modules
│   └── lib/json.lua      # bundle small libs yourself (no luarocks on device)
├── assets/               # fonts, images, sounds
├── bin/                  # ARM64 love + libs.aarch64/ (never commit to git if large)
├── mux_launch.sh         # muOS launch script
├── yourapp.gptk          # gptokeyb input mapping
├── build.sh              # packages the .muxupd
└── run-mac.sh            # local testing helper
```

## 3. conf.lua — Device-Safe Window Config

The device GPU/driver stack (Mali, KMSDRM) is picky. Rules learned the hard way:

- **MSAA 0.** Requesting MSAA can make SDL window creation fail outright.
- **Non-resizable on device.** Only enable `resizable` for desktop testing.
- `t.modules.joystick = true` is **required** — both gptokeyb and native
  gamepad input depend on it.

`conf.lua` runs before Love modules exist, so detect the platform with LuaJIT:

```lua
function love.conf(t)
    local onDesktop = jit and (jit.os == "OSX" or jit.os == "Windows")
    t.window.width = 640
    t.window.height = 480
    t.window.resizable = onDesktop
    t.window.msaa = 0
    t.modules.joystick = true
end
```

Design for 480px height and scale by `love.graphics.getHeight() / 480` so
640x480 and 720x480 devices both render correctly.

---

## 4. mux_launch.sh — The Launch Script

This is where most "app doesn't start" problems live. muOS changed
significantly at the **2508 "Jacaranda"** release, so a robust script handles
both eras.

### 4.1 Required header

```sh
#!/bin/sh
# HELP: One-line description shown in the muOS menu
# ICON: yourapp
# GRID: Your App Name
```

### 4.2 Never hardcode the app path

Depending on muOS version and which SD card the app is on, the app may live at:

- `/run/muos/storage/application/<App>` (Jacaranda bind mount)
- `/opt/muos/share/application/<App>` (stock apps)
- `<rom mount>/MUOS/application/<App>` (legacy; rom mount from `GET_VAR`)

The bulletproof approach — since muOS runs *your* script, its own directory
**is** the app directory:

```sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
```

Probe candidates and pick the one containing `main.lua` (see this repo's
`mux_launch.sh`).

### 4.3 Environment setup — use muOS helpers

Source the system functions, then let muOS set up SDL and HOME. Skipping this
is a common cause of instant crashes (missing `SDL_HQ_SCALER`, `SDL_ROTATION`,
`SDL_BLITTER_DISABLED`, controller config, unset `HOME`):

```sh
. /opt/muos/script/var/func.sh

if command -v SETUP_APP >/dev/null 2>&1; then
    # Jacaranda or newer: does act_go, HOME, foreground process, SDL env
    SETUP_APP "love" ""
else
    # Legacy fallback
    echo app >/tmp/act_go
    command -v SETUP_SDL_ENVIRONMENT >/dev/null 2>&1 && SETUP_SDL_ENVIRONMENT
    SET_VAR "SYSTEM" "FOREGROUND_PROCESS" "love"
fi

export LD_LIBRARY_PATH="$APPDIR/bin/libs.aarch64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export XDG_DATA_HOME="$APPDIR/data"   # keep Love2D's save dir inside the app
```

The second argument to `SETUP_APP` forces a control scheme: `"modern"`,
`"retro"`, or `""` (user preference).

### 4.4 RK3576 workaround

Some devices (Vita Pro etc.) need the Mali EGL driver pinned — stock muOS
apps all carry this block:

```sh
if grep -q "rk3576" /proc/device-tree/compatible 2>/dev/null; then
    for M in /usr/lib/libmali.so /usr/lib/aarch64-linux-gnu/libmali.so; do
        [ -e "$M" ] && export SDL_VIDEO_EGL_DRIVER="$M" && break
    done
    export SDL_OPENGL_ES_DRIVER=1
fi
```

### 4.5 Debug logging from line one

Make the script self-diagnosing. Before anything that can fail, redirect all
output to a log in the app root and enable command tracing:

```sh
DEBUG_LOG="$SCRIPT_DIR/debug.log"
exec >>"$DEBUG_LOG" 2>&1
set -x
```

Now every command the script runs, plus everything Love2D prints, ends up in
one file you can pull off the SD card. If `debug.log` doesn't exist after a
launch attempt, the script never ran — that points at packaging/install.

---

## 5. Filesystem Rules

| Rule | Why |
| --- | --- |
| Never write to `/tmp` | Non-persistent/inaccessible on many builds |
| Never use the Love2D default save dir | Keep everything in the app folder — set `XDG_DATA_HOME` |
| Never hardcode `/mnt/mmc` or `/mnt/sdcard` | Breaks on SD2 installs and newer layouts |
| Write runtime files to `$APPDIR/runtime`, `$APPDIR/data`, etc. | Survives updates, easy to inspect |

To read/write files outside the Love2D mount (absolute paths), use plain Lua
`io.open` — `love.filesystem` only sees the game source and save directory.
To load an image from an absolute path:

```lua
local f = io.open(path, "rb")
local data = f:read("*a"); f:close()
local img = love.graphics.newImage(love.filesystem.newFileData(data, "x.png"))
```

---

## 6. Launching Other Programs (RetroArch, PortMaster)

Don't keep Love2D running while another fullscreen program owns the display —
use the **exit-and-relaunch loop** pattern in `mux_launch.sh`:

```sh
while :; do
    rm -f "$APPDIR/runtime/next_launch.sh"
    "$BINDIR/love" .                       # app writes next_launch.sh, then quits
    if [ -f "$APPDIR/runtime/next_launch.sh" ]; then
        sh "$APPDIR/runtime/next_launch.sh"   # run the game
    else
        break                               # user exited: back to muOS menu
    fi
done
```

The generated script should mirror muOS's own libretro launcher
(`script/launch/lr-general.sh`):

```sh
. /opt/muos/script/var/func.sh
command -v SETUP_STAGE_OVERLAY >/dev/null 2>&1 && SETUP_STAGE_OVERLAY
command -v SETUP_SDL_ENVIRONMENT >/dev/null 2>&1 && SETUP_SDL_ENVIRONMENT
SET_VAR "system" "foreground_process" "retroarch"
HOME="$(GET_VAR "device" "board/home")"; export HOME
RA_ARGS=$(CONFIGURE_RETROARCH)   # device resolution + controls cfg
retroarch $RA_ARGS -v -f -L "/opt/muos/share/core/<core>.so" "/path/to/rom"
```

Cores live at `/opt/muos/share/core/` on current muOS
(`<rom mount>/MUOS/core/` on older builds). The `retroarch` binary is on
`PATH` at `/usr/bin/retroarch`. PortMaster games are just `.sh` scripts — run
them directly.

Kill gptokeyb before the game starts (it would double-drive RetroArch's
input) and restart it when your app comes back.

---

## 7. Packaging (.muxupd)

A `.muxupd` is an **uncompressed** zip (`zip -0`) that mirrors the root
filesystem:

```
YourApp.muxupd
├── mnt/mmc/MUOS/application/Your App/     <- entire app folder
└── opt/muos/default/MUOS/theme/active/glyph/muxapp/yourapp.png
```

Critical details:

- `zip -0qr` — store method only; Archive Manager expects no compression.
- `chmod +x` the launch script and `bin/love` before zipping.
- Strip macOS junk or it ships: `find .build \( -name ".DS_Store" -o -name "._*" \) -delete`
- Install by copying to the SD card's `ARCHIVE/` folder → muOS Archive Manager.

See `build.sh` in this repo for a complete, working example.

---

## 8. Local Development (macOS)

- `brew install --cask love`, then `love .` from the app folder.
- Gate device-only behavior on `love.system.getOS()` (`"OS X"` vs `"Linux"`),
  and add an env override (e.g. `GL_FORCE_DEVICE=1`) so you can exercise the
  device code path locally — e.g. verifying the generated launch script.
- Simulate: log the would-be RetroArch command instead of running it.
- Automate screenshots for visual verification: `love.graphics.captureScreenshot`
  triggered by an env var, then inspect the PNG.

## 9. Debugging Checklist

1. **No `debug.log`?** `mux_launch.sh` never ran — bad archive structure,
   wrong install location, missing exec bit.
2. **Log stops before "launching love"?** Path or binary problem — the log
   shows every candidate checked and the `bin/` listing.
3. **Love exits immediately?** SDL/video failure — check the env dump in the
   log; usually missing `SETUP_SDL_ENVIRONMENT` or bad window flags (MSAA).
4. **Lua crash?** The traceback is in the log; also override
   `love.errorhandler` to write it explicitly.
5. **App runs, controls dead?** See [CONTROLS.md](CONTROLS.md) — check the
   `[Input]` lines in the log.
