// =========================================================================
// NotifyButton - the bell, and what it says
// =========================================================================
//
// Three states in one glyph, because the bar has room for one:
//
//   bell            nothing waiting
//   bell-badge      history has unread entries
//   bell-off        do not disturb, in the danger colour
//
// CLICK OPENS THE PANEL, it does not toggle silence. Silencing is a mode you
// leave on for an hour, and a control you might hit by accident while
// reaching for the volume is the wrong home for it - the toggle lives inside
// the panel, where confirming what it did costs no extra click. The same
// reasoning that keeps couch mode and power behind two clicks.

import Quickshell
import QtQuick

Item {
    id: root

    implicitWidth: 22
    implicitHeight: 22

    readonly property bool dnd: NotificationService.doNotDisturb
    readonly property bool hasHistory: NotificationService.history.length > 0

    // CODEPOINTS VERIFIED BY RENDERING THEM, not by reading a table: the
    // first set taken from an icon list drew a bluetooth mark, a star and a
    // screen. These three were picked out of a printed grid of candidates.
    readonly property string glyph: {
        if (root.dnd)        return "\u{F009B}"   // bell with a slash
        if (root.hasHistory) return "\u{F009A}"   // filled bell
        return "\u{F009C}"                        // outline bell
    }

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
        text: root.glyph
        font.family: Theme.glyphFont
        // 17, NOT 20 LIKE THE SPEAKER, and that is measured rather than
        // eyeballed. The bell fills more of its em box than the other
        // glyphs: rendered at pixelSize 60 and measured off a screenshot,
        // the bell inks 52.4px against the speaker's and the wifi arc's
        // 44.7 - a seventh taller for the same nominal size, which is
        // exactly what made it look oversized in the bar. 20 x 44.7/52.4
        // is 17.1, so 17 puts the same amount of ink on screen.
        font.pixelSize: 17
        // Danger for silence, matching the muted speaker: both mean "this
        // machine is deliberately not telling you something".
        color: root.dnd      ? Theme.danger
             : hover.hovered ? Theme.fg
                             : Theme.pluginIcon
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
}
