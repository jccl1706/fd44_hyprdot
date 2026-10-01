// =========================================================================
// ThemeLibrary - the palettes in themes/, and which one is on
// =========================================================================
//
// WallpaperLibrary for colours. The settings panel shows the wallpapers as
// tiles you click, and asked the same of the themes - so this supplies the
// same three things that row needs: a list, which one is current, and a way
// to choose another.
//
// IT ASKS bin/theme.sh RATHER THAN READING themes/*.conf. That script already
// parses these files to apply them, and `theme.sh json` reports exactly what a
// swatch needs to draw. A QML parser beside the bash one would be a second
// implementation of the same format, out of step the first time a key moves.
//
// AND THE LIST IS NOT WRITTEN DOWN ANYWHERE. Until this existed, adding a
// palette meant adding a file AND editing a hardcoded options list in
// Settings.qml - one of which is easy to forget, and the symptom is a theme
// that works from the terminal and cannot be chosen from the panel.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: library

    // [{ name, appearance, bg, fg, surface, surfaceTop, accent, outline }]
    property var themes: []

    // The name of the one in use. Theme.qml already knows this - it is reading
    // the active palette - so there is no second source of truth here.
    readonly property string current: Theme.name

    readonly property string script:
        "\"$(dirname \"$(readlink -f '" + Quickshell.shellDir + "')\")/bin/theme.sh\""

    function rescan(): void {
        if (lister.running) return
        lister.command = ["sh", "-c", library.script + " json"]
        lister.running = true
    }

    // Applying a theme is bin/theme.sh's job, not this shell's: it has to reach
    // kitty, btop, GTK and hyprlock as well, and the bar re-colours by watching
    // the file the script writes rather than by being told.
    function choose(name: string): void {
        if (!name || name === library.current) return
        setter.command = ["sh", "-c", library.script + " set '" + name + "'"]
        setter.running = true
    }

    function isCurrent(name: string): bool {
        return name === library.current
    }

    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    library.themes = JSON.parse((text || "[]").trim() || "[]")
                } catch (e) {
                    library.themes = []
                }
            }
        }
    }

    Process { id: setter }

    Component.onCompleted: library.rescan()
}
