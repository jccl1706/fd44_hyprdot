#!/usr/bin/env bash
# =========================================================================
# btrfs-scrub-setup.sh - install the monthly scrub, or take it out again
# =========================================================================
#
# Usage:  sudo bin/btrfs-scrub-setup.sh [--dry-run]
#         sudo bin/btrfs-scrub-setup.sh --remove
#
# WHAT THIS TOUCHES
#   - installs bin/btrfs-scrub.sh as /usr/local/sbin/fd44-btrfs-scrub
#   - installs systemd/system/btrfs-scrub.{service,timer} into /etc/systemd/system
#   - enables and starts btrfs-scrub.timer
#   - verifies all of it, including whether the installed copies have drifted
#
# Idempotent: run it again after moving the checkout, or to repair.
#
# OPT-IN, like bin/cooling-setup.sh and bin/chromium-policy-setup.sh, and for
# the same reason: it needs root and it is not part of what the installer
# builds. It is also pointless on a machine with no btrfs, which it says
# rather than installing a timer that would find nothing.
#
# A FIXED PATH FOR THE SCRIPT, because a system unit has no %h and root's home
# is not where the repository lives - so the ~/.config indirection the user
# units use has nothing to hang on. /usr/local/sbin is the FHS location for
# exactly this: a locally installed administrative program.
#
# COPIES, NOT SYMLINKS, WHICH IS THE OPPOSITE OF THE RULE EVERYWHERE ELSE
# HERE - and this is why. The first version of this script linked the units
# into the checkout the way bin/link-dotfiles.sh does, and `systemctl enable`
# answered "Access denied":
#
#   AVC avc: denied { read } for pid=1 comm="systemd" name="btrfs-scrub.timer"
#     scontext=system_u:system_r:init_t:s0
#     tcontext=unconfined_u:object_r:user_home_t:s0 tclass=file
#
# PID 1 is confined as init_t and cannot read a file labelled user_home_t.
# The symlink trick works for USER units because the user's own manager runs
# unconfined; it cannot work for system units on any machine with SELinux
# enforcing, and relabelling the checkout would be undone by the next
# restorecon - which btrfs-patrol's setup has good reason to run.
#
# So the unit files and the script are installed as copies, with their
# contexts restored, and `check` reports when the installed copy has drifted
# from the checkout. Re-run this script after editing either: that is the
# price of the copies, and it is stated here rather than discovered.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN=/usr/local/sbin/fd44-btrfs-scrub
UNITDIR=/etc/systemd/system

green=$'\033[1;32m'; dim=$'\033[2m'; bold=$'\033[1m'; reset=$'\033[0m'
note() { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s!!%s  %s\n' "$bold" "$reset" "$*" >&2; }

DRY=0; REMOVE=0
case "${1-}" in
    --dry-run) DRY=1 ;;
    --remove)  REMOVE=1 ;;
    "")        ;;
    *) echo "usage: $0 [--dry-run|--remove]" >&2; exit 2 ;;
esac

[[ $EUID -eq 0 ]] || { echo "btrfs-scrub-setup: run with sudo" >&2; exit 2; }

run() { if [[ $DRY -eq 1 ]]; then printf '  %swould:%s %s\n' "$dim" "$reset" "$*"; else "$@"; fi; }

if [[ $REMOVE -eq 1 ]]; then
    note "removing"
    systemctl disable --now btrfs-scrub.timer 2>/dev/null || true
    rm -f "$BIN" "$UNITDIR/btrfs-scrub.timer" "$UNITDIR/btrfs-scrub.service"
    systemctl daemon-reload
    note "gone. Snapshots (btrfs-patrol) are untouched."
    exit 0
fi

# Nothing to scrub is a reason not to install, not a thing to discover monthly.
if ! findmnt -rno FSTYPE | grep -qx btrfs; then
    warn "no mounted btrfs filesystem on this machine - not installing"
    exit 1
fi

# install(1) replaces the destination atomically, and `rm -f` first because an
# earlier version of this script left SYMLINKS there: install would otherwise
# follow one and write into the checkout.
put() {
    local src="$1" dst="$2" mode="$3"
    run rm -f "$dst"
    run install -m "$mode" -T "$src" "$dst"
    # The label matters as much as the bytes - see the header. A file created
    # under /etc or /usr/local inherits the right type here, but restorecon
    # makes that true rather than assumed.
    command -v restorecon >/dev/null 2>&1 && run restorecon -F "$dst" || true
}

note "the script"
put "$repo/bin/btrfs-scrub.sh" "$BIN" 0755

note "the units"
put "$repo/systemd/system/btrfs-scrub.service" "$UNITDIR/btrfs-scrub.service" 0644
put "$repo/systemd/system/btrfs-scrub.timer"   "$UNITDIR/btrfs-scrub.timer"   0644

note "the timer"
run systemctl daemon-reload
run systemctl enable --now btrfs-scrub.timer

if [[ $DRY -eq 1 ]]; then
    echo; note "dry run: nothing changed"
    exit 0
fi

# --- verify ------------------------------------------------------------
echo
note "checking"
ok=0
[[ -x $BIN ]] && printf '    %-34s %s\n' "$BIN" "ok" || { warn "$BIN missing"; ok=1; }
for u in btrfs-scrub.service btrfs-scrub.timer; do
    state="$(systemctl is-enabled "$u" 2>&1)"
    printf '    %-34s %s\n' "$u" "$state"
done
# COPIES DRIFT; SAY SO. This is the one thing symlinks would have given for
# free, so it is checked explicitly rather than left to be discovered when an
# edit in the checkout quietly does nothing.
for pair in "$repo/bin/btrfs-scrub.sh:$BIN" \
            "$repo/systemd/system/btrfs-scrub.service:$UNITDIR/btrfs-scrub.service" \
            "$repo/systemd/system/btrfs-scrub.timer:$UNITDIR/btrfs-scrub.timer"; do
    if ! cmp -s "${pair%%:*}" "${pair##*:}"; then
        warn "installed copy differs from the checkout: ${pair##*:} - re-run this script"
        ok=1
    fi
done

next="$(systemctl list-timers --all --no-pager --no-legend btrfs-scrub.timer 2>/dev/null | head -1)"
[[ -n $next ]] && printf '    %snext: %s%s\n' "$dim" "$next" "$reset" || { warn "timer not scheduled"; ok=1; }

echo
if [[ $ok -eq 0 ]]; then
    note "installed. First run: $(systemctl show btrfs-scrub.timer -p NextElapseUSecRealtime --value)"
    echo "    Run one now with:  sudo systemctl start btrfs-scrub.service"
    echo "    Watch it with:     journalctl -fu btrfs-scrub.service"
else
    warn "something above is not right"
    exit 1
fi
