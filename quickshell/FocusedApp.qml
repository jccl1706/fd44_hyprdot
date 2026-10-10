// =========================================================================
// FocusedApp - the icon of whatever window has the keyboard
// =========================================================================
//
// NOT A BAR PLUGIN. It lives in a circle of its own beside the workspaces
// pill, placed directly by Bar.qml: the dots say WHERE you are, this says
// WHAT is there, and the gap between them says they are two different
// questions. It was a plugin in the left zone once, inside the same pill as
// the dots, and that read as one more thing crowding the row.
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

    // focusHistoryID 0 IS NOT ENOUGH, and that was a bug: move to an empty
    // workspace and Hyprland does not reset the history, so the window you
    // were last in keeps id 0 while sitting on the workspace you just left.
    // The bar went on showing its icon over an empty screen.
    //
    // Measured on workspace 7 with nothing on it:
    //
    //     activewindow        ''            (nothing is focused)
    //     focusHistoryID 0 -> kitty on workspace 2
    //     focused workspace   7
    //
    // So the window must ALSO be on the workspace being looked at. Both
    // halves are needed: the workspace alone would match every window on it,
    // and the history alone matches a window that is not here.
    readonly property var focusedRaw: {
        const w = Compositor.focusedWindow
        if (!w) return null
        const here = Compositor.focusedWorkspaceId
        if (here === -1 || w.workspaceId !== here) return null
        return w
    }

    // AND IT MUST SURVIVE OUR OWN POPUPS, which is the second time a layer
    // surface has blanked this icon. The note above is about hyprlock doing it
    // on Hyprland; this is every panel in this shell doing it on niri.
    //
    // niri reports NO focused window at all while a layer surface holds the
    // keyboard - the same fact NiriFocusGrab.qml depends on to know a panel
    // still has focus. So opening the launcher, the power menu, the wallpaper
    // or theme picker made `focusedWindow` null and the icon vanished, every
    // time, returning when the panel closed. Measured on the running
    // compositor: `kitty` focused, then NONE while a popup was up.
    //
    // The icon answers "which application am I in", and that does not change
    // because a menu opened over it. So the last window seen focused is held.
    property var lastFocused: null
    onFocusedRawChanged: if (root.focusedRaw) root.lastFocused = root.focusedRaw

    readonly property var focused: {
        if (root.focusedRaw) return root.focusedRaw

        // Nothing holds the keyboard. Either one of our own surfaces took it,
        // or the workspace really is empty - and ONLY THE SECOND should clear
        // the icon. That distinction is the whole bug documented above: an
        // empty workspace must still blank it.
        const here = Compositor.focusedWorkspaceId
        if (here === -1) return null

        const last = root.lastFocused
        // A window remembered from another workspace is not this one's answer,
        // so switching workspace while a panel is open does not drag an icon
        // across with it.
        if (!last || last.workspaceId !== here) return null

        for (const w of Compositor.windows)
            if (w.workspaceId === here) return last
        return null
    }

    // WHAT THE EVENT SAID, WITHOUT WAITING TO BE TOLD AGAIN.
    //
    // `activewindow` arrives as "class,title" - the class is right there, and
    // it is the same string the client list would give a round trip later.
    // Waiting for that round trip is what made the icon lag: measured at four
    // consecutive screenshots, roughly 400ms, between stepping onto a
    // workspace and its icon appearing.
    //
    // AN EMPTY CLASS IS NOT AN ANSWER, AND TREATING IT AS ONE BROKE SLEEP.
    // Hyprland sends `activewindow>>,` with nothing after the comma whenever
    // focus leaves every window, and locking or blanking the screen does
    // exactly that - hyprlock is a layer surface, not a toplevel. Coming back
    // it hands focus to the same window it took it from, WITHOUT a new
    // `activewindow`, because from Hyprland's side nothing changed. So the
    // empty string stayed the last thing said about focus and the circle sat
    // blank beside an open terminal until the next click. Reproduced after a
    // resume: `hyprctl activewindow` said kitty, focusHistoryID 0, workspace
    // 2, and the bar showed nothing.
    //
    // So a class only wins while it names something. Empty falls through to
    // the client list, which answers this correctly and quickly: `focused`
    // matches the window against the CURRENT workspace, and the workspace
    // updates from its own event, so stepping onto an empty workspace clears
    // the icon on the same frame without the empty event being trusted.
    property string liveClass: ""

    // The refreshed client list is still the authority - it is what survives a
    // shell restart, when no event has been seen at all - but only until the
    // next event that names a window, which is fresher by definition.
    readonly property string modelClass: root.focused
        ? (root.focused.appId || root.focused.initialAppId || "") : ""

    readonly property string appClass:
        root.liveEvent && root.liveClass !== "" ? root.liveClass : root.modelClass

    //: Set once an event has been seen; before that the model answers.
    property bool liveEvent: false

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

    // A fixed size: the circle around it is what appears and disappears, and
    // it reads `iconSource` to decide. Sizing this to nothing as well would
    // shrink the circle around the icon as it went, which is a second
    // animation saying the same thing.
    implicitWidth: 18
    implicitHeight: 18

    // NO WIDTH ANIMATION. The icon already travels when the workspace row
    // beside it changes size - it is anchored after it - and animating its own
    // width on top of that made it arrive twice: slide, then grow. It appears
    // at full size and lets the fade do the rest.

    Image {
        id: icon
        anchors.fill: parent
        source: root.iconSource
        sourceSize.width: Theme.glyphSize * 2     // crisp on a scaled display
        sourceSize.height: Theme.glyphSize * 2
        fillMode: Image.PreserveAspectFit
        smooth: true

        // SYNCHRONOUS, WHICH IS THE RIGHT WAY ROUND FOR A 20px ICON. Async
        // loading exists so a big image cannot stall the frame; these are
        // small, already on disk, and Qt caches them after the first look, so
        // the only thing the background thread bought was a frame or two of
        // blank space every time focus moved. Measured at ~200ms from the
        // switch to the first pixel, most of it waiting rather than working.
        asynchronous: false
        cache: true

        // A swap without this is a blink; with it the new icon arrives as the
        // old one leaves, which is what the workspace chips do when focus
        // moves and is the reason the two read as one movement.
        // The fade stays, but at half the length: long enough that a swap
        // between two applications is a dissolve rather than a cut, short
        // enough that it is not felt as the icon "taking a moment".
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast / 2 } }
    }

    // Hyprland says "focus moved"; it does not say what focusHistoryID now is
    // for every window. Asking costs one IPC round trip per focus change,
    // which is the same order as the workspace chips already do.
    // HYPRLAND ONLY, AND NOT NEEDED ON NIRI. This block is the latency fix
    // described above: it reads the class out of the event itself instead of
    // waiting for the model to catch up. niri has no equivalent event
    // vocabulary - no `activewindow`, no `workspacev2` - and no need for one,
    // because its event stream updates Compositor.focusedWindow directly with
    // no round trip to wait for. So on niri the fast path is switched off and
    // appClass falls through to modelClass, which is already current.
    Connections {
        target: Hyprland
        enabled: !Compositor.onNiri
        function onRawEvent(event): void {
            switch (event.name) {
            case "activewindow": {
                // "class,title", and an empty class when nothing is focused.
                const data = event.data || ""
                const comma = data.indexOf(",")
                root.liveClass = comma >= 0 ? data.substring(0, comma) : data
                root.liveEvent = true
                Compositor.refreshWindows()
                return
            }
            case "activewindowv2":
            case "openwindow":
            case "closewindow":
            case "movewindow":
            // Moving between workspaces changes nothing about the windows and
            // everything about which one is "here", and an empty workspace
            // emits only this - `activewindow` arrives with an empty class,
            // but the workspace event is what says where you now are.
            case "workspace":
            case "workspacev2":
            case "focusedmon":
                // A workspace change with no window on the other side sends no
                // `activewindow` of its own on some paths, so the model is
                // asked - and `liveClass` is left alone, because the event
                // that set it is still the most recent thing anyone said about
                // focus.
                Compositor.refreshWindows()
            }
        }
    }

    Component.onCompleted: Compositor.refreshWindows()
}
