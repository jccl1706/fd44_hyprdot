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
# CONTAINMENT 2, APPLET 7 is this machine's panel layout and is not a constant.
# If the tray is somewhere else the key lands in a group nothing reads, which
# is harmless but does nothing - check with --show, and find the right numbers
# with: grep -n systemtray ~/.config/plasma-org.kde.plasma.desktop-appletsrc
kw plasma-org.kde.plasma.desktop-appletsrc \
   --group Containments --group 2 --group Applets --group 7 --group General \
   --key shownItems org.kde.plasma.battery
echo "system tray   battery applet always shown"

printf '\nDone. Two of these need a nudge:\n'
printf '  systemctl --user restart plasma-plasmashell   for the tray\n'
printf '  unplug and replug                             for the power profiles\n'
printf 'konsole picks up its profile in new windows.\n\n'
