// =========================================================================
// WallpaperState - which wallpaper is on screen
// =========================================================================
//
// One value, shared by every monitor's Wallpaper and by the picker: the
// absolute path of the wallpaper in use.
//
// THE STATE FILE IS THE SOURCE OF TRUTH, not this object. bin/wallpaper.sh
// records the choice in ~/.local/state/wallpaper, and this watches that file.
// So a wallpaper set from a terminal (`wallpaper.sh set <path>`) fades in live
// exactly like one chosen in the picker, and a quickshell restart comes back
// showing the same image - there is nothing to re-apply.
//
// The picker does not wait for that round trip: apply() changes `path` first,
// so the fade starts on the keypress, and then has the script record it. The
// watcher then reads back the same path and nothing changes a second time.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: state

    // "" until the state file has been read.
    property string path: ""

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
              + "/wallpaper"
        watchChanges: true
        // Missing is the normal state on a first login, until autostart's
        // `wallpaper.sh restore` has picked a default.
        printErrors: false
        onFileChanged: file.reload()
        onLoaded: {
            retry.stop()
            const p = file.text().trim()
            // An empty file is a write caught halfway (the watcher can fire
            // between truncate and write), not a choice of "no wallpaper".
            if (p !== "") state.path = p
        }
        onLoadFailed: err => { if (retry.tries < retry.maxTries) retry.start() }
    }

    // A watch on a file that does not exist yet sees nothing when it appears,
    // so on a first login look again until restore has written it. A minute
    // is far longer than that takes; after it, a machine with no wallpapers at
    // all stops polling and simply shows the theme's background colour.
    Timer {
        id: retry
        property int tries: 0
        readonly property int maxTries: 60
        interval: 1000
        repeat: true
        onTriggered: {
            tries++
            if (tries >= maxTries) stop()
            file.reload()
        }
    }

    Process {
        id: recorder
        onExited: (code, status) => {
            if (code !== 0) console.warn("wallpaper.sh set failed with", code)
        }
    }

    // Show `p` now and remember it. `script` is bin/wallpaper.sh, which the
    // picker resolves - this has no way of its own to find the repo.
    function apply(p: string, script: string): void {
        if (!p) return
        state.path = p
        if (!script) return
        recorder.command = [script, "set", p]
        recorder.running = true
    }
}
