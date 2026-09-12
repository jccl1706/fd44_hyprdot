#!/usr/bin/env bash
# =========================================================================
# backlight.sh - the display backlight, on whatever machine this is
# =========================================================================
#
# Usage:  backlight.sh device        print the backlight device name
#         backlight.sh path          print its sysfs directory
#         backlight.sh set 5%+       adjust it
#         backlight.sh set 50%       set it
#
# WHY THIS EXISTS. `amdgpu_bl1` was hardcoded in four places - the two
# brightness keybinds, power-mode.sh and the OSD - which is this laptop's
# panel and nothing else's. A desktop has NO backlight device at all, an Intel
# laptop calls it `intel_backlight`, and a second AMD machine could easily be
# `amdgpu_bl0`. Detecting it once, here, is what makes the rest of this
# repository run on a machine it was not written on.
#
# A MACHINE WITH NO BACKLIGHT IS NOT AN ERROR. Every subcommand exits 0 and
# prints nothing, so a desktop runs the same keybinds and the same power
# script as a laptop and simply does nothing when they fire. The alternative -
# failing loudly - would mean either guarding every call site or listening to
# a brightness key error on a machine that has no brightness.
#
# RESOLVED FROM /sys/class/backlight, not from `brightnessctl` with no
# arguments. The leds class next door holds the keyboard backlight, the power
# LED and the caps-lock indicator, and on this ChromeOS-derived board there
# are eleven of them; anything that picks "the first device" across both
# classes is one kernel change away from setting the brightness of a caps-lock
# light. The backlight class contains display backlights and nothing else.

set -euo pipefail

device() {
    local d
    for d in /sys/class/backlight/*; do
        # A directory with a readable brightness file. The glob itself matches
        # the literal pattern when nothing is there, hence the -e test.
        [[ -e "$d/brightness" ]] || continue
        basename "$d"
        return 0
    done
    return 1
}

case "${1:-}" in
    device)
        device || true
        ;;
    path)
        d="$(device)" && printf '/sys/class/backlight/%s\n' "$d" || true
        ;;
    set)
        [[ -n ${2:-} ]] || { printf 'backlight: usage: %s set <spec>\n' "$0" >&2; exit 1; }
        d="$(device)" || exit 0            # no backlight: nothing to do
        command -v brightnessctl >/dev/null 2>&1 || exit 0
        # -e4 is a quartic curve, which tracks perceived brightness rather than
        # raw value, and -n2 keeps it from ever reaching zero - a screen at 0%
        # is indistinguishable from one that has failed.
        #
        # STDERR IS DISCARDED, and that is not laziness. brightnessctl
        # ENUMERATES every device in both the backlight and leds classes before
        # acting, even when told exactly which one to use with -d, and on this
        # ChromeOS-derived board several of the LED classes expose no readable
        # brightness:
        #   End-of-file reading brightness of device 'chromeos:white:power'.
        # It then proceeds to set the right device correctly. Letting that
        # through would print two errors on every brightness keypress for an
        # operation that succeeded.
        brightnessctl -d "$d" -e4 -n2 set "$2" >/dev/null 2>&1
        ;;
    ""|-h|--help)
        printf 'usage: %s {device|path|set <spec>}\n' "$0" >&2
        exit 1
        ;;
    *)
        printf 'backlight: unknown command: %s\n' "$1" >&2
        exit 1
        ;;
esac
