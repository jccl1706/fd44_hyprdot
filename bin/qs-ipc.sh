#!/usr/bin/env bash
# =========================================================================
# qs-ipc.sh - talk to the running shell, from anywhere
# =========================================================================
#
# Usage:  bin/qs-ipc.sh call <target> <function> [args...]
#         bin/qs-ipc.sh pid         print the live shell's process id
#         bin/qs-ipc.sh which       everything known about the live instance
#         bin/qs-ipc.sh             the targets the shell exposes
#
# Examples:
#         bin/qs-ipc.sh call units status
#         bin/qs-ipc.sh call backups check
#         ssh gaming00 'Work/fd44_hyprdot/bin/qs-ipc.sh call updates status'
#
# WHY THIS EXISTS. `qs ipc call ...` works from a terminal inside the session
# and is unreliable from anywhere else, which is exactly where a diagnostic is
# run from. Both failures were hit repeatedly on the gaming desktop over ssh:
#
#   No running instances for "/home/jc/.config/quickshell/shell.qml"
#       while `qs list --all` showed that very instance running. qs resolves
#       "the current config" from the environment, and over ssh there is not
#       enough of one.
#
#   No instance found for pid 18977
#       from `qs ipc --pid $(pgrep -f "quickshell -d")`, because pgrep -f also
#       matches the ssh command line carrying that string, and matches a
#       process that has just exited.
#
# `qs list --all` is the one answer that does not depend on the environment:
# it is quickshell's own registry of live instances. This reads it, picks the
# instance, and forwards - so every remote diagnostic is one command that
# works the same on both machines.

set -uo pipefail

red=$'\033[1;31m'; dim=$'\033[2m'; reset=$'\033[0m'
die() { printf '%sqs-ipc:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
command -v qs >/dev/null 2>&1 || die "quickshell (qs) is not installed"

# "pid<TAB>config path<TAB>launch time" per live instance, newest last - which
# is the order qs prints them in.
instances() {
    qs list --all 2>/dev/null | awk '
        /^  Process ID:/   { pid = $3 }
        /^  Config path:/  { cfg = $3 }
        /^  Launch time:/  { print pid "\t" cfg "\t" $3 " " $4; pid=""; cfg="" }
    '
}

# THE PROCESS HAS TO STILL BE THERE. quickshell's registry is files under
# $XDG_RUNTIME_DIR, and a killed shell leaves its entry behind - the same
# litter that made `ls -t` pick a dead Hyprland in bin/qs-restart.sh. kill -0
# is the cheapest proof that a pid is alive and ours.
live_pid() {
    local pid cfg rest chosen=""
    while IFS=$'\t' read -r pid cfg rest; do
        [[ -n $pid ]] || continue
        kill -0 "$pid" 2>/dev/null || continue
        # Prefer one whose config is the default shell, but take any live
        # instance rather than none - a shell started with `qs -p` is still a
        # shell worth talking to.
        [[ $cfg == *"/quickshell/shell.qml" ]] && chosen="$pid"
        [[ -z $chosen ]] && chosen="$pid"
    done < <(instances)
    [[ -n $chosen ]] || return 1
    printf '%s' "$chosen"
}

case "${1-}" in
    pid)
        pid="$(live_pid)" || die "no running quickshell instance"
        echo "$pid"
        ;;
    which)
        pid="$(live_pid)" || die "no running quickshell instance"
        qs list --all 2>/dev/null | awk -v want="$pid" '
            /^Instance /      { block = $0; keep = 0 }
            /^  Process ID:/  { if ($3 == want) keep = 1 }
            { if (keep) print }
            /^  Launch time:/ { if (keep) exit }
        '
        ;;
    call)
        shift
        (( $# )) || die "usage: $0 call <target> <function> [args...]"
        pid="$(live_pid)" || die "no running quickshell instance"
        exec qs ipc --pid "$pid" call "$@"
        ;;
    ""|-h|--help|help)
        pid="$(live_pid)" || die "no running quickshell instance"
        printf '%sthe shell this talks to: pid %s%s\n\n' "$dim" "$pid" "$reset"
        qs ipc --pid "$pid" show 2>/dev/null
        ;;
    *) die "unknown command: $1 (call, pid, which)" ;;
esac
