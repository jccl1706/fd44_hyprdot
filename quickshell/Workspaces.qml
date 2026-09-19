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

            // THE FOCUSED CHIP STRETCHES INTO AN OVAL. A circle among
            // circles says which one is current by colour alone; growing it
            // says so by shape as well, and the growth itself is the signal -
            // the eye follows the movement to the new workspace rather than
            // hunting for which disc changed colour.
            //
            // The chips after it slide along as it grows, and that is the
            // effect rather than a side effect: the row reads as one thing
            // shifting its weight, not as six things redrawing.
            width: chip.focused ? 26 : 18
            height: 18

            // ANIMATED, or the stretch is just a jump. OutCubic so it leaves
            // quickly and arrives gently, which is what makes it read as the
            // chip settling rather than snapping. animReveal (220ms) rather
            // than animNormal: at 140 the movement is over before the eye has
            // followed it, which wastes the only reason to move at all.
            Behavior on width {
                NumberAnimation { duration: Theme.animReveal; easing.type: Easing.OutCubic }
            }

            // Fully rounded at both sizes - a circle at 18, an oval at 26 -
            // because the radius follows the HEIGHT, which does not change.
            // Half the width would make the oval a lozenge that flattens as
            // it grows, and the corners would animate along with it.
            //
            // Not Theme.cornerRadius either: it is 12, larger than half this
            // chip's height, and Qt clamps a radius at half the shorter side.
            // It would land on the same circle by accident rather than on
            // purpose, and stop being one the moment the chip grew.
            radius: height / 2

            // A STATE LAYER, in the Material sense: hover does not swap the
            // colour, it adds a translucent film over whatever the chip
            // already is. That way an occupied chip and an empty one both
            // respond to the pointer, and neither has to know what the other
            // looks like.
            color: focused  ? Theme.accent
                 : exists   ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.25)
                            : "transparent"

            border.width: exists || focused ? 0 : 1
            border.color: Qt.rgba(Theme.dim.r, Theme.dim.g, Theme.dim.b, 0.5)

            // Colour animates so switching reads as a change rather than a
            // jump. Kept short - the bar should feel instant. The width
            // animation that used to sit beside this went with the widening:
            // a Behavior on a property that never changes is dead code.
            Behavior on color  { ColorAnimation  { duration: Theme.animNormal } }

            Text {
                anchors.centerIn: parent
                text: chip.wsId
                font.family: Theme.font
                font.pixelSize: Theme.fontSizeSmall
                // One weight for every chip, a step up from the medium the
                // unfocused ones used to carry. The focused one no longer
                // needs a heavier number to stand out - it is the only
                // coloured square in the row - and matching weights suit
                // chips that are now all the same size.
                //
                // Semi rather than Bold: Theme reserves Bold for the clock,
                // which should stay the heaviest thing in the bar.
                font.weight: Theme.weightSemi
                font.letterSpacing: Theme.trackingLoose
                color: chip.focused ? Theme.accentFg
                     : chip.exists  ? Theme.fg
                                    : Theme.dim
                visible: chip.focused || chip.exists
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Theme.fg
                opacity: hover.containsMouse && !chip.focused ? 0.12 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
            }

            MouseArea {
                id: hover
                anchors.fill: parent
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
