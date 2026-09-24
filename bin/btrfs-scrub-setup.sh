#!/usr/bin/env bash
# =========================================================================
# btrfs-scrub-setup.sh - install the monthly scrub, or take it out again
# =========================================================================
#
# Usage:  sudo bin/btrfs-scrub-setup.sh [--dry-run]
#         sudo bin/btrfs-scrub-setup.sh --remove
#
# WHAT THIS TOUCHES
#   - symlinks bin/btrfs-scrub.sh to /usr/local/sbin/fd44-btrfs-scrub
#   - links systemd/system/btrfs-scrub.{service,timer} into /etc/systemd/system
#   - enables and starts btrfs-scrub.timer
#   - verifies all of it
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
# THE UNITS ARE LINKED, NOT COPIED, so editing them in the checkout is enough
# and `git status` keeps telling the truth about what the machine runs - the
# same rule bin/link-dotfiles.sh follows. `systemctl enable` on an absolute
# path is systemd's own supported way to do that.
#
# The cost, written down because it is real: those links point into /home. If
# /home were ever not mounted, systemd would see a dangling unit and say so on
# daemon-reload. For a monthly maintenance timer that is a warning, not a
# broken boot - but it is why the units carry no ordering that anything else
# depends on.

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

note "the script"
run ln -sfn "$repo/bin/btrfs-scrub.sh" "$BIN"
# Inside the guard: printed unconditionally, a dry run reported a symlink it
# had not made, which is the one thing a dry run must never do.
#
# An `if` and not `[[ ... ]] && printf`, which under `set -e` would exit the
# whole script the moment the test was false - that is, on every dry run.
if [[ $DRY -eq 0 ]]; then
    printf '    %s%s -> %s%s\n' "$dim" "$BIN" "$repo/bin/btrfs-scrub.sh" "$reset"
fi

note "the units"
run systemctl link -f "$repo/systemd/system/btrfs-scrub.service"
run systemctl link -f "$repo/systemd/system/btrfs-scrub.timer"

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
