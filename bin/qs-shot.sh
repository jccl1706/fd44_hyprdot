#!/usr/bin/env bash
# =========================================================================
# qs-shot.sh - photograph one of the shell's panels, cropped to the panel
# =========================================================================
#
# Usage:  bin/qs-shot.sh settings            open it, shoot it, close it
#         bin/qs-shot.sh settings Display    and switch to a page first
#         bin/qs-shot.sh launcher firefox    or, for the launcher, search it
#         bin/qs-shot.sh --bar               just the bar
#         bin/qs-shot.sh --full              the whole screen
#         bin/qs-shot.sh -v settings Bar     shoot it and show it, here
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

# THE SCRIPT'S OWN LOCATION, THROUGH ANY SYMLINK. ~/.local/bin/qs-shot is a
# link to this file, and dirname of the LINK is ~/.local/bin, whose parent is
# ~/.local - so the repository was looked for in ~/.local/quickshell and the
# only symptom was a grep complaining about a path nobody wrote. readlink -f
# resolves to the real file first, which is the whole difference between a
# script that works on PATH and one that works only from its own directory.
self="$(readlink -f "${BASH_SOURCE[0]:-$0}")"
root="$(cd "$(dirname "$self")/.." && pwd)"
out_dir="${QS_SHOT_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/fd44-shots}"

c_r=$'\033[1;31m'; c_d=$'\033[2m'; c_0=$'\033[0m'
die() { printf '%sqs-shot:%s %s\n' "$c_r" "$c_0" "$*" >&2; exit 1; }

command -v qs   >/dev/null || die "quickshell (qs) is not installed"
command -v grim >/dev/null || die "grim is not installed - it is what takes the picture"

# The panels this can open, as ipc target -> the call that opens it. Only
# targets with a toggle are listed: a panel that cannot be opened from the
# outside cannot be photographed by a script either.
targets=$(grep -oE 'target: "[a-z]+"' "$root/quickshell/shell.qml" | sed 's/.*"\(.*\)"/\1/' | sort -u)

# SHOOT AND SHOW IT, in one word rather than a remembered pipeline.
#
# The composition this replaces is
#   kitten icat "$(qs-shot settings Bar 2>/dev/null)"
# which is correct, and which nobody is going to type twice. A screenshot you
# have to assemble a command to look at is one you take less often than you
# should, and the whole point of this script is to make looking cheap.
view=false
if [[ ${1:-} == -v || ${1:-} == --view ]]; then
    view=true
    shift
fi

# WHAT CAN ACTUALLY DRAW HERE, decided once. kitten draws real pixels through
# kitty's graphics protocol; chafa falls back to coloured text blocks and works
# over ssh, where the protocol does not. Neither being present is not an error -
# the path is printed either way, which is what the script did before any of
# this.
show() {
    local f="$1"
    # NOT A TERMINAL means nothing can be drawn into it: piped into a file, run
    # from an editor, or called by something that captured the output. Printing
    # escape sequences into that is how a binary blob ends up in a log.
    [[ -t 1 ]] || return 0
    if command -v kitten >/dev/null 2>&1; then
        kitten icat --align left "$f"
    elif command -v chafa >/dev/null 2>&1; then
        chafa "$f"
    else
        printf '  %s(install kitty or chafa to see it here)%s\n' "$c_d" "$c_0"
    fi
}

if [[ ${1:-} == --list ]]; then
    printf '  %s\n' $targets
    exit 0
fi

