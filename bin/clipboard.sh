#!/usr/bin/env bash
# =========================================================================
# clipboard.sh - the clipboard remembers what you copied
# =========================================================================
#
# Usage:  bin/clipboard.sh watch        start the watchers (run at login)
#         bin/clipboard.sh list         history as JSON, for the panel
#         bin/clipboard.sh copy <id>    put that entry back on the clipboard
#         bin/clipboard.sh save <id>    write it out where it belongs, print the path
#         bin/clipboard.sh save <id> <dir>  ... or into that directory
#         bin/clipboard.sh saveas <id>  ... or wherever a file dialog says
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

# WHERE A SAVED ENTRY GOES, and it is not the cache.
#
# The first version wrote to ~/.cache/fd44-clips, which is wrong in a way that
# only shows up later: a cache is something the system may clear, and these are
# files you asked to keep. They go to the XDG directories instead - an image to
# Pictures, text to Documents - so they are where you would look for them and
# where a backup already covers them.
#
# Overridable per call, because "save it HERE" is a reasonable thing to want and
# the panel should not be the only way in.
pics="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
docs="$(xdg-user-dir DOCUMENTS 2>/dev/null || echo "$HOME/Documents")"
# How many IMAGES to keep. Text keeps cliphist's default 750; images do not,
# for the reason spelled out in `watch` below. 40 full-screen captures is about
# 80MB, which is a cache and not a filing cabinet - anything worth keeping is a
# save away, and that is what the save button is for.
IMAGE_ITEMS="${FD44_CLIP_IMAGES:-40}"

# This script's own path, resolved through any symlink, so the image watcher can
# call back into it. ~/.local/bin/clipboard is a symlink to the checkout.
SELF="$(readlink -f "${BASH_SOURCE[0]}")"

CLIP_PICS="${FD44_CLIP_PICTURES:-$pics/clips}"
CLIP_DOCS="${FD44_CLIP_DOCUMENTS:-$docs/clips}"

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

    # THE IMAGE WATCHER PRUNES AFTER EVERY STORE, because cliphist cannot do
    # this itself. Its -max-items is a limit on the WHOLE DATABASE, not on the
    # watcher that passes it: measured, not assumed - storing one item with
    # -max-items 5 took a 25 entry history down to 5, text and all. So an image
    # cap expressed that way would quietly throw away the text history, which
    # is the opposite of the point.
    #
    # (It also only parses before the subcommand. `cliphist store -max-items 40`
    # is accepted in silence and does nothing at all, which is how the first
    # version of this looked like it worked.)
    #
    # A full-screen capture off this machine is about 2MB and a line of shell
    # is tens of bytes, so the two kinds cannot share a count. Text keeps
    # cliphist's own default; images are trimmed by `prune` below.
    setsid wl-paste --type text  --watch cliphist store >/dev/null 2>&1 &
    setsid wl-paste --type image --watch sh -c \
        'cliphist store; "$0" prune' "$SELF" >/dev/null 2>&1 &
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
    # PIPED, SO THE EXIT STATUS IS wl-copy's, NOT cliphist's - an entry that has
    # since been dropped would otherwise put an empty clipboard up and call it
    # a success. pipefail makes the whole pipeline fail on either.
    set -o pipefail
    printf '%s\t' "$2" | cliphist decode | wl-copy || die "could not copy entry $2"
    ;;

save)
    # save <id> [directory]
    [[ -n ${2:-} ]] || die "save needs an id"
    dest="${3:-}"
    tmpdir="$(mktemp -d)"
    tmp="$tmpdir/clip"
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
    # The directory follows the TYPE unless one was named: an image belongs in
    # Pictures and a snippet of text does not.
    if [[ -z $dest ]]; then
        case "$ext" in
            .png|.jpg|.webp|.gif) dest="$CLIP_PICS" ;;
            *)                    dest="$CLIP_DOCS" ;;
        esac
    fi
    # EVERY STEP IS CHECKED, because the failure here is not "nothing
    # happened" - it is printing a path that was never written. `mv` failing
    # left the exit status at 0 and the path on stdout, so the panel reported
    # "saved" and copied a filename that does not exist. A save that lies is
    # worse than one that refuses.
    mkdir -p "$dest" 2>/dev/null || { rm -rf "$tmpdir"; die "cannot create $dest"; }
    out="$dest/clip-$(date +%Y%m%d-%H%M%S)$ext"
    mv "$tmp" "$out" 2>/dev/null || { rm -rf "$tmpdir"; die "cannot write to $dest"; }
    rmdir "$tmpdir" 2>/dev/null
    printf '%s\n' "$out"
    ;;

