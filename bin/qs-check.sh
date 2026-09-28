#!/usr/bin/env bash
# =========================================================================
# qs-check.sh - load the shell config and fail if it complains
# =========================================================================
#
# Usage:  bin/qs-check.sh [path to config dir or shell.qml]
#
# Exits 0 when the configuration loads clean, non-zero with the offending
# lines when it does not. Defaults to the quickshell/ folder beside this
# script, so from the repository it is just `bin/qs-check.sh`.
#
# WHY THIS EXISTS. The expensive failures in this repository are not crashes,
# they are configs that load WRONG, because nothing tells you until you look
# at the bar:
#
#   - `readonly property real fixedWidth` with a Behavior on it. A Behavior
#     animates by WRITING, so the assignment was refused, the whole config
#     failed to load, and the desktop had no bar at all for minutes until
#     `qs -p` was run by hand and printed the reason.
#
#   - a tray menu row built to the card's width instead of the column's,
#     which drew a hairline of separator on the wallpaper outside the card.
#     That one loaded silently and shipped.
#
# The first kind is exactly what a load produces an error for. This turns
# "run it and look" into something a pre-commit hook can do in five seconds.
# The second kind needs eyes on a screenshot and is not what this is for.
#
# IN A COMPOSITOR OF ITS OWN, and that is the whole difficulty. The config is
# a layer-shell client: it needs a Wayland compositor, and running it against
# the live one puts a second bar on screen over the real one, registers the
# global shortcuts twice and leaves the bar flickering every time anyone
# commits. The alternatives were measured rather than assumed:
#
#   QT_QPA_PLATFORM=offscreen   loads, then EXITS 255 in teardown
#                               ("Trying to construct an instance of an
#                               invalid type") whether the config is good or
#                               bad - it cannot tell them apart, so it is
#                               useless as a test.
#
#   a headless Hyprland         WLR_BACKENDS=headless gives a real compositor
#                               with no output and no input devices, on its
#                               own Wayland socket. Nothing appears on screen
#                               and the running session is untouched.  <- this
#
# WHAT COUNTS AS FAILURE. "Configuration Loaded" must appear, and no WARN or
# ERROR lines may - except the notification-server clash, which is not a fault
# in the config: a second instance cannot own org.freedesktop.Notifications
# while the real shell has it, and it says so every time.

set -uo pipefail

# Where the repository is, from this script's own location.
src="${BASH_SOURCE[0]:-}"
if [[ -n $src && -e $src ]]; then
    root="$(cd "$(dirname "$src")/.." && pwd)"
else
    root="${FD44_HYPRDOT_DIR:-$HOME/Work/fd44_hyprdot}"
fi

config="${1:-$root/quickshell}"

# How long to give each stage. The load itself takes about a second; the rest
# is starting a compositor.
compositor_wait=8
load_wait=20

