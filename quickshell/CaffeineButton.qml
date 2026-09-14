// =========================================================================
// CaffeineButton - the coffee cup beside the theme toggle
// =========================================================================
//
// Switches Caffeine.qml on and off: while it is on the machine does not lock,
// blank the screen or suspend on idle. A movable plugin like the others, so
// clicks and drags are Bar.qml's; this only draws.
//
// SHOWS THE STATE IT IS IN, like ThemeToggle: a full cup in the accent colour
// means "staying awake", an outline cup in the dim colour means "normal idle
// behaviour". Accent rather than danger red - being kept awake is a choice,
// not a fault, but it should still be noticeable from across the room.

import QtQuick

Item {
    id: root

    implicitWidth: 20
    implicitHeight: 20

    readonly property string cupGlyph:     "\u{F0176}"   // nf-md-coffee
    readonly property string outlineGlyph: "\u{F06CA}"   // nf-md-coffee_outline

    // Hover backdrop, behind the glyph so hovering never resizes the pill.
    Rectangle {
        anchors.centerIn: parent
        width: 20
        height: 20
        radius: width / 2
        color: Theme.surfaceHigh
        opacity: hover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    Text {
        anchors.centerIn: parent
        text: Caffeine.active ? root.cupGlyph : root.outlineGlyph
        font.family: Theme.glyphFont
        // 14, not ThemeToggle's 13: the cup is a solid shape that fills more of
        // its em box than the thin-line moon. At 15 it drew 13.2 x 11.8 px
        // beside the moon's 10.2 x 11.3 and read as the heavier icon; at 13
        // it would come out shorter than the moon.
        font.pixelSize: 14
        color: Caffeine.active ? Theme.accent
             : hover.hovered   ? Theme.fg
                               : Theme.dim
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        // A small bump when it switches, so the change registers as the
        // result of the click rather than as the icon being swapped.
        scale: 1
        Connections {
            target: Caffeine
            function onActiveChanged() { bump.restart() }
        }
        SequentialAnimation on scale {
            id: bump
            running: false
            NumberAnimation { to: 1.25; duration: Theme.animFast; easing.type: Easing.OutCubic }
            NumberAnimation { to: 1.0;  duration: Theme.animNormal; easing.type: Easing.InOutCubic }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
}
