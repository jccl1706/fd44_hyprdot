// =========================================================================
// Niri - the compositor state this bar needs, from niri's IPC
// =========================================================================
//
// The niri half of Compositor.qml. Nothing here is used directly by the bar:
// ask Compositor, which picks this or Quickshell.Hyprland at runtime.
//
// WHY THIS FILE EXISTS AT ALL. quickshell ships Quickshell.Hyprland and has no
// niri equivalent - checked against the installed binary, which contains 37
// references to Hyprland and none to niri. So the state the bar reads from
// Hyprland (workspaces, the focused output, the focused window) has to be
// assembled here from niri's own IPC.
//
// ONE LONG-LIVED EVENT STREAM, NOT POLLING. `niri msg --json event-stream`
// writes one JSON object per line for the life of the compositor and is the
// supported way to follow its state; polling `niri msg` on a timer would both
// lag and burn a process per tick. The stream opens with a full snapshot -
// WorkspacesChanged and WindowsChanged carry complete lists - so there is no
// separate "fetch the initial state" step.
//
// THE TWELVE EVENTS, measured by driving a nested niri 26.04 and recording what
// came out: WorkspacesChanged, WorkspaceActivated, WorkspaceActiveWindowChanged,
// WorkspaceUrgencyChanged, WindowsChanged, WindowOpenedOrChanged, WindowClosed,
// WindowFocusChanged, WindowFocusTimestampChanged, WindowLayoutsChanged,
// KeyboardLayoutsChanged, KeyboardLayoutSwitched, OverviewOpenedOrClosed,
// ConfigLoaded, CastsChanged. Only the first eight matter to this bar; the rest
// are accepted and ignored rather than logged, because an unknown event is
// niri being newer than this file, not a fault.
//
// OUTPUTS ARE FETCHED, NOT WATCHED, and that is a real gap rather than a
// choice: there is no OutputsChanged event in the stream. Monitors are read
// once at startup and again on ConfigLoaded, which is what fires when a display
// is reconfigured through the config. A monitor hotplugged with no config change
// will not be noticed until something calls refreshOutputs().
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // NIRI_SOCKET is set by niri in every client's environment, so its presence
    // is the test for "this bar is running under niri" - no process list, no
    // version probe.
    readonly property bool available: (Quickshell.env("NIRI_SOCKET") || "") !== ""

    // Raw niri shapes, kept as niri hands them over. Translation into something
    // compositor-neutral happens in Compositor.qml, so this file stays a mirror
    // of the IPC and is easy to check against `niri msg --json`.
    property var workspaces: []          // [{id, idx, name, output, is_active, is_focused, active_window_id}]
    property var windows: []             // [{id, title, app_id, pid, workspace_id, is_focused, ...}]
    property var outputs: ({})           // {name: {name, make, model, logical:{x,y,width,height,scale}}}

    readonly property var focusedWorkspace: {
        for (const w of workspaces) if (w.is_focused) return w
        return null
    }

    readonly property var focusedWindow: {
        for (const w of windows) if (w.is_focused) return w
        return null
    }

    // The output name of the focused workspace. niri has no "focused output"
    // event, but a workspace belongs to exactly one output and the focused
    // workspace moves with the focus, so this follows it for free.
    readonly property string focusedOutputName: focusedWorkspace ? (focusedWorkspace.output || "") : ""

    // --- actions -------------------------------------------------------------
    //
    // `niri msg action ...` rather than writing to the socket directly: the
    // action vocabulary is large and changes between releases, and niri's own
    // client is the thing that tracks it.
    function action(args) {
        if (!available) return
        actor.command = ["niri", "msg", "action"].concat(args)
        actor.running = true
    }

    function focusWorkspaceId(id) { action(["focus-workspace", String(id)]) }
    function focusWorkspaceDown() { action(["focus-workspace-down"]) }
    function focusWorkspaceUp()   { action(["focus-workspace-up"]) }
    function quitCompositor()     { action(["quit", "--skip-confirmation"]) }
    function powerOffMonitors()   { action(["power-off-monitors"]) }

    function refreshOutputs() {
        if (!available) return
        outputReader.running = true
    }

    Process {
        id: actor
        // Deliberately no stdout handling: an action either works or niri
        // prints to stderr, and a bar that pops up errors for a failed
        // workspace switch would be worse than one that does not.
    }

    Process {
        id: outputReader
        command: ["niri", "msg", "--json", "outputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    // A MAP KEYED BY OUTPUT NAME, not a list - unlike
                    // workspaces and windows. Kept in that shape because every
                    // lookup here is by name.
                    root.outputs = JSON.parse((text || "{}").trim() || "{}")
                } catch (e) {
                    root.outputs = ({})
                }
            }
        }
    }

    // --- the event stream ----------------------------------------------------
    Process {
        id: stream
        running: root.available
        command: ["niri", "msg", "--json", "event-stream"]

        // RESTARTED IF IT DIES, because this is the only source of state: a
        // stream that ends silently would leave the bar frozen on whatever it
        // last saw, which looks like the bar being broken rather than the
        // stream being gone. niri exiting takes quickshell with it anyway, so
        // in practice this covers a crashed `niri msg`, not a logout.
        onExited: if (root.available) restart.start()

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => root.handleEvent(line)
        }
    }

    Timer {
        id: restart
        interval: 1000
        onTriggered: stream.running = true
    }

    Component.onCompleted: if (available) refreshOutputs()

    // --- event handling ------------------------------------------------------
    //
    // Lists are REPLACED WHOLE where niri sends a whole list, and patched where
    // it sends one item. Patching means rebuilding the array rather than
    // mutating it in place: QML only re-evaluates bindings on a property
    // ASSIGNMENT, so mutating workspaces[i] would update the data and leave
    // every binding that reads it showing the old value.
    function handleEvent(line) {
        const text = (line || "").trim()
        if (!text) return

        let ev
        try { ev = JSON.parse(text) } catch (e) { return }

        if (ev.WorkspacesChanged) {
            workspaces = ev.WorkspacesChanged.workspaces || []

        } else if (ev.WorkspaceActivated) {
            const id = ev.WorkspaceActivated.id
            const focused = ev.WorkspaceActivated.focused === true
            // Activating a workspace deactivates the others ON ITS OUTPUT only -
            // every output has its own active workspace. The focused flag is
            // global, so that one clears everywhere.
            const target = workspaces.find(w => w.id === id)
            const out = target ? target.output : null
            workspaces = workspaces.map(w => {
                const next = Object.assign({}, w)
                if (w.output === out) next.is_active = (w.id === id)
                if (focused) next.is_focused = (w.id === id)
                return next
            })

        } else if (ev.WorkspaceActiveWindowChanged) {
            const d = ev.WorkspaceActiveWindowChanged
            workspaces = workspaces.map(w => w.id === d.workspace_id
                ? Object.assign({}, w, { active_window_id: d.active_window_id })
                : w)

        } else if (ev.WorkspaceUrgencyChanged) {
            const d = ev.WorkspaceUrgencyChanged
            workspaces = workspaces.map(w => w.id === d.id
                ? Object.assign({}, w, { is_urgent: d.urgent === true })
                : w)

        } else if (ev.WindowsChanged) {
            windows = ev.WindowsChanged.windows || []

        } else if (ev.WindowOpenedOrChanged) {
            const win = ev.WindowOpenedOrChanged.window
            if (!win) return
            const rest = windows.filter(w => w.id !== win.id)
            // A window arriving focused means nothing else is: niri sends no
            // separate WindowFocusChanged for the window it just opened.
            windows = (win.is_focused
                ? rest.map(w => w.is_focused ? Object.assign({}, w, { is_focused: false }) : w)
                : rest).concat([win])

        } else if (ev.WindowClosed) {
            const id = ev.WindowClosed.id
            windows = windows.filter(w => w.id !== id)

        } else if (ev.WindowFocusChanged) {
            // id is null when focus leaves every window - clicking the
            // background, or the last window on a workspace closing.
            const id = ev.WindowFocusChanged.id
            windows = windows.map(w => Object.assign({}, w, { is_focused: w.id === id }))

        } else if (ev.ConfigLoaded) {
            // The only hint niri gives that outputs may have moved.
            refreshOutputs()
        }
        // Everything else - WindowLayoutsChanged, WindowFocusTimestampChanged,
        // KeyboardLayout*, OverviewOpenedOrClosed, CastsChanged - is ignored on
        // purpose. See the header.
    }
}
