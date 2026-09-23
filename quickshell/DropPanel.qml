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
import Quickshell.Hyprland
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


    // CLOSE WHEN THE POINTER LEAVES THIS SCREEN, and this is a bug fix rather
    // than a flourish.
    //
    // While a panel is up it holds WlrKeyboardFocus.Exclusive, which is
    // compositor-wide rather than per-monitor. Open the audio panel on one
    // screen, move to the other and click that bar's speaker glyph, and the
    // click never reached the bar: Hyprland refocused the exclusive surface
    // first, so the press landed on THIS panel's dismissing MouseArea and
    // merely closed it. The second click worked, which is what made it look
    // like the other monitor's panel was broken. Read off Hyprland's own
    // events while reproducing it:
    //
    //   openlayer>>quickshell-audio     opened on the external
    //   focusedmon>>eDP-1,7             pointer moved to the laptop
    //   focusedmon>>DP-2,1              focus snapped BACK to the external
    //   closelayer>>quickshell-audio    the click was spent closing it
    //
    // One openlayer, never two. Closing as the pointer leaves means there is
    // no exclusive surface left to swallow the next click, and the bar on the
    // other screen behaves as if nothing had been open - which is also what a
    // dropdown should do when you walk away from it.
    //
    // focusedMonitor, not an enter/leave handler: this window covers its own
    // output only, so it never sees the pointer arrive on the other one.
    Connections {
        target: Hyprland
        function onFocusedMonitorChanged() {
            if (!root.revealed || !root.screen) return
            const mon = Hyprland.focusedMonitor
            // A null focusedMonitor is the second or so after a shell restart,
            // before the first event lands. Not knowing where the pointer is
            // is not a reason to close anything.
            //
            // By name: focusedMonitor and monitorFor() return different
            // wrapper objects for the same output, so identity between them
            // cannot be relied on.
            if (mon && root.screen && String(root.screen.name) !== String(mon.name)) root.close()
        }
    }

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
        //
        // THE SNAP IS ABOUT THE FRAME, so it still applies when floating even
        // though there is no strip to join: the sliver it exists to avoid is
        // between the card and the screen edge, and that is there either way.
        // What changes is what "side" then means - welded to the frame, or
        // simply held edgeInset off the edge like the bar above it.
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

    // A FADE WANTS LESS TIME THAN A SLIDE. A slide covers distance and the eye
    // follows it, so 260ms reads as deliberate; a cross-fade has nothing to
    // follow and the same 260 reads as the panel being slow to make up its
    // mind. The scrim shares this number, so shortening it here keeps the card
    // and the dimming in step - which is the whole reason the two are not
    // tuned separately.
    readonly property int openDuration: BarStyle.joined ? 260 : 170
    readonly property int closeDuration: BarStyle.joined ? 140 : 110
    property int slideDuration: openDuration

    // How far the card starts UNDER the bar's bottom edge, in px.
    //
    // Butted up exactly, the card's top edge lands wherever the bar's bottom
    // does - mid-pixel at fractional scaling (38 logical px is 59.53 physical
    // on the laptop's 1.5667). The card's first rows are then only partly
    // covered, and since the card is translucent the darker content under it
    // shows through right against the opaque bar: a grey hairline across the
    // top of the panel on cream. Measured from a screenshot: bar #faf4ed,
    // two rows of #e4ded8 / #e2ddd7, then the card's #f2ece6.
    //
    // Overlapping the bar hides that edge where it cannot show: the card's top
    // gradient stop is exactly Theme.bg, so over the bar it is the bar's own
    // colour whatever the panel alpha. The contents, fillets and padding are
    // pushed down by the same amount, so nothing visibly moves. The launcher
    // and power menu already avoid this by running under the frame.
    // NOTHING TO HIDE WHEN FLOATING: the card starts a clear gap below the
    // bar, so there is no junction for a hairline to appear at, and sliding
    // the card 2px up under a bar it does not touch would just misplace it.
    readonly property int seamOverlap: BarStyle.joined ? 2 : 0

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

        // Frame mode only - see BarStyle.scrim. Not composited at all when
        // floating, rather than painted at zero alpha.
        visible: BarStyle.scrim
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
    // emerge from the bar's bottom edge instead - from seamOverlap px under it,
    // so its top edge never sits on the bar's edge (see seamOverlap).
    Item {
        id: well
        anchors { fill: parent; topMargin: BarStyle.barBottom - root.seamOverlap }
        clip: true

        Item {
            id: card

            readonly property int pad: 14

            // Against a side frame, the extra frameThickness runs under the
            // frame strip, as in PowerMenu.qml, so the card and the frame are
            // one shape.
            width: root.panelWidth + (root.side === "none" ? 0 : BarStyle.frameRun)

            // Tracks the contents every frame, so anything inside that
            // animates its own height grows the card on that same curve.
            height: body.childrenRect.height + pad * 2 + root.seamOverlap

            // Anchored at the frames rather than placed by x there: a freshly
            // mapped surface learns its width only after the compositor
            // configures it, and an x computed from it would be stale.
            anchors.right: root.side === "right" ? parent.right : undefined
            anchors.left:  root.side === "left"  ? parent.left  : undefined
            anchors.top: parent.top

            // Held off the screen edge when floating, flush against it when
            // framed - where the last frameRun pixels run under the strip.
            anchors.rightMargin: BarStyle.edgeInset
            anchors.leftMargin:  BarStyle.edgeInset

            // X THROUGH A Binding, NOT A PROPERTY BINDING, and that is a bug
            // fix rather than a style. An active anchor overrides x AND
            // breaks any binding on it; clearing the anchor afterwards does
            // not bring the binding back. So a panel that had ever been
            // anchored - and every panel starts with side "right" - kept
            // whatever x it held at the time. Measured: opened centred under
            // the clock the card sat at x=-304, a whole panel width off the
            // left edge, because parent.width was still 0 when the surface
            // was first mapped and 0 - 304 is where anchoring right put it.
            //
            // A Binding with `when` only asserts itself while the card is
            // unanchored, so the two never fight over the same property.
            Binding {
                target: card
                property: "x"
                value: root.cardX
                when: root.side === "none"
                restoreMode: Binding.RestoreNone
            }

            // Closed offset includes the fillet that hangs below the card.
            // Bound to `height`, which only changes while closed if the
            // contents do; that merely re-runs an invisible slide.
            anchors.topMargin: (root.revealed || !BarStyle.joined)
                               ? 0 : -(height + Theme.cornerRadius)

            Behavior on anchors.topMargin {
                NumberAnimation {
                    duration: root.slideDuration
                    easing.type: Easing.InOutCubic
                    onRunningChanged: {
                        if (!running && !root.revealed) root.visible = false
                    }
                }
            }

            // FADE INSTEAD OF SLIDE WHEN FLOATING. A slide is a statement
            // about where the card comes FROM - out of the bar, in from the
            // edge - and it only reads that way while the card is joined to
            // the thing it slides out of. With a gap all round there is
            // nothing to emerge from, so the same motion looks like the card
            // is being dragged in from off screen for no reason.
            //
            // Exactly one of the two animates in either mode, which matters
            // because the surface is UNMAPPED from a Behavior's
            // onRunningChanged: the position binding is constant when
            // floating and the opacity binding is constant when framed, so a
            // Behavior whose value never changes never runs, and the one that
            // does run is always the one that owns the unmap. Both carry the
            // handler for that reason - drop it from either and closing that
            // mode leaves a fully transparent overlay mapped across the
            // screen, still swallowing every click on the dismissing
            // MouseArea underneath it.
            opacity: (BarStyle.joined || root.revealed) ? 1 : 0

            Behavior on opacity {
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

                    // FRAMED, the launcher's gradient turned upside down:
                    // this card grows out of the BAR, so its TOP stop is
                    // exactly Theme.bg and the junction has no seam.
                    //
                    // FLOATING, there is no junction to match and the card is
                    // an object in its own right, so it is lit from above like
                    // the bar pills and the launcher - the light in this shell
                    // comes from the top of the screen, and a card lit from
                    // below among things lit from above looks like a mistake
                    // long before anyone works out which one.
                    gradient: Gradient {
                        GradientStop { position: 0.0
                                       color: BarStyle.joined ? Theme.bg : Theme.panelTop }
                        GradientStop { position: 1.0
                                       color: BarStyle.joined ? Theme.panelTop : Theme.bg }
                    }

                    // Only corners out in the open are rounded. Framed, the
                    // top edge is the bar and a side against a frame is the
                    // frame, so neither gets a radius. Floating, every corner
                    // is out in the open and all four are rounded - the card
                    // is an object lying on the wallpaper, like the pills.
                    topLeftRadius:     BarStyle.joined ? 0 : Theme.cornerRadius
                    topRightRadius:    BarStyle.joined ? 0 : Theme.cornerRadius
                    bottomLeftRadius:  BarStyle.joined && root.side === "left"
                                       ? 0 : Theme.cornerRadius
                    bottomRightRadius: BarStyle.joined && root.side === "right"
                                       ? 0 : Theme.cornerRadius

                    // A rim only when floating, for the same reason the bar
                    // pills have one and the framed card does not: framed, a
                    // border would draw a line straight across the junction
                    // it is trying to hide.
                    border.width: BarStyle.joined ? 0 : 1
                    border.color: Theme.rim
                }

                // Where the card's left edge meets the bar.
                InnerCorner {
                    visible: BarStyle.joined && root.side !== "left"
                    corner: "topright"
                    anchors { top: parent.top; topMargin: root.seamOverlap
                              right: panelBody.left; rightMargin: -1 }
                }

                // Where the card's right edge meets the bar.
                InnerCorner {
                    visible: BarStyle.joined && root.side !== "right"
                    corner: "topleft"
                    anchors { top: parent.top; topMargin: root.seamOverlap
                              left: panelBody.right; leftMargin: -1 }
                }

                // Where the card's bottom edge meets the right frame.
                InnerCorner {
                    visible: BarStyle.joined && root.side === "right"
                    corner: "topright"
                    anchors { top: panelBody.bottom; topMargin: -1
                              right: panelBody.right; rightMargin: Theme.frameThickness }
                }

                // Where the card's bottom edge meets the left frame.
                InnerCorner {
                    visible: BarStyle.joined && root.side === "left"
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
                    top: parent.top;     topMargin: card.pad + root.seamOverlap
                    left: parent.left;   leftMargin: card.pad + (root.side === "left" ? BarStyle.frameRun : 0)
                    right: parent.right; rightMargin: card.pad + (root.side === "right" ? BarStyle.frameRun : 0)
                }
            }
        }
    }
}
