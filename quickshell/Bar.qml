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

    implicitHeight: 34

    // Layer-shell surfaces can reserve space, so tiled windows are placed
    // below the bar instead of underneath it. Hyprland honours this via
    // `exclusiveZone`; leaving it at the default means the bar would overlap
    // windows. Setting it to the bar's own height reserves exactly that.
    exclusiveZone: implicitHeight

    color: "transparent"

    // --- palette ---------------------------------------------------------
    // Kept here for now. Once a second component needs these they should move
    // to a shared singleton rather than be duplicated.
    readonly property color bgColor:   "#1e1e2e"
    readonly property color fgColor:   "#cdd6f4"
    readonly property color dimColor:  "#6c7086"
    readonly property color accent:    "#89b4fa"

    // Set explicitly rather than relying on Qt's default. Unset, Qt uses
    // whatever fontconfig resolves for sans-serif (Noto Sans here), which
    // means the bar would look different on a machine with a different font
    // set - including a fresh install from the installer in install/.
    // NOTE the family is "Inter Variable", NOT "Inter". rsms-inter-vf-fonts
    // registers it under that name; asking for "Inter" silently falls back to
    // Noto Sans, which looks like the font failed to install.
    // Check with:  fc-match "Inter Variable"
    readonly property string fontFamily: "Inter Variable"

    // Bar text is bold throughout - at these sizes regular weight reads thin
    // against the dark background.
    readonly property bool fontBold: true

    Rectangle {
        anchors.fill: parent
        color: root.bgColor

        // A hairline under the bar reads as a deliberate edge rather than the
        // bar just stopping.
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: Qt.darker(root.bgColor, 1.4)
        }

        // Three regions: left, centre, right. Laid out independently so a
        // wide centre widget cannot push the side ones around, which is what
        // happens if the whole bar is one RowLayout.
        Item {
            id: leftRegion
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: 12 }
            width: leftRow.implicitWidth

            Row {
                id: leftRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Logo {
                    anchors.verticalCenter: parent.verticalCenter
                    fgColor: root.fgColor
                    hoverColor: root.accent
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
                    color: Qt.rgba(root.dimColor.r, root.dimColor.g, root.dimColor.b, 0.5)
                }

                Workspaces {
                    anchors.verticalCenter: parent.verticalCenter
                    fgColor: root.fgColor
                    dimColor: root.dimColor
                    accentColor: root.accent
                    fontFamily: root.fontFamily
                    fontBold: root.fontBold
                }

                // Hidden until a volume/brightness key is pressed. Sits right
                // after the workspaces and collapses to zero width when idle,
                // so nothing else in the bar moves while it is hidden.
                Osd {
                    id: osd
                    anchors.verticalCenter: parent.verticalCenter
                    fgColor: root.fgColor
                    dimColor: root.dimColor
                    accentColor: root.accent
                    fontFamily: root.fontFamily
                    fontBold: root.fontBold
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
                    fgColor: root.fgColor
                    fontFamily: root.fontFamily
                }
            }
        }

        Item {
            id: rightRegion
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: 12 }
            width: rightRow.implicitWidth

            Row {
                id: rightRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Text {
                    text: "right"
                    color: root.dimColor
                    font.family: root.fontFamily
                    font.bold: root.fontBold
                    font.pixelSize: 12
                }
            }
        }
    }
}
