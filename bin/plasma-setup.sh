#!/usr/bin/env bash
# =========================================================================
# plasma-setup.sh - the KDE Plasma settings that cannot be symlinked
# =========================================================================
#
# Usage:  bin/plasma-setup.sh            apply them (no sudo)
#         bin/plasma-setup.sh --show     print what is set now and exit
#
# WHY A SCRIPT AND NOT LINKS. Everything link-dotfiles.sh handles is a file
# this repository owns and Plasma only reads. These are the opposite: Plasma
# WRITES them, every time you move a widget or touch a settings page, so a
# symlink would either be clobbered or would push edits back into git as
# noise. kwriteconfig6 changes one key and leaves the rest of the file to
# Plasma, which is the only arrangement that survives.
#
# WHAT IT DOES NOT DO. It does not install Plasma, choose a theme, or touch
# anything the installer already sets. It is the short list of things that
# were worked out by hand on the Framework on 2026-09-23 and would otherwise
# have to be rediscovered on the next machine.
#
# Safe to run twice - every setting is written by key, not appended.

set -euo pipefail

have() { command -v "$1" >/dev/null 2>&1; }

have kwriteconfig6 || { echo "kwriteconfig6 not found - this is a Plasma machine only" >&2; exit 1; }
have plasmashell    || { echo "plasmashell not found - nothing to configure" >&2; exit 1; }

kr()  { kreadconfig6  --file "$@" 2>/dev/null; }
kw()  { kwriteconfig6 --file "$@"; }

if [[ "${1:-}" == "--show" ]]; then
    printf '\ncurrent Plasma settings this script manages\n\n'
    printf '  konsole default profile   %s\n' "$(kr konsolerc --group 'Desktop Entry' --key DefaultProfile)"
    for s in AC Battery LowBattery; do
        printf '  power profile on %-12s %s\n' "$s" \
            "$(kr powerdevilrc --group "$s" --group Performance --key PowerProfile)"
    done
    printf '  tray always-shown         %s\n' \
        "$(kr plasma-org.kde.plasma.desktop-appletsrc \
             --group Containments --group 2 --group Applets --group 7 \
             --group General --key shownItems)"
    printf '\n  fonts (blank = Plasma default, which is what is wanted)\n'
    for k in font fixed smallestReadableFont toolBarFont menuFont; do
        printf '    %-22s %s\n' "$k" "$(kr kdeglobals --group General --key "$k")"
    done
    printf '    %-22s %s\n' "fontconfig sans" "$(fc-match sans 2>/dev/null)"
    printf '    %-22s %s\n' "fontconfig rgba" \
        "$(fc-match --verbose sans 2>/dev/null | awk '/rgba:/{print $2}')"
    printf '\n'
    exit 0
fi

# ---- konsole -------------------------------------------------------------
#
# The profile and its colour scheme ARE linked, by link-dotfiles.sh, into
# ~/.local/share/konsole. Only the choice of default profile lives here,
# because konsolerc is rewritten by konsole itself.
#
# The scheme matters more than it sounds: tmux.conf names ANSI colours rather
# than hex so the status bar follows the terminal, which makes konsole's
# palette the bar's palette. konsole 26 ships no .colorscheme files at all -
# they are compiled into the binary - and starts on the classic palette, not
# Breeze.
if [[ -e "${XDG_DATA_HOME:-$HOME/.local/share}/konsole/fd44.profile" ]]; then
    kw konsolerc --group 'Desktop Entry' --key DefaultProfile fd44.profile
    echo "konsole       default profile -> fd44.profile"
else
    echo "konsole       SKIPPED - run bin/link-dotfiles.sh first"
fi

# ---- power profiles ------------------------------------------------------
#
# THE KEY IS IN A SUBGROUP, and that is the whole reason this block exists.
# Writing `powerProfile` into [Battery] looks right, is accepted silently and
# does nothing; powerdevil reads `PowerProfile` from [Battery][Performance].
# Measured on the Framework: with only the former set, unplugging moved the
# energy-performance hint to balance_power but left the profile on balanced.
#
# It applies on an AC TRANSITION, not on login or on a powerdevil restart, so
# nothing appears to happen until the charger is next moved.
#
# AC is performance rather than balanced, deliberately: this is a laptop that
# spends its plugged-in life on a desk, and the fan noise is the price.
kw powerdevilrc --group AC         --group Performance --key PowerProfile performance
kw powerdevilrc --group Battery    --group Performance --key PowerProfile power-saver
kw powerdevilrc --group LowBattery --group Performance --key PowerProfile power-saver
echo "powerdevil    AC performance / battery power-saver"

