#!/bin/sh
# HELP: Vitro Launcher - stop booting straight into the launcher
# ---------------------------------------------------------------------
# Removes the fast-boot patch that vitrolauncher_fastboot_on.sh applied
# to /opt/muos/script/init/S99muos.sh, restoring the stock
# "FRONTEND start" line so the device boots to the muOS menu again.
# Also removes blocks written by older releases (named Game Launcher,
# GAMELAUNCHER markers).
#
# Run from a shell, or copy to MUOS/task/ and run it from
# Applications > Tasks. Safe to run when the patch isn't installed.
#
# Logs to MUOS/log/vitrolauncher_fastboot.log.
# ---------------------------------------------------------------------

[ -f /opt/muos/script/var/func.sh ] && . /opt/muos/script/var/func.sh

# Matches current markers and the GAMELAUNCHER ones from older releases
MARK_RE="(GAME|VITRO)LAUNCHER-FASTBOOT"

# The boot script moved between muOS versions; operate on whichever
# candidate carries our patch (falling back to the first that exists).
# Test hook: GL_S99 overrides when exercising this script off-device.
TARGET=""
FIRST_FOUND=""
for CAND in \
    "${GL_S99:-}" \
    "/opt/muos/script/init/S99muos.sh" \
    "/opt/muos/script/system/startup.sh"; do
    [ -n "$CAND" ] && [ -f "$CAND" ] || continue
    [ -n "$FIRST_FOUND" ] || FIRST_FOUND="$CAND"
    if grep -qE "$MARK_RE" "$CAND"; then
        TARGET="$CAND"
        break
    fi
done
[ -n "$TARGET" ] || TARGET="$FIRST_FOUND"

BACKUP="$TARGET.vitrolauncher.bak"
# Adopt the pristine backup an older Game Launcher install left behind
[ ! -f "$BACKUP" ] && [ -f "$TARGET.gamelauncher.bak" ] &&
    mv -f "$TARGET.gamelauncher.bak" "$BACKUP"

ROM_MOUNT="$(command -v GET_VAR >/dev/null 2>&1 && GET_VAR "device" "storage/rom/mount")"
LOG="${ROM_MOUNT:-/tmp}/MUOS/log/vitrolauncher_fastboot.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || LOG="/tmp/vitrolauncher_fastboot.log"
: >"$LOG"
log() {
    printf '%s %s\n' "$(date '+%H:%M:%S')" "$1" >>"$LOG"
    printf '%s\n' "$1"
}

[ -f "$TARGET" ] || { log "$TARGET not found - nothing to do"; exit 0; }

if ! grep -qE "$MARK_RE" "$TARGET"; then
    log "No fastboot patch in $TARGET - nothing to do"
    rm -f "$BACKUP"
    exit 0
fi

# Replace the marked block with the stock line it displaced (recorded
# as GL_STOCK_LINE inside the block; older blocks get the plain line)
NEW="$TARGET.vitrolauncher.new"
awk -v re="$MARK_RE" '
    $0 ~ (re " >>>") { skip = 1; stock = "\tFRONTEND start"; next }
    skip && index($0, "GL_STOCK_LINE:") {
        stock = substr($0, index($0, "GL_STOCK_LINE:") + 14); next
    }
    $0 ~ (re " <<<") { skip = 0; print stock; next }
    !skip { print }
' "$TARGET" >"$NEW"

ok=1
grep -qE "$MARK_RE" "$NEW" && ok=0
grep -q '^[[:space:]]*FRONTEND start[[:space:]]*$' "$NEW" || ok=0
sh -n "$NEW" 2>>"$LOG" || ok=0

if [ "$ok" = "1" ]; then
    mv -f "$NEW" "$TARGET"
    chmod 755 "$TARGET"
    sync
    rm -f "$BACKUP"
    log "Fast boot disabled: $TARGET restored to stock behavior."
    exit 0
fi

rm -f "$NEW"
log "ERROR: could not cleanly remove the fastboot block"
if [ -f "$BACKUP" ]; then
    cp -p "$BACKUP" "$TARGET"
    chmod 755 "$TARGET"
    sync
    rm -f "$BACKUP"
    log "$TARGET restored from backup instead."
    exit 0
fi
log "No backup available - $TARGET was left untouched."
exit 1
