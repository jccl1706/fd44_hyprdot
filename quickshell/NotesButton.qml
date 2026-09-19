// =========================================================================
// NotesButton - the scratchpad's glyph
// =========================================================================
//
// Outlined when empty, filled when there is something in it - the same
// two-state shape the bell uses, so "there is something here" reads the same
// way across the bar without needing a colour.
//
// Codepoints verified by rendering a grid and looking: F0EBF is the outlined
// notebook and F082E the filled one.

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
        text: Notes.hasContent ? "\u{F082E}" : "\u{F0EBF}"
        font.family: Theme.glyphFont
        // 16: a notebook is a tall cell like the battery and inks taller than
        // the speaker at the same nominal size.
        font.pixelSize: 16
        color: hover.hovered ? Theme.fg : Theme.pluginIcon
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    HoverHandler {
        id: hover
        // No cursorShape - see the note in Bar.qml.
    }
}
