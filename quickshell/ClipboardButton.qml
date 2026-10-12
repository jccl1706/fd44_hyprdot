// =========================================================================
// ClipboardButton - the clipboard history's glyph
// =========================================================================
//
// A GLYPH AND NOTHING ELSE, for the reason ClaudeButton.qml gives: a clipboard
// history is something you consult when you want it, never something you
// watch. A count of kept entries would be a number that changes every time you
// copy anything and tells you nothing you wanted to know.
//
// NO STATE, NOT EVEN THE TWO-STATE SHAPE the bell and the notebook use. Those
// say "there is something here" about a thing that was put there FOR you - an
// unread notification, a note you wrote. The clipboard always has something in
// it the moment you copy anything, so a filled glyph would mean "you have used
// this computer" and would be filled permanently.
//
// IT IS ALSO THE ONE PLUGIN WITH A KEYBIND, Mod+Shift+C, so this button is a
// second door rather than the only one - which is why hiding it costs less
// than hiding the others, and BarLayout's help text says so.

import Quickshell
import QtQuick

Item {
    id: root

    implicitWidth: 22
    implicitHeight: 22

    Rectangle {
        anchors.centerIn: parent
        width: 22
        height: 22
        radius: width / 2
        color: Theme.surfaceHigh
        opacity: hover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    Text {
        anchors.centerIn: parent
        // F0192, an outlined clipboard. VERIFIED BY RENDERING IT, the way
        // NotesButton's codepoints were: F1364 was the first guess and the
        // font has it, so nothing warned - but it draws a filled note with a
        // folded corner, and the bar grew a mystery square that read as tofu
        // and was not.
        //
        //   python3 -c '...' > g.txt
        //   pango-view --font="Symbols Nerd Font 36" -o g.png g.txt
        //
        // fc-list ":charset=F1364" said yes and the cmap gave a real glyph id:
        // both answer "is it in the font", which was never the question.
        text: "\u{F0192}"
        font.family: Theme.glyphFont
        // 16, matching the notebook: a clipboard is the same tall narrow cell
        // the notebook is, unlike the wide note glyph this started as.
        font.pixelSize: 16
        color: hover.hovered ? Theme.fg : Theme.pluginIcon
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    HoverHandler {
        id: hover
        // No cursorShape - see the note in Bar.qml.
    }
}
