// =========================================================================
// BatteryButton - charge level, and whether that is a problem
// =========================================================================
//
// Glyph plus the number, because neither alone is enough at a glance: the
// glyph says "fine / low / charging" without reading, the number says
// whether 20% means twenty minutes or two hours. The lock screen and tmux
// have shown both for a while; the bar was the one place that showed
// neither.
//
// COLOUR CARRIES THE MEANING, the glyph carries the level:
//
//   accent      charging, or plugged in and holding at the charge limit
//   danger      running down and low
//   pluginIcon  running down, nothing to say
//
// THE CHARGE LIMIT IS NOT A WARNING. Plugged in at 80% reporting "Not
// charging" is this laptop's BIOS doing what it was told, so it gets the
// same accent as charging rather than the danger colour - see Battery.qml.
// A bar that looks alarmed every time the machine is behaving correctly
// teaches you to ignore it.
//
// Codepoints verified by rendering a grid of candidates and looking, the
// same way the bell's were: F0084 is the bolt, F007A to F0082 climb from a
// tenth to nine tenths, F0079 is full and F0083 is the exclamation.

import Quickshell
import QtQuick

Item {
    id: root

    implicitWidth: glyph.width + label.width + 4
    implicitHeight: 22

    readonly property string levelGlyph: {
        const p = Battery.percent
        if (p >= 95) return "\u{F0079}"                 // full
        if (p < 10)  return "\u{F008E}"                 // empty outline
        // 10-19 -> F007A, 20-29 -> F007B, ... 90-94 -> F0082
        return String.fromCodePoint(0xF007A + Math.min(8, Math.floor(p / 10) - 1))
    }

    readonly property string shownGlyph:
        Battery.charging ? "\u{F0084}"                  // bolt
      : Battery.critical ? "\u{F0083}"                  // exclamation
                         : root.levelGlyph

    readonly property color shownColor:
        Battery.critical           ? Theme.danger
      : Battery.low                ? Theme.danger
      : Battery.charging           ? Theme.accent
      : Battery.limited            ? Theme.accent
      : hover.hovered              ? Theme.fg
                                   : Theme.pluginIcon

    Rectangle {
        anchors.centerIn: parent
        width: root.implicitWidth + 8
        height: 22
        radius: 11
        color: Theme.surfaceHigh
        opacity: hover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    Text {
        id: glyph
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        text: root.shownGlyph
        font.family: Theme.glyphFont
        // 16: these glyphs are a tall narrow cell and read larger than the
        // speaker at the same nominal size, the same trap the bell fell into.
        font.pixelSize: 16
        color: root.shownColor
        Behavior on color { ColorAnimation { duration: Theme.animNormal } }
    }

    Text {
        id: label
        anchors { left: glyph.right; leftMargin: 4; verticalCenter: parent.verticalCenter }
        // An em dash until the first read lands, rather than "0%".
        text: Battery.ready ? Battery.percent + "%" : "\u2014"
        font.family: Theme.font
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.weightMedium
        // The number stays readable even when the glyph is shouting: only
        // the genuinely low states tint it.
        color: (Battery.critical || Battery.low) ? Theme.danger
             : hover.hovered                     ? Theme.fg
                                                 : Theme.dim
        Behavior on color { ColorAnimation { duration: Theme.animNormal } }
    }

    HoverHandler {
        id: hover
        // No cursorShape - see the note in Bar.qml.
    }
}
