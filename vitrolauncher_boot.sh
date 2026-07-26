#!/bin/sh
# HELP: Vitro Launcher - open automatically at boot
# ---------------------------------------------------------------------
# Launches Vitro Launcher on top of the muOS frontend at boot.
#
# Install:
#   1. Copy this file to MUOS/init/ on the SD card.
#   2. Enable "User Init Scripts" (Configuration > Settings > Advanced).
#   3. Set muOS's Startup setting to Main Menu (not last/resume).
#   4. Reboot.
# Disable: delete this file from MUOS/init/.
#
# How it works: exactly what the muOS menu does when you select an app -
# write the app path to $APP_GO and "app" to $ACT_GO, then end the menu
# binary. The frontend loop reads the action and runs our mux_launch.sh,
# whose internal loop keeps the launcher coming back between games.
# Exiting the launcher (L1+X+START held) drops you on
# the normal muOS menu until next boot.
#
# Migration: earlier versions of this project (named Game Launcher)
# patched /opt/muos/script/mux/frontend.sh to fully replace the home
# screen. That approach is retired; if the patch is found it is removed
# here. The GAMELAUNCHER marker/backup names below are those legacy
# artifacts - they keep the old spelling on purpose.
#
# Logs to MUOS/log/vitrolauncher_boot.log.
# ---------------------------------------------------------------------

. /opt/muos/script/var/func.sh

APP_NAME="Vitro Launcher"
FRONTEND_SH="/opt/muos/script/mux/frontend.sh"
BACKUP="$FRONTEND_SH.gamelauncher.bak"
MARK_BEGIN="# >>> GAMELAUNCHER-HOME >>>"
MARK_END="# <<< GAMELAUNCHER-HOME <<<"

LOG="$(GET_VAR "device" "storage/rom/mount")/MUOS/log/vitrolauncher_boot.log"
log() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$1" >>"$LOG"; }
: >"$LOG"

# --- remove the legacy home-takeover patch, if present ------------------
if grep -qF "$MARK_BEGIN" "$FRONTEND_SH" 2>/dev/null; then
    NEW="$FRONTEND_SH.gamelauncher.new"
    sed "/$MARK_BEGIN/,/$MARK_END/d" "$FRONTEND_SH" >"$NEW"
    if ! grep -qF "$MARK_BEGIN" "$NEW" && sh -n "$NEW" 2>>"$LOG"; then
        mv -f "$NEW" "$FRONTEND_SH"
        chmod 755 "$FRONTEND_SH"
        sync
        log "Removed legacy home-takeover patch from frontend.sh"
    else
        rm -f "$NEW"
        log "WARNING: failed to remove legacy patch from frontend.sh"
    fi
fi
rm -f "$BACKUP" /tmp/gamelauncher_fastexit

# --- locate the app across storage layouts ------------------------------
APPDIR=""
for CANDIDATE in \
    "${MUOS_STORE_DIR:-/run/muos/storage}/application/$APP_NAME" \
    "$(GET_VAR "device" "storage/rom/mount")/MUOS/application/$APP_NAME" \
    "/mnt/mmc/MUOS/application/$APP_NAME" \
    "/mnt/sdcard/MUOS/application/$APP_NAME"; do
    if [ -f "$CANDIDATE/mux_launch.sh" ]; then
        APPDIR="$CANDIDATE"
        break
    fi
done

if [ -z "$APPDIR" ]; then
    log "$APP_NAME not found - nothing to do"
    exit 1
fi
log "Found app at: $APPDIR"
chmod +x "$APPDIR/mux_launch.sh" 2>/dev/null

# --- dispatch into the launcher once the menu is up ----------------------
if pgrep -x love >/dev/null 2>&1; then
    log "Launcher already running - nothing to do"
    exit 0
fi

TRIES=0
until pgrep -x muxfrontend >/dev/null 2>&1 || pgrep -x muxlaunch >/dev/null 2>&1; do
    if pgrep -x love >/dev/null 2>&1; then
        log "Launcher came up on its own - nothing to do"
        exit 0
    fi
    TRIES=$((TRIES + 1))
    if [ "$TRIES" -ge 600 ]; then
        log "Menu never appeared - giving up"
        exit 1
    fi
    sleep 0.1 2>/dev/null || sleep 1
done
log "Menu is up"
# Brief settle so the menu binary is past its startup before we kill it.
# The frontend loop re-reads ACT_GO every iteration, so this can be tiny.
sleep 0.1 2>/dev/null || sleep 1

# Queue the app launch, exactly like the menu does on selection
printf "%s" "$APPDIR" >"${APP_GO:-/tmp/app_go}"
printf "app" >"${ACT_GO:-/tmp/act_go}"
sync
log "Queued app action"

# Unblock EXEC_MUX's post-exit wait, then end ONLY the menu binary.
# The frontend loop reads our action and runs the app.
: >"${SAFE_QUIT:-/tmp/safe_quit}"
killall -q muxfrontend muxlaunch 2>/dev/null
log "Menu stopped - frontend loop should now start $APP_NAME"

exit 0
