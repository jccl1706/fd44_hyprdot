// =========================================================================
// ThermalButton - the graphics card's temperature, while it matters
// =========================================================================
//
// THE ONE PLUGIN HERE THAT IS NOT AN ALARM. The update box, the backup disk
// and the failure triangle appear only when something wants doing; this is a
// readout, present whenever there is a card to read. The question it answers -
// how hot is it under this load - is asked while something is happening, and
// a number that only appears once the machine is already too hot has missed
// the part worth watching.
//
// ABSENT ENTIRELY ON A MACHINE WITH NO DISCRETE CARD, which is how it stays
// off the laptop without a per-machine setting: bin/thermal.sh reports ok
// false there and this draws nothing.
//
// THE COLOUR IS THE ALARM PART. Dim while it is cool, because a number that
// is always bright is a number the eye stops reading; accent once it is warm
// enough to be worth noticing; danger near the point where the card starts
// pulling its own clocks down. The thresholds are for this card - an RTX 5090
// throttles in the high 80s - and are named below rather than buried.
//
// ONE CLICK OPENS THE LIVE VIEW, refreshing every two seconds: a single
// snapshot of a temperature is the least useful form of it.

import QtQuick

Item {
    id: root

    // Its own flag, not `visible` - which reports EFFECTIVE visibility and
    // would read false inside a hidden Loader. See BarZone.qml.
    readonly property bool shown: Thermals.present && Thermals.gpuTemp >= 0

    visible: root.shown
    implicitWidth: root.shown ? content.implicitWidth : 0
    implicitHeight: 22

    // A CHIP, NOT A THERMOMETER. The number beside it already carries a
    // degree sign, so a thermometer would say "temperature" twice and "of
    // what" not at all. Picked out of a rendered grid, like every other glyph
    // here - a monitor was the first choice and reads as "display".
    readonly property string chipGlyph: "\u{F061A}"   // nf-md-memory

    // Warm enough to notice; hot enough to care. Measured against this card:
    // idle sits in the low 50s, a game runs in the 60s and 70s, and NVIDIA's
    // own slowdown threshold is in the high 80s.
    readonly property int warmAt: 70
    readonly property int hotAt: 83

    readonly property color tone:
        Thermals.gpuTemp >= root.hotAt  ? Theme.danger
      : Thermals.gpuTemp >= root.warmAt ? Theme.accent
                                        : Theme.dim

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
            text: root.chipGlyph
            font.family: Theme.glyphFont
            font.pixelSize: 14
            color: hover.hovered ? Theme.fg : root.tone
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            // The degree sign, not "C": the unit is never in doubt on a
            // desktop and the glyph beside it already says what is being
            // measured, so the letter is two pixels of nothing.
            text: Thermals.gpuTemp + "°"
            font.family: Theme.font
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.weightMedium
            // Tabular figures, so the pill does not twitch every time the
            // temperature crosses a digit - this updates every five seconds
            // and sits beside a clock.
            font.features: { "tnum": 1 }
            color: hover.hovered ? Theme.fg : root.tone
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
    }

    opacity: root.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
}
