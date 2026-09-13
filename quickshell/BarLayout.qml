// =========================================================================
// BarLayout - where the movable plugins sit in the bar
// =========================================================================
//
// A singleton, like Theme.qml, so every bar on every monitor shows the same
// arrangement and a move on one moves them all.
//
// THE BAR HAS FOUR ZONES a plugin can live in:
//
//   [ logo workspaces |left| ]   [ |centerLeft| clock |centerRight| ]   [ |right| ]
//
// Fixed spots rather than free placement: an icon dropped at an arbitrary x
// could land on the clock or the workspaces, and a position that fits one
// monitor's width is wrong on another's.
//
// SAVED TO ~/.local/state/fd44-hyprdot/bar-layout.json, beside the active
// theme - per machine, not in the repo. What the repo holds is `defaults`.
// The file is read back through normalise(), so a hand-edited or stale file
// cannot lose a plugin or show one twice: unknown ids are dropped, duplicates
// keep their first position, and a plugin the file does not mention (a newly
// added one, say) appears where the defaults put it.
//
// Reset from a terminal:  qs ipc call bar resetLayout

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: layout

    readonly property var zones: ["left", "centerLeft", "centerRight", "right"]

    // Every movable plugin, and where it lives when nothing says otherwise.
    // A new plugin needs an entry here and a component in Bar.qml.
    readonly property var defaults: ({
        left: [],
        centerLeft: [],
        centerRight: ["theme"],
        right: ["network", "audio"]
    })

    // zone name -> ordered list of plugin ids. Always complete and valid.
    property var current: normalise(defaults)

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
              + "/fd44-hyprdot/bar-layout.json"
        watchChanges: true
        // No file is the normal state until the first move - not worth a
        // warning in the log on every start.
        printErrors: false
        onFileChanged: file.reload()
        onLoaded: layout.current = layout.normalise(layout.parse(file.text()))
        onLoadFailed: err => layout.current = layout.normalise(layout.defaults)
        onSaveFailed: err => console.warn("bar layout: could not save:", FileViewError.toString(err))
    }

    function parse(text: string): var {
        // An empty file is a write caught halfway (the watcher can fire
        // between truncate and write), not a broken one.
        if (text.trim() === "") return {}
        try {
            return JSON.parse(text)
        } catch (e) {
            console.warn("bar layout: ignoring unreadable", file.path, "-", e)
            return {}
        }
    }

    function normalise(raw): var {
        const known = layout.zones.reduce((all, z) => all.concat(layout.defaults[z]), [])
        const seen = {}
        const out = {}
        for (const z of layout.zones) {
            out[z] = []
            const list = (raw && Array.isArray(raw[z])) ? raw[z] : []
            for (const id of list) {
                if (known.includes(id) && !seen[id]) {
                    seen[id] = true
                    out[z].push(id)
                }
            }
        }
        for (const z of layout.zones) {
            for (const id of layout.defaults[z]) {
                if (!seen[id]) {
                    seen[id] = true
                    out[z].push(id)
                }
            }
        }
        return out
    }

    // Put `id` at `index` in `zone`. The index counts the zone's other
    // plugins, i.e. the list as it is with `id` already taken out.
    function move(id: string, zone: string, index: int): void {
        if (!layout.zones.includes(zone)) return
        const out = {}
        for (const z of layout.zones)
            out[z] = layout.current[z].filter(i => i !== id)
        out[zone].splice(Math.max(0, Math.min(index, out[zone].length)), 0, id)
        layout.current = out
        layout.save()
    }

    function reset(): void {
        layout.current = layout.normalise(layout.defaults)
        layout.save()
    }

    function save(): void {
        file.setText(JSON.stringify(layout.current, null, 2) + "\n")
    }
}
