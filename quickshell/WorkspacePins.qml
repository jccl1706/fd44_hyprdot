pragma Singleton

// =========================================================================
// WorkspacePins - which workspaces belong to which screen
// =========================================================================
//
// hypr/rules.lua pins workspaces to monitors: 1-5 to the external display,
// 6-9 to the laptop panel. Without knowing that, both bars drew the same
// five chips - so the laptop showed 1-5, which live on the other screen,
// and never showed its own.
//
// IT ASKS HYPRLAND RATHER THAN REPEATING THE RULES HERE. `hyprctl
// workspacerules -j` returns the pinning the compositor actually loaded, so
// this cannot drift out of step with rules.lua the way a second copy of the
// numbers would. Change the split there and the bar follows on reload
// without anything here being touched.
//
// TWO CALLS, AT STARTUP, NOT PER FRAME. Both are one-shot reads whose
// results are cached in `byScreen`; the bar binds to that. They run again
// only when the compositor says something changed - a config reload, or a
// monitor appearing or disappearing.
//
// The JSON is parsed in JavaScript rather than piped through jq or python:
// QML has JSON.parse, and neither of those is guaranteed to be installed on
// a machine this config is meant to work on.

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

Singleton {
    id: pins

    // Screen name -> the workspace ids pinned to it, ascending.
    // Reassigned wholesale rather than mutated, so bindings that read it
    // through idsFor() re-evaluate.
    property var byScreen: ({})

    // Monitor name -> its EDID description, needed to resolve the `desc:`
    // form a rule may use.
    property var descriptions: ({})

    // Connected monitors in the order Hyprland lists them, so "the first
    // connected screen" means something stable rather than whatever order a
    // JavaScript object happens to iterate in.
    property var monitorOrder: []
    property var rules: []
    property bool haveMonitors: false
    property bool haveRules: false

    // The workspaces for a screen, or an empty list when nothing is pinned
    // to it - which is the normal case on a single-monitor machine, where
    // none of the rules name a connected output.
    function idsFor(screenName) {
        const list = pins.byScreen[screenName]
        return list ? list : []
    }

    function refresh(): void {
        pins.haveMonitors = false
        pins.haveRules = false
        monitorsProc.running = true
        rulesProc.running = true
    }

    // A rule names its monitor either by connector - "eDP-1" - or as "desc:"
    // followed by a PREFIX of the description, the same two forms
    // hypr/monitors.lua uses. Prefix, because Hyprland appends a serial
    // number that the rule does not have to spell out.
    function screenFor(spec) {
        if (spec.indexOf("desc:") === 0) {
            const want = spec.substring(5)
            for (const name in pins.descriptions) {
                if (pins.descriptions[name].indexOf(want) === 0) return name
            }
            return ""
        }
        // A connector name only counts if that output is actually present;
        // otherwise a rule for a monitor on the other machine would claim
        // workspaces here.
        return pins.descriptions.hasOwnProperty(spec) ? spec : ""
    }

    function recompute(): void {
        if (!pins.haveMonitors || !pins.haveRules) return

        const out = {}
        const orphans = []          // pinned to a monitor that is not here
        for (let i = 0; i < pins.rules.length; i++) {
            const r = pins.rules[i]
            if (!r || !r.monitor || r.enabled === false) continue

            // Numeric workspaces only. `special:btop` and the named
            // selectors like `w[tv1]` are rules too, and none of them is a
            // chip in the bar.
            const id = parseInt(r.workspaceString, 10)
            if (!(id > 0) || String(id) !== String(r.workspaceString)) continue

            const screen = pins.screenFor(r.monitor)
            if (!screen) {
                orphans.push(id)
                continue
            }
            if (!out[screen]) out[screen] = []
            if (out[screen].indexOf(id) < 0) out[screen].push(id)
        }

        // WORKSPACES PINNED TO A MONITOR THAT IS NOT CONNECTED STILL HAVE TO
        // APPEAR SOMEWHERE, and that was a real bug rather than a nicety.
        //
        // Unplug the external and Hyprland migrates its workspaces to a
        // remaining monitor - the windows are still there, on 1 to 5, on the
        // laptop. But the rules pinning 1-5 to the external stop resolving,
        // so those numbers were dropped from every screen's list and the
        // laptop's bar drew only 6 to 9. The workspace you were actually
        // standing on was not on the bar at all.
        //
        // The 1-5 fallback in Workspaces.qml did not save it either: the
        // laptop's list was [6,7,8,9], which is not empty, so the fallback
        // never fired. That fallback is for a machine no rule mentions - the
        // desktop - and this is a different case.
        //
        // They go to the first connected monitor, which is exactly right
        // when only one is left, and an arbitrary but harmless choice when
        // several are. Hyprland makes the same kind of choice when it
        // migrates them.
        if (orphans.length > 0 && pins.monitorOrder.length > 0) {
            const host = pins.monitorOrder[0]
            if (!out[host]) out[host] = []
            for (let i = 0; i < orphans.length; i++) {
                if (out[host].indexOf(orphans[i]) < 0) out[host].push(orphans[i])
            }
        }

        for (const k in out) out[k].sort((a, b) => a - b)
        pins.byScreen = out
    }

    Process {
        id: monitorsProc
        running: true
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {}
                const order = []
                try {
                    const arr = JSON.parse(text)
                    for (let i = 0; i < arr.length; i++) {
                        map[arr[i].name] = arr[i].description || ""
                        order.push(arr[i].name)
                    }
                } catch (e) {
                    console.warn("WorkspacePins: monitors -j did not parse:", e)
                }
                pins.descriptions = map
                pins.monitorOrder = order
                pins.haveMonitors = true
                pins.recompute()
            }
        }
    }

    Process {
        id: rulesProc
        running: true
        command: ["hyprctl", "workspacerules", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let arr = []
                try {
                    arr = JSON.parse(text)
                } catch (e) {
                    console.warn("WorkspacePins: workspacerules -j did not parse:", e)
                }
                pins.rules = arr
                pins.haveRules = true
                pins.recompute()
            }
        }
    }

    // Re-read when the compositor's own view changes. `hyprctl reload` emits
    // configreloaded, and plugging a display in emits monitoradded - both
    // change the answer, and neither is something to poll for.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const n = String(event.name)
            if (n === "configreloaded" || n === "monitoradded"
                || n === "monitoraddedv2" || n === "monitorremoved") {
                pins.refresh()
            }
        }
    }
}
