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
    implicitWidth: root.shown ? capsule.width : 0
    implicitHeight: 22

    // Warm enough to notice; hot enough to care. Measured against this card:
    // idle sits in the low 50s, a game runs in the 60s and 70s, and NVIDIA's
    // own slowdown threshold is in the high 80s.
    readonly property int warmAt: 70
    readonly property int hotAt: 83

    readonly property color tone:
        Thermals.gpuTemp >= root.hotAt ? Theme.danger : Theme.accent

    // A CAPSULE OF ITS OWN, not a glyph and a number tacked onto the clock.
    // Rendered side by side against the alternatives before choosing: the
    // chip glyph was a muddy smudge at 14px, a thermometer read only slightly
    // better, and both left the number looking like a suffix to the time -
    // "18:36 52" reads as one thing. Boxed and labelled it reads as a second
    // thing in the pill, which is what it is. FocusedApp does the same with
    // its own circle beside the workspaces.
    //
    // THE WORD "GPU" IS THE ICON. Three letters at 9px are legible where a
    // 14px pictogram of a chip is not, and they say which of the machine's
    // several temperatures this is - something no icon here managed.
    Rectangle {
        id: capsule
        anchors.centerIn: parent
        width: content.implicitWidth + 14
        height: 20
        radius: height / 2

        color: hover.hovered ? Theme.surfaceHigh : Theme.surface
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        // The rim carries the warning as well as the digits do. A number
        // changing colour is easy to miss at a glance; an outline lighting up
        // is not, and it keeps the readout legible while it does - the text
        // stays high-contrast instead of turning into a coloured smudge.
        border.width: 1
        border.color: Thermals.gpuTemp >= root.warmAt ? root.tone : Theme.rim
        Behavior on border.color { ColorAnimation { duration: Theme.animNormal } }

        Row {
            id: content
            anchors.centerIn: parent
            spacing: 4

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "GPU"
                font.family: Theme.font
                font.pixelSize: 9
                font.weight: Theme.weightSemi
                font.letterSpacing: 0.6
                color: Theme.dim
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                // The degree sign, not "C": the unit is never in doubt, and
                // the label beside it already says what is measured.
                text: Thermals.gpuTemp + "\u00b0"
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Theme.weightMedium
                // Tabular figures, so a pill beside a clock does not twitch
                // every time the temperature crosses a digit.
                font.features: { "tnum": 1 }
                color: Thermals.gpuTemp >= root.warmAt ? root.tone : Theme.fg
                Behavior on color { ColorAnimation { duration: Theme.animNormal } }
            }
        }
    }

    opacity: root.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
}
