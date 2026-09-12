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

# --- backends ------------------------------------------------------------
#
# TWO OF THEM, CHOSEN AT RUNTIME, not per host.
#
# hyprpaper is preferred: it has an IPC, so changing a wallpaper is a message
# to a running daemon rather than a process restart, and it can be told about
# one monitor at a time.
#
# swaybg is the fallback, and it exists because hyprpaper 0.8.4 cannot start
# at all on some machines. On this project's desktop it aborts every single
# time inside libhyprtoolkit's wl_seat capability handler - glibc catching
# heap corruption, signal 6, a fresh coredump per attempt. It is not a race
# and not the peripherals: unplugging devices changed nothing, and there is no
# newer hyprpaper packaged in either Fedora or the COPR to move to. swaybg
# does no seat handling whatsoever, so it structurally cannot hit that bug.
#
# Detected rather than configured, because "which wallpaper daemon works" is a
# property of the machine, not a preference, and a per-host setting is one
# more thing that has to be right on every clone.

backend() {
    # A responding hyprpaper wins. `listactive` is used as the probe rather
    # than pgrep: a hyprpaper that is running but not answering its socket is
    # no use, and that is a state this has actually been in.
    if hyprctl hyprpaper listactive >/dev/null 2>&1; then
        echo hyprpaper; return 0
    fi
    if pgrep -x swaybg >/dev/null 2>&1 || command -v swaybg >/dev/null 2>&1; then
        echo swaybg; return 0
    fi
    echo none
}

apply() {
    local img="$1" mon applied=0
    [[ -f $img ]] || die "no such file: $img"

    case "$(backend)" in
        hyprpaper)
            # NAME EVERY MONITOR EXPLICITLY. The documented `,path` form -
            # empty monitor field, meaning "all of them" - is accepted by
            # hyprctl without complaint on hyprpaper 0.8.4 and then does
            # nothing at all: no error, no change, exit status 0. Passing the
            # real output name works. Cost an hour of thinking the webp
            # decoder was at fault.
            while read -r mon; do
                [[ -n $mon ]] || continue
                hyprctl hyprpaper wallpaper "$mon,$img" >/dev/null 2>&1 && applied=1
            done < <(hyprctl monitors -j 2>/dev/null \
                     | sed -n 's/.*"name": *"\([^"]*\)".*/\1/p')
            (( applied )) || die "hyprpaper did not accept it - is it running, with ipc = on?"
            ;;
        swaybg)
            # swaybg has no IPC, so a change means a new process. START THE
            # NEW ONE FIRST, then kill the old: the reverse leaves a frame or
            # two of bare compositor background, which reads as a flash. With
            # no -o it covers every output.
            # `|| true` is load-bearing: pgrep exits 1 when nothing matches,
            # and under `set -o pipefail` that fails the whole pipeline and
            # kills the script - silently, since the failure is an exit status
            # and not a message. On the very first run there is no swaybg yet,
            # so the common case IS the failing one.
            local old
            old="$(pgrep -x swaybg | tr '\n' ' ' || true)"
            swaybg -m fill -i "$img" >/dev/null 2>&1 &
            disown
            sleep 0.3
            [[ -n $old ]] && kill $old 2>/dev/null || true
            pgrep -x swaybg >/dev/null 2>&1 || die "swaybg did not stay running"
            ;;
        *)
            die "no wallpaper backend: hyprpaper is not responding and swaybg is not installed"
            ;;
    esac
}

# Starts whichever backend this machine can actually use. Called from
# hypr/autostart.lua instead of running hyprpaper directly.
start_daemon() {
    if pgrep -x hyprpaper >/dev/null 2>&1 || pgrep -x swaybg >/dev/null 2>&1; then
        log "a wallpaper daemon is already running"
        return 0
    fi

    if command -v hyprpaper >/dev/null 2>&1; then
        hyprpaper >/dev/null 2>&1 &
        disown
        # Give it a moment to either come up or die. hyprpaper's failure mode
        # here is an immediate abort, so this does not need to be generous.
        local i
        for i in 1 2 3 4 5 6 7 8 9 10; do
            sleep 0.2
            hyprctl hyprpaper listactive >/dev/null 2>&1 && { log "backend: hyprpaper"; return 0; }
        done
        log "hyprpaper did not come up - falling back"
    fi

    if command -v swaybg >/dev/null 2>&1; then
        # Started with whatever is remembered, or nothing - `restore` runs
        # straight after this and will set the real one.
        log "backend: swaybg"
        return 0
    fi

    log "no wallpaper backend available"
    return 0
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
        # FIRST BOOT: nothing chosen yet. This used to exit 0 and leave it to
        # hyprpaper.conf, but that config deliberately carries no wallpaper
        # line - it only sets ipc/splash/unload - so hyprpaper came up with an
        # empty list and the desktop showed Hyprland's built-in splash art
        # instead. The wallpapers were installed the whole time; nothing ever
        # named one. Only visible on a fresh install: a machine that has used
        # the picker once has a state file and takes the branch below.
        #
        # First alphabetically, rather than a name hardcoded here, so adding
        # or removing wallpapers never needs this script edited. The choice is
        # then WRITTEN to the state file, which makes it stick: re-deriving it
        # every boot would silently change the wallpaper the day someone adds
        # one that sorts earlier.
        if [[ ! -f $state_file ]]; then
            src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../wallpapers" 2>/dev/null && pwd)" || exit 0
            shopt -s nullglob
            candidates=("$src_dir"/*.webp "$src_dir"/*.png "$src_dir"/*.jpg "$src_dir"/*.jpeg)
            shopt -u nullglob
            # LC_ALL=C so the ordering is byte-order and identical on every
            # machine - a locale-collated sort can disagree about case and
            # punctuation, and this has to pick the same file everywhere.
            first="$(printf '%s\n' "${candidates[@]}" | LC_ALL=C sort | head -1)"
            # No wallpapers shipped is not an error - a clone without them
            # should still boot to a working desktop.
            [[ -n $first ]] || exit 0
            # apply() first: it dies if hyprpaper is not listening, and a
            # state file naming a wallpaper that was never applied would be a
            # lie every subsequent boot then acts on.
            apply "$first"
            mkdir -p "$state_dir"
            printf '%s\n' "$first" > "$state_file"
            printf 'wallpaper: no choice yet, defaulting to %s\n' "$(basename "$first")" >&2
            exit 0
        fi
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

    daemon)
        start_daemon
        ;;
    backend)
        backend
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
