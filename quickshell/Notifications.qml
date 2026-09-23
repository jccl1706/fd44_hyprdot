// =========================================================================
// Notifications - the toast stack
// =========================================================================
//
// One surface per monitor, holding the cards NotificationService is
// currently showing. Top-right, under the bar and inside the frame, which
// is where the panels already live - a notification arrives from the same
// corner the volume and network panels drop out of.
//
// ONLY ON THE FOCUSED MONITOR. A toast on every screen is the OSD's
// arrangement and is right for it - a volume change is about the machine,
// so it appears wherever you are looking. A notification is a thing to read
// and click, and two copies of it means dismissing it twice. Same rule as
// the launcher and the panels, and the same Hyprland.focusedMonitor behind
// it.
//
// SMALL AND FIXED, NOT FULL-SCREEN, and both halves of that matter.
//
// Fixed, because a layer-shell surface that resizes as cards come and go
// gives the compositor a stale buffer to scale for a frame, which reads as
// the cards stretching. Learned from Omarchy, who hit it first.
//
// Small, because Qt Quick repaints the WHOLE window whenever anything in it
// changes, and hovering a card changes something on every pointer move. At
// full screen that was 2560x1440 - 3.7 million pixels redrawn to animate a
// close button, which made the pointer stutter over the toasts exactly as it
// did over the audio panel. At 400x620 it is 248 thousand, fifteen times
// less. The panels cannot do this because they have to catch clicks
// anywhere on screen to dismiss; toasts have no such duty, so the surface
// only has to be big enough to hold them.
//
// The height fits about six cards. A seventh would be clipped rather than
// pushing the stack off screen, which is the better failure: six unread
// toasts already means something has gone wrong upstream.
//
// Nothing here is clickable except the cards themselves, and the window
// never takes keyboard focus - a toast must not steal input from what you
// are typing into.

import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    // A PLAIN PROPERTY DRIVEN BY A SIGNAL, not a binding, and that is not
    // stylistic. Hyprland.monitorFor() is an ordinary function call, so Qt
    // cannot know when its result changes and will not re-evaluate a binding
    // that depends on it. Worse, Hyprland.focusedMonitor starts null - the
    // Hyprland connection populates it only once something subscribes - so a
    // binding evaluated at creation latched onto "not focused" and stayed
    // there. Measured: the window never mapped at all until the check was
    // removed.
    property bool onFocusedMonitor: false

    function refreshFocus(): void {
        const mon = Hyprland.focusedMonitor
        if (!mon) {
            // Not knowing yet. One arbitrary screen beats all of them, and
            // beats none - a notification that never appears is worse than
            // one that appears on the wrong monitor for a second.
            root.onFocusedMonitor = Quickshell.screens.length > 0
                                    && Quickshell.screens[0] === root.modelData
            return
        }
        // BY NAME. focusedMonitor and monitorFor() are different wrapper
        // objects for the same output, so `===` between them is false during
        // the monitor-list churn at startup - which is exactly when this
        // first runs, so the window latched "not focused" and never mapped.
        root.onFocusedMonitor = root.modelData
                                && String(root.modelData.name) === String(mon.name)
    }

    Connections {
        target: Hyprland
        function onFocusedMonitorChanged() { root.refreshFocus() }
    }

    Component.onCompleted: root.refreshFocus()

    visible: NotificationService.popups.count > 0 && root.onFocusedMonitor

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; right: true }
    implicitWidth: 400
    implicitHeight: 620
    color: "transparent"

    // Click-through everywhere except the cards. Without this the whole
    // screen would swallow clicks whenever a toast was up, which is the bug
    // the audio panel had for a different reason.
    mask: Region { item: column }

    Column {
        id: column
        anchors {
            top: parent.top
            right: parent.right
            // Measured from the BOTTOM OF THE BAR and from the inside of
            // whatever holds the right edge - the frame strip when there is
            // one, the same gap the bar keeps when it is floating. Spelling
            // either as a Theme constant directly assumes the frame exists.
            topMargin: BarStyle.barBottom + Theme.barPadding
            rightMargin: BarStyle.contentInset + Theme.barPadding
        }
        spacing: 8

        Repeater {
            model: NotificationService.popups

            NotificationToast {
                required property var model

                key:      model.key
                summary:  model.summary
                body:     model.body
                appName:  model.appName
                appIcon:  model.appIcon
                image:    model.image
                urgency:  model.urgency
                duration: model.duration

                onActivated: NotificationService.activate(key)
                onDismissed: NotificationService.close(key, true)

                // Cards slide in from the right rather than appearing, so a
                // toast arriving while you are reading another one is
                // something you notice at the edge of vision rather than a
                // sudden change of the whole stack.
                opacity: 0
                x: 40
                Component.onCompleted: {
                    opacity = 1
                    x = 0
                }
                Behavior on opacity { NumberAnimation { duration: Theme.animReveal } }
                Behavior on x {
                    NumberAnimation { duration: Theme.animReveal; easing.type: Easing.OutCubic }
                }
            }
        }
    }
}
