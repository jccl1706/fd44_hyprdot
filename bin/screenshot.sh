#!/usr/bin/env bash
# =========================================================================
# screenshot.sh - take one, keep it, and say so
# =========================================================================
#
# Usage:  bin/screenshot.sh region    drag a rectangle
#         bin/screenshot.sh screen    the focused output, whole
#         bin/screenshot.sh window    the focused window, cropped to it
#         bin/screenshot.sh draw      a region, straight into the annotator
#         bin/screenshot.sh edit [f]  annotate a file, or the last shot taken
#
# THE OLD BINDS WERE FIRE AND FORGET. `grim -g "$(slurp)" - | wl-copy` put an
# image on the clipboard and said nothing whatever, so there was no way to tell
# a capture from a missed one except by pasting somewhere and looking. Two of
# the three threw the file away entirely; the third wrote a file and never named
# it. This keeps every shot, puts it on the clipboard as well, and shows you
# what it caught.
#
# BOTH, NOT EITHER. A screenshot you only put on the clipboard is gone the
# moment you copy anything else, and one you only write to disk is a file you
# then have to go and find. Doing both costs a few hundred kilobytes and means
# neither habit is wrong.
#
# THE NOTIFICATION CARRIES THE IMAGE because a screenshot is the one thing a
# toast can show rather than describe: "Screenshot saved" tells you nothing
# about whether slurp caught the right rectangle, and a thumbnail tells you at
# a glance. Clicking it opens the file - the default action, which is the one
# the shell's notification service invokes on a click.

set -euo pipefail

DIR="${FD44_SHOTS:-$HOME/Pictures/Screenshots}"
APP="Screenshot"

die() { printf 'screenshot: %s\n' "$*" >&2; exit 1; }

note() {
    # -h string:image-path: is what makes the toast show the capture itself
    # rather than a generic icon. -i is set to the same file for daemons that
    # read only that; this one reads the hint.
    #
    # DETACHED AND WAITING, because -A makes notify-send block until the toast
    # is clicked or expires, printing the chosen action. The bind would
    # otherwise sit there for the life of the notification. setsid rather than
    # a bare & so it survives this script exiting.
    #
    # `default` IS THE ACTION A CLICK INVOKES - the shell's notification service
    # looks for exactly that identifier - so the whole card is the button and
    # there is nothing extra to aim at.
    local f="$1"; shift
    setsid -f bash -c '
        chosen="$(notify-send -a "$1" -i "$2" -h "string:image-path:$2" \
                              -A default=Open -p "${@:3}")" || exit 0
        [[ $chosen == default ]] && exec xdg-open "$2"
    ' bash "$APP" "$f" "$@" >/dev/null 2>&1
}

mode="${1:-region}"
mkdir -p "$DIR" || die "cannot create $DIR"
out="$DIR/Screenshot-$(date +%Y%m%d-%H%M%S).png"

case "$mode" in
region)
    # slurp WRITES THE SELECTION TO STDOUT AND EXITS 1 WHEN CANCELLED, which is
    # the user pressing Escape rather than anything going wrong - so it leaves
    # quietly, with no file and no notification.
    geo="$(slurp 2>/dev/null)" || exit 0
    [[ -n $geo ]] || exit 0
    grim -g "$geo" "$out" || die "grim failed on $geo"
    ;;
screen)
    # -o NAMES THE OUTPUT, and without it grim composites every monitor into one
    # image - which on a laptop plus an external is a picture of neither.
    o="$(niri msg --json focused-output 2>/dev/null \
         | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["name"])' 2>/dev/null)" || o=""
    if [[ -n $o ]]; then grim -o "$o" "$out"; else grim "$out"; fi
    ;;
window)
    # niri gives the focused window's geometry in LOGICAL coordinates, which is
    # the same space grim -g expects. See niri/outputs.kdl: anything handed
    # physical pixels here captures nothing at all.
    geo="$(niri msg --json focused-window 2>/dev/null | python3 -I -c '
import json, sys
w = json.load(sys.stdin)
l = w.get("layout") or {}
pos, size = l.get("pos_in_scrolling_layout"), l.get("window_size")
if not (pos and size): raise SystemExit(1)
print(f"{int(pos[0])},{int(pos[1])} {int(size[0])}x{int(size[1])}")' 2>/dev/null)" \
        || die "no focused window"
    [[ -n $geo ]] || die "no focused window"
    grim -g "$geo" "$out" || die "grim failed on $geo"
    ;;
draw|edit)
    # STRAIGHT INTO swappy, WITHOUT SAVING FIRST. `draw` is for when you already
    # know you are going to mark the thing up - a plain capture followed by
    # opening it is two steps and leaves an unannotated file behind that you
    # then have to decide about.
    #
    # swappy writes the result itself, with Ctrl+S, into the directory
    # swappy/config names - the same one as everything here - so this script
    # does not name the output and does not notify. The window IS the feedback.
    command -v swappy >/dev/null 2>&1 || die "swappy is not installed"
    rm -f "$out"                     # no plain copy is kept for these

    if [[ $mode == edit ]]; then
        # With no argument, the most recent shot: "annotate what I just took"
        # is the thing you actually want after looking at the toast.
        src="${2:-$(ls -t "$DIR"/*.png 2>/dev/null | head -1)}"
        [[ -n $src && -f $src ]] || die "nothing to edit in $DIR"
        exec swappy -f "$src"
    fi

    geo="$(slurp 2>/dev/null)" || exit 0
    [[ -n $geo ]] || exit 0
    # grim TO A PIPE AND swappy FROM ONE, so the unannotated capture never
    # reaches the disk at all.
    exec sh -c 'grim -g "$1" - | swappy -f -' sh "$geo"
    ;;
*)
    die "unknown mode: $mode (region, screen, window, draw, edit)"
    ;;
esac

[[ -s $out ]] || die "capture produced nothing"

# The clipboard copy is backgrounded and detached: wl-copy must stay alive to
# serve the selection, so waiting for it here would hang the bind for as long as
# the image is on the clipboard.
( wl-copy --type image/png < "$out" & ) 2>/dev/null

size="$(du -h "$out" | cut -f1)"
# THE DIMENSIONS COME OUT OF THE PNG HEADER, not from ImageMagick, which is
# not installed here and would be a 100MB dependency for two integers. A PNG's
# width and height are big-endian at bytes 16..24, right after the signature
# and the IHDR length and tag.
dim="$(python3 -I -c '
import struct, sys
with open(sys.argv[1], "rb") as f:
    h = f.read(24)
if len(h) == 24 and h[:8] == b"\x89PNG\r\n\x1a\n":
    print("%dx%d" % struct.unpack(">II", h[16:24]))' "$out" 2>/dev/null || echo "")"
note "$out" "Screenshot saved" "${dim:+$dim · }$size · copied"
printf '%s\n' "$out"
