#!/bin/sh
# HELP: Vitro Launcher - tile-based home screen for your games
# ICON: vitrolauncher
# GRID: Vitro Launcher

# ---------------------------------------------------------------------
# DEBUG LOGGING - starts before anything that can fail.
# debug.log lives in the app root (next to this script) and captures
# every command this script runs plus all Love2D output.
# ---------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEBUG_LOG="$SCRIPT_DIR/debug.log"

{
    echo "=== Vitro Launcher debug log ==="
    echo "date:   $(date)"
    echo "script: $0"
    echo "dir:    $SCRIPT_DIR"
    echo "user:   $(id 2>/dev/null)"
    echo "uname:  $(uname -a 2>/dev/null)"
    echo "==============================="
} >"$DEBUG_LOG" 2>&1

# From here on, everything (stdout, stderr, command trace) goes to debug.log
exec >>"$DEBUG_LOG" 2>&1
set -x

. /opt/muos/script/var/func.sh

APP_NAME="Vitro Launcher"
ROM_MOUNT="$(GET_VAR "device" "storage/rom/mount")"

# ---------------------------------------------------------------------
# Locate the app directory across muOS versions and storage layouts
# ---------------------------------------------------------------------
APPDIR=""
for CANDIDATE in \
    "$SCRIPT_DIR" \
    "${MUOS_STORE_DIR:-/run/muos/storage}/application/$APP_NAME" \
    "${MUOS_SHARE_DIR:-/opt/muos/share}/application/$APP_NAME" \
    "$ROM_MOUNT/MUOS/application/$APP_NAME" \
    "/mnt/mmc/MUOS/application/$APP_NAME" \
    "/mnt/sdcard/MUOS/application/$APP_NAME"; do
    echo "checking candidate: $CANDIDATE"
    if [ -f "$CANDIDATE/main.lua" ]; then
        APPDIR="$CANDIDATE"
        break
    fi
done

if [ -z "$APPDIR" ]; then
    echo "FATAL: could not find app directory containing main.lua"
    exit 1
fi
echo "APPDIR resolved to: $APPDIR"

BINDIR="$APPDIR/bin"
cd "$APPDIR" || { echo "FATAL: cd $APPDIR failed"; exit 1; }

ls -la "$APPDIR"
ls -la "$BINDIR" 2>/dev/null || echo "FATAL: bin/ directory missing - Love2D binaries not installed"
ls -la "$BINDIR/libs.aarch64" 2>/dev/null | head -5

if [ ! -f "$BINDIR/love" ]; then
    echo "FATAL: $BINDIR/love does not exist"
    exit 1
fi
chmod +x "$BINDIR/love" 2>/dev/null

mkdir -p "$APPDIR/runtime" "$APPDIR/data" "$APPDIR/config"

# ---------------------------------------------------------------------
# Environment setup - muOS helpers when available (Jacaranda+),
# legacy fallback otherwise
# ---------------------------------------------------------------------
if command -v SETUP_APP >/dev/null 2>&1; then
    echo "using SETUP_APP (modern muOS)"
    # Deliberately NOT calling SETUP_STAGE_OVERLAY here: it LD_PRELOADs
    # libmustage.so (the muOS 2601+ "stage" overlay that draws the
    # volume/brightness OSD by hooking SDL_GL_SwapWindow). Its GL state
    # save/restore corrupts Love2D's cached GL state the moment the OSD
    # appears, leaving a permanent black screen. Volume keys still work
    # in the launcher - muOS just doesn't draw the indicator over it.
    # Games get the overlay as normal: the generated launch script does
    # its own SETUP_STAGE_OVERLAY.
    unset LD_PRELOAD
    SETUP_APP "love" ""
else
    echo "using legacy environment setup"
    echo app >/tmp/act_go
    command -v SETUP_SDL_ENVIRONMENT >/dev/null 2>&1 && SETUP_SDL_ENVIRONMENT
    [ -z "$SDL_GAMECONTROLLERCONFIG_FILE" ] &&
        export SDL_GAMECONTROLLERCONFIG_FILE="/usr/lib/gamecontrollerdb.txt"
    SET_VAR "SYSTEM" "FOREGROUND_PROCESS" "love" 2>/dev/null ||
        SET_VAR "system" "foreground_process" "love"
fi

