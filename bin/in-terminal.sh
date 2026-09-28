#!/usr/bin/env bash
# =========================================================================
# in-terminal.sh - run something in a terminal window, and leave it open
# =========================================================================
#
# Usage:  bin/in-terminal.sh "<window title>" command [args...]
#
# For the bar's icons: clicking one that starts a long, talkative job opens a
# window rather than doing it silently. bin/updates.sh and bin/backup.sh both
# want this, and neither should own it.
#
# THE WINDOW STAYS OPEN AFTER THE COMMAND ENDS. A terminal that vanishes on
# success tells you nothing about what it did, and one that vanishes on
# failure tells you less - the whole point of showing the window is the
# transcript.
#
# IT DOES NOT DETACH. Whoever calls it decides that: quickshell backgrounds it
# so the shell is not the parent of a window someone leaves open for an hour,
# and a person running it from a terminal wants it in the foreground.

set -uo pipefail

title="${1:?usage: in-terminal.sh TITLE COMMAND [ARGS...]}"
shift
(( $# )) || { printf 'in-terminal: nothing to run\n' >&2; exit 2; }

# kitty is the terminal on both machines; the rest are there so this still
# works on a machine with something else.
for term in kitty alacritty foot xterm; do
    command -v "$term" >/dev/null 2>&1 && break
    term=""
done
[[ -n $term ]] || { printf 'in-terminal: no terminal found (kitty, alacritty, foot, xterm)\n' >&2; exit 2; }

# The command is passed to bash as "$@" rather than pasted into a string, so
# an argument with a space in it stays one argument.
# OPAQUE, for kitty. These windows appear over whatever was already on
# screen - a terminal full of text, a game - and the translucency that suits a
# terminal you work in over a wallpaper makes two lines of output compete with
# everything behind them. Hyprland cannot fix this from a window rule: kitty
# renders its own alpha and a compositor opacity rule only scales what the
# client drew.
opaque=()
[[ $term == kitty ]] && opaque=(-o background_opacity=1)

exec "$term" "${opaque[@]}" --title "$title" -e bash -c '
    "$@"
    status=$?
    printf "\n\033[1;32m==>\033[0m %s" "done"
    (( status )) && printf " \033[1;31m(exit %s)\033[0m" "$status"
    printf " - press enter to close"
    read -r
' bash "$@"
