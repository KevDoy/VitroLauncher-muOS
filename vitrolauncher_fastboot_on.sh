#!/bin/sh
# HELP: Vitro Launcher - boot straight into the launcher (fast boot)
# ---------------------------------------------------------------------
# Fast boot: the device boots directly into Vitro Launcher instead of
# starting the muOS menu first and dispatching into the launcher from
# there (which is what the MUOS/init script does, and why a few seconds
# of muOS menu show up before the launcher).
#
# How: /opt/muos/script/init/S99muos.sh starts the frontend loop with
# "FRONTEND start" (no module). frontend.sh accepts a startup module as
# $1, so replacing that one line with a marked block that seeds the app
# path into APP_GO and calls "FRONTEND start app" makes the stock
# frontend loop's FIRST action "run Vitro Launcher". Nothing in the
# loop's dispatch logic is touched: when the launcher exits
# (L1+X+START), stock frontend.sh writes "appmenu" and starts the muOS
# menu exactly as it does after any app - no takeover, no escape flags.
#
# Install: run once from a shell or from MUOS/task/ (Applications >
# Tasks) - or copy it to MUOS/init/ to run on every boot: it exits
# immediately when the current patch is already installed, and
# re-applies it automatically after muOS updates overwrite S99muos.sh
# (the boot that follows an update goes to the muOS menu once; keeping
# vitrolauncher_boot.sh in MUOS/init/ too covers even that boot).
# Undo with vitrolauncher_fastboot_off.sh.
#
# Safety: original file is backed up, the patched file must pass a
# shell syntax check (sh -n) before it replaces the original, and the
# patch is only applied when the running muOS version supports the
# frontend module argument.
#
# Logs to MUOS/log/vitrolauncher_fastboot.log.
#
# Migration: patches installed by older releases (named Game Launcher)
# used GAMELAUNCHER-FASTBOOT markers; the marker regex below matches
# both spellings so an old block is refreshed in place.
# ---------------------------------------------------------------------

[ -f /opt/muos/script/var/func.sh ] && . /opt/muos/script/var/func.sh

# Test hooks: override the system paths when exercising this script off-device
FRONTEND_SH="${GL_FRONTEND:-/opt/muos/script/mux/frontend.sh}"
FUNC_SH="${GL_FUNC:-/opt/muos/script/var/func.sh}"

# The boot script moved between muOS versions:
#   2601 (Jacaranda) - /opt/muos/script/system/startup.sh
#   later dev builds - /opt/muos/script/init/S99muos.sh
# Both start the frontend loop with a plain "FRONTEND start" line.
TARGET=""
for CAND in \
    "${GL_S99:-}" \
    "/opt/muos/script/init/S99muos.sh" \
    "/opt/muos/script/system/startup.sh"; do
    [ -n "$CAND" ] && [ -f "$CAND" ] && TARGET="$CAND" && break
done

BACKUP="$TARGET.vitrolauncher.bak"
MARK_BEGIN="# >>> VITROLAUNCHER-FASTBOOT >>>"
# Matches current markers and the GAMELAUNCHER ones from older releases
MARK_RE="(GAME|VITRO)LAUNCHER-FASTBOOT"
# Bump whenever the patch block below changes, so an already-patched
# file gets refreshed (and an up-to-date one is left untouched - this
# script is safe to run from MUOS/init/ on every boot).
PATCH_VERSION="vitrolauncher-fastboot-v3"

# Adopt the pristine backup an older Game Launcher install left behind
[ -n "$TARGET" ] && [ ! -f "$BACKUP" ] && [ -f "$TARGET.gamelauncher.bak" ] &&
    mv -f "$TARGET.gamelauncher.bak" "$BACKUP"

ROM_MOUNT="$(command -v GET_VAR >/dev/null 2>&1 && GET_VAR "device" "storage/rom/mount")"
LOG="${ROM_MOUNT:-/tmp}/MUOS/log/vitrolauncher_fastboot.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || LOG="/tmp/vitrolauncher_fastboot.log"
: >"$LOG"
log() {
    printf '%s %s\n' "$(date '+%H:%M:%S')" "$1" >>"$LOG"
    printf '%s\n' "$1"
}

fail() {
    log "ERROR: $1"
    log "Nothing was changed."
    exit 1
}

[ -n "$TARGET" ] ||
    fail "no muOS boot script found (looked for script/init/S99muos.sh and script/system/startup.sh)"

# --- fast path: current patch already installed (e.g. run from init) ----
if grep -qF "$PATCH_VERSION" "$TARGET" 2>/dev/null; then
    log "Fast boot already installed ($PATCH_VERSION) - nothing to do"
    exit 0
fi

