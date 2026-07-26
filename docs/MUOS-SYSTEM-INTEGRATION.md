# muOS System Integration: volume, brightness, battery, time, power

Field notes from building Vitro Launcher, written so a person (or an
agent) can wire muOS system features into an app without re-discovering
the quirks. Every mechanism below is implemented and shipping in this
repo — each section points at the source file that proves it works.

For app packaging, the launch script, and the `.muxupd` format, see
[BUILDING-MUOS-APPS.md](BUILDING-MUOS-APPS.md). This document is about
talking to the OS once your app is running.

**The golden rule:** muOS already has a script or a var file for almost
everything. Prefer shelling out to muOS's own scripts over poking
hardware directly — they handle per-device quirks (inverted panels,
different mixers, different battery chips) that you cannot enumerate
yourself.

---

## 1. The muOS var system (read this first)

muOS exposes device- and session-state as tiny files, with shell
helpers to access them:

```sh
. /opt/muos/script/var/func.sh   # gives you GET_VAR / SET_VAR

ROM_MOUNT="$(GET_VAR "device" "storage/rom/mount")"   # e.g. /mnt/mmc
HOME="$(GET_VAR "device" "board/home")"
SET_VAR "system" "foreground_process" "retroarch"
```

- Runtime vars live under `/run/muos/` (tmpfs, rebuilt each boot):
  `/run/muos/device/...` (hardware facts), `/run/muos/config/...`
  (current settings), `/run/muos/storage` (storage root symlinks).
- `GET_VAR`/`SET_VAR` are just `cat`/`echo` over those files, so from
  a non-shell language you can **read the files directly** — that's
  what this launcher does from Lua.
- Case matters across versions: older muOS used
  `SET_VAR "SYSTEM" "FOREGROUND_PROCESS"`, newer uses lowercase. Try
  one, fall back to the other (see `src/launcher.lua`).

`foreground_process` tells muOS's watchdog what is supposed to own the
screen. Set it to your binary name (`love`, `retroarch`, `external`
for ports) or muOS may consider the process rogue.

---

## 2. Volume

**Mechanism:** plain ALSA via `amixer`. The catch is that the mixer
control name varies per device (`Master`, `Playback`, `SPK`, ...), so
never hardcode it — ask `amixer` for the first simple control:

```sh
amixer scontrols
# -> Simple mixer control 'Master',0

amixer -M sget 'Master'          # read  -> look for "[57%]"
amixer -M -q sset 'Master' 70%   # write
```

- `-M` maps volume to a human-perceived scale; without it the
  percentages don't match what muOS's own OSD shows.
- Reference implementation, including the control-name discovery and a
  1-second read cache: `src/system.lua` (`System.getVolume/setVolume`).

**Cache your reads.** `amixer` is a process fork; calling it every
frame from a settings screen will tank the UI. This repo caches reads
for 1 second and updates the cache optimistically on writes.

**Note:** the hardware volume keys keep working while your app runs —
muOS handles them globally. You only need `amixer` if your own UI
shows or changes volume.

---

## 3. Screen brightness

**Do not write to `/sys/class/backlight` yourself.** Some panels are
inverted, some devices need extra steps; muOS's script handles all of
it:

```sh
sh /opt/muos/script/device/bright.sh U   # step up (muOS's own increment)
sh /opt/muos/script/device/bright.sh D   # step down
sh /opt/muos/script/device/bright.sh I   # recompute the percent file
```

Reading the current level, in preference order:

