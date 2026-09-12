#!/usr/bin/env bash
#
# Apply and remember the wallpaper.
#
#   wallpaper.sh set <path>   apply it now and remember it
#   wallpaper.sh restore      re-apply whatever was last set
#   wallpaper.sh current      print the current path, if any
#
# WHY A SCRIPT AND NOT JUST hyprctl:
# hyprpaper has no memory. `hyprctl hyprpaper wallpaper` applies an image to
# a running daemon and that is all - restart hyprpaper, or reboot, and it is
# gone. The choice is recorded here instead, and `restore` is what
# autostart.lua runs so the wallpaper survives a session.
#
# The state file lives in ~/.local/state, NOT in this repository. Writing it
# into hypr/hyprpaper.conf would mean every click in the picker leaves the
# working tree dirty.

set -euo pipefail

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}"
state_file="$state_dir/wallpaper"

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

apply() {
    local img="$1" mon applied=0
    [[ -f $img ]] || die "no such file: $img"

    # NAME EVERY MONITOR EXPLICITLY. The documented `,path` form - empty
    # monitor field, meaning "all of them" - is accepted by hyprctl without
    # complaint on hyprpaper 0.8.4 and then does nothing at all: no error, no
    # change, exit status 0. Passing the real output name works. Cost an hour
    # of thinking the webp decoder was at fault.
    while read -r mon; do
        [[ -n $mon ]] || continue
        hyprctl hyprpaper wallpaper "$mon,$img" >/dev/null 2>&1 && applied=1
    done < <(hyprctl monitors -j 2>/dev/null \
             | sed -n 's/.*"name": *"\([^"]*\)".*/\1/p')

    (( applied )) || die "hyprpaper did not accept it - is the daemon running, with ipc = on?"
}

case "${1:-}" in
    set)
        [[ $# -ge 2 ]] || die "usage: wallpaper.sh set <path>"
        want="$2"

        # The picker hands over the path of a PREVIEW, which lives in the
        # cache directory and is always .webp regardless of what the original
        # is. Map it back by basename: it is the original that gets applied
        # and remembered, never the thumbnail.
        if [[ ! -f $want ]] || [[ $want == "$thumb_dir"/* ]]; then
            src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../wallpapers" && pwd)"
            base="$(basename "${want%.*}")"
            for ext in webp png jpg jpeg; do
                [[ -f "$src_dir/$base.$ext" ]] && { want="$src_dir/$base.$ext"; break; }
            done
        fi

        # Check before realpath, not after: realpath exits non-zero on a
        # missing file and `set -e` kills the script with realpath's message
        # instead of one that says which command was being run.
        [[ -f "$want" ]] || die "no such file: $2"
        img="$(realpath -- "$want")"
        apply "$img"
        mkdir -p "$state_dir"
        printf '%s\n' "$img" > "$state_file"
        ;;

    restore)
        # Nothing chosen yet is not an error - a fresh install has no state
        # file and should simply come up with whatever hyprpaper.conf says.
        [[ -f $state_file ]] || exit 0
        img="$(< "$state_file")"
        # A wallpaper that has since been deleted should not take the session
        # down with it, nor leave a stale entry that fails on every boot.
        if [[ -f $img ]]; then
            apply "$img"
        else
            printf 'wallpaper: %s is gone, forgetting it\n' "$img" >&2
            rm -f "$state_file"
        fi
        ;;

    current)
        [[ -f $state_file ]] && cat "$state_file"
        ;;

    thumbs)
        # Regenerate any preview that is missing or older than its source.
        # Cheap to run unconditionally, which is why autostart.lua just calls
        # it on every login rather than trying to detect changes.
        command -v cwebp >/dev/null 2>&1 || die "cwebp not found - install libwebp-tools"
        src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../wallpapers" && pwd)"
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
        printf '%s\n' "$thumb_dir"
        ;;

    *)
        die "usage: wallpaper.sh {set <path>|restore|current|thumbs|thumbdir}"
        ;;
esac
