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

# THE PERCEPTUAL CURVE, AND THE ONLY PLACE IT IS WRITTEN DOWN.
#
# A percentage given to this script is what you want to SEE; brightnessctl
# raises it to this power to get the value the panel wants. quickshell/
# Backlight.qml asks for this number with `backlight.sh curve` and inverts it to
# display a level, so the slider, the OSD and this script cannot drift apart.
#
# 2.2 IS THE DISPLAY GAMMA, NOT A TUNING. It was -e4, brightnessctl's default,
# and a fourth power is far steeper than the eye: it put the whole lower half of
# every slider into the bottom 6% of the panel's range.
#
#     slider    -e4         2.2
#        10%    raw 7       raw 413
#        30%    raw 531     raw 4636
#        50%    raw 4096    raw 14263
#
# At -e4 this panel was simply off at 10% and unreadable at 50%, which is how it
# was noticed. 2.2 is the sRGB gamma - the same exponent used to encode the
# images on the screen - so a slider at half now looks about half lit.
#
# CHANGING IT CHANGES WHAT EVERY STORED LEVEL MEANS. settings.json holds
# brightnessOnAc and brightnessOnBattery as numbers on this curve, so they get
# brighter or dimmer when this moves. Nothing breaks; they just want redialling.
CURVE=2.2

case "${1:-}" in
    curve)
        printf '%s\n' "$CURVE"
        ;;
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
        # THE CURVE IS $CURVE AND IT IS DEFINED ONCE - see the note there.
        # -n2 keeps it from ever reaching zero: a screen at 0% is
        # indistinguishable from one that has failed.
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
        brightnessctl -d "$d" -e"$CURVE" -n2 set "$2" >/dev/null 2>&1
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