| Path | Contains |
| --- | --- |
| `/tmp/current_brightness_percent` | Percentage, maintained by `bright.sh` (run mode `I` once if it doesn't exist yet this boot) |
| `/run/muos/config/settings/general/brightness` | Raw current value |
| `/opt/muos/config/brightness.txt` | Raw current value (legacy muOS) |
| `/run/muos/device/screen/bright` | Device maximum (divide raw by this for a %) |

Two gotchas learned the hard way (`src/system.lua`,
`System.changeBrightness`):

- **Never step down to 0.** `bright.sh` blanks the panel at 0 and the
  device looks dead mid-menu. Clamp at 1 (raw) / ~10%.
- Stepping with `U`/`D` matches the increments of muOS's own
  MENU+VOL hotkeys, so your UI and the OS agree on the levels.

---

## 4. Battery

**Mechanism:** standard Linux sysfs `power_supply` interface. The
supply name varies per device (`axp2202-battery` on many Anbernic
units, other PMICs elsewhere), so scan instead of hardcoding:

```sh
ls /sys/class/power_supply/
# for each entry:
cat /sys/class/power_supply/<name>/capacity   # 0-100
cat /sys/class/power_supply/<name>/type       # "Battery" for the right one
cat /sys/class/power_supply/<name>/status     # Charging / Discharging / Full
```

Selection rule that works in practice (`src/battery.lua`): prefer an
entry whose `type` is `Battery` or whose name contains "battery" and
which has a numeric `capacity`; otherwise accept any capacity-bearing
entry. Treat `status == "Charging"` **or** `"Full"` as "on power".

Poll on a timer (this repo uses 10 s), not every frame — each read is
a file open. Cache the found path; the scan itself only needs to run
once per app start.

---

## 5. System time

Nothing special: muOS keeps the RTC / NTP in sync, and the normal libc
path gives you local time. From Lua it's just `os.date`:

```lua
local t = os.date("*t")   -- t.hour, t.min, ...
```

(`src/ui/statusbar.lua` formats the "11:44 PM" clock this way.) The
timezone is whatever the user picked in muOS settings — don't apply
your own offsets. Unix timestamps from `os.time()` are what this repo
stores in `stats.json` (`lastPlayed`), so they survive timezone
changes.

---

## 6. Power off / quitting cleanly

To power the device off, use muOS's quit script; raw `poweroff` is the
fallback only:

```sh
if [ -x /opt/muos/script/mux/quit.sh ]; then
    /opt/muos/script/mux/quit.sh poweroff frontend
else
    sync; poweroff
fi
```

Pattern used here (`main.lua` `shutdownDevice` + `mux_launch.sh`): the
app itself never calls `poweroff` — it writes a flag file
(`runtime/power_off`) and exits; the launch shell script sees the flag
and runs the sequence above. Keeping privileged operations in the
shell wrapper keeps the app testable on desktop.

The same flag-file idea powers the game-launch loop: the app writes
`runtime/next_launch.sh` and quits, the wrapper runs it, then reopens
the app. Anything your app can't (or shouldn't) do while running —
launching a game, powering off — becomes "write a file, exit, let the
wrapper act on it".

---

## 7. Launching content (RetroArch and standalone emulators)

How muOS actually starts games, distilled from its own
`script/launch/lr-general.sh`:

```sh
. /opt/muos/script/var/func.sh
command -v SETUP_STAGE_OVERLAY >/dev/null 2>&1 && SETUP_STAGE_OVERLAY
command -v SETUP_SDL_ENVIRONMENT >/dev/null 2>&1 && SETUP_SDL_ENVIRONMENT
SET_VAR "system" "foreground_process" "retroarch"
HOME="$(GET_VAR "device" "board/home")"; export HOME

# Core dir moved between versions:
CORE_DIR="/opt/muos/share/core"
[ -d "$CORE_DIR" ] || CORE_DIR="$(GET_VAR "device" "storage/rom/mount")/MUOS/core"

RA_ARGS=""
command -v CONFIGURE_RETROARCH >/dev/null 2>&1 && RA_ARGS=$(CONFIGURE_RETROARCH)
retroarch $RA_ARGS -v -f -L "$CORE_DIR/mgba_libretro.so" "/path/rom.gba"
```

- `CONFIGURE_RETROARCH` emits the device-specific flags (config path
  etc.). Leave `$RA_ARGS` **unquoted** — muOS's own scripts do, and
  the value is multiple arguments.
- To override RetroArch settings for your launches only, append
  `--appendconfig=/tmp/yourapp_extra.cfg`. Appendconfig has the highest
  precedence and muOS ships `config_save_on_exit` off, so nothing
  leaks into the user's saved config. If `$RA_ARGS` already contains
  an `--appendconfig=`, join yours with `|`. This is how the launcher
  implements in-folder saves and MENU-to-exit — full override list in
  `src/launcher.lua` (`writeDeviceLaunchScript`).
- Keep generated config paths space-free (`/tmp/...`): unquoted
  `$RA_ARGS` splits on spaces.
