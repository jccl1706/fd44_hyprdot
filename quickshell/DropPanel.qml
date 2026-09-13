// =========================================================================
// DropPanel - a card that slides down out of the bar's top-right corner
// =========================================================================
//
// The shared chrome of the bar's drop-down panels (AudioPanel, NetworkPanel):
// a full-screen overlay with a scrim, and a card that comes down out of the
// bar against the right frame, joined to both by concave fillets. A panel
// supplies only its contents:
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

    // --- public API ------------------------------------------------------

    function open(): void {
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

    function toggle(): void {
        if (root.revealed) root.close()
        else root.open()
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

            // The extra frameThickness runs under the right frame strip, as
            // in PowerMenu.qml, so the card and the frame are one shape.
            width: root.panelWidth + Theme.frameThickness

            // Tracks the contents every frame, so anything inside that
            // animates its own height grows the card on that same curve.
            height: body.childrenRect.height + pad * 2

            anchors.right: parent.right
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
                anchors.fill: parent
                anchors.leftMargin:   -Theme.cornerRadius
                anchors.bottomMargin: -Theme.cornerRadius
                opacity: Theme.panelAlpha
                layer.enabled: true

                Rectangle {
                    id: panelBody
                    anchors.fill: parent
                    anchors.leftMargin:   Theme.cornerRadius
                    anchors.bottomMargin: Theme.cornerRadius

                    // The launcher's gradient turned upside down: this card
                    // grows out of the BAR, so its TOP stop is exactly
                    // Theme.bg and the junction has no seam.
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.bg }
                        GradientStop { position: 1.0; color: Theme.panelTop }
                    }

                    // Only the corner that is out in the open is rounded. The
                    // top edge is the bar and the right edge is the frame.
                    bottomLeftRadius: Theme.cornerRadius
                }

                // Where the card's left edge meets the bar.
                InnerCorner {
                    corner: "topright"
                    anchors { top: parent.top
                              right: panelBody.left; rightMargin: -1 }
                }

                // Where the card's bottom edge meets the right frame.
                InnerCorner {
                    corner: "topright"
                    anchors { top: panelBody.bottom; topMargin: -1
                              right: parent.right; rightMargin: Theme.frameThickness }
                }
            }

            // Swallows clicks so they do not reach the dismissing MouseArea.
            MouseArea { anchors.fill: parent }

            Item {
                id: body
                anchors {
                    top: parent.top;     topMargin: card.pad
                    left: parent.left;   leftMargin: card.pad
                    right: parent.right; rightMargin: card.pad + Theme.frameThickness
                }
            }
        }
    }
}
