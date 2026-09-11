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

    property color fgColor:     "#cdd6f4"
    property color dimColor:    "#6c7086"
    property color accentColor: "#89b4fa"
    property string fontFamily: "Inter Variable"
    property bool fontBold: true

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

            color: focused  ? root.accentColor
                 : exists   ? Qt.rgba(root.fgColor.r, root.fgColor.g, root.fgColor.b, 0.25)
                            : "transparent"

            border.width: exists || focused ? 0 : 1
            border.color: Qt.rgba(root.dimColor.r, root.dimColor.g, root.dimColor.b, 0.5)

            // Width and colour animate so switching reads as movement rather
            // than a jump. Kept short - the bar should feel instant.
            Behavior on width  { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on color  { ColorAnimation  { duration: 140 } }

            Text {
                anchors.centerIn: parent
                text: chip.wsId
                font.family: root.fontFamily
                font.pixelSize: 10
                font.bold: root.fontBold || chip.focused
                color: chip.focused ? "#1e1e2e"
                     : chip.exists  ? root.fgColor
                                    : root.dimColor
                visible: chip.focused || chip.exists
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch("workspace " + chip.wsId)
            }
        }
    }
}
