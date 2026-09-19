pragma Singleton

// =========================================================================
// Notes - the scratchpad's text, and keeping it
// =========================================================================
//
// One plain file, ~/.local/state/fd44-hyprdot/notes.md, beside the bar
// layout and the active theme. Markdown by extension rather than by
// rendering: nothing here parses it, but a scratchpad's contents end up
// somewhere else often enough that the name is worth getting right.
//
// SAVED ON A DEBOUNCE, not on every keystroke. Typing at speed would
// otherwise write the whole file a dozen times a second. 800ms after the
// last change is long enough to cover a sentence and short enough that
// nothing is lost to a crash you would not also have lost the window to.
//
// AND ON CLOSE, because the debounce has not necessarily fired when the
// panel goes away - the last thing typed before dismissing it is exactly
// the thing worth keeping.

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: notes

    property string text: ""
    property bool dirty: false

    // Drives the bar glyph: an empty scratchpad looks different from one
    // with something in it, the same way the bell does.
    readonly property bool hasContent: notes.text.trim() !== ""

    function setText(t): void {
        const s = String(t)
        if (s === notes.text) return
        notes.text = s
        notes.dirty = true
        saveTimer.restart()
    }

    function flush(): void {
        if (!notes.dirty) return
        file.setText(notes.text)
        notes.dirty = false
    }

    Timer {
        id: saveTimer
        interval: 800
        onTriggered: notes.flush()
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
              + "/fd44-hyprdot/notes.md"
        // No file until the first note, which is not worth a warning on
        // every start.
        printErrors: false
        onLoaded: {
            // Only on the way in. A reload after our own write would
            // otherwise stamp on whatever has been typed since.
            if (!notes.dirty) notes.text = file.text()
        }
        onSaveFailed: err => console.warn("notes: could not save:",
                                          FileViewError.toString(err))
    }
}