[[ $# -ge 1 ]] || die "nothing to photograph - try --list, --bar or --full"

mkdir -p "$out_dir"
stamp="$(date +%Y%m%d-%H%M%S)"

# A CALL THAT DID NOTHING LOOKS EXACTLY LIKE ONE THAT WORKED.
#
# `qs ipc call` exits 0 whether or not the function exists - a missing one
# merely prints "Function not found." on stdout. So the second argument used to
# be swallowed in silence: `qs-shot.sh launcher firefox` photographed an empty
# launcher and said nothing about having ignored the word, which is worse than
# refusing, because the picture looks like an answer.
ipc() { # target function [arg] -> dies if the function is not there
    local out
    out="$(qs ipc call "$@" 2>&1)"
    case "$out" in
        *"Function not found"*)
            die "'$1' has no '$2' - it supports: $(panel_functions "$1" | tr '\n' ' ')" ;;
        *"Target not found"*)
            die "no panel called '$1' (try --list)" ;;
    esac
    printf '%s' "$out"
}

# The ipc functions a target declares, read out of shell.qml - the same source
# --list uses for the targets themselves, so the two cannot disagree.
panel_functions() {
    awk -v t="target: \"$1\"" '
        index($0, t) { inside = 1; next }
        # THE HANDLER CLOSES AT FOUR SPACES, A FUNCTION AT EIGHT. Matching
        # eight ended the scan at the first multi-line function in the block,
        # so `settings` appeared to have only the functions declared before its
        # `search` - page is written after it - and qs-shot refused a page it
        # has always supported. It broke the moment a multi-line function was
        # added above another, which is to say immediately.
        inside && /^    }/ { exit }
        inside && match($0, /function [a-zA-Z]+/) {
            print substr($0, RSTART + 9, RLENGTH - 9)
        }' "$root/quickshell/shell.qml"
}

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
    $view && show "$path"
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

# OPEN AND CLOSE WHERE THEY EXIST, TOGGLE ONLY WHERE THEY DO NOT.
#
# `toggle` is the wrong verb for a script: it means "change state", and a
# script that does not know the current state cannot predict the result. Two
# runs in quick succession proved it - the second toggle CLOSED the panel the
# first had left open, `shot rect` answered none, and the run died with its
# explanation on stderr, which anyone piping stdout into a variable never sees.
#
# Most panels have open/close, which are idempotent and say what they mean.
# Some - claude, battery - have only toggle, so for those the state is checked
# afterwards and corrected: if nothing is open after a toggle, the toggle
# closed something, and a second one opens what was asked for.
fns="$(panel_functions "$panel")"

if grep -qx open <<<"$fns"; then
    ipc "$panel" open >/dev/null
else
    ipc "$panel" toggle >/dev/null
fi

# A panel animates in, and a photograph taken during that catches it part-grown
# and half-transparent - which looks exactly like a layout bug and is not one.
sleep 0.6

close_panel() {
    if grep -qx close <<<"$fns"; then
        qs ipc call "$panel" close >/dev/null 2>&1
    else
        qs ipc call "$panel" toggle >/dev/null 2>&1
    fi
}

# WHAT THE SECOND ARGUMENT MEANS DEPENDS ON THE PANEL, and the panel says
# which it understands. Settings has pages; the launcher has a search box and
# no pages at all. Anything else with neither refuses rather than quietly
# photographing the wrong thing.
if [[ -n $page ]]; then
    if grep -qx page <<<"$fns"; then
        ipc "$panel" page "$page" >/dev/null
    elif grep -qx query <<<"$fns"; then
        ipc "$panel" query "$page" >/dev/null
    else
        close_panel
        die "'$panel' takes no second argument - it has neither 'page' nor 'query'"
    fi
    sleep 0.4
fi

geo="$(qs ipc call shot rect 2>/dev/null)"

# The correction described above, for the toggle-only panels.
if [[ -z $geo || $geo == none ]] && ! grep -qx open <<<"$fns"; then
    ipc "$panel" toggle >/dev/null
    sleep 0.6
    geo="$(qs ipc call shot rect 2>/dev/null)"
fi

if [[ -z $geo || $geo == none ]]; then
    close_panel
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

close_panel
printf '%s  %s%s%s\n' "$path" "$c_d" "$geo" "$c_0" >&2
