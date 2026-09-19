// =========================================================================
// BatteryButton - charge level
// =========================================================================
//
// One glyph, coloured like every other glyph in the bar. The level is in the
// SHAPE - the cell fills as the charge does, a bolt means charging - so the
// colour is free to mean what it means everywhere else on the bar: grey at
// rest, brighter under the pointer.
//
// NO PERCENTAGE. The number was tried and removed: it makes this the only
// plugin with text in it, and the glyph already says what a glance needs. If
// the exact figure is wanted it is in the lock screen and in tmux, both of
// which already show it.
//
// COLOUR ONLY WHEN SOMETHING IS WRONG, which is the convention the speaker
// follows - grey normally, danger when muted. The difference here is what
// counts as wrong: this laptop is plugged in and holding at its 80% charge
// limit almost all the time, and tinting that left the battery permanently
// coloured while everything beside it was grey. Charging and the charge
// limit are ordinary states and get the ordinary colour; only genuinely low
// on mains-free charge earns the danger one.
//
// Codepoints verified by rendering a grid and looking, the same way the
// bell's were: F0084 is the bolt, F007A to F0082 climb from a tenth to nine
// tenths, F0079 is full and F0083 is the exclamation.

import Quickshell
import QtQuick

Item {
    id: root

    implicitWidth: 22
    implicitHeight: 22

    readonly property string levelGlyph: {
        const p = Battery.percent
        if (p >= 95) return "\u{F0079}"                 // full
        if (p < 10)  return "\u{F008E}"                 // empty outline
        // 10-19 -> F007A, 20-29 -> F007B, ... 90-94 -> F0082
        return String.fromCodePoint(0xF007A + Math.min(8, Math.floor(p / 10) - 1))
    }

    readonly property string shownGlyph:
        !Battery.ready     ? "\u{F008E}"                // nothing read yet
      : Battery.charging   ? "\u{F0084}"                // bolt
      : Battery.critical   ? "\u{F0083}"                // exclamation
                           : root.levelGlyph

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
        text: root.shownGlyph
        font.family: Theme.glyphFont
        // 16 rather than the speaker's 20: a battery is a tall narrow cell
        // and inks taller than a speaker at the same nominal size - the same
        // trap the bell fell into, measured the same way.
        font.pixelSize: 16
        color: (Battery.critical || Battery.low) ? Theme.danger
             : hover.hovered                     ? Theme.fg
                                                 : Theme.pluginIcon
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    HoverHandler {
        id: hover
        // No cursorShape - see the note in Bar.qml.
    }
}
