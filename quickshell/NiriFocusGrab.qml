// =========================================================================
// NiriFocusGrab - dismiss a panel when the compositor takes focus away
// =========================================================================
//
// The niri half of what HyprlandFocusGrab does, with the same two members -
// `active` and `cleared()` - so a panel carries one of each and reads the same.
//
// WHY IT IS NEEDED. niri does not implement hyprland-focus-grab, so a panel that
// relies on it stays open when you click another window: measured by opening the
// launcher and spawning a terminal, after which the quickshell-launcher layer was
// still there. Clicks inside the panel's own surface already dismiss it through
// its MouseArea; this is for everything outside it.
//
// HOW IT KNOWS, with no protocol for it: niri reports NO focused window while a
// layer surface holds keyboard focus. Checked on the running compositor -
// `niri msg focused-window` prints the terminal, then null while the launcher is
// up, then the terminal again once focus returns. So a focused window appearing
// while the panel is open means the panel no longer has focus.
//
// THE `held` FLAG IS NOT OPTIONAL. At the moment a panel opens, focus has not
// moved to it yet and niri still reports the window that had it - without
// waiting for focus to arrive first, the panel would close itself on the frame
// it opened. So the grab arms only after it has seen focus leave the windows,
// and fires on the first one that takes it back.

import QtQuick

Item {
    id: grab

    property bool active: false
    signal cleared()

    // Whether focus has actually reached the panel yet.
    property bool held: false

    onActiveChanged: grab.held = false

    Connections {
        target: Compositor
        enabled: grab.active && Compositor.onNiri

        function onFocusedWindowChanged(): void {
            if (!Compositor.focusedWindow) {
                grab.held = true          // the panel has focus now
                return
            }
            if (grab.held) {
                grab.held = false
                grab.cleared()
            }
        }
    }
}
