#!/usr/bin/env bash
# =========================================================================
# game-dnd.sh - silence notifications while a game is running
# =========================================================================
#
# Usage:  bin/game-dnd.sh on|off
#
# GameMode's start and end hooks call this, so a toast cannot land over a
# fullscreen game - on Wayland an overlay surface drawn above a game is not
# just a distraction, it is a frame the compositor has to composite differently
# and, with some games, a moment of stutter.
#
# WHY A HOOK AND NOT A RULE IN THE SHELL. Quickshell could watch for a
# fullscreen window instead, and that would silence a film as well as a game.
# GameMode is the signal that means "a game asked for the machine's attention",
# and it is already wired on both machines for the CPU governor - this is the
# same event, used twice.
#
# CRITICAL NOTIFICATIONS STILL GET THROUGH: NotificationService.bypassesDnd
# lets an urgent message from this repository's own scripts past, so a backup
# that failed mid-game still says so. Silence is for chat and updates.
#
# IT NEVER FAILS A GAME. Every path exits 0: if the shell is not running, or
# the call does not land, a game must still start and still end. A silenced
# desktop is a nuisance; a game that will not launch because a bar is missing
# is a broken machine.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || here="$HOME/Work/fd44_hyprdot/bin"

case "${1-}" in
    on|off) state="$1" ;;
    *) printf 'usage: %s on|off\n' "${0##*/}" >&2; exit 2 ;;
esac

# bin/qs-ipc.sh finds the running shell from quickshell's own registry, which
# is what makes this work from gamemoded's environment rather than only from a
# terminal in the session.
if [[ -x $here/qs-ipc.sh ]]; then
    "$here/qs-ipc.sh" call notifications silence "$state" >/dev/null 2>&1 || true
fi
exit 0
