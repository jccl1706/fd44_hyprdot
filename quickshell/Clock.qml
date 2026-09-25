// =========================================================================
// Clock - 24 hour time, centre of the bar
// =========================================================================
//
// Uses Quickshell's SystemClock rather than a QtQuick Timer. SystemClock is
// driven by the system clock itself, so it ticks exactly on the boundary and
// survives suspend/resume and timezone changes - a Timer drifts, and after a
// resume it can sit on a stale value until its next interval elapses. That
// matters here: this laptop suspends on idle.
//
// precision: Minutes means it only wakes once a minute. Seconds would wake 60x
// as often for a display that does not show seconds.

import Quickshell
import QtQuick

Item {
    id: root

    // Reads Theme directly - no properties to declare, nothing for Bar.qml
    // to pass down.

    // "HH" is 24 hour, zero padded. "hh" would be 12 hour.
    property string timeFormat: "HH:mm"

    // Clicking opens the calendar. The clock is not a bar plugin - it is
    // placed directly, between the two centre zones - so it signals upward
    // rather than going through componentFor and activate().
    signal activated()

    // IN FOCUS MODE THIS IS THE WAY OUT, and says so under the pointer: the
    // time fades to a close cross while the pointer is on it, and Bar.qml
    // sends `activated` to Settings.leaveFocus() instead of to the calendar.
    //
    // The clock is the right place for it. Focus hides every pill but the
    // middle one, so the middle one is where the eye already is - which is
    // where the first version of this feature put a button, before the button
    // grew into a notch and the notch turned out to be a worse pill.
    //
    // THE CROSS TAKES THE TIME'S WIDTH, not its own. Swapping a five-glyph
    // label for a one-glyph icon would shrink the pill around it and shift
    // the two zones either side, so the cross is centred inside the label's
    // footprint and nothing moves.
    property bool exits: false

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Text {
        id: label
        anchors.centerIn: parent

        text: Qt.formatDateTime(clock.date, root.timeFormat)

        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSizeClock
        font.weight: Theme.weightBold
        font.letterSpacing: Theme.trackingTight

        // Inter carries an optical-size axis (opsz 14-32) and Qt does NOT
        // apply it on its own - left alone the clock is drawn with letterforms
        // meant for 14px body text. Matching opsz to the rendered size is what
        // the axis is for: tighter spacing and slightly finer joins at display
        // sizes. Needs Qt 6.7+; this is 6.11.
        font.variableAxes: ({ "opsz": Theme.fontSizeClock })

        // Digits are drawn at a fixed advance width so the label does not
        // shift as the numbers change - without this, 11:11 is narrower than
        // 10:00 in a proportional face and the clock jitters every minute.
        font.features: { "tnum": 1 }

        // Brightens under the pointer, the same acknowledgement the bar's
        // glyphs give. No backdrop: the clock is wider than a glyph and a
        // pill behind it would read as a button, which it is not really.
        opacity: (root.exits && hover.hovered) ? 0
                                               : (hover.hovered ? 1 : 0.92)
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    Text {
        id: exitCross
        anchors.centerIn: label
        text: "\u{F0156}"
        font.family: Theme.glyphFont
        font.pixelSize: Theme.fontSizeClock
        color: Theme.fg
        opacity: (root.exits && hover.hovered) ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    HoverHandler {
        id: hover
        // No cursorShape - see the note in Bar.qml.
    }

    TapHandler {
        onTapped: root.activated()
    }
}
