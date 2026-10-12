#!/usr/bin/env bash
# =========================================================================
# clipboard.sh - the clipboard remembers what you copied
# =========================================================================
#
# Usage:  bin/clipboard.sh watch        start the watchers (run at login)
#         bin/clipboard.sh list         history as JSON, for the panel
#         bin/clipboard.sh copy <id>    put that entry back on the clipboard
#         bin/clipboard.sh save <id>    write that entry to a file, print the path
#         bin/clipboard.sh delete <id>  forget one entry
#         bin/clipboard.sh wipe         forget everything
#         bin/clipboard.sh status       what is running and how much is stored
#
# THE STORE IS cliphist, NOT SOMETHING WRITTEN HERE. It is packaged by Fedora,
# handles images as well as text, deduplicates, and caps itself at 750 entries.
# A clipboard manager is a boring problem that someone has already solved, and
# the interesting part - showing it and getting an image out of it - is what
# this and the panel add.
#
# TWO WATCHERS, NOT ONE. wl-paste --watch only follows the type it was asked
# for: `--type text` misses images entirely and no `--type` at all misses text
# on some clients. cliphist's own README runs both, and so does this.
#
# IMAGES ARE WHY THIS EXISTS. Pasting a screenshot into something that wants a
# file is the friction that started it: the clipboard had the image and nothing
# could reach it. `save` writes the entry out and prints the path, which is the
# thing a terminal actually needs.

set -uo pipefail

SHOTS="${XDG_CACHE_HOME:-$HOME/.cache}/fd44-clips"

die() { printf 'clipboard: %s\n' "$*" >&2; exit 1; }
command -v cliphist >/dev/null 2>&1 || die "cliphist is not installed (sudo dnf install cliphist)"

case "${1:-status}" in

watch)
    command -v wl-paste >/dev/null 2>&1 || die "wl-paste is not installed"
    # Already watching? Count only real wl-paste processes - matching the
    # pattern with pgrep catches this script's own command line, which has
    # bitten every version of this check written today.
    n=$(ps -eo comm --no-headers | grep -cx wl-paste)
    (( n >= 2 )) && { echo "clipboard: already watching"; exit 0; }
    pkill -x wl-paste 2>/dev/null
    setsid wl-paste --type text --watch cliphist store >/dev/null 2>&1 &
    setsid wl-paste --type image --watch cliphist store >/dev/null 2>&1 &
    sleep 1
    echo "clipboard: watching text and images"
    ;;

list)
    # JSON for the panel. cliphist list is "<id>\t<preview>", and the preview
    # for an image is a line like "[[ binary data 31 KiB png 1920x1080 ]]".
    cliphist list 2>/dev/null | python3 -I -c '
import json, re, sys
out = []
for line in sys.stdin:
    line = line.rstrip("\n")
    if "\t" not in line:
        continue
    cid, preview = line.split("\t", 1)
    m = re.match(r"\[\[\s*binary data (.+?)\s*\]\]", preview)
    out.append({
        "id": cid,
        "kind": "image" if m else "text",
        # The panel shows this; for an image it is the size and dimensions,
        # which is the only useful thing to say about bytes.
        "preview": (m.group(1) if m else preview)[:200],
    })
json.dump(out, sys.stdout)
'
    ;;

copy)
    [[ -n ${2:-} ]] || die "copy needs an id"
    # decode writes the ORIGINAL bytes, so an image goes back as an image.
    printf '%s\t' "$2" | cliphist decode | wl-copy
    ;;

save)
    [[ -n ${2:-} ]] || die "save needs an id"
    mkdir -p "$SHOTS"
    tmp="$(mktemp "$SHOTS/clip-XXXXXX")"
    printf '%s\t' "$2" | cliphist decode > "$tmp" || die "could not decode $2"
    # NAMED BY WHAT IT TURNED OUT TO BE, not by what was guessed beforehand.
    # `file` is installed here now; without it the extension is left off rather
    # than being wrong, because a .png that is not a PNG is worse than no suffix.
    ext=""
    if command -v file >/dev/null 2>&1; then
        case "$(file -b --mime-type "$tmp")" in
            image/png)  ext=.png  ;; image/jpeg) ext=.jpg ;;
            image/webp) ext=.webp ;; image/gif)  ext=.gif ;;
            text/*)     ext=.txt  ;;
        esac
    fi
    out="$SHOTS/clip-$(date +%Y%m%d-%H%M%S)$ext"
    mv "$tmp" "$out"
    printf '%s\n' "$out"
    ;;

delete)
    [[ -n ${2:-} ]] || die "delete needs an id"
    printf '%s\t' "$2" | cliphist delete
    ;;

wipe)
    cliphist wipe
    echo "clipboard: history cleared"
    ;;

status)
    n=$(ps -eo comm --no-headers | grep -cx wl-paste)
    printf '  %-12s %s\n' watching "$([ "$n" -ge 2 ] && echo yes || echo "no ($n of 2 watchers)")"
    printf '  %-12s %s\n' entries "$(cliphist list 2>/dev/null | wc -l)"
    db=~/.cache/cliphist/db
    printf '  %-12s %s\n' store "$([ -f "$db" ] && du -h "$db" | cut -f1 || echo empty)"
    printf '  %-12s %s\n' saved "$([ -d "$SHOTS" ] && ls "$SHOTS" | wc -l || echo 0) file(s) in ${SHOTS/#$HOME/\~}"
    ;;

*)
    die "unknown command: $1"
    ;;
esac
