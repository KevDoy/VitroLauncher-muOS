#!/bin/sh
# HELP: Vitro Launcher - stop opening automatically at boot
# ---------------------------------------------------------------------
# Disables launch-at-boot: removes vitrolauncher_boot.sh from MUOS/init/
# and cleans up the legacy frontend.sh home-takeover patch left behind
# by older versions of this project (then named Game Launcher - the
# GAMELAUNCHER marker/backup/flag names below keep the old spelling on
# purpose). Run it from a shell, or from MUOS/task/
# (Applications > Tasks).
# ---------------------------------------------------------------------

. /opt/muos/script/var/func.sh

FRONTEND_SH="/opt/muos/script/mux/frontend.sh"
BACKUP="$FRONTEND_SH.gamelauncher.bak"
MARK_BEGIN="# >>> GAMELAUNCHER-HOME >>>"
MARK_END="# <<< GAMELAUNCHER-HOME <<<"

ROM_MOUNT="$(GET_VAR "device" "storage/rom/mount")"
LOG="$ROM_MOUNT/MUOS/log/vitrolauncher_boot.log"
log() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$1" >>"$LOG"; }
: >"$LOG"

# If the legacy patched frontend.sh is somehow still live, this flag
# makes it step aside for the current session.
: >"/tmp/gamelauncher_off"
rm -f "/tmp/gamelauncher_fastexit"

# Strip the legacy home-takeover block from frontend.sh, if present
if grep -qF "$MARK_BEGIN" "$FRONTEND_SH" 2>/dev/null; then
    NEW="$FRONTEND_SH.gamelauncher.new"
    sed "/$MARK_BEGIN/,/$MARK_END/d" "$FRONTEND_SH" >"$NEW"

    if ! grep -qF "$MARK_BEGIN" "$NEW" && sh -n "$NEW" 2>>"$LOG"; then
        mv -f "$NEW" "$FRONTEND_SH"
        chmod 755 "$FRONTEND_SH"
        sync
        log "Legacy patch removed from frontend.sh"
    else
        rm -f "$NEW"
        log "ERROR: could not cleanly remove legacy patch from frontend.sh"
        if [ -f "$BACKUP" ]; then
            cp -p "$BACKUP" "$FRONTEND_SH"
            sync
            log "frontend.sh restored from backup instead"
        fi
    fi
else
    log "frontend.sh is clean - nothing to remove"
fi
rm -f "$BACKUP"

# Remove boot scripts (current and legacy names) so nothing runs at boot
for INIT_DIR in \
    "${MUOS_STORE_DIR:-/run/muos/storage}/init" \
    "$ROM_MOUNT/MUOS/init"; do
    for NAME in vitrolauncher_boot.sh gamelauncher_boot.sh gamelauncher_home_on.sh; do
        if [ -f "$INIT_DIR/$NAME" ]; then
            rm -f "$INIT_DIR/$NAME"
            log "Removed boot script: $INIT_DIR/$NAME"
        fi
    done
done

log "Done - Vitro Launcher no longer opens at boot"
exit 0
