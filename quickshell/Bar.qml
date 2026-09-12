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

        // Square on every corner. The bar is the TOP EDGE of the frame that
        // Frame.qml draws down the sides and across the bottom, so rounding
        // where they meet would leave a visible notch at the junction instead
        // of one continuous border. The rounding lives on the frame's outer
        // bottom corners instead.

        // No bottom hairline any more: with rounded corners it cut straight
        // across them. The corner radius is the edge now.

        // Three regions: left, centre, right. Laid out independently so a
        // wide centre widget cannot push the side ones around, which is what
        // happens if the whole bar is one RowLayout.
        // Each region sits on its own rounded container rather than directly
        // on the bar. That is the single change that makes this read as a
        // designed bar instead of icons floating on a strip: it groups what
        // belongs together, and gives the eye edges to rest against.
        Item {
            id: leftRegion
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: Theme.barPadding }
            width: leftPill.width

            Rectangle {
                id: leftPill
                anchors.verticalCenter: parent.verticalCenter
                height: Theme.pillHeight
                // Tracks its contents, so the OSD sliding out widens the pill
                // with it instead of overflowing.
                // The OSD is NOT in leftRow - see Osd.qml. It is added here
                // instead, width and leading gap together, so the whole thing
                // grows and shrinks on one animated value.
                width: leftRow.implicitWidth + osd.implicitWidth + Theme.pillPadding * 2
                radius: height / 2

                // Lit from above - see the depth note in Theme.qml.
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.surfaceTop }
                    GradientStop { position: 1.0; color: Theme.surface }
                }
                border.width: 1
                border.color: Theme.rim

                // NO Behavior ON THIS WIDTH, deliberately.
                //
                // leftRow.implicitWidth is ALREADY animating - the OSD inside
                // it animates its own implicitWidth on Theme.animReveal. An
                // animation here would be a second one chasing a target that
                // moves every frame, restarting a fresh curve each time, so
                // the pill lags its own contents and then snaps to catch up at
                // the end. Collapsing was where that showed worst.
                //
                // Tracking the row instantly means one animation drives the
                // whole motion and the pill's edge stays welded to its
                // contents in both directions.

            Row {
                id: leftRow
                anchors { left: parent.left
                          leftMargin: Theme.pillPadding
                          verticalCenter: parent.verticalCenter }
                spacing: Theme.itemSpacing

                Logo {
                    anchors.verticalCenter: parent.verticalCenter
                    // Nothing wired to the click yet - this is where a
                    // launcher or a menu would go once one exists.
                    onActivated: console.log("logo clicked")
                }

                // The separator that used to sit here is gone. It existed to
                // stop the logo and the workspaces reading as one run of
                // shapes on a flat strip - a job the surrounding pill now
                // does. Left in, it was a stray hairline inside a container.

                Workspaces {
                    anchors.verticalCenter: parent.verticalCenter
                }

            }

            // Hidden until a volume/brightness key is pressed. Sits right
            // after the workspaces and collapses to nothing when idle.
            // Outside the Row on purpose - it carries its own leading gap.
            Osd {
                id: osd
                anchors { left: leftRow.right
                          verticalCenter: parent.verticalCenter }
            }
            }
        }

        Item {
            id: centerRegion
            anchors.centerIn: parent
            width: centerRow.implicitWidth
            height: parent.height

            Rectangle {
                anchors.centerIn: parent
                height: Theme.pillHeight
                width: centerRow.implicitWidth + Theme.pillPadding * 2
                radius: height / 2

                // Lit from above - see the depth note in Theme.qml.
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.surfaceTop }
                    GradientStop { position: 1.0; color: Theme.surface }
                }
                border.width: 1
                border.color: Theme.rim

                Row {
                    id: centerRow
                    anchors.centerIn: parent
                    spacing: 10

                    Clock {
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        Item {
            id: rightRegion
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: Theme.barPadding }
            width: rightPill.width

            Rectangle {
                id: rightPill
                anchors.verticalCenter: parent.verticalCenter
                height: Theme.pillHeight
                width: rightRow.implicitWidth + Theme.pillPadding * 2
                radius: height / 2

                // Lit from above - see the depth note in Theme.qml.
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.surfaceTop }
                    GradientStop { position: 1.0; color: Theme.surface }
                }
                border.width: 1
                border.color: Theme.rim

            Row {
                id: rightRow
                anchors.centerIn: parent
                spacing: 10

                Text {
                    text: "right"
                    color: Theme.dim
                    font.family: Theme.font
                    font.weight: Theme.weightMedium
                    font.pixelSize: Theme.fontSize
                }
            }
            }
        }
    }
}