red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }
green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
log()   { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

[[ -e $config ]] || { red "qs-check: no such config: $config"; exit 2; }
command -v qs >/dev/null       || { red "qs-check: quickshell (qs) is not installed"; exit 2; }
command -v Hyprland >/dev/null || { red "qs-check: Hyprland is not installed"; exit 2; }

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

work="$(mktemp -d)"
hl_pid=""
cleanup() {
    [[ -n $hl_pid ]] && kill "$hl_pid" 2>/dev/null
    # The compositor's children go with it, but give them a moment to notice
    # before the socket disappears under them.
    sleep 0.3
    rm -rf "$work"
}
trap cleanup EXIT INT TERM

# --- a compositor with no screen -----------------------------------------
#
# An EMPTY config, deliberately: the repository's own hypr config would start
# the autostart programs - a second quickshell among them - and this is a test
# of the QML, not a second desktop session.
: > "$work/empty.conf"

# The sockets that exist BEFORE, so the new one can be told apart from the
# session's own. Matching on mtime alone picked the live socket when the
# headless one was slow to appear.
mapfile -t before < <(cd "$XDG_RUNTIME_DIR" && ls -d wayland-[0-9]* 2>/dev/null)
is_old() { local s; for s in ${before+"${before[@]}"}; do [[ $s == "$1" ]] && return 0; done; return 1; }

log "starting a headless compositor"
WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 \
    Hyprland -c "$work/empty.conf" > "$work/hyprland.log" 2>&1 &
hl_pid=$!

sock=""
for _ in $(seq 1 $((compositor_wait * 5))); do
    for s in "$XDG_RUNTIME_DIR"/wayland-[0-9]*; do
        [[ -S $s ]] || continue
        name="${s##*/}"
        is_old "$name" || { sock="$name"; break; }
    done
    [[ -n $sock ]] && break
    kill -0 "$hl_pid" 2>/dev/null || { red "qs-check: the compositor exited early"; tail -5 "$work/hyprland.log"; exit 2; }
    sleep 0.2
done
[[ -n $sock ]] || { red "qs-check: no new Wayland socket after ${compositor_wait}s"; exit 2; }

sig="$(cd "$XDG_RUNTIME_DIR/hypr" && ls -t 2>/dev/null | head -1)"
log "compositor up on $sock"

# --- load the config -----------------------------------------------------
#
# It never exits on its own - a shell runs until it is killed - so waiting for
# it to finish means waiting out the whole timeout. WAIT FOR THE SENTENCE
# INSTEAD: quickshell prints "Configuration Loaded" when it is up, and that is
# the moment there is an answer. Sitting out the full timeout instead made a
# passing check take 20 seconds, which is 20 seconds nobody will accept before
# every commit; watching for the line brings it under five.
log "loading $config"
WAYLAND_DISPLAY="$sock" HYPRLAND_INSTANCE_SIGNATURE="$sig" \
    qs -p "$config" > "$work/qs.log" 2>&1 &
qs_pid=$!

status=0
loaded=0
for _ in $(seq 1 $((load_wait * 5))); do
    if grep -qa 'Configuration Loaded' "$work/qs.log" 2>/dev/null; then
        loaded=1
        # A breath for anything the load logs immediately after saying it is
        # up - a binding evaluated on the first frame, a singleton's first
        # complaint - which would otherwise be killed before it was written.
        sleep 0.5
        break
    fi
    if ! kill -0 "$qs_pid" 2>/dev/null; then
        wait "$qs_pid"; status=$?
        break
    fi
    sleep 0.2
done

if kill -0 "$qs_pid" 2>/dev/null; then
    kill "$qs_pid" 2>/dev/null
    status=124                      # stopped by us, which is the good case
    wait "$qs_pid" 2>/dev/null
fi

plain() { sed 's/\x1b\[[0-9;]*m//g' "$work/qs.log"; }

# Not a fault in the config: the live shell owns the notification bus name, so
# a second instance cannot, and says so. Anything else is worth reading.
problems="$(plain | grep -aE 'WARN|ERROR' \
    | grep -avE 'service\.notifications: (Could not register notification server|Registration will be attempted)' \
    || true)"

if (( ! loaded )); then
    red "qs-check: the configuration did NOT load"
    printf '%s\n' "----"
    plain | grep -aE 'ERROR|WARN|error:|\.qml' | head -20 | sed 's/^/  /'
    printf '%s\n' "----"
    exit 1
fi

if [[ -n $problems ]]; then
    red "qs-check: it loaded, but complained"
    printf '%s\n' "$problems" | head -20 | sed 's/^/  /'
    exit 1
fi

# 124 is the timeout, which is what a shell that stays up looks like. Anything
# else means it stopped by itself, which a working config does not do.
if (( status != 124 )); then
    red "qs-check: it exited on its own with status $status"
    plain | tail -10 | sed 's/^/  /'
    exit 1
fi

green "qs-check: $config loads clean"
