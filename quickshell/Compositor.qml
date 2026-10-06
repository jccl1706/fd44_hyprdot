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

    readonly property string focusedWorkspaceLabel: {
        for (const w of workspaceList) if (w.focused) return w.label
        return ""
    }

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

    // WORKSPACES, NORMALISED, for the row that draws them. The raw lists above
    // stay as they are because the old call sites read only .id off them; this
    // is what a compositor-neutral workspace row needs instead.
    //
    //   label    what to print. niri names are strings and are "1".."9" here by
    //            choice, so the bar reads the same on both; an unnamed niri
    //            workspace falls back to its idx, which is its position in that
    //            output's strip.
    //   output   the connector this workspace lives on. On niri every workspace
    //            carries it, which is why no pinning rules need reading - on
    //            Hyprland the same information comes off the monitor object.
    //   named    niri only, and the whole point of design B: a named workspace
    //            ALWAYS EXISTS, so the row can be a fixed set of chips rather
    //            than one that reflows as workspaces come and go.
    //   occupied whether anything is on it. ON NIRI THIS CANNOT BE INFERRED FROM
    //            EXISTENCE, which is the difference that matters: a named niri
    //            workspace exists whether or not it holds a window, while a
    //            Hyprland workspace is destroyed when its last window leaves - so
    //            on Hyprland "in the list" already means occupied.
    //   order    what to sort by. niri HANDS THESE OVER UNORDERED - measured as
    //            2,3,5,6,4,1,7,9,8 for workspaces declared 1 to 9 - so a row that
    //            draws them in list order draws them scrambled. idx is their
    //            position in that output's strip, which for named workspaces is
    //            the order they were declared in. Hyprland has no idx and its ids
    //            ARE the numbers, so the id serves.
    //
    // PLACEHOLDERS ARE SKIPPED on the Hyprland side. Its model briefly carries
    // entries with id -1 and an empty lastIpcObject - a workspace known by name
    // before it has been fetched - and anything drawing those gets a chip for a
    // workspace that does not exist yet. Measured in a live session: one of four
    // entries looked like that.
    readonly property var workspaceList: {
        if (onNiri) {
            return (Niri.workspaces || []).map(w => ({
                id: w.id,
                label: w.name ? String(w.name) : String(w.idx),
                output: w.output ? String(w.output) : "",
                focused: w.is_focused === true,
                named: !!w.name,
                occupied: (Niri.windows || []).some(win => win.workspace_id === w.id),
                order: w.idx
            }))
        }
        const out = []
        if (Hyprland.workspaces) {
            for (const w of Hyprland.workspaces.values) {
                if (!w || w.id < 0) continue
                out.push({
                    id: w.id,
                    label: String(w.name || w.id),
                    output: w.monitor ? String(w.monitor.name || "") : "",
                    focused: w.focused === true,
                    named: false,
                    occupied: true,
                    order: w.id
                })
            }
        }
        return out
    }

    // The named workspaces on one output, in strip order - the fixed row for
    // design B. Empty on Hyprland, which has no such concept and keeps using
    // WorkspacePins instead.
    function namedWorkspacesOn(outputName) {
        if (!onNiri) return []
        return workspaceList
            .filter(w => w.named && w.output === String(outputName))
            .sort((a, b) => a.order - b.order)
    }

    // --- what the bar asks for -----------------------------------------------

    // BY LABEL, NOT BY ID, because the two compositors number differently and the
    // bar thinks in the numbers it draws. Hyprland's ids ARE 1-9; niri's are
    // global and arbitrary, and its named workspaces are addressed by name -
    // which is why they are named "1".."9" in niri/workspaces.kdl.
    //
    // HYPRLAND 0.56 EVALUATES A DISPATCH AS LUA, so the string form
    // `dispatch("workspace 3")` is a syntax error - ")' expected near '3'" - and
    // it fails SILENTLY: the click does nothing and only quickshell's log knows.
    // The first version of this file had exactly that bug. The Lua form below is
    // the one hypr/binds.lua uses for the same job.
    function focusWorkspaceLabel(label) {
        if (onNiri) Niri.action(["focus-workspace", String(label)])
        else Hyprland.dispatch("hl.dsp.focus({ workspace = " + Number(label) + " })")
    }

    // delta > 0 is "the next one". Hyprland counts workspaces globally and niri
    // stacks them per output, so "next" means a different thing on each - which
    // is the compositor's model showing through, not something to paper over.
    function focusWorkspaceStep(delta) {
        if (onNiri) {
            if (delta > 0) Niri.focusWorkspaceDown()
            else Niri.focusWorkspaceUp()
        } else {
            Hyprland.dispatch(delta > 0
                ? 'hl.dsp.focus({ workspace = "e+1" })'
                : 'hl.dsp.focus({ workspace = "e-1" })')
        }
    }

    // A NO-OP ON NIRI, and that is the point of having it. Hyprland's toplevel
    // list is a cache that goes stale and has to be asked to refresh; niri's
    // event stream keeps its list current, so there is nothing to refresh. The
    // call sites keep calling it and stop caring which compositor they are on.
    function refreshWindows() {
        if (!onNiri) Hyprland.refreshToplevels()
    }
}