# ---- system tray ---------------------------------------------------------
#
# Pin the battery applet, which is where KDE keeps its "keep awake" switch -
# "Manually block sleep and screen locking", the thing other desktops call
# caffeine. Without this the tray leaves it on automatic and collapses it into
# the overflow arrow, so the toggle is two clicks away instead of one.
#
# ONLY WHERE THERE IS A SYSTEM BATTERY, and "is there a battery" is a narrower
# question than it looks. /sys/class/power_supply holds anything that reports a
# charge, which on fedora-gaming00 is
#
#     hidpp_battery_0   type=Battery   model=PRO X Wireless
#
# a wireless headset. Testing for type=Battery pinned the applet on a desktop
# and put a permanent headset-charge icon in the tray, which is not what this
# setting is for. A laptop has BAT0 or BAT1; peripherals do not.
#
# THE NUMBERS ARE FOUND, NOT ASSUMED. This used to write to containment 2,
# applet 7 - the Framework's layout on the day it was worked out - with a
# comment saying it would do nothing elsewhere. It did nothing elsewhere: on
# the rebuilt desktop the tray is containment 285, applet 290, and the key went
# into a group no program reads. Harmless, silent, and useless, which is the
# worst combination because --show reported the value it had just written.
#
# Applet ids are generated per machine and change whenever a panel is rebuilt,
# so the only reliable way to name the tray is to look for the plugin.
APPLETSRC="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-org.kde.plasma.desktop-appletsrc"
tray_group="$(awk '
    /^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$/ { grp = $0 }
    /^plugin=org\.kde\.plasma\.systemtray$/ { print grp; exit }
' "$APPLETSRC" 2>/dev/null)"

has_system_battery() {
    local b
    for b in /sys/class/power_supply/BAT*; do [[ -e $b ]] && return 0; done
    return 1
}

if [[ ! $tray_group =~ \[Containments\]\[([0-9]+)\]\[Applets\]\[([0-9]+)\] ]]; then
    echo "system tray   not found in $APPLETSRC - nothing written"
elif has_system_battery; then
    kw plasma-org.kde.plasma.desktop-appletsrc \
       --group Containments --group "${BASH_REMATCH[1]}" \
       --group Applets --group "${BASH_REMATCH[2]}" --group General \
       --key shownItems org.kde.plasma.battery
    echo "system tray   battery applet always shown (containment ${BASH_REMATCH[1]}, applet ${BASH_REMATCH[2]})"
else
    # NOT LEFT ALONE - UNDONE. A machine that once had this pinned by an earlier
    # version of this script keeps it pinned forever otherwise, which is how the
    # headset icon survived being explained.
    kw plasma-org.kde.plasma.desktop-appletsrc \
       --group Containments --group "${BASH_REMATCH[1]}" \
       --group Applets --group "${BASH_REMATCH[2]}" --group General \
       --key shownItems --delete
    echo "system tray   no system battery here - battery applet left on automatic"
fi

# ---- fonts ---------------------------------------------------------------
#
# NOTHING TO SET, and that is the finding worth recording rather than a gap.
# ~/.config/kdeglobals has no font keys at all on a working Plasma machine:
# every role sits on the Plasma default, which on Fedora 44 resolves to
#
#     font                  Noto Sans, 10
#     fixed                 Noto Sans Mono, 10
#     smallestReadableFont  Noto Sans, 8
#     toolBarFont           Noto Sans, 9
#     menuFont              Noto Sans, 10
#
# Writing those out would pin values that are already right and would stop
# following the distribution if it ever revised them.
#
# AND THAT IS STILL TRUE OF THIS SCRIPT, BUT NO LONGER TRUE OF EVERY MACHINE.
# fedora-gaming00 reads
#
#     font    Inter,10,-1,5,400,...
#
# because bin/font-setup.sh was run there deliberately: Inter, with hinting
# almost off, for type that renders the way macOS renders it. That is a choice
# made per machine and asked for, not a default that drifted - which is exactly
# why it lives in its own opt-in script and not here. --show prints whatever is
# set, so a non-blank font line means font-setup.sh has been run on that
# machine, not that something went wrong.
#
# WHAT ACTUALLY MAKES PLASMA TEXT LOOK BETTER is not a Plasma setting at all.
# Fedora's kde-settings ships /etc/fonts/conf.d/10-sub-pixel-rgb-for-kde.conf,
# which tests the desktop name and enables RGB sub-pixel rendering FOR KDE
# ONLY. Measured on this laptop against the Hyprland desktop:
#
#     Plasma     rgba: 1 (rgb)    hinting: True(s)   sans: Noto Sans
#     Hyprland   rgba: 5 (none)   hinting: True(w)   sans: DejaVu Sans
#
# So Hyprland or Sway on the same Fedora release gets grey-scale antialiasing
# while Plasma gets sub-pixel, and nothing in either desktop says so. On NixOS
# the equivalent is declarative - fd44_nixos modules/packages.nix,
# fonts.fontconfig.subpixel.rgba - because nixpkgs disables it by default and
# names DejaVu as the default sans.
#
# To give a non-KDE session the same treatment, drop a fontconfig file that
# sets rgba unconditionally instead of testing the desktop name.

printf '\nDone. Two of these need a nudge:\n'
printf '  systemctl --user restart plasma-plasmashell   for the tray\n'
printf '  unplug and replug                             for the power profiles\n'
printf 'konsole picks up its profile in new windows.\n\n'
