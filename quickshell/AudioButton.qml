// =========================================================================
// AudioButton - the speaker glyph in the bar's right pill
// =========================================================================
//
// Opens AudioPanel. The glyph follows the default output the same way the OSD
// does - muted, low, medium, high - so it is an indicator you can also click,
// like ThemeToggle beside the clock.
//
// It knows nothing about the panel. It only announces the click; Bar.qml
// passes that up to shell.qml, which opens the panel on THIS monitor. A
// button reaching for a window by id would tie the bar to one panel instance.

import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

Item {
    id: root

    signal activated()

    // 22, not ThemeToggle's 20: alone in its pill it has nothing beside it to
    // borrow presence from, and at 14px the speaker read as a speck.
    implicitWidth: 22
    implicitHeight: 22

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    readonly property real volume: Pipewire.defaultAudioSink?.audio?.volume ?? 0
    readonly property bool muted:  Pipewire.defaultAudioSink?.audio?.muted ?? false

    // Same thresholds and glyphs as Osd.qml, so the two never disagree about
    // what "medium" looks like.
    readonly property string glyph: {
        if (muted)          return "\u{F075F}"   // nf-md-volume_off
        if (volume < 0.34)  return "\u{F057F}"   // nf-md-volume_low
        if (volume < 0.67)  return "\u{F0580}"   // nf-md-volume_medium
        return "\u{F057E}"                       // nf-md-volume_high
    }

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
        text: root.glyph
        font.family: Theme.glyphFont
        // 20, above Theme.glyphSize: the speaker glyphs fill only part of
        // their em box - the "low" one, with no waves, most of all - so at 18
        // it still drew about 11px across in a 26px pill.
        font.pixelSize: 20
        color: hover.hovered ? Theme.fg : Theme.dim
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    HoverHandler { id: hover }

    TapHandler {
        cursorShape: Qt.PointingHandCursor
        onTapped: root.activated()
    }
}
