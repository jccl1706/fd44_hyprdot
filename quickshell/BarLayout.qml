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
// added one, say) appears BESIDE THE PLUGIN IT FOLLOWS IN THE DEFAULTS,
// wherever that one has been dragged to - so the coffee cup lands next to the
// theme toggle on a machine where the toggle was moved - or, with nothing to
// follow, where the defaults put it.
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
    //
    // THE ORDER HERE IS ALSO THE ORDER A NEW PLUGIN ARRIVES IN - normalise()
    // places one the saved file has never heard of immediately after the
    // plugin it follows in this list, so adding to the end of a zone is how
    // an existing machine gains an icon without its arrangement being reset.
    //
    // couch and power sit at the right-hand end, in that order, so the power
    // symbol is the last thing in the bar. That is where a power control is
    // looked for, and it keeps the two-click buttons as far as possible from
    // the panels next to them - a slip off the audio glyph lands on empty
    // frame rather than on something that ends the session.
    readonly property var defaults: ({
        left: [],
        centerLeft: [],
        centerRight: ["theme", "caffeine"],
        right: ["notify", "network", "audio", "battery", "couch", "power"]
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
            const defs = layout.defaults[z]
            for (let i = 0; i < defs.length; i++) {
                const id = defs[i]
                if (seen[id]) continue
                seen[id] = true
                // Right after the plugin it follows in the defaults, if that
                // one is placed; otherwise at the end of its default zone.
                const prev = i > 0 ? defs[i - 1] : ""
                const home = prev ? layout.zones.find(zz => out[zz].includes(prev)) : undefined
                if (home !== undefined)
                    out[home].splice(out[home].indexOf(prev) + 1, 0, id)
                else
                    out[z].push(id)
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
