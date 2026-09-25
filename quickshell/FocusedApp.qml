// =========================================================================
// FocusedApp - the icon of whatever window has the keyboard
// =========================================================================
//
// A bar plugin, so it can be placed in any zone from the settings window.
// Sitting next to the workspaces is what it was asked for: the chips say
// WHERE you are, this says WHAT is there.
//
// WHICH WINDOW IS FOCUSED, and why not the obvious property. Quickshell's
// Hyprland.activeToplevel exists and is null until an `activewindow` event
// arrives - so a shell restarted while you sit still shows nothing until you
// click something, which is precisely when you are looking at the bar
// wondering why it is empty. Hyprland's own answer is in every toplevel:
// focusHistoryID counts back from the focused window, so 0 IS the focused
// one, and it is correct the moment the list is first read.
//
// THE LIST HAS TO BE ASKED, NOT AWAITED. focusHistoryID lives in the IPC
// object Hyprland returns for `clients`, and Hyprland does not push a new one
// when focus moves - it only says "activewindow". So the events are the
// trigger and refreshToplevels() is the question; without the refresh the
// icon would be right once and then lie.
//
// CLASS TO ICON, through DesktopEntries like everything else here: a window
// says it is "org.gnome.Nautilus" or "chromium-browser", and the desktop
// entry of that id carries the icon name that bin/icon-bridge.sh has already
// made resolvable. Windows with no matching entry - a dialog, a game, an
// XWayland oddity - get no icon and this collapses to nothing rather than
// showing a broken-image square.

import Quickshell
import Quickshell.Hyprland
import QtQuick

Item {
    id: root

    readonly property var focused: {
        const all = Hyprland.toplevels.values
        for (const t of all) {
            const o = t.lastIpcObject
            if (o && o.focusHistoryID === 0) return o
        }
        return null
    }

    readonly property string appClass: root.focused
        ? (root.focused.class || root.focused.initialClass || "") : ""

    // The desktop entry whose id matches the window class, case-insensitively
    // because Hyprland reports what the application set and applications are
    // inconsistent about it - "Chromium-browser" and "chromium-browser" are
    // the same program.
    readonly property var entry: {
        const want = root.appClass.toLowerCase()
        if (!want) return null
        for (const e of DesktopEntries.applications.values) {
            const id = (e.id || "").toLowerCase().replace(/\.desktop$/, "")
            if (id === want) return e
        }
        // A second pass on StartupWMClass, which is the field that exists for
        // exactly this question and is what applications/youtube.desktop sets.
        for (const e of DesktopEntries.applications.values) {
            if ((e.startupClass || "").toLowerCase() === want) return e
        }
        return null
    }

    readonly property string iconSource: root.entry && root.entry.icon
        ? Quickshell.iconPath(root.entry.icon, true) : ""

    // Collapses when there is nothing to show, so the pill closes up around
    // it rather than holding an empty square. BarZone measures this width.
    implicitWidth: root.iconSource ? 20 : 0        // what ThemeToggle and the rest are
    implicitHeight: Theme.glyphSize
    visible: implicitWidth > 0

    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
    }

    Image {
        id: icon
        anchors.fill: parent
        source: root.iconSource
        sourceSize.width: Theme.glyphSize * 2     // crisp on a scaled display
        sourceSize.height: Theme.glyphSize * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true

        // A swap without this is a blink; with it the new icon arrives as the
        // old one leaves, which is what the workspace chips do when focus
        // moves and is the reason the two read as one movement.
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    // Hyprland says "focus moved"; it does not say what focusHistoryID now is
    // for every window. Asking costs one IPC round trip per focus change,
    // which is the same order as the workspace chips already do.
    Connections {
        target: Hyprland
        function onRawEvent(event): void {
            switch (event.name) {
            case "activewindow":
            case "activewindowv2":
            case "openwindow":
            case "closewindow":
            case "movewindow":
                Hyprland.refreshToplevels()
            }
        }
    }

    Component.onCompleted: Hyprland.refreshToplevels()
}
