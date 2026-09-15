#!/usr/bin/env bash
#
# Apply power-source-dependent settings.
#
#   on battery   power-saver profile, 50% brightness
#   on AC        balanced profile,   100% brightness
#
# Screen-off timeouts are NOT handled here - hypridle.conf checks the power
# source itself when its listeners fire, so nothing needs restarting when the
# charger moves. The one exception is the idle suspend: see unplug_suspend().
#
# Usage:
#   power-mode.sh apply    apply settings for the current power source, once
#   power-mode.sh watch    apply now, then re-apply on every power_supply event
#
# Runs entirely as the user: powerprofilesctl and brightnessctl both work
# unprivileged here, so there is no udev rule and no root involved.

set -u

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
    # NO BATTERY AT ALL means mains - the same rule, for the same reason, as
    # on_ac() in idle-action.sh. This used to assume battery whenever the AC
    # file was missing, so the gaming desktop - no ACAD, no BAT*, only a
    # wireless mouse's hidpp_battery - logged "battery" at every login and
    # asked for the power-saver profile (it failed only because
    # power-profiles-daemon is not installed there).
    compgen -G '/sys/class/power_supply/BAT*' >/dev/null || return 0

    # The charger BY TYPE, not by name: ACAD on the Framework, AC on a
    # ThinkPad T480. Keyed on the name, the T480 never found its charger and
    # ran power-saver at 50% brightness plugged in. USB-C ports (type USB) are
    # ignored - they report online whenever a cable is in, charging or not.
    # A battery but no Mains supply online -> battery.
    local p
    for p in /sys/class/power_supply/*; do
        [[ -r $p/type && -r $p/online ]] || continue
        [[ $(< "$p/type") == Mains && $(< "$p/online") == 1 ]] && return 0
    done
    return 1
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

# SUSPEND AFTER AN IDLE UNPLUG.
#
# hypridle's 15-minute suspend listener is battery-scoped, and a listener fires
# once per idle period. If the laptop is on AC when it fires, it skips - which
# is right - but it does not fire again when the charger is pulled later in the
# same idle period. So a laptop left idle on AC, then unplugged, stayed awake on
# battery until someone touched it. Observed 2026-09-13: suspend skipped on AC
# at 13:45:54, display off at 13:46:24, charger pulled at 14:01:32, and still
# awake 21 minutes later at 14:22:33.
#
# So an unplug while the display is ALREADY idle-blanked schedules one check,
# UNPLUG_SUSPEND_DELAY later (bin/idle-action.sh suspend-if-idle): still on
# battery with the display still off means nobody came back, and it suspends.
# Plugging back in cancels the check, and the check re-reads both anyway.
#
# An unplug with the display ON needs nothing: then hypridle's blank listeners
# have not all fired yet this idle period, and neither has its later suspend,
# which will still run - on battery now - when its time comes.
#
# The delay is a grace period, not a timeout: the machine has already been
# idle for over fifteen minutes, so the only question is whether the unplug
# was someone picking it up. A minute answers that.
UNPLUG_SUSPEND_DELAY=60
IDLE_ACTION="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/idle-action.sh"

unplug_suspend() {
    local now="$1" dpms
    # Whatever happens next, a check scheduled by an earlier unplug is stale.
    systemctl --user stop idle-unplug-suspend.timer idle-unplug-suspend.service 2>/dev/null || true
    [[ $now == battery ]] || return 0

    dpms=$(hyprctl monitors 2>/dev/null | grep -o 'dpmsStatus: [01]' | head -1 | awk '{print $2}')
    if [[ -z $dpms ]]; then
        log "battery: cannot read the display state - leaving the idle suspend to hypridle"
        return 0
    elif [[ $dpms == 1 ]]; then
        return 0
    fi

    log "battery: charger pulled while idle-blanked - suspend check in ${UNPLUG_SUSPEND_DELAY}s"
    # A transient timer, not `sleep` in this watcher: it survives this service
    # restarting, and `systemctl --user stop` above can cancel it cleanly.
    systemd-run --user --quiet --collect --unit=idle-unplug-suspend \
        --on-active="${UNPLUG_SUSPEND_DELAY}s" "$IDLE_ACTION" suspend-if-idle 2>/dev/null \
        || log "battery: could not schedule the suspend check"
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
            unplug_suspend "$now"
        fi
    done
}

case "${1:-apply}" in
    apply) apply ;;
    watch) watch_events ;;
    *)     echo "usage: $0 {apply|watch}" >&2; exit 2 ;;
esac
