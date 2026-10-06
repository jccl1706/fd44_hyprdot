#!/usr/bin/env bash
# =========================================================================
# plasma-panels.sh - the top bar and dock, applied to a running Plasma
# =========================================================================
#
# Usage:  bin/plasma-panels.sh [--go]
#         bin/plasma-panels.sh --restore   put back the panels as they were
#
# REPLACES EVERY PANEL, so it takes a copy of the current layout first. The
# copy is plasma-org.kde.plasma.desktop-appletsrc, which is the only record of
# a layout that was arranged by hand.
#
# DRY BY DEFAULT, like everything else here that changes a machine.
set -euo pipefail

green=$'\033[1;32m'; red=$'\033[1;31m'; bold=$'\033[1m'; reset=$'\033[0m'
note() { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s!!%s  %s\n' "$bold" "$reset" "$*" >&2; }
die()  { printf '%spanels:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/plasma/panels.js"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-org.kde.plasma.desktop-appletsrc"
BACKUP="$CONFIG.before-fd44-panels"

(( EUID == 0 )) && die "run this as yourself - it configures a session, not a system"
[[ -f $SCRIPT ]] || die "missing $SCRIPT"

# gdbus RATHER THAN qdbus, because qdbus is not installed on a Fedora KDE spin
# built from packages rather than a group - and gdbus comes with glib, which
# everything pulls in.
command -v gdbus >/dev/null || die "gdbus is not installed (glib2)"

apply() {
    gdbus call --session \
        --dest org.kde.plasmashell \
        --object-path /PlasmaShell \
        --method org.kde.PlasmaShell.evaluateScript \
        "$(cat "$1")"
}

if [[ ${1-} == --restore ]]; then
    [[ -f $BACKUP ]] || die "no backup at $BACKUP"
    cp -p "$BACKUP" "$CONFIG"
    note "restored $CONFIG - log out and back in, or restart plasmashell"
    exit 0
fi

if [[ ${1-} != --go ]]; then
    note "would back up $CONFIG"
    note "would apply $SCRIPT to the running plasmashell:"
    grep -E '^\s*(top|dock)\.(location|height|hiding)|addWidget' "$SCRIPT" |
        sed 's/^\s*/    /'
    warn "DRY RUN. Re-run with --go."
    exit 0
fi

cp -p "$CONFIG" "$BACKUP"
note "backed up to $(basename "$BACKUP")"
note "applying"
apply "$SCRIPT" | sed 's/^/  /'
note "done - bin/plasma-panels.sh --restore puts the old layout back"
