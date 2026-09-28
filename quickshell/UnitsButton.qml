// =========================================================================
// UnitsButton - the warning that appears when something has failed
// =========================================================================
//
// Absent while the machine is healthy, like the update box and the backup
// disk. The three of them are the same idea at three levels of insistence:
// packages waiting is news, a stale backup is a reminder, and a failed unit
// is a fault.
//
// SO THIS ONE IS ALWAYS DANGER-COLOURED. The others earn red by degree - the
// backup disk turns red only past the threshold its own script fails on. A
// unit does not fail by degree: it either did or it did not, and something on
// this machine has already decided that it did.
//
// AN ALERT TRIANGLE, picked by rendering the candidates beside the others in
// the pill. It is the one shape in the set that means "wrong" rather than
// "thing" - a box means packages, a disk means the backup, and a cog or a
// wrench would mean "settings" to anyone who has used a computer.
//
// ONE CLICK OPENS THE LOGS, not a fix. `systemctl reset-failed` would make
// this icon disappear without anything being repaired, which is the one
// action a bar icon must never take by itself; bin/units.sh prints the
// command and leaves the decision where it belongs.

import QtQuick

Item {
    id: root

    // Its own flag rather than reading back `visible`, which returns
    // EFFECTIVE visibility - false inside a hidden Loader, which is how the
    // update box once hid itself permanently. See BarZone.qml.
    readonly property bool shown: Units.failing

    visible: root.shown
    implicitWidth: root.shown ? content.implicitWidth : 0
    implicitHeight: 22

    readonly property string alertGlyph: "\u{F0026}"   // nf-md-alert

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
            text: root.alertGlyph
            font.family: Theme.glyphFont
            // 14, like the disk and the coffee cup: a solid shape that fills
            // its em box, unlike the thin-line moon beside it.
            font.pixelSize: 14
            color: hover.hovered ? Theme.fg : Theme.danger
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            // The count only. WHICH units have failed is a sentence, not a
            // glyph, and it is one click away in a terminal that also says
            // why - which is the part worth reading.
            text: String(Units.total)
            font.family: Theme.font
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.weightMedium
            font.features: { "tnum": 1 }
            color: hover.hovered ? Theme.fg : Theme.danger
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
    }

    // A SLOW PULSE WHILE IT IS THERE, which nothing else in this bar does.
    // The workspace chips pulse for an urgent window and that is the whole
    // precedent: a thing that appeared while you were looking elsewhere has
    // to catch the eye once, and a static red glyph beside a clock does not.
    // Slow enough - two seconds - not to be a flashing light.
    SequentialAnimation on opacity {
        running: root.shown
        loops: Animation.Infinite
        NumberAnimation { from: 1.0; to: 0.55; duration: 1000; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.55; to: 1.0; duration: 1000; easing.type: Easing.InOutSine }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
}