# Keep Love2D's own writes (save dir) inside the app folder
export XDG_DATA_HOME="$APPDIR/data"
export LD_LIBRARY_PATH="$BINDIR/libs.aarch64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Workaround for RK3576 devices (from stock muOS app scripts)
if grep -q "rk3576" /proc/device-tree/compatible 2>/dev/null; then
    for MALI_LIBRARY in /usr/lib/libmali.so /usr/lib/aarch64-linux-gnu/libmali.so; do
        [ -e "$MALI_LIBRARY" ] && export SDL_VIDEO_EGL_DRIVER="$MALI_LIBRARY" && break
    done
    export SDL_OPENGL_ES_DRIVER=1
fi

env | sort

# gptokeyb location and binary name vary between muOS builds
GPTOKEYB=""
for G in "$ROM_MOUNT/MUOS/emulator/gptokeyb/gptokeyb2.armhf" \
    "$ROM_MOUNT/MUOS/emulator/gptokeyb/gptokeyb2" \
    "${MUOS_STORE_DIR:-/run/muos/storage}/emulator/gptokeyb/gptokeyb2.armhf" \
    "${MUOS_STORE_DIR:-/run/muos/storage}/emulator/gptokeyb/gptokeyb2" \
    "/usr/bin/gptokeyb2.armhf" \
    "/usr/bin/gptokeyb2"; do
    [ -f "$G" ] && GPTOKEYB="$G" && break
done
echo "gptokeyb: ${GPTOKEYB:-NOT FOUND}"

# ---------------------------------------------------------------------
# Launcher <-> game loop:
#   1. Run the Love2D launcher.
#   2. Picking a game writes runtime/next_launch.sh and the launcher exits.
#   3. Run that script (RetroArch or a PortMaster .sh).
#   4. When the game exits, loop back so the launcher reopens.
#   5. Exiting the launcher without picking a game (L1+X+START held)
#      breaks the loop and returns to the muOS menu.
# ---------------------------------------------------------------------
while :; do
    rm -f "$APPDIR/runtime/next_launch.sh"

    if [ -n "$GPTOKEYB" ]; then
        "$GPTOKEYB" "love" -c "$APPDIR/vitrolauncher.gptk" &
        GPTOKEYB_PID="$!"
        sleep 0.5 2>/dev/null || sleep 1
        if ! kill -0 "$GPTOKEYB_PID" 2>/dev/null; then
            echo "gptokeyb died with config, retrying without (stock style)"
            "$GPTOKEYB" "love" &
            GPTOKEYB_PID="$!"
        fi
        echo "gptokeyb running as PID $GPTOKEYB_PID"
    fi

    echo "--- launching love ---"
    "$BINDIR/love" .
    LOVE_RC=$?
    echo "--- love exited (code $LOVE_RC) ---"

    # Free the input bridge before the game grabs the controls
    [ -n "$GPTOKEYB_PID" ] && kill "$GPTOKEYB_PID" 2>/dev/null
    kill -9 $(pidof gptokeyb2) $(pidof gptokeyb2.armhf) 2>/dev/null

    # Shut Down button in the launcher UI writes this flag and quits
    if [ -f "$APPDIR/runtime/power_off" ]; then
        rm -f "$APPDIR/runtime/power_off"
        echo "--- power off requested ---"
        if [ -x /opt/muos/script/mux/quit.sh ]; then
            /opt/muos/script/mux/quit.sh poweroff frontend
        else
            sync
            poweroff
        fi
        exit 0
    fi

    if [ -f "$APPDIR/runtime/next_launch.sh" ]; then
        echo "--- running next_launch.sh ---"
        cat "$APPDIR/runtime/next_launch.sh"
        # Playtime heartbeat: stamp the epoch every 30s while the game
        # runs. If the device dies mid-game (battery, hard power-off),
        # the launcher closes the play session from the last stamp
        # instead of counting the whole off-time (see src/stats.lua).
        (while :; do date +%s >"$APPDIR/runtime/heartbeat"; sleep 30; done) &
        HEARTBEAT_PID=$!
        sh "$APPDIR/runtime/next_launch.sh"
        GAME_RC=$?
        kill "$HEARTBEAT_PID" 2>/dev/null
        date +%s >"$APPDIR/runtime/heartbeat"
        echo "--- game exited (code $GAME_RC) ---"
    else
        echo "no next_launch.sh - exiting to muOS menu"
        break
    fi
done
