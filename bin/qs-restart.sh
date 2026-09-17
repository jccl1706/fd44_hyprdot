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
# Plain sleep, and it takes fractions: coreutils' does everywhere this runs.
# It used to shell out to python3 for this, which is not installed on the
# NixOS desktop at all - under `set -e` the first wait killed the script.
nap()  { sleep "$1"; }

(( EUID != 0 )) || die "run as your own user, not root - quickshell runs in your session"

# The session's environment, when run from somewhere that lacks it (ssh, a tty).
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    # Newest first, and only ls sorts by time. The names are Hyprland's own
    # instance signatures - no spaces or newlines to trip over.
    # shellcheck disable=SC2012
    sig="$(ls -t "$XDG_RUNTIME_DIR/hypr/" 2>/dev/null | head -1 || true)"
    [[ -n $sig ]] || die "no running Hyprland found in $XDG_RUNTIME_DIR/hypr"
    export HYPRLAND_INSTANCE_SIGNATURE="$sig"
fi
if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
    for s in "$XDG_RUNTIME_DIR"/wayland-*; do
        if [[ ${s##*/} =~ ^wayland-[0-9]+$ ]]; then WAYLAND_DISPLAY="${s##*/}"; break; fi
    done
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}"
fi
hyprctl version >/dev/null 2>&1 || die "cannot reach Hyprland (instance $HYPRLAND_INSTANCE_SIGNATURE)"

# BY EXECUTABLE, NOT BY PROCESS NAME. `pgrep -x quickshell` is the obvious way
# to do this and it finds nothing on NixOS: what is on PATH there is a wrapper,
# so the process is named after the wrapper - ".quickshell-wrapped", which the
# kernel truncates to ".quickshell-wra" - and -x matches names exactly. The
# script then said "quickshell was not running", killed nothing, and started
# another one. Four shells were stacked on the gaming desktop before anyone
# noticed, which is the exact thing this script exists to prevent.
#
# /proc/PID/exe is what is actually being run, whatever the wrapper is called.
# Reading it also cannot match this script, the ssh command line that started
# it, or an editor with the word in a filename - which is why the tempting
# `pkill -f quickshell` is still not used.
running() {
    local p exe
    for p in /proc/[0-9]*; do
        [[ -O $p ]] || continue                        # our own processes only
        exe="$(readlink -f "$p/exe" 2>/dev/null)" || continue
        case "${exe##*/}" in
            qs|quickshell|.qs-wrapped|.quickshell-wrapped) echo "${p##*/}" ;;
        esac
    done
}

before="$(running | wc -l)"
if (( before )); then
    log "stopping quickshell ($before process(es))"
    # shellcheck disable=SC2046  # bare pids, one per line, no quoting needed
    kill -KILL $(running) 2>/dev/null || true
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
