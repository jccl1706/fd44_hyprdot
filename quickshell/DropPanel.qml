// =========================================================================
// DropPanel - a card that slides down out of the bar's top-right corner
// =========================================================================
//
// The shared chrome of the bar's drop-down panels (AudioPanel, NetworkPanel):
// a full-screen overlay with a scrim, and a card that comes down out of the
// bar UNDER THE GLYPH THAT OPENED IT, joined to the bar by concave fillets.
// A panel supplies only its contents:
//
//     DropPanel {
//         layerNamespace: "quickshell-something"
//         Column { width: parent.width; ... }
//     }
//
// The surface arrangement - full-screen for click-outside, unmapped when
// closed, exclusion ignored, keyboard focus only while open - is the same as
// Launcher.qml's and PowerMenu.qml's, and is explained there.
//
// WHERE THE CARD GOES follows the plugin, which can be dragged anywhere along
// the bar (Bar.qml). open(x) centres the card under x - unless that would
// leave it within 64px of a side frame, where a sliver of desktop between
// card and frame looks like a mistake. There it joins the frame instead,
// running under it, as the original top-right panels did:
//
//   side "right"   against the right frame, fillets at bar and frame
//   side "left"    the mirror image, against the left frame
//   side "none"    floating, a fillet into the bar on each side
//
// Opened without an x (IPC, a keybind) it goes to the right.
//
// Each panel needs its own namespace, and hypr/rules.lua a no_anim rule for
// it, or Hyprland's layer fade runs on top of the slide.

