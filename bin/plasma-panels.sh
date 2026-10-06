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
command -v busctl >/dev/null || die "busctl is not installed (systemd)"

# THE COLORIZER SETTINGS ARE SUBSTITUTED IN, NOT PASTED IN. panels.js carries a
# placeholder; the JSON lives beside it as a file that can be read and diffed.
# It is JSON inside a JS string literal inside a D-Bus argument - two layers of
# escaping - which python does correctly and sed does not.
prepare() {
    local json="$REPO/plasma/panel-colorizer-dock.json"
    if [[ -f $json ]]; then
        python3 -c 'import json,sys
script = open(sys.argv[1]).read()
blob = json.dumps(open(sys.argv[2]).read().strip())
sys.stdout.write(script.replace(chr(34) + "@COLORIZER_SETTINGS@" + chr(34), blob))' \
            "$SCRIPT" "$json" > "$1"
    else
        sed 's/"@COLORIZER_SETTINGS@"/""/' "$SCRIPT" > "$1"
    fi
}

# busctl RATHER THAN gdbus. gdbus parses each argument as GVariant text, so a
# string has to survive that grammar on its way through - which a 12KB script
# carrying JSON full of quotes and braces does not: it fails with "expected
# value" and points at the first line, which is not where the problem is.
# busctl takes a plain string for an "s" parameter and nothing is parsed.
apply() {
    busctl --user call \
        org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript \
        s "$(cat "$1")"
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
prepared="$(mktemp)"
trap 'rm -f "$prepared" "${readback:-}"' EXIT
prepare "$prepared"
apply "$prepared" | sed 's/^/  /'

# READ IT BACK. Panel properties are assigned without complaint and then
# ignored when the value is not one this Plasma knows - "windowscover" sets
# nothing and reads back as "none". Printing what the panels actually are is
# the only way to know the layout that was asked for is the one that exists.
note "what the panels actually are now"
readback="$(mktemp)"
trap 'rm -f "$readback"' EXIT
cat > "$readback" <<'READBACK'
var out = [];
for (var i = 0; i < panels().length; i++) {
    var p = panels()[i];
    out.push(p.location + ": " + p.height + "px, hiding=" + p.hiding +
             ", align=" + p.alignment + ", length=" + p.lengthMode +
             ", floating=" + p.floating);
}
print(out.join(" / "));
READBACK
apply "$readback" | sed 's/^/  /'

note "done - bin/plasma-panels.sh --restore puts the old layout back"
