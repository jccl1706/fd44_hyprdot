// =========================================================================
// Bar - a full-width panel across the top of one monitor
// =========================================================================
//
// BLOCK 1: just the bar itself. No modules in it yet - those come next, one
// at a time. Right now it is a bar-shaped surface with its regions marked out
// so it is obvious the layout works before anything is put in them.

import Quickshell
import QtQuick

PanelWindow {
    id: root

    // Exposed so the IpcHandler in shell.qml can trigger it.
    property alias osd: osd

    // Variants sets this, one instance per monitor. The name must be exactly
    // `modelData` - that is what Variants assigns into the delegate.
    required property var modelData

    // PanelWindow's own `screen` property decides which output the layer
    // surface is placed on.
    screen: modelData

    // PanelWindow is a layer-shell surface. Anchoring to three edges is what
    // makes it span the full width: left+right pins both sides, so the width
    // follows the monitor instead of being a fixed number.
    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: Theme.barHeight

    // Layer-shell surfaces can reserve space, so tiled windows are placed
    // below the bar instead of underneath it. Hyprland honours this via
    // `exclusiveZone`; leaving it at the default means the bar would overlap
    // windows. Setting it to the bar's own height reserves exactly that.
    exclusiveZone: implicitHeight

    color: "transparent"


    Rectangle {
        anchors.fill: parent
        color: Theme.bg

        // Per-corner radius needs Qt 6.7+ (this is 6.11). Only the bottom is
        // rounded: the top edge is flush against the top of the screen, so
        // rounding it would open a gap onto the desktop rather than look
        // deliberate.
        bottomLeftRadius: Theme.cornerRadius
        bottomRightRadius: Theme.cornerRadius

        // No bottom hairline any more: with rounded corners it cut straight
        // across them. The corner radius is the edge now.

        // Three regions: left, centre, right. Laid out independently so a
        // wide centre widget cannot push the side ones around, which is what
        // happens if the whole bar is one RowLayout.
        Item {
            id: leftRegion
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: Theme.barPadding }
            width: leftRow.implicitWidth

            Row {
                id: leftRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.itemSpacing

                Logo {
                    anchors.verticalCenter: parent.verticalCenter
                    // Nothing wired to the click yet - this is where a
                    // launcher or a menu would go once one exists.
                    onActivated: console.log("logo clicked")
                }

                // Separator between the logo and the workspaces, so they read
                // as two things rather than one run of shapes.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: 14
                    color: Qt.rgba(Theme.dim.r, Theme.dim.g, Theme.dim.b, 0.5)
                }

                Workspaces {
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Hidden until a volume/brightness key is pressed. Sits right
                // after the workspaces and collapses to zero width when idle,
                // so nothing else in the bar moves while it is hidden.
                Osd {
                    id: osd
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Item {
            id: centerRegion
            anchors.centerIn: parent
            width: centerRow.implicitWidth
            height: parent.height

            Row {
                id: centerRow
                anchors.centerIn: parent
                spacing: 10

                Clock {
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Item {
            id: rightRegion
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: Theme.barPadding }
            width: rightRow.implicitWidth

            Row {
                id: rightRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Text {
                    text: "right"
                    color: Theme.dim
                    font.family: Theme.font
                    font.bold: Theme.bold
                    font.pixelSize: Theme.fontSize
                }
            }
        }
    }
}
