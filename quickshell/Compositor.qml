// =========================================================================
// Compositor - the one place the bar asks what the compositor is doing
// =========================================================================
//
// A facade over Quickshell.Hyprland and Niri.qml, so this bar runs on either
// without a fork. Same shape as fd44.desktop on the NixOS machine: one switch,
// both supported, nothing duplicated.
//
// WHY A FACADE AND NOT A PORT. Nine of the bar's QML files touched Hyprland
// directly, and between them they used nine APIs - focusedMonitor, monitorFor,
// workspaces, focusedWorkspace, toplevels, activeToplevel, refreshToplevels,
// dispatch, and the HyprlandMonitor type. That is a small enough surface to put
// behind one object, and keeping it behind one object is what stops a second
// compositor doubling the bar.
//
// IT EXPOSES INTENTIONS, NOT COMMANDS. The old call sites wrote
// `Hyprland.dispatch("workspace e+1")`, which cannot be translated by a facade
// because niri's vocabulary is different words with different arguments. So the
// methods here are named for what the bar WANTS - focusWorkspaceStep(1) - and
// each backend says it its own way.
//
// NAMES, NOT OBJECTS, for monitors. A ShellScreen and a HyprlandMonitor
// describe the same output and are different objects; niri has neither type and
// identifies outputs by name. Every comparison in the bar was already
// screen.name against monitor.name, so the facade hands over the name and the
// types stop mattering.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    // niri wins when both could answer, because NIRI_SOCKET is only set by a
    // running niri while HYPRLAND_INSTANCE_SIGNATURE can linger in an inherited
    // environment.
    readonly property bool onNiri: Niri.available
    readonly property string backend: onNiri ? "niri" : "hyprland"

    // --- what the bar reads --------------------------------------------------

    // The output the focused window is on, by name. Empty until the compositor
    // has said anything, which it has not at startup - every call site already
    // guards for that, because Hyprland.focusedMonitor starts null too.
    readonly property string focusedMonitorName: onNiri
        ? Niri.focusedOutputName
        : (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")

    // Workspaces as plain objects carrying at least { id }. The bar reads only
    // .id off these, so the two backends' extra fields are harmless.
    readonly property var workspaces: onNiri
        ? Niri.workspaces
        : (Hyprland.workspaces ? Hyprland.workspaces.values : [])

    readonly property int focusedWorkspaceId: {
        if (onNiri) return Niri.focusedWorkspace ? Niri.focusedWorkspace.id : -1
        return Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    }

    // THE FOCUSED WINDOW, NORMALISED, because the two sides disagree about
    // nearly everything here. Hyprland has no "is focused" flag and marks the
    // focused client with focusHistoryID === 0; niri has is_focused and no
    // history. Hyprland calls it `class`, niri calls it `app_id`. What the bar
    // wants in both cases is the app id, the title, and which workspace it is
    // on - so that is what comes out.
    //
    // initialAppId IS CARRIED FOR HYPRLAND ONLY and is empty on niri. It is
    // Hyprland's initialClass, which FocusedApp falls back to for a client that
    // renamed itself after mapping; niri reports one app_id and never a first
    // one, so there is nothing to fall back to rather than something missing.
    //
    // THE WORKSPACE IS REPORTED, NOT FILTERED ON. Hyprland's focus history can
    // point at a window on another workspace, so a caller that means "what is
    // focused HERE" has to compare workspaceId itself - FocusedApp does, and the
    // comment there explains what goes wrong otherwise.
    readonly property var focusedWindow: {
        if (onNiri) {
            const w = Niri.focusedWindow
            if (!w) return null
            return {
                appId: w.app_id || "",
                initialAppId: "",
                title: w.title || "",
                workspaceId: w.workspace_id
            }
        }
        if (!Hyprland.toplevels) return null
        for (const t of Hyprland.toplevels.values) {
            const o = t.lastIpcObject
            if (o && o.focusHistoryID === 0 && o.workspace)
                return {
                    appId: o.class || "",
                    initialAppId: o.initialClass || "",
                    title: o.title || "",
                    workspaceId: o.workspace.id
                }
        }
        return null
    }

    // --- what the bar asks for -----------------------------------------------

    function focusWorkspaceId(id) {
        if (onNiri) Niri.focusWorkspaceId(id)
        else Hyprland.dispatch("workspace " + id)
    }

    // delta > 0 is "the next one". Hyprland counts workspaces globally and niri
    // stacks them per output, so "next" means a different thing on each - which
    // is the compositor's model showing through, not something to paper over.
    function focusWorkspaceStep(delta) {
        if (onNiri) {
            if (delta > 0) Niri.focusWorkspaceDown()
            else Niri.focusWorkspaceUp()
        } else {
            Hyprland.dispatch(delta > 0 ? "workspace e+1" : "workspace e-1")
        }
    }

    function quitCompositor() {
        if (onNiri) Niri.quitCompositor()
        else Hyprland.dispatch("exit")
    }

    function powerOffMonitors() {
        if (onNiri) Niri.powerOffMonitors()
        else Hyprland.dispatch("dpms off")
    }

    // A NO-OP ON NIRI, and that is the point of having it. Hyprland's toplevel
    // list is a cache that goes stale and has to be asked to refresh; niri's
    // event stream keeps its list current, so there is nothing to refresh. The
    // call sites keep calling it and stop caring which compositor they are on.
    function refreshWindows() {
        if (!onNiri) Hyprland.refreshToplevels()
    }
}
