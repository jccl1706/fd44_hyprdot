#!/usr/bin/env bash
# =========================================================================
# qs-restart.sh - restart quickshell, and leave exactly one running
# =========================================================================
#
# Usage:  bin/qs-restart.sh
#
# Works from a terminal in the session and over ssh alike.
#
# WHY NOT `qs kill`. On quickshell 0.3.1 a normal exit can SEGFAULT: the
# teardown destroys the GlobalShortcut objects after their Wayland proxy is
# already gone (backtrace: GlobalShortcut::~GlobalShortcut -> wl_proxy_marshal
# -> wl_map_insert_at). Quickshell's crash handler then relaunches the shell
# on its own - and whatever you start next is a SECOND instance. Seen on the
# gaming desktop: `qs kill; qs -d` left two shells running, two bars stacked
# on top of each other, every shortcut and IPC target registered twice.
#
# So this sends SIGKILL instead. Nothing runs on the way out, so there is no
# crash, and the crash handler dies in the same sweep instead of respawning.
# Hyprland drops the killed client's surfaces and shortcuts itself, as it
# does for any client that disconnects. Nothing is lost that a normal exit
# would have saved: the bar layout and theme are written as they change.
#
# It kills EVERY quickshell process of this user, including a test instance
# started with `qs -p`. It does not touch other users.
#
# WHY THROUGH HYPRLAND. `hl.exec_cmd` starts the new shell inside the
# compositor's session (session.slice/wayland-wm@hyprland.desktop.service),
# where autostart.lua puts it at login. Started straight from this script it
# would belong to whatever terminal or ssh session ran it, and die with it.
#
# Side effects worth knowing: an open panel closes, and the coffee cup
# (Caffeine.qml) is off again - its inhibitor is released within two seconds.

set -euo pipefail

die()  { printf '\033[1;31mqs-restart:\033[0m %s\n' "$*" >&2; exit 1; }
log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
nap()  { python3 -c "import time; time.sleep($1)"; }

(( EUID != 0 )) || die "run as your own user, not root - quickshell runs in your session"

# The session's environment, when run from somewhere that lacks it (ssh, a tty).
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    sig="$(ls -t "$XDG_RUNTIME_DIR/hypr/" 2>/dev/null | head -1 || true)"
    [[ -n $sig ]] || die "no running Hyprland found in $XDG_RUNTIME_DIR/hypr"
    export HYPRLAND_INSTANCE_SIGNATURE="$sig"
fi
if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
    WAYLAND_DISPLAY="$(ls "$XDG_RUNTIME_DIR" 2>/dev/null | grep -m1 -E '^wayland-[0-9]+$' || true)"
    export WAYLAND_DISPLAY
fi
hyprctl version >/dev/null 2>&1 || die "cannot reach Hyprland (instance $HYPRLAND_INSTANCE_SIGNATURE)"

# By exact process name: `qs` is the launcher's name, `quickshell` the one a
# crash-handler relaunch runs under. Never `pkill -f`, which would match this
# script's own command line.
running() { pgrep -u "$(id -u)" -x 'qs|quickshell' || true; }

before="$(running | wc -l)"
if (( before )); then
    log "stopping quickshell ($before process(es))"
    pkill -KILL -u "$(id -u)" -x 'qs|quickshell' || true
    for _ in $(seq 1 25); do
        [[ -z "$(running)" ]] && break
        nap 0.2
    done
    [[ -z "$(running)" ]] || die "quickshell processes survived SIGKILL: $(running | tr '\n' ' ')"
else
    log "quickshell was not running"
fi

log "starting quickshell through Hyprland"
hyprctl eval 'hl.exec_cmd("qs -d")' >/dev/null || die "hyprctl could not start it"

# Wait for the one instance to load its config, rather than a fixed sleep.
loaded=0
for _ in $(seq 1 50); do
    if qs log 2>/dev/null | grep -q 'Configuration Loaded'; then loaded=1; break; fi
    nap 0.2
done

instances="$(qs list 2>/dev/null | grep -c '^Instance' || true)"
problems="$(qs log 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'WARN|ERROR' || true)"

printf '    processes : %s\n' "$(running | tr '\n' ' ')"
printf '    instances : %s\n' "$instances"
printf '    loaded    : %s\n' "$( (( loaded )) && echo yes || echo 'NOT within 10 s' )"
if [[ -n $problems ]]; then
    printf '    log       :\n'
    printf '%s\n' "$problems" | tail -10 | sed 's/^/      /'
fi

(( loaded )) || die "quickshell did not report 'Configuration Loaded' - see: qs log"
[[ $instances == 1 ]] || die "expected exactly one instance, found $instances"
log "quickshell restarted"
