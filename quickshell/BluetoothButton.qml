// =========================================================================
// BluetoothButton - the Bluetooth glyph in the bar's right pill
// =========================================================================
//
// Opens BluetoothPanel. Built like AudioButton and NetworkButton beside it: it
// draws, and Bar.qml handles the click and the drag that moves it along the bar.
//
// WHAT IT SHOWS, in order of precedence:
//   something connected      the connected glyph, in the accent colour
//   on, nothing connected    the plain glyph, dim
//   switched off             the struck-through glyph, dim
//
// NOT RED WHEN OFF, unlike the muted speaker. A muted machine is a state you
// did not mean; Bluetooth switched off is usually deliberate, and a red icon
// for a deliberate choice trains the eye to ignore red.
//
// ABSENT ENTIRELY WHERE THERE IS NO ADAPTER, so it costs a machine without
// Bluetooth nothing - no icon, and the singleton stops polling after the first
// answer. Same arrangement as the thermal readout, which is absent on the
// laptop for the same kind of reason.

import QtQuick

Item {
    id: root

    // Its own flag, not `visible` - which reports EFFECTIVE visibility and
    // would read false inside a hidden Loader. See BarZone.qml.
    readonly property bool shown: Bluetooth.present

    visible: root.shown
    implicitWidth: root.shown ? 22 : 0
    implicitHeight: 22

    // Picked out of a rendered grid, like every other glyph here.
    readonly property string glyph:
          !Bluetooth.powered   ? "\u{F00B2}"   // nf-md-bluetooth_off
        : Bluetooth.connected  ? "\u{F00B1}"   // nf-md-bluetooth_connect
                               : "\u{F00AF}"   // nf-md-bluetooth

    readonly property color tone:
          Bluetooth.connected ? Theme.accent
                              : Theme.dim

    // Hover backdrop, behind the glyph so hovering never resizes the pill.
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
        visible: root.shown
        text: root.glyph
        font.family: Theme.glyphFont
        // 18, not the speaker's 20: the Bluetooth rune fills its em box, so at
        // 20 it stood taller than the glyphs either side of it.
        font.pixelSize: 18
        color: hover.hovered ? Theme.fg : root.tone
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    opacity: root.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
}
