// =========================================================================
// Media - MPRIS transport control for the media keys
// =========================================================================
//
// Replaces playerctl. The four XF86Audio media keys used to shell out to it
// once per press; quickshell speaks MPRIS itself, so the keys now reach this
// through a global shortcut and no process is spawned at all.
//
// That is the same reasoning binds.lua already gives for the launcher and the
// wallpaper picker using global shortcuts rather than exec_cmd - the media
// keys were simply the ones that had not been moved over yet. It also drops a
// package: playerctl was never in the installer's list and survived on the
// development machine only as a weak dependency of something unrelated.
//
// WHICH PLAYER A KEY ACTS ON. playerctl picks the most recently active by
// default and that is roughly what is wanted here, but quickshell hands over
// an unordered set, so the choice is made explicitly:
//
//   1. one that is actually playing, if there is one
//   2. otherwise the first controllable one
//
// Rule 2 matters more than it looks. Paused media still responds to a media
// key, and after a pause the "playing" set is empty - without the fallback,
// pressing play again would do nothing at all, which reads as the key being
// broken rather than as there being no player.
//
// Every call is guarded by the player's own capability flag. MPRIS clients
// advertise what they support and they are not all the same: Chromium reports
// canGoNext false on a page with a single audio element, and calling next()
// there is at best ignored and at worst an error on the bus.

pragma Singleton

import Quickshell
import Quickshell.Services.Mpris
import QtQuick

Singleton {
    id: root

    readonly property var active: {
        const players = Mpris.players.values
        for (const p of players)
            if (p.canControl && p.isPlaying) return p
        for (const p of players)
            if (p.canControl) return p
        return null
    }

    // True when there is anything to control - the bar can use this later to
    // show or hide a transport module without asking about players itself.
    readonly property bool hasPlayer: root.active !== null

    function togglePlaying(): void {
        const p = root.active
        if (p && p.canTogglePlaying) p.togglePlaying()
    }

    function next(): void {
        const p = root.active
        if (p && p.canGoNext) p.next()
    }

    function previous(): void {
        const p = root.active
        if (p && p.canGoPrevious) p.previous()
    }
}
