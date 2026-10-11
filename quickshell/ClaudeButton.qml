// =========================================================================
// ClaudeButton - the pill glyph for Claude Code's token usage
// =========================================================================
//
// A GLYPH AND NOTHING ELSE. The numbers live in ClaudePanel, a click away,
// because none of them is worth the width in a bar: a token count is a figure
// you consult when you wonder about it, not one you monitor. The plugins that
// do carry text here - updates, backup, failures - earn it by being silent
// until something is waiting for you.
//
// COLOUR ONLY WHEN SOMETHING IS WRONG is this bar's rule, stated in
// BatteryButton.qml, and it is why this glyph does not tint by volume. There
// is no threshold to tint against: the transcripts record what was spent and
// never what the allowance was, so "a lot" is a judgement this plugin is not
// entitled to make. The one state it does colour is the block running out,
// which is a fact about the clock rather than an opinion about the usage.

import QtQuick

Item {
    id: root
    implicitWidth: 20
    implicitHeight: 20

    // nf-md-creation: a many-pointed star, the closest glyph in the Nerd Font
    // set to the mark Claude uses, and distinct from everything else in the
    // pill at this size.
    readonly property string glyph: "\u{F0674}"

    // The last ten minutes of a block. Not a warning - nothing is wrong - but
    // it is the one moment when knowing changes what you do next, so it is the
    // one moment the glyph speaks up.
    readonly property bool rollingOver:
        ClaudeUsage.ready && ClaudeUsage.blockEndsIn > 0
        && ClaudeUsage.blockEndsIn < 600

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
        text: root.glyph
        font.family: Theme.glyphFont
        font.pixelSize: 14
        // Unread is dimmer than idle, so a shell that has not scanned yet does
        // not look like one that has and found nothing.
        color: !ClaudeUsage.ready ? Qt.rgba(Theme.dim.r, Theme.dim.g, Theme.dim.b, 0.5)
             : root.rollingOver   ? Theme.accent
             : hover.hovered      ? Theme.fg
                                  : Theme.dim
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    HoverHandler { id: hover }

    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: (ev) => {
            // Right click rescans now rather than waiting for the timer, which
            // is the only thing a second action could usefully do here.
            if (ev.button === Qt.RightButton) { ClaudeUsage.refresh(); return }
            root.requested()
        }
    }

    signal requested()
}
