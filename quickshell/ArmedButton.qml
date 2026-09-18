// =========================================================================
// ArmedButton - a bar glyph that takes two clicks
// =========================================================================
//
// The base of CouchButton and PowerButton. The first click arms the button,
// the second one fires it, and it disarms itself after four seconds.
//
// WHY THESE TWO ARE NOT ORDINARY BUTTONS. Every other plugin in the bar is
// harmless to press by accident: a panel opens, a theme flips, a coffee cup
// comes on. These two end the session - one hands the machine to Steam, the
// other switches it off - and both throw away whatever is open. A single
// click is the wrong amount of commitment for that.
//
// THE SAME ARM-THEN-FIRE IDIOM AS PowerMenu.qml, and for the same reasons,
// which are written out there: the confirmation stays on the control that
// started it, so the second click is in the same place as the first, and a
// tick says "again" without needing any words.
//
// NO DISARM ON HOVER-OUT, which is where this differs from the menu. There
// the buttons are large rows and leaving one cancels it. Here the target is
// a 20px glyph, and the pointer aimed at it is often a Steam controller's
// trackpad - which drifts while the click is being made. Cancelling on a
// pointer that slipped off the glyph would turn the second click into a coin
// toss. The timer is the guard instead, and four seconds is short enough
// that nothing is left armed behind you.

import Quickshell.Io
import QtQuick

Item {
    id: root

    // The idle glyph, and its size in px. Each button picks its own size:
    // Nerd Font glyphs are not drawn to a common ink height, so matching
    // them by eye means different pixelSize values - see the notes in
    // CouchButton.qml and PowerButton.qml for what was measured.
    property string glyph: ""
    property int glyphSize: 15

    // What the second click runs.
    property var command: []

    // nf-md-check. Drawn two px larger than the idle glyph, as the menu
    // does: a tick is a light shape and needs the extra size to read as the
    // deliberate change of state it is.
    readonly property string tickGlyph: "\u{F012C}"

    property bool armed: false

    // 24 wide where the other plugins are 20, and every one of the extra
    // four pixels is empty: the hover circle and the glyph stay exactly the
    // size of their neighbours, so the bar looks unchanged. Bar.qml's hit
    // test is the slot's full width by the bar's full height, so this is a
    // 20% wider target for nothing - which matters when the pointer is a
    // thumb on a trackpad three metres from the screen.
    implicitWidth: 24
    implicitHeight: 20

    Process {
        id: runner
        command: root.command
        onExited: (code, status) => {
            if (code !== 0)
                console.warn("bar:", root.command.join(" "), "exited with", code)
        }
    }

    Timer {
        id: disarm
        interval: 4000
        onTriggered: root.armed = false
    }

    // Called by Bar.qml, which owns clicks on every movable plugin - a
    // TapHandler here would fire as well, and cannot tell a click from the
    // press-and-hold that drags the button elsewhere in the bar.
    function activate(): void {
        if (!root.armed) {
            root.armed = true
            disarm.restart()
            return
        }
        root.armed = false
        disarm.stop()
        runner.running = true
    }

    // Hover backdrop, behind the glyph so hovering never resizes the pill.
    // Armed, it fills with the danger colour and stays filled - the button
    // is lit whether or not the pointer is still on it, which is the point
    // of not disarming on hover-out.
    Rectangle {
        anchors.centerIn: parent
        width: 20
        height: 20
        radius: width / 2
        color: root.armed ? Theme.danger : Theme.surfaceHigh
        opacity: (root.armed || hover.hovered) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    Text {
        id: face
        anchors.centerIn: parent
        text: root.armed ? root.tickGlyph : root.glyph
        font.family: Theme.glyphFont
        font.pixelSize: root.armed ? root.glyphSize + 2 : root.glyphSize
        // On the danger fill the tick takes the background colour, as the
        // menu's armed buttons do - a red tick on a red disc would not be
        // there at all.
        color: root.armed     ? Theme.bg
             : hover.hovered  ? Theme.fg
                              : Theme.pluginIcon
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        // A bump on arming, so the change registers as the result of the
        // click rather than as the icon having been swapped.
        scale: 1
        SequentialAnimation on scale {
            id: bump
            running: false
            NumberAnimation { to: 1.25; duration: Theme.animFast;   easing.type: Easing.OutCubic }
            NumberAnimation { to: 1.0;  duration: Theme.animNormal; easing.type: Easing.InOutCubic }
        }
    }

    onArmedChanged: if (root.armed) bump.restart()

    HoverHandler {
        id: hover
        // No cursorShape: crossing the bar's icons flipped the pointer
        // shape, and the hand's hotspot sits at the fingertip where the
        // arrow's is near its corner - so the pointer appeared to jump a
        // few pixels at every icon edge. See Bar.qml.
    }
}
