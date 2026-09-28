// =========================================================================
// BackupButton - the disk that appears when a backup is overdue
// =========================================================================
//
// Absent while backups are current, like the update box: an icon that is
// always there and merely changes colour has to be read every time, and this
// one only ever means one thing. Its arrival IS the message.
//
// A HARD DISK AND A NUMBER OF DAYS, picked by rendering the candidates the
// way NotifyButton's bell and the update box were. A shield says "protected"
// and a floppy says "save"; neither says the thing that actually has to
// happen, which is that a disk in a drawer needs plugging in.
//
// TWO COLOURS, AND THE SECOND ONE IS EARNED. Accent while it is a reminder,
// danger once it passes the threshold bin/backup.sh itself fails on, or if
// the machine has never backed up at all - at that point it is not a nudge,
// it is a machine with nothing to restore from.
//
// AND MILDER WHEN THE DISK IS ALREADY CONNECTED, because then the next timer
// tick fixes it without anybody doing anything, and an alarm about something
// already in hand is how alarms get ignored.
//
// ONE CLICK OPENS A TERMINAL that runs the backup. It does not run silently:
// a backup talks, it can take minutes, and the transcript is the point.

import QtQuick

Item {
    id: root

    // Its own flag rather than reading back `visible`, which returns
    // EFFECTIVE visibility and would be false inside a hidden Loader - the
    // trap that once left the update box invisible with seven packages
    // waiting. BarZone hides a plugin by its width for the same reason.
    readonly property bool shown: Backups.overdue

    visible: root.shown
    implicitWidth: root.shown ? content.implicitWidth : 0
    implicitHeight: 22

    readonly property string diskGlyph: "\u{F02CA}"   // nf-md-harddisk

    readonly property color tone:
        Backups.critical && !Backups.connected ? Theme.danger : Theme.accent

    Rectangle {
        anchors.centerIn: content
        width: content.implicitWidth + 8
        height: 22
        radius: height / 2
        color: Theme.surfaceHigh
        opacity: hover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 4

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.diskGlyph
            font.family: Theme.glyphFont
            // 14, matching the coffee cup rather than the bell: the disk is a
            // solid rounded shape that fills its em box the same way.
            font.pixelSize: 14
            color: hover.hovered ? Theme.fg : root.tone
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            // "never" is a word, not a number, because no number is right for
            // it - 99999 days is what the script reports and that is an
            // implementation detail leaking onto the bar.
            text: Backups.never ? "never" : Backups.days + "d"
            font.family: Theme.font
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.weightMedium
            font.features: { "tnum": 1 }
            color: hover.hovered ? Theme.fg : root.tone
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
    }

    // It appears on its own, without anyone touching the bar, so it fades in
    // rather than arriving between two frames. The width is animated by the
    // zone around it; this is only the ink.
    opacity: root.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
}
