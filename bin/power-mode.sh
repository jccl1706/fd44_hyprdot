#!/usr/bin/env bash
#
# Apply power-source-dependent settings.
#
#   on battery   power-saver profile, 50% brightness
#   on AC        balanced profile,   100% brightness
#
# Screen-off timeouts are NOT handled here - hypridle.conf checks the power
# source itself when its listeners fire, so nothing needs restarting when the
# charger moves.
#
# Usage:
#   power-mode.sh apply    apply settings for the current power source, once
#   power-mode.sh watch    apply now, then re-apply on every power_supply event
#
# Runs entirely as the user: powerprofilesctl and brightnessctl both work
# unprivileged here, so there is no udev rule and no root involved.

set -u

AC_ONLINE=/sys/class/power_supply/ACAD/online

# The backlight device is RESOLVED, not named. bin/backlight.sh finds it in
# /sys/class/backlight, which is this laptop's amdgpu_bl1, an Intel laptop's
# intel_backlight, or nothing at all on a desktop - where it exits 0 and this
# script simply sets a power profile and no brightness.
BACKLIGHT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/backlight.sh"

BATTERY_PROFILE=power-saver
BATTERY_BRIGHTNESS=50%

AC_PROFILE=balanced
AC_BRIGHTNESS=100%

log() { printf '[power-mode] %s\n' "$*"; }

on_ac() {
    [[ -r $AC_ONLINE ]] || return 1      # no AC device readable -> assume battery
    [[ $(< "$AC_ONLINE") == 1 ]]
}

apply() {
    local profile brightness source
    if on_ac; then
        profile=$AC_PROFILE; brightness=$AC_BRIGHTNESS; source=AC
    else
        profile=$BATTERY_PROFILE; brightness=$BATTERY_BRIGHTNESS; source=battery
    fi

    # Only set the profile if it differs, so replugging does not spam the
    # daemon or clobber a profile the user deliberately chose mid-session
    # more often than necessary.
    local current
    current=$(powerprofilesctl get 2>/dev/null)
    if [[ $current != "$profile" ]]; then
        if powerprofilesctl set "$profile" 2>/dev/null; then
            log "$source: profile $current -> $profile"
        else
            log "$source: FAILED to set profile $profile"
        fi
    else
        log "$source: profile already $profile"
    fi

    # No backlight is the normal state on a desktop, not a failure, so it is
    # reported differently from one that exists and refused to be set.
    bl_device="$("$BACKLIGHT" device)"
    if [[ -z $bl_device ]]; then
        log "$source: no backlight on this machine - brightness skipped"
    elif "$BACKLIGHT" set "$brightness"; then
        log "$source: brightness -> $brightness ($bl_device)"
    else
        log "$source: FAILED to set brightness on $bl_device"
    fi
}

watch_events() {
    apply

    # udevadm monitor is event-driven, not a poll, and works unprivileged.
    # A plug or unplug emits several power_supply events (ACAD plus each USB-C
    # port's ucsi-source-psy device), so collapse bursts: remember the last
    # state applied and ignore events that do not change it.
    local last
    last=$(on_ac && echo ac || echo battery)

    udevadm monitor --udev --subsystem-match=power_supply 2>/dev/null |
    while read -r _; do
        local now
        now=$(on_ac && echo ac || echo battery)
        if [[ $now != "$last" ]]; then
            last=$now
            apply
        fi
    done
}

case "${1:-apply}" in
    apply) apply ;;
    watch) watch_events ;;
    *)     echo "usage: $0 {apply|watch}" >&2; exit 2 ;;
esac
