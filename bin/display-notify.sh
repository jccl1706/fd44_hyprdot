#!/usr/bin/env bash
# =========================================================================
# display-notify.sh - say something when a monitor is plugged in or unplugged
# =========================================================================
#
# Usage:  bin/display-notify.sh watch     follow udev and notify (the unit)
#         bin/display-notify.sh status    what it can see right now
#
# The other half of bin/usb-notify.sh. That one watches the usb subsystem and
# cannot see this at all: a monitor on USB-C is DisplayPort over the cable,
# and the adapter that carries it is a Billboard device with no video of its
# own. Plugging the ADAPTER in is a usb event; plugging a CABLE into an
# adapter already sitting there is a drm one, and nothing was listening.
#
# THE EVENT SAYS NOTHING. A drm hotplug is a `change` on the card device with
# no hint of which connector moved or which way - so this keeps the last
# status of every connector and compares. That is also what makes it quiet:
# drm emits change events for mode sets and DPMS as well as hotplugs, and an
# event that moves no connector produces no notification.
#
# NOTHING IS ANNOUNCED AT STARTUP. The first scan is taken before the watch
# begins, so the displays already attached when the session starts are the
# baseline rather than a burst of notifications about a screen you are
# already looking at.
#
# THE NAME COMES FROM HYPRLAND, not from sysfs. The kernel knows the
# connector - DP-2 - and the monitor's name is in the EDID blob beside it,
# which is a binary format this has no business parsing when `hyprctl
# monitors` has already done it. On the way OUT there is nothing left to ask,
# so the description is remembered from when it arrived, the same way
# usb-notify.sh remembers a device across its remove event.

set -uo pipefail

# NO ICON IS SENT: the shell draws a coloured dot rather than a picture
# (quickshell/NotificationToast.qml), so a name here would be read by nobody.
# video-display is the one to put back if that changes.
notify() {
    notify-send -a "Display" "$1" "$2" 2>/dev/null \
        || printf 'display-notify: %s - %s\n' "$1" "$2" >&2
}

# "<connector> <status>" per line. The directory is card<N>-<connector>, and
# the connector is what everything else calls the output.
scan() {
    local c n
    for c in /sys/class/drm/card*-*; do
        [[ -f $c/status ]] || continue
        n=${c##*/}
        printf '%s %s\n' "${n#card*-}" "$(<"$c/status")"
    done
}

# Hyprland's own name for an output: "LG Electronics LG ULTRAGEAR ...".
# Empty when it cannot say, and the connector is used instead - which is the
# case for a monitor that has been unplugged and one Hyprland has not
# configured yet.
describe() {
    hyprctl monitors 2>/dev/null |
        awk -v want="$1" '
            /^Monitor /            { n = $2 }
            /^\tdescription:/      { sub(/^\tdescription: /, "")
                                     if (n == want) { print; exit } }'
}

declare -A STATUS=()
declare -A SEEN=()

# Compare against what was there last time and announce the differences.
# Called once before the watch to fill STATUS without announcing anything.
poll() {
    local quiet=${1-} line name state was desc
    while read -r name state; do
        was=${STATUS[$name]-}
        STATUS[$name]=$state
        [[ $was == "$state" ]] && continue
        [[ -z $quiet ]] || continue

        if [[ $state == connected ]]; then
            desc=$(describe "$name")
            [[ -n $desc ]] && SEEN[$name]=$desc
            notify "Display connected" "${desc:-$name} · $name"
        elif [[ $was == connected ]]; then
            # Only from connected: a connector going "disconnected" to
            # "unknown" is not something anyone unplugged.
            desc=${SEEN[$name]-}
            unset "SEEN[$name]"
            notify "Display disconnected" "${desc:-$name}${desc:+ · $name}"
        fi
    done < <(scan)
}

case "${1:-watch}" in
    watch)
        poll quiet
        # --udev, not --kernel: the events as they leave udev, which is what
        # every other watcher in this repo follows.
        udevadm monitor --udev --subsystem-match=drm 2>/dev/null |
        while read -r _; do poll; done
        ;;
    status)
        while read -r name state; do
            printf '  %-12s %-12s %s\n' "$name" "$state" \
                   "$([[ $state == connected ]] && describe "$name")"
        done < <(scan)
        ;;
    *) echo "usage: $0 {watch|status}" >&2; exit 2 ;;
esac
