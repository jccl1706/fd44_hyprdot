#!/usr/bin/env bash
# =========================================================================
# qs-shot.sh - photograph one of the shell's panels, cropped to the panel
# =========================================================================
#
# Usage:  bin/qs-shot.sh settings            open it, shoot it, close it
#         bin/qs-shot.sh settings Display    and switch to a page first
#         bin/qs-shot.sh --bar               just the bar
#         bin/qs-shot.sh --full              the whole screen
#         bin/qs-shot.sh --list              what can be opened
#
# Writes a PNG and prints its path.
#
# WHY THIS EXISTS. bin/qs-check.sh answers "does it load", and that is all it
# can answer: overlapping text, a slider that renders at zero height, a card
# that grew past its own panel and a label truncated mid-sentence are all
# perfectly valid QML. Every one of those shipped in this repository, and each
# was found by eye afterwards rather than by the check.
#
# So the only real verification of a layout change is a photograph of it, and
# the friction was always the crop. A panel's own window is the WHOLE OUTPUT -
# DropPanel anchors to all four edges so it can place its card freely - so
# `grim` of the window gives a screenshot of the desktop with the panel
# somewhere in it, and framing the panel meant guessing X,Y WxH and re-cropping
# until it looked right. Six or seven times in the session that produced this,
# with two of the guesses cutting the thing being examined in half.
#
# The panel knows where it is. DropPanel.screenRect() maps its card to the
# screen and prints grim's own geometry format; `qs ipc call shot rect` returns
# whichever panel is currently open. This just joins them up.
#
# IT RESTORES WHAT IT FOUND. Opening a panel to photograph it closes whatever
# was open - the bar panels are mutually exclusive by design - so this closes
# what it opened afterwards rather than leaving the desktop rearranged by a
# command that was supposed to only look.

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
out_dir="${QS_SHOT_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/fd44-shots}"

c_r=$'\033[1;31m'; c_d=$'\033[2m'; c_0=$'\033[0m'
die() { printf '%sqs-shot:%s %s\n' "$c_r" "$c_0" "$*" >&2; exit 1; }

command -v qs   >/dev/null || die "quickshell (qs) is not installed"
command -v grim >/dev/null || die "grim is not installed - it is what takes the picture"

# The panels this can open, as ipc target -> the call that opens it. Only
# targets with a toggle are listed: a panel that cannot be opened from the
# outside cannot be photographed by a script either.
targets=$(grep -oE 'target: "[a-z]+"' "$root/quickshell/shell.qml" | sed 's/.*"\(.*\)"/\1/' | sort -u)

if [[ ${1:-} == --list ]]; then
    printf '  %s\n' $targets
    exit 0
fi

[[ $# -ge 1 ]] || die "nothing to photograph - try --list, --bar or --full"

mkdir -p "$out_dir"
stamp="$(date +%Y%m%d-%H%M%S)"

shoot() { # geometry name -> path
    local geo="$1" name="$2"
    # SEPARATE STATEMENTS, and not for tidiness. bash expands every word of a
    # command before performing any of its assignments, so `local a="$1"
    # b="$a"` expands $a while it is still unset - which under `set -u` is a
    # fatal "unbound variable" naming a variable that is assigned two words to
    # its left. It printed the geometry it had just worked out and then died.
    local path="$out_dir/$name-$stamp.png"
    if [[ -z $geo ]]; then
        grim "$path" >/dev/null 2>&1 || die "grim failed"
    else
        grim -g "$geo" "$path" >/dev/null 2>&1 || die "grim failed on geometry '$geo'"
    fi
    printf '%s\n' "$path"
}

case "${1}" in
    --full)
        shoot "" full
        exit 0
        ;;
    --bar)
        # ASKED, NOT MEASURED. This used to read the output's width out of the
        # first bytes of `grim -`, which broke in a way worth remembering: grim
        # is killed by SIGPIPE when the reader stops after 33 bytes, and under
        # `set -o pipefail` that failed the whole pipeline, so the `|| echo`
        # fallback ran AS WELL as the successful parse and the width came out
        # as two lines. The bar knows its own geometry, including the insets a
        # floating pill leaves at the edges, so it is simply asked.
        geo="$(qs ipc call shot bar 2>/dev/null)"
        [[ -n $geo && $geo != none ]] || die "the bar did not report a rectangle"
        shoot "$geo" bar
        exit 0
        ;;
esac

panel="$1"
page="${2:-}"

grep -qx "$panel" <<<"$targets" || die "no such panel: $panel (try --list)"

# WAS ANYTHING ALREADY OPEN. Asked before anything is touched, so the desktop
# can be put back the way it was found.
was_open="$(qs ipc call shot rect 2>/dev/null || echo none)"

qs ipc call "$panel" toggle >/dev/null 2>&1 \
    || die "$panel has no 'toggle' - it may not be a panel"

# A panel animates in, and a photograph taken during that catches it part-grown
# and half-transparent - which looks exactly like a layout bug and is not one.
sleep 0.6

[[ -n $page ]] && { qs ipc call "$panel" page "$page" >/dev/null 2>&1; sleep 0.4; }

geo="$(qs ipc call shot rect 2>/dev/null)"
if [[ -z $geo || $geo == none ]]; then
    qs ipc call "$panel" toggle >/dev/null 2>&1
    die "$panel did not report a rectangle - is it actually open?"
fi

# A few pixels of wallpaper around it, so the panel's own edge, its shadow and
# its corner radius are IN the picture. Cropped flush they cannot be checked,
# and the edge is where a panel most often goes wrong.
read -r xy wh <<<"$geo"
pad=8
geo="$(python3 -I -c '
import sys
x, y = (int(v) for v in sys.argv[1].split(","))
w, h = (int(v) for v in sys.argv[2].split("x"))
p = int(sys.argv[3])
x, y = max(0, x - p), max(0, y - p)
print(f"{x},{y} {w + 2 * p}x{h + 2 * p}")' "$xy" "$wh" "$pad")"

path="$(shoot "$geo" "${panel}${page:+-$page}")"

qs ipc call "$panel" toggle >/dev/null 2>&1
printf '%s  %s%s%s\n' "$path" "$c_d" "$geo" "$c_0" >&2