- **Standalone emulators** (PSP → PPSSPP, etc.): don't reinvent their
  setup. muOS ships `ext-*` scripts that take `NAME CORE FILE`:

```sh
/opt/muos/script/launch/ext-ppsspp.sh "Game Name" ppsspp "/path/game.iso"
```

They do their own overlay/SDL/HOME work — skip your own setup lines
when using them.

---

## 8. PortMaster titles

PortMaster launch scripts are self-locating: `control.txt` derives the
SD card from **path components 2+3 of `$0`** (e.g. `/mnt/mmc/...` →
card `/mnt/mmc`). Consequences (`src/launcher.lua`):

- You cannot run a port script from an arbitrary directory — it would
  resolve a bogus card path. Find which card holds `ports/<name>/`,
  copy the script to a staging dir on that card, run the copy, delete
  it after.
- The port name is greppable from the script:
  `grep -o '\$directory/ports/[^"/]*' script.sh`.
- Run scripts with their own shebang (they're bash); BusyBox `sh`
  breaks them.
- **Clean your environment**: unset `XDG_DATA_HOME` (ports use it to
  find the PortMaster control folder), `LD_LIBRARY_PATH`, and
  `LD_PRELOAD` before executing a port, or your app's library paths
  shadow the port's bundled ones.
- Set `foreground_process` to `external` (matches muOS's own
  `ext-general.sh`).

---

## 9. Pitfalls that cost real debugging time

- **`SETUP_STAGE_OVERLAY` breaks GL apps (muOS 2601+).** It
  `LD_PRELOAD`s `libmustage.so`, which hooks `SDL_GL_SwapWindow` to
  draw the volume/brightness OSD. Its GL state save/restore corrupts
  Love2D's cached state — permanent black screen the moment the OSD
  appears. For a GL app: `unset LD_PRELOAD`, skip the overlay for your
  own process, but keep it in generated game-launch scripts so games
  get the OSD (see `mux_launch.sh`).
- **Process forks are expensive.** Every `io.popen`/`os.execute` is a
  fork on a weak ARM core. Cache reads (volume, brightness), batch
  filesystem probes (`find` once instead of `test -d` per entry — see
  `Platform.listDirs`), and poll batteries on a 10 s timer.
- **Everything BusyBox.** No GNU extensions in generated shell; test
  flags conservatively. `sleep 0.5` may not exist (`sleep 0.5 || sleep 1`).
- **Paths move between muOS versions.** Cores:
  `/opt/muos/share/core` vs `<rom mount>/MUOS/core`. Brightness raw
  value: `/run/muos/config/...` vs `/opt/muos/config/brightness.txt`.
  Storage roots: `/run/muos/storage` vs direct mounts. Always probe a
  candidate list in order (see `mux_launch.sh` for the APPDIR probe).
- **Playtime across power loss.** If you track play sessions, stamp a
  heartbeat file (`date +%s`, every 30 s) while a game runs; on the
  next start, close any open session from the last stamp instead of
  counting the whole off-time. Implemented in `mux_launch.sh` +
  `src/stats.lua`.

---

## 10. Quick reference

| Feature | Read | Write / act |
| --- | --- | --- |
| Volume | `amixer -M sget '<ctl>'` → `[NN%]` | `amixer -M -q sset '<ctl>' NN%` |
| Mixer name | `amixer scontrols` (first entry) | — |
| Brightness % | `/tmp/current_brightness_percent` (run `bright.sh I` if absent) | `bright.sh U` / `bright.sh D` |
| Brightness raw/max | `/run/muos/config/settings/general/brightness`, `/run/muos/device/screen/bright` | — |
| Battery % | `/sys/class/power_supply/<scan>/capacity` | — |
| Charging | `.../status` == `Charging` or `Full` | — |
| Time | `os.date`, `date` | muOS settings own the clock |
| Power off | — | `/opt/muos/script/mux/quit.sh poweroff frontend` |
| Device facts | `GET_VAR "device" "..."` (files under `/run/muos/device/`) | — |
| Foreground app | — | `SET_VAR "system" "foreground_process" "<name>"` |
| RetroArch flags | `CONFIGURE_RETROARCH` | append `--appendconfig=` for overrides |
| Cores dir | `/opt/muos/share/core`, else `<rom mount>/MUOS/core` | — |