saveas)
    # saveas <id> - the same as `save`, but you pick where.
    #
    # ZENITY, BECAUSE THE PORTAL IS NOT CALLABLE FROM A SHELL SCRIPT. The GNOME
    # desktop portal is running and would give the native chooser, but reaching
    # it means a D-Bus request/response dance with a reply object - not
    # something to hand-roll in bash. zenity is a few hundred kilobytes and
    # talks to that same portal.
    #
    # THE DIALOG IS PRE-FILLED with the automatic destination and a name, so
    # Enter does exactly what `save` would have done and anything else is a
    # deliberate choice. A save dialog that opens on an empty field in the home
    # directory makes you do work the script already did.
    [[ -n ${2:-} ]] || die "saveas needs an id"
    command -v zenity >/dev/null 2>&1 || die "zenity is not installed"

    tmpdir="$(mktemp -d)"; tmp="$tmpdir/clip"
    printf '%s\t' "$2" | cliphist decode > "$tmp" || die "could not decode $2"
    ext=""
    if command -v file >/dev/null 2>&1; then
        case "$(file -b --mime-type "$tmp")" in
            image/png)  ext=.png  ;; image/jpeg) ext=.jpg ;;
            image/webp) ext=.webp ;; image/gif)  ext=.gif ;;
            text/*)     ext=.txt  ;;
        esac
    fi
    case "$ext" in
        .png|.jpg|.webp|.gif) start="$CLIP_PICS" ;;
        *)                    start="$CLIP_DOCS" ;;
    esac
    mkdir -p "$start"
    suggested="$start/clip-$(date +%Y%m%d-%H%M%S)$ext"

    # 2>/dev/null because GTK writes accessibility and portal chatter to stderr
    # that has nothing to do with whether the user picked a file.
    chosen="$(zenity --file-selection --save --confirm-overwrite \
                     --title="Save clipboard entry" \
                     --filename="$suggested" 2>/dev/null)" || {
        rm -rf "$tmpdir"
        exit 1          # cancelled - not an error, and nothing is written
    }
    [[ -n $chosen ]] || { rm -rf "$tmpdir"; exit 1; }
    # Checked for the same reason as `save` above. The chooser happily lets you
    # pick a directory you cannot write to - it is only picking a name.
    mkdir -p "$(dirname "$chosen")" 2>/dev/null \
        || { rm -rf "$tmpdir"; die "cannot create $(dirname "$chosen")"; }
    mv "$tmp" "$chosen" 2>/dev/null \
        || { rm -rf "$tmpdir"; die "cannot write to $(dirname "$chosen")"; }
    rmdir "$tmpdir" 2>/dev/null
    printf '%s\n' "$chosen"
    ;;

delete)
    [[ -n ${2:-} ]] || die "delete needs an id"
    printf '%s\t' "$2" | cliphist delete
    ;;

prune)
    # Drop every image entry past the newest $IMAGE_ITEMS, leaving text alone.
    #
    # cliphist list is newest first and prints "<id>\t<preview>"; an image's
    # preview is the line "[[ binary data 2 MiB png 2256x1504 ]]", which is the
    # only way to tell the two kinds apart from the outside. `cliphist delete`
    # wants that whole line back on stdin, not the id.
    keep="${2:-$IMAGE_ITEMS}"
    n=0
    while IFS= read -r row; do
        printf '%s\n' "$row" | cliphist delete && n=$((n + 1))
    done < <(cliphist list 2>/dev/null | grep -F 'binary data' | tail -n +$((keep + 1)))
    [[ $n -gt 0 ]] && echo "clipboard: pruned $n image(s), keeping $keep"
    exit 0
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
    printf '  %-12s %s\n' images "$([ -d "$CLIP_PICS" ] && ls "$CLIP_PICS" | wc -l || echo 0) in ${CLIP_PICS/#$HOME/\~}"
    printf '  %-12s %s\n' text   "$([ -d "$CLIP_DOCS" ] && ls "$CLIP_DOCS" | wc -l || echo 0) in ${CLIP_DOCS/#$HOME/\~}"
    ;;

*)
    die "unknown command: $1"
    ;;
esac
