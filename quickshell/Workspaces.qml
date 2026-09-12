// =========================================================================
// Workspaces - five fixed slots, live state from Hyprland
// =========================================================================
//
// Five workspaces are always shown whether or not they exist yet, so the
// widget never changes width as you move around - a bar that reflows every
// time you open a window on workspace 4 is hard to aim at.
//
// State comes from Quickshell's built-in Hyprland IPC, not from polling
// hyprctl: Hyprland.workspaces is a live model that updates on the
// compositor's own events.

import Quickshell
import Quickshell.Hyprland
import QtQuick

Row {
    id: root

    // How many slots to draw. Workspaces beyond this still work, they just
    // are not shown here.
    readonly property int count: 5

    spacing: 6

    Repeater {
        model: root.count

        Rectangle {
            id: chip

            // Repeater gives each delegate `index`, 0-based; workspaces are
            // 1-based.
            required property int index
            readonly property int wsId: index + 1

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

            width: focused ? 26 : 18
            height: 18
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

            // Width and colour animate so switching reads as movement rather
            // than a jump. Kept short - the bar should feel instant.
            Behavior on width  { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
            Behavior on color  { ColorAnimation  { duration: Theme.animNormal } }

            Text {
                anchors.centerIn: parent
                text: chip.wsId
                font.family: Theme.font
                font.pixelSize: Theme.fontSizeSmall
                font.weight: chip.focused ? Theme.weightSemi : Theme.weightMedium
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
