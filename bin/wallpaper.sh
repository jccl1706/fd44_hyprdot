#!/usr/bin/env bash
#
# Remember the wallpaper, and make the picker's previews.
#
#   wallpaper.sh set <path>   use this wallpaper (it fades in straight away)
#   wallpaper.sh restore      make sure one is chosen - run at every login
#   wallpaper.sh current      print the current path, if any
#   wallpaper.sh thumbs       generate missing or outdated previews
#   wallpaper.sh thumbdir     print where the previews are, if there are any
#
# QUICKSHELL DRAWS THE WALLPAPER (quickshell/Wallpaper.qml). There is no
# wallpaper daemon to talk to. This script only records the choice, in
# ~/.local/state/wallpaper, and quickshell watches that file - so writing it is
# what changes the wallpaper, from the picker and from a terminal alike.
#
# The state file lives in ~/.local/state, NOT in this repository: every click in
# the picker would otherwise leave the working tree dirty.

set -euo pipefail

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}"
state_file="$state_dir/wallpaper"
src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../wallpapers" 2>/dev/null && pwd || true)"

# Where the picker reads its previews from.
#
# NOT the wallpapers themselves. Those are 2560px wide, and eleven of them is
# ~38 megapixels for the picker to decode before it can show anything - which
# is a visible pause on a keypress no matter where the work is scheduled.
# Thumbnails at 960px are ~6 MP for the whole set, and 960 still exceeds the
# ~832 physical pixels the expanded tile occupies, so nothing looks softer.
#
# In the cache directory, not the repo: they are derived files, they would
# double the repo's binary weight, and they can be regenerated at any time.
thumb_dir="${XDG_CACHE_HOME:-$HOME/.cache}/fd44-hyprdot/wallpapers"
thumb_width=960

die() { printf 'wallpaper: %s\n' "$*" >&2; exit 1; }

# Written in place rather than renamed over: quickshell's watcher follows the
# file, and an empty read caught mid-write is ignored on that side.
record() {
    mkdir -p "$state_dir"
    printf '%s\n' "$1" > "$state_file"
}

case "${1:-}" in
    set)
        [[ $# -ge 2 ]] || die "usage: wallpaper.sh set <path>"
        want="$2"

        # A PREVIEW's path is mapped back to its original by basename: previews
        # live in the cache directory and are always .webp, whatever the
        # original is. It is the original that gets shown and remembered.
        if [[ ! -f $want || $want == "$thumb_dir"/* ]] && [[ -n $src_dir ]]; then
            base="$(basename "${want%.*}")"
            for ext in webp png jpg jpeg; do
                [[ -f "$src_dir/$base.$ext" ]] && { want="$src_dir/$base.$ext"; break; }
            done
        fi

        # Check before realpath, not after: realpath exits non-zero on a
        # missing file and `set -e` kills the script with realpath's message
        # instead of one that says which command was being run.
        [[ -f "$want" ]] || die "no such file: $2"
        record "$(realpath -- "$want")"
        ;;

    restore)
        # A wallpaper that has since been deleted is forgotten, and then
        # replaced by the default below rather than leaving a blank desktop.
        if [[ -f $state_file ]]; then
            img="$(< "$state_file")"
            [[ -f $img ]] && exit 0
            printf 'wallpaper: %s is gone, forgetting it\n' "$img" >&2
            rm -f "$state_file"
        fi

        # FIRST BOOT: nothing chosen yet. First alphabetically, rather than a
        # name hardcoded here, so adding or removing wallpapers never needs
        # this script edited. The choice is then WRITTEN to the state file,
        # which makes it stick: re-deriving it every boot would silently change
        # the wallpaper the day someone adds one that sorts earlier.
        #
        # No wallpapers shipped is not an error - a clone without them should
        # still boot to a working desktop, in the theme's background colour.
        [[ -n $src_dir ]] || exit 0
        shopt -s nullglob
        candidates=("$src_dir"/*.webp "$src_dir"/*.png "$src_dir"/*.jpg "$src_dir"/*.jpeg)
        shopt -u nullglob
        (( ${#candidates[@]} )) || exit 0
        # LC_ALL=C so the ordering is byte-order and identical on every
        # machine - a locale-collated sort can disagree about case and
        # punctuation, and this has to pick the same file everywhere.
        first="$(printf '%s\n' "${candidates[@]}" | LC_ALL=C sort | head -1)"
        record "$first"
        printf 'wallpaper: no choice yet, defaulting to %s\n' "$(basename "$first")" >&2
        ;;

    current)
        [[ -f $state_file ]] && cat "$state_file"
        ;;

    thumbs)
        # Regenerate any preview that is missing or older than its source.
        # Cheap to run unconditionally, which is why autostart.lua just calls
        # it on every login rather than trying to detect changes.
        command -v cwebp >/dev/null 2>&1 || die "cwebp not found - install libwebp-tools"
        [[ -n $src_dir ]] || die "no wallpapers/ directory next to bin/"
        mkdir -p "$thumb_dir"
        made=0 kept=0
        for img in "$src_dir"/*.{png,jpg,jpeg,webp}; do
            [[ -f $img ]] || continue
            out="$thumb_dir/$(basename "${img%.*}").webp"
            # -nt is false when out does not exist, which is the case we want
            if [[ -f $out && $out -nt $img ]]; then kept=$((kept+1)); continue; fi
            tmp="$(mktemp --suffix=.png)"
            # cwebp cannot READ webp, only write it, so a webp source has to be
            # decoded first. Anything else cwebp reads directly.
            if [[ ${img,,} == *.webp ]]; then
                dwebp -quiet "$img" -o "$tmp" 2>/dev/null || { rm -f "$tmp"; continue; }
                cwebp -quiet -q 82 -resize "$thumb_width" 0 "$tmp" -o "$out" 2>/dev/null
            else
                cwebp -quiet -q 82 -resize "$thumb_width" 0 "$img" -o "$out" 2>/dev/null
            fi
            rm -f "$tmp"
            made=$((made+1))
        done
        # Previews for wallpapers that no longer exist would show up in the
        # picker as entries that cannot be applied.
        for old_thumb in "$thumb_dir"/*.webp; do
            [[ -f $old_thumb ]] || continue
            base="$(basename "${old_thumb%.webp}")"
            found=0
            for ext in png jpg jpeg webp; do
                [[ -f "$src_dir/$base.$ext" ]] && { found=1; break; }
            done
            (( found )) || { rm -f "$old_thumb"; printf 'wallpaper: dropped stale preview %s\n' "$base" >&2; }
        done
        printf 'wallpaper: %d preview(s) generated, %d already current\n' "$made" "$kept"
        ;;

    thumbdir)
        # Prints NOTHING when there are no previews yet.
        #
        # The picker uses this to decide whether to show previews or fall back
        # to the full-size originals, and an unconditional path defeats that:
        # the directory exists but is empty, the picker points at it, and the
        # result is an empty picker rather than a slow one. Reporting emptiness
        # here keeps that decision with the code that knows about it.
        if compgen -G "$thumb_dir/*.webp" >/dev/null 2>&1; then
            printf '%s\n' "$thumb_dir"
        fi
        ;;

    *)
        die "usage: wallpaper.sh {set <path>|restore|current|thumbs|thumbdir}"
        ;;
esac