import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    // Layer-shell namespace, e.g. "quickshell-audio".
    required property string layerNamespace

    // Visible width of the card. It is frameThickness wider in fact - see card.
    property int panelWidth: 340

    // Children declared inside a DropPanel land in the card, below the pad.
    default property alias content: body.data

    property bool revealed: false

    // Emitted at the start of open()/close(), for a panel to reset its own
    // state - collapse a dropdown, start or stop a scan.
    signal opening()
    signal closing()

    // Every key the card receives. Accept the event to keep it; an unaccepted
    // Escape closes the panel, so a panel can use Escape to back out of
    // something of its own first.
    signal keyPressed(var event)

    // --- window ----------------------------------------------------------

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: root.layerNamespace
    WlrLayershell.keyboardFocus: revealed ? WlrKeyboardFocus.Exclusive
                                          : WlrKeyboardFocus.None

    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: false

    // Placement, fixed at open() so the card never wanders while it is up.
    property string side: "right"
    property real cardX: 0

    function place(x): void {
        const sw = root.screen ? root.screen.width : root.width
        const half = root.panelWidth / 2
        // 64px. A glyph just after the workspaces centres a 340px card about
        // 45px from the left frame - close enough to read as a near miss.
        const snap = Theme.cornerRadius * 5 + Theme.frameThickness
        if (typeof x !== "number" || x < 0 || x + half > sw - snap) {
            root.side = "right"
        } else if (x - half < snap) {
            root.side = "left"
        } else {
            root.side = "none"
            root.cardX = Math.round(x - half)
        }
    }

    // --- public API ------------------------------------------------------

    // `x` is the screen x to open under - the centre of the glyph. Omit it
    // to open at the right.
    function open(x): void {
        root.place(x)
        root.opening()
        root.visible = true
        // Before `revealed`, always - see the duration note in PowerMenu.qml.
        root.slideDuration = root.openDuration
        root.revealed = true
        card.forceActiveFocus()
    }

    function close(): void {
        root.closing()
        root.slideDuration = root.closeDuration
        root.revealed = false
    }

    function toggle(x): void {
        if (root.revealed) root.close()
        else root.open(x)
    }

    // Takes keyboard focus back from a text field inside the panel, so the
    // panel's own keys work again.
    function focusCard(): void {
        card.forceActiveFocus()
    }

    readonly property int openDuration: 260
    readonly property int closeDuration: 140
    property int slideDuration: openDuration

    // --- scrim -----------------------------------------------------------
    //
    // Inset past the bar and the frame and rounded to the well, exactly as in
    // PowerMenu.qml - a square scrim dims the frame's concave corner pieces.

    Rectangle {
        anchors {
            fill: parent
            topMargin:    Theme.barHeight
            leftMargin:   Theme.frameThickness
            rightMargin:  Theme.frameThickness
            bottomMargin: Theme.frameThickness
        }
        radius: Theme.cornerRadius
        color: "#000000"
        opacity: root.revealed ? 0.35 : 0
        Behavior on opacity {
            NumberAnimation { duration: root.slideDuration; easing.type: Easing.InOutCubic }
        }
    }

    // Covers the bar too, so clicking the bar glyph again closes the panel
    // rather than reaching the bar underneath and reopening it.
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    // --- card ------------------------------------------------------------

    // The card slides down from BEHIND the bar, and this surface is an overlay
    // above it - unclipped, the card would be drawn across the bar's right
    // pill on its way down. Clipping to the region below the bar makes it
    // emerge from the bar's bottom edge instead.
    Item {
        id: well
        anchors { fill: parent; topMargin: Theme.barHeight }
        clip: true

        Item {
            id: card

            readonly property int pad: 14

            // Against a side frame, the extra frameThickness runs under the
            // frame strip, as in PowerMenu.qml, so the card and the frame are
            // one shape.
            width: root.panelWidth + (root.side === "none" ? 0 : Theme.frameThickness)

            // Tracks the contents every frame, so anything inside that
            // animates its own height grows the card on that same curve.
            height: body.childrenRect.height + pad * 2

            // Anchored at the frames rather than placed by x there: a freshly
            // mapped surface learns its width only after the compositor
            // configures it, and an x computed from it would be stale.
            anchors.right: root.side === "right" ? parent.right : undefined
            anchors.left:  root.side === "left"  ? parent.left  : undefined
            x: root.cardX
            anchors.top: parent.top

            // Closed offset includes the fillet that hangs below the card.
            // Bound to `height`, which only changes while closed if the
            // contents do; that merely re-runs an invisible slide.
            anchors.topMargin: root.revealed ? 0 : -(height + Theme.cornerRadius)

            Behavior on anchors.topMargin {
                NumberAnimation {
                    duration: root.slideDuration
                    easing.type: Easing.InOutCubic
                    onRunningChanged: {
                        if (!running && !root.revealed) root.visible = false
                    }
                }
            }

            focus: true
            Keys.onPressed: event => {
                root.keyPressed(event)
                if (!event.accepted && event.key === Qt.Key_Escape) {
                    root.close()
                    event.accepted = true
                }
            }

            // Background and fillets flattened into one translucent layer -
            // see PowerMenu.qml for why layer.enabled is required.
            Item {
                id: panel
                // Wider than the card by a radius on each side and below:
                // a layer is clipped to its item, and the fillets live outside
                // the card.
                anchors.fill: parent
                anchors.leftMargin:   -Theme.cornerRadius
                anchors.rightMargin:  -Theme.cornerRadius
                anchors.bottomMargin: -Theme.cornerRadius
                opacity: Theme.panelAlpha
                layer.enabled: true

                Rectangle {
                    id: panelBody
                    anchors.fill: parent
                    anchors.leftMargin:   Theme.cornerRadius
                    anchors.rightMargin:  Theme.cornerRadius
                    anchors.bottomMargin: Theme.cornerRadius

                    // The launcher's gradient turned upside down: this card
                    // grows out of the BAR, so its TOP stop is exactly
                    // Theme.bg and the junction has no seam.
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.bg }
                        GradientStop { position: 1.0; color: Theme.panelTop }
                    }

                    // Only corners out in the open are rounded. The top edge
                    // is the bar, and a side against a frame is the frame.
                    bottomLeftRadius:  root.side === "left"  ? 0 : Theme.cornerRadius
                    bottomRightRadius: root.side === "right" ? 0 : Theme.cornerRadius
                }

                // Where the card's left edge meets the bar.
                InnerCorner {
                    visible: root.side !== "left"
                    corner: "topright"
                    anchors { top: parent.top
                              right: panelBody.left; rightMargin: -1 }
                }

                // Where the card's right edge meets the bar.
                InnerCorner {
                    visible: root.side !== "right"
                    corner: "topleft"
                    anchors { top: parent.top
                              left: panelBody.right; leftMargin: -1 }
                }

                // Where the card's bottom edge meets the right frame.
                InnerCorner {
                    visible: root.side === "right"
                    corner: "topright"
                    anchors { top: panelBody.bottom; topMargin: -1
                              right: panelBody.right; rightMargin: Theme.frameThickness }
                }

                // Where the card's bottom edge meets the left frame.
                InnerCorner {
                    visible: root.side === "left"
                    corner: "topleft"
                    anchors { top: panelBody.bottom; topMargin: -1
                              left: panelBody.left; leftMargin: Theme.frameThickness }
                }
            }

            // Swallows clicks so they do not reach the dismissing MouseArea.
            MouseArea { anchors.fill: parent }

            Item {
                id: body
                // Padding measured from the VISIBLE edges - the part running
                // under a frame does not count.
                anchors {
                    top: parent.top;     topMargin: card.pad
                    left: parent.left;   leftMargin: card.pad + (root.side === "left" ? Theme.frameThickness : 0)
                    right: parent.right; rightMargin: card.pad + (root.side === "right" ? Theme.frameThickness : 0)
                }
            }
        }
    }
}
