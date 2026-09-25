// =========================================================================
// Workspaces - this screen's slots, live state from Hyprland
// =========================================================================
//
// A fixed set of slots is always shown whether or not those workspaces exist
// yet, so the widget never changes width as you move around - a bar that
// reflows every time you open a window on workspace 4 is hard to aim at.
//
// WHICH slots depends on the screen, and that is the part that was missing.
// hypr/rules.lua pins workspaces to monitors, so this row draws the ones
// pinned to the monitor it is on: the external bar carries 1-5 and the
// laptop's 6-9. Before, both bars drew the same five chips, which meant the
// laptop showed five workspaces that live on the other screen and none of
// its own. WorkspacePins reads the pinning from the compositor - see it for
// why the numbers are not repeated here.
//
// WITH NOTHING PINNED IT FALLS BACK TO 1-5. That is the single-monitor case:
// none of the rules name an output that machine has, so nothing claims a
// screen and the bar behaves exactly as it did before any of this existed.
//
// State comes from Quickshell's built-in Hyprland IPC, not from polling
// hyprctl: Hyprland.workspaces is a live model that updates on the
// compositor's own events.

import Quickshell
import Quickshell.Hyprland
import QtQuick

Row {
    id: root

    // The monitor this row is drawn on - Bar.qml passes its own. Required
    // rather than defaulted: a bar that forgot to pass it would silently
    // show the fallback on every screen, which is the bug this fixes.
    required property string screenName

    // The slots to draw: the workspaces pinned to this screen, or 1-5 when
    // none are. Workspaces outside the set still work, they are just not
    // shown here.
    readonly property var slots: {
        const own = WorkspacePins.idsFor(root.screenName)
        const taken = WorkspacePins.inheritedFor(root.screenName)

        // Nothing inherited: the ordinary case, both monitors present.
        if (taken.length === 0) return own.length > 0 ? own : [1, 2, 3, 4, 5]

        // A monitor is unplugged and this screen has taken its workspaces
        // in. Show THOSE, not both sets - the other screen's numbers are
        // where the windows went, and nine chips on a 13" panel is not a
        // bar, it is a ruler.
        //
        // EXCEPT ANY OF OUR OWN THAT ACTUALLY EXIST. A workspace with
        // windows on it must always be on the bar; hiding one is the bug
        // this file was just fixed for, and it would be no better inverted.
        // In practice the laptop's own 6-9 are empty when the external is
        // unplugged, so this shows five chips and not nine.
        const live = []
        const all = Hyprland.workspaces.values
        for (let i = 0; i < own.length; i++) {
            for (let j = 0; j < all.length; j++) {
                if (all[j].id === own[i]) { live.push(own[i]); break }
            }
        }
        return taken.concat(live).sort((a, b) => a - b)
    }

    spacing: 6

    // SCROLL THE ROW TO CHANGE WORKSPACE, the same gesture SUPER+scroll does
    // over the desktop (hypr/binds.lua), here without the modifier because
    // the pointer is already on the thing it acts on.
    //
    // e+1/e-1 STEP THROUGH WORKSPACES THAT EXIST, skipping empty ones, rather
    // than to id+1 - the same call the keybind makes, so a wheel click on the
    // bar and one over a window land in the same place.
    //
    // Hyprland 0.56 EVALUATES DISPATCHES AS LUA: "workspace e+1" is a syntax
    // error, not a command, and fails silently from the bar's side. The
    // chips' own click handler carries the same note.
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            Hyprland.dispatch(event.angleDelta.y > 0
                ? 'hl.dsp.focus({ workspace = "e-1" })'
                : 'hl.dsp.focus({ workspace = "e+1" })')
        }
    }

    Repeater {
        model: root.slots

        Rectangle {
            id: chip

            // Repeater hands array entries over as `modelData`. It used to
            // count from `index`, which only worked while the slots were
            // always 1..5.
            required property var modelData
            readonly property int wsId: chip.modelData

            // Does this workspace exist in Hyprland right now? A workspace
            // only exists once something is on it.
            readonly property var ws: {
                const list = Hyprland.workspaces.values
                for (let i = 0; i < list.length; i++) {
                    if (list[i].id === wsId) return list[i]
                }
                return null
            }

            readonly property bool exists: ws !== null
            readonly property bool focused: Hyprland.focusedWorkspace
                                            && Hyprland.focusedWorkspace.id === wsId

            // Set by Hyprland when a window on a workspace you are NOT
            // looking at asks for attention - xdg-activation, or an X11
            // client setting the urgency hint. `=== true` rather than a plain
            // truth test: on a workspace that does not exist `ws` is null and
            // on an older Hyprland the property may be undefined, and neither
            // should read as urgent.
            readonly property bool urgent: ws !== null && ws.urgent === true

            // DOTS, NOT NUMBERED CHIPS. Eight pixels tall, so the row is a
            // line of punctuation rather than six labelled buttons: at a
            // glance you read the SHAPE of where you are - one long dash
            // among short ones - without reading anything at all.
            //
            // THREE WIDTHS, and the middle one is what makes it feel alive:
            //   8   empty or merely occupied
            //   14  under the pointer - the row answers before you click
            //   26  focused
            //
            // The dots after the focused one slide along as it grows, and
            // that is the effect rather than a side effect: the row reads as
            // one thing shifting its weight, not as six things redrawing.
            width: chip.focused ? 26 : (hover.containsMouse ? 14 : 8)
            height: 8

            // OUTBACK, which overshoots by a hair and settles back. Normally
            // this file would refuse that - hypr/look.lua rejects overshoot
            // for windows, where a thing sailing past its place and coming
            // back reads as sloppy - but at eight pixels the overshoot is
            // under a pixel of travel and what it buys is the feeling that
            // the dot has weight. 250ms for the same reason: long enough to
            // watch, which is the only reason to move at all.
            // A CHIP THAT HAS JUST BEEN CREATED MUST NOT ANIMATE INTO EXISTENCE.
            // Switching to an empty workspace inserts a dot, and a Behavior
            // runs on a property's FIRST value as readily as on its later
            // ones - so the new dot grew from nothing while its colour faded
            // from grey to the accent, which looked like a lozenge flashing
            // in the middle of the row rather than like arriving somewhere.
            //
            // Both Behaviors are therefore off until the chip has been built
            // and painted once. After that they do what they are for:
            // animating a CHANGE.
            // AND IT IS NOT ENOUGH TO DO THIS ONCE. A Repeater fed a JavaScript
            // array RECYCLES its delegates: switching to an empty workspace
            // does not build a new dot, it hands an existing one a different
            // wsId. That dot was created long ago, so `settled` was already
            // true and the colour animated from whatever the PREVIOUS
            // workspace's dot looked like - grey sliding to accent, which is
            // the flash that was reported.
            //
            // So the gate closes again whenever a chip changes identity, and
            // reopens on the next turn of the event loop, by which time the
            // bindings have painted the new workspace's real colour and size.
            property bool settled: false
            Component.onCompleted: resettle.restart()
            onWsIdChanged: {
                chip.settled = false
                resettle.restart()
            }

            // A QUARTER SECOND, NOT ONE MILLISECOND, and the difference is the
            // whole fix. The chip is created the instant Hyprland creates the
            // workspace, and at that instant `Hyprland.focusedWorkspace` still
            // names the workspace being LEFT - so the chip's first colour is
            // the grey of an occupied-but-unfocused dot, and focus lands a few
            // frames later. With animations already armed, that second value
            // arrived as a 140ms grey-to-accent slide: a pale lozenge
            // appearing in the row and then turning blue, which is what got
            // reported as weird glyphs when switching to an empty workspace.
            //
            // Waiting lets the first few frames settle silently. Anything that
            // changes within 250ms of a chip appearing is part of it arriving,
            // not a change worth animating.
            Timer {
                id: resettle
                interval: 250
                onTriggered: chip.settled = true
            }

            Behavior on width {
                enabled: chip.settled
                NumberAnimation { duration: 250; easing.type: Easing.OutBack }
            }

            // Fully rounded at every width - a disc at 8, a pill at 26 -
            // because the radius follows the HEIGHT, which does not change.
            // Half the width would flatten the pill as it grew and animate
            // the corners along with it.
            radius: height / 2

            // A STATE LAYER, in the Material sense: hover does not swap the
            // colour, it adds a translucent film over whatever the chip
            // already is. That way an occupied chip and an empty one both
            // respond to the pointer, and neither has to know what the other
            // looks like.
            // URGENT BEATS EVERYTHING, including focused - a window asking
            // for attention on the workspace you are already looking at is
            // still worth seeing, and the pulse below is what carries it.
            // `exists` survives as the last branch only to cover the frame
            // between a workspace being destroyed and the row rebuilding.
            // AN EMPTY WORKSPACE KEEPS ITS PLACE AND SHOWS NOTHING. Removing
            // the dot entirely is what made the row jump: leave an empty
            // workspace for another one and Hyprland destroys the first, the
            // Repeater drops its item, and every dot after it slides along to
            // fill the gap - a whole row twitching sideways because you
            // changed which nothing you were looking at.
            //
            // Invisible rather than absent: the slot is still laid out, so
            // nothing moves, and the only thing that changes width is the
            // focused dot's own stretch, which is the movement the row is
            // FOR. It also leaves the empty workspaces clickable, which is a
            // side effect rather than the reason, but a welcome one - 4 and 5
            // are reachable with the mouse again without drawing anything for
            // them.
            opacity: chip.exists || chip.focused ? 1 : 0
            Behavior on opacity {
                enabled: chip.settled
                NumberAnimation { duration: Theme.animFast }
            }

            color: chip.urgent ? Theme.danger
                 : focused     ? Theme.accent
                 : exists      ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.25)
                               : "transparent"

            // No border: the outlined circle used to mean "this workspace is
            // in your set but has nothing on it", and nothing is drawn for
            // that case any more.

            // Colour animates so switching reads as a change rather than a
            // jump. Kept short - the bar should feel instant. The width
            // animation that used to sit beside this went with the widening:
            // a Behavior on a property that never changes is dead code.
            Behavior on color  {
                enabled: chip.settled
                ColorAnimation { duration: Theme.animNormal }
            }

            // A SLOW BREATH, not a blink. Two seconds a cycle and never below
            // 0.55: an indicator that flashes is read as an error in the bar
            // itself, and one that disappears entirely is invisible exactly
            // when it is trying to be seen. Runs only while urgent, so it
            // costs nothing the rest of the time.
            SequentialAnimation on opacity {
                running: chip.urgent
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.55; duration: 1000; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0;  duration: 1000; easing.type: Easing.InOutSine }
            }

            // NO NUMBER, and that is the trade this design makes. A dot
            // eight pixels tall cannot carry a legible digit, so the row
            // stops telling you WHICH workspace you are on and tells you
            // only where you are in the line - which, with six of them and
            // SUPER+1..0 on the keyboard, is what the eye actually used it
            // for. The chips that carried numbers are in the history if the
            // trade turns out wrong.
            //
            // NO HOVER FILM EITHER. The old chips brightened under the
            // pointer because they could not change size without pushing the
            // row about; these answer by growing to 14, which is the same
            // acknowledgement in the vocabulary this row already speaks.

            MouseArea {
                id: hover
                anchors.fill: parent

                // BIGGER THAN THE DOT IT SERVES. Eight pixels is a hard
                // target for a pointer and an impossible one in a hurry; the
                // margin takes the hit area out to the full height of the
                // pill without changing what is drawn. Negative margins
                // overlap between neighbours by design - the gap is 6, so
                // each dot claims three pixels of it and none is dead space.
                anchors.margins: -5

                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                // Hyprland 0.56 EVALUATES DISPATCHES AS LUA, so the old
                // string form "workspace 3" is a syntax error, not a command:
                //   ')' expected near '3'
                // It fails silently from the bar's point of view - the click
                // simply does nothing - and only shows up in quickshell's log.
                // Same call the keybinds use, see hypr/binds.lua.
                onClicked: Hyprland.dispatch(
                    "hl.dsp.focus({ workspace = " + chip.wsId + " })")
            }
        }
    }
}