# --- preflight: this muOS version must support the module argument ------
grep -q 'ACT="\$1"' "$FRONTEND_SH" 2>/dev/null ||
    fail "frontend.sh does not accept a startup module (older muOS?) - use vitrolauncher_boot.sh in MUOS/init/ instead"
grep -q 'frontend\.sh "\$2"' "$FUNC_SH" 2>/dev/null ||
    fail "FRONTEND helper does not pass a module through (older muOS?) - use vitrolauncher_boot.sh in MUOS/init/ instead"

# --- normalize: strip any existing fastboot block (idempotent re-run) ---
WORK="$TARGET.vitrolauncher.work"
if grep -qE "$MARK_RE" "$TARGET"; then
    log "Existing fastboot patch found - refreshing it"
    # The block records the stock line it displaced (GL_STOCK_LINE);
    # older blocks without it get the plain line back.
    awk -v re="$MARK_RE" '
        $0 ~ (re " >>>") { skip = 1; stock = "\tFRONTEND start"; next }
        skip && index($0, "GL_STOCK_LINE:") {
            stock = substr($0, index($0, "GL_STOCK_LINE:") + 14); next
        }
        $0 ~ (re " <<<") { skip = 0; print stock; next }
        !skip { print }
    ' "$TARGET" >"$WORK"
else
    cp "$TARGET" "$WORK"
fi

grep -q '^[[:space:]]*FRONTEND start[[:space:]]*$' "$WORK" || {
    rm -f "$WORK"
    fail "could not find the 'FRONTEND start' line in $TARGET (unexpected muOS version)"
}

# --- the patch block (tabs match the stock file's indentation) ----------
# GL_* variable names (incl. GL_STOCK_LINE) are kept from the Game
# Launcher era so removal works on blocks written by any version.
BLOCK="$TARGET.vitrolauncher.block"
cat >"$BLOCK" <<'EOF'
	# >>> VITROLAUNCHER-FASTBOOT >>>
	# vitrolauncher-fastboot-v3
	# Boot straight into Vitro Launcher: seed the app action so the stock
	# frontend loop's first iteration runs it instead of the muOS menu.
	# Exiting the launcher drops onto the muOS menu as normal (the loop
	# itself writes "appmenu" after any app exits). Installed by
	# vitrolauncher_fastboot_on.sh; removed by vitrolauncher_fastboot_off.sh.
	GL_APP=""
	for GL_DIR in \
		"${MUOS_STORE_DIR:-/run/muos/storage}/application/Vitro Launcher" \
		"$(GET_VAR "device" "storage/rom/mount")/MUOS/application/Vitro Launcher" \
		"/mnt/mmc/MUOS/application/Vitro Launcher" \
		"/mnt/sdcard/MUOS/application/Vitro Launcher"; do
		if [ -f "$GL_DIR/mux_launch.sh" ]; then
			GL_APP="$GL_DIR"
			break
		fi
	done
	if [ -n "$GL_APP" ]; then
		chmod +x "$GL_APP/mux_launch.sh" 2>/dev/null
		printf "%s" "$GL_APP" >"${APP_GO:-/tmp/app_go}"
		FRONTEND start app
	else
		FRONTEND start
	fi
	# <<< VITROLAUNCHER-FASTBOOT <<<
EOF

# --- splice: replace the first 'FRONTEND start' line with the block -----
NEW="$TARGET.vitrolauncher.new"
awk -v block="$BLOCK" '
    !done && $0 ~ /^[[:space:]]*FRONTEND start[[:space:]]*$/ {
        while ((getline line < block) > 0) {
            print line
            # Record the exact line we displaced, so removal (or a
            # future refresh) restores it byte-for-byte.
            if (line ~ /VITROLAUNCHER-FASTBOOT >>>/) print "\t# GL_STOCK_LINE:" $0
        }
        close(block)
        done = 1
        next
    }
    { print }
' "$WORK" >"$NEW"
rm -f "$WORK" "$BLOCK"

# --- validate before touching the live file -----------------------------
sh -n "$NEW" 2>>"$LOG" || { rm -f "$NEW"; fail "patched file failed the shell syntax check"; }
grep -qF "$MARK_BEGIN" "$NEW" || { rm -f "$NEW"; fail "patched file is missing the fastboot block"; }
grep -q 'FRONTEND start app' "$NEW" || { rm -f "$NEW"; fail "patched file is missing the fastboot dispatch"; }

# Keep the pristine original from the first install (not a patched copy)
[ -f "$BACKUP" ] || cp -p "$TARGET" "$BACKUP"

mv -f "$NEW" "$TARGET"
chmod 755 "$TARGET"
sync

log "Fast boot enabled: $TARGET now boots straight into Vitro Launcher."
log "Backup of the original saved at: $BACKUP"
log "Note: muOS updates replace this file - re-run this task afterwards."
exit 0
