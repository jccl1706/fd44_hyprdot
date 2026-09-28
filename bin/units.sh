#!/usr/bin/env bash
# =========================================================================
# units.sh - which systemd units have failed, and what they said
# =========================================================================
#
# Usage:  bin/units.sh check    what has failed, as JSON on stdout
#         bin/units.sh report   the failures with their logs, for reading
#         bin/units.sh open     that report, in a terminal
#
# The bar's failure indicator (quickshell/Units.qml) calls `check` on a timer
# and `open` when clicked.
#
# WHY THE BAR NEEDS THIS. Everything careful in this repository reports a
# problem by FAILING A UNIT: backup.service fails once a backup is a fortnight
# overdue, btrfs-scrub.service fails when a scrub finds errors, btrfs-patrol
# fails when a snapshot cannot be taken. That is the right design - a failed
# unit is durable, timestamped and sits in `systemctl --failed` where a sweep
# of the machine looks first - and it has one gap: nobody runs a sweep. The
# failures found on these machines this week were all found by hand.
#
# So the bar reads the same list, and only ever shows something when it is not
# empty. This is the general case of the update box and the backup disk: those
# two answer specific questions, this one answers "is anything broken".
#
# BOTH MANAGERS. A user unit failing is as real as a system one - backup.timer
# and daylight.timer are user units - and `systemctl --failed` alone shows
# only the system manager, which is how a failing user timer stays invisible.
#
# IT IS CHEAP: two read-only dbus calls, about 55 milliseconds together, and
# no privileges. Nothing here writes, resets or restarts anything; clearing a
# failure is a decision for a person, and `report` prints the command rather
# than running it.

set -uo pipefail

src="${BASH_SOURCE[0]:-}"
if [[ -n $src && -e $src ]]; then
    self="$(cd "$(dirname "$src")" && pwd)"
else
    self="${FD44_HYPRDOT_DIR:-$HOME/Work/fd44_hyprdot}/bin"
fi

green=$'\033[1;32m'; red=$'\033[1;31m'; dim=$'\033[2m'; reset=$'\033[0m'

# The unit names only, one per line. --plain drops the bullet that would
# otherwise be the first field.
failed_system() { systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}'; }
failed_user()   { systemctl --user --failed --no-legend --plain 2>/dev/null | awk '{print $1}'; }

cmd_check() {
    local sys usr n_sys n_usr names
    sys="$(failed_system)"; usr="$(failed_user)"
    n_sys="$(grep -c . <<<"$sys")"; n_usr="$(grep -c . <<<"$usr")"
    # grep -c on empty input says 0, but on a single empty line it also says 0
    # only because the line is empty - keep both honest.
    [[ -z ${sys//[[:space:]]/} ]] && n_sys=0
    [[ -z ${usr//[[:space:]]/} ]] && n_usr=0

    names="$( { [[ $n_sys -gt 0 ]] && echo "$sys"; [[ $n_usr -gt 0 ]] && echo "$usr"; } \
              | sed 's/\.\(service\|timer\|mount\|socket\|path\|target\)$//' \
              | head -3 | paste -sd, - | sed 's/,/, /g')"
    local total=$(( n_sys + n_usr ))
    (( total > 3 )) && names="$names and $((total - 3)) more"

    printf '{"total":%s,"system":%s,"user":%s,"names":"%s"}\n' \
        "$total" "$n_sys" "$n_usr" "${names//\"/\'}"
}

# What each failure actually says. The unit list alone names the thing that
# broke and not why, and "why" is the reason anyone opens this.
cmd_report() {
    local any=0 u
    while read -r u; do
        [[ -n $u ]] || continue
        any=1
        printf '\n%s==>%s %s %s(system)%s\n' "$green" "$reset" "$u" "$dim" "$reset"
        systemctl status --no-pager -n 20 "$u" 2>/dev/null | sed 's/^/  /'
    done < <(failed_system)
    while read -r u; do
        [[ -n $u ]] || continue
        any=1
        printf '\n%s==>%s %s %s(user)%s\n' "$green" "$reset" "$u" "$dim" "$reset"
        systemctl --user status --no-pager -n 20 "$u" 2>/dev/null | sed 's/^/  /'
    done < <(failed_user)

    if (( ! any )); then
        printf '%s==>%s %s\n' "$green" "$reset" "nothing has failed"
        return 0
    fi

    # NOT RUN, ONLY PRINTED. `reset-failed` makes the indicator go away
    # without fixing anything, which is a decision for a person who has just
    # read why it failed - not for a script, and certainly not for a bar icon.
    printf '\n%s--%s %s\n' "$dim" "$reset" "once a failure is understood and dealt with, clear it with:"
    printf '     systemctl reset-failed <unit>          %s(system units need sudo)%s\n' "$dim" "$reset"
    printf '     systemctl --user reset-failed <unit>\n'
}

cmd_open() {
    exec "$self/in-terminal.sh" "Failed units" "$self/units.sh" report
}

case "${1:-check}" in
    check)  cmd_check ;;
    report) cmd_report ;;
    open)   cmd_open ;;
    -h|--help|help) sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
    *) printf '%sunits:%s unknown command: %s (check, report, open)\n' "$red" "$reset" "$1" >&2; exit 2 ;;
esac
