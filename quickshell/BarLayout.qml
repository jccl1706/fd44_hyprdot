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
// A plugin can also be switched OFF entirely, which is separate from where it
// sits: `hidden` below. A hidden plugin keeps its place in the arrangement and
// simply is not drawn, so switching it back on returns it to where it was
// rather than to the end of a zone.
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
        right: ["notes", "notify", "network", "audio", "battery", "couch", "power"]
    })

    // THE HUMAN NAME AND THE COST OF HIDING, per plugin. Here rather than in
    // Settings.qml so that adding a plugin is still ONE entry in this file:
    // what a plugin is belongs beside where it goes.
    //
    // The help text says what is lost, because for most of these the bar is
    // the only door. None of them has a keybind.
    readonly property var meta: ({
        theme:    { label: "Theme toggle",
                    help: "one click between dark and cream. Hidden, the theme is still on the Appearance page and in bin/theme.sh" },
        caffeine: { label: "Caffeine",
                    help: "holds off the idle lock. Hidden, there is no other way to switch it on" },
        notes:    { label: "Notes",
                    help: "the scratch pad. Hidden, what you wrote is kept but cannot be opened" },
        notify:   { label: "Notifications",
                    help: "the history panel and the unread count. Toasts still appear either way" },
        network:  { label: "Network",
                    help: "signal strength, and the panel that joins a network. Hidden, there is no other way to change network" },
        audio:    { label: "Audio",
                    help: "the panel that picks an output device. The volume keys and the OSD work either way" },
        battery:  { label: "Battery",
                    help: "charge and time remaining. The low-battery warnings still arrive when hidden" },
        couch:    { label: "Couch mode",
                    help: "moves the session to the television" },
        power:    { label: "Power",
                    help: "log out, reboot and shut down, each behind a second click" }
    })

    // zone name -> ordered list of plugin ids. Always complete and valid.
    property var current: normalise(defaults)

    // Plugins switched off, as an id array. Saved beside the arrangement and
    // for the same reason: it is a per-machine preference, and the laptop and
    // the desktop share one checkout but should be free to show different bars.
    property var hidden: []

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
              + "/fd44-hyprdot/bar-layout.json"
        watchChanges: true
        // No file is the normal state until the first move - not worth a
        // warning in the log on every start.
        printErrors: false
        onFileChanged: file.reload()
        onLoaded: {
            const raw = layout.parse(file.text())
            layout.current = layout.normalise(raw)
            layout.hidden = layout.normaliseHidden(raw)
        }
        onLoadFailed: err => {
            layout.current = layout.normalise(layout.defaults)
            layout.hidden = []
        }
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

    // Unknown ids dropped and duplicates collapsed, exactly as normalise()
    // does for the zones: a stale file naming a plugin that no longer exists
    // must not be able to hide one that does.
    function normaliseHidden(raw): var {
        const known = layout.zones.reduce((all, z) => all.concat(layout.defaults[z]), [])
        const list = (raw && Array.isArray(raw.hidden)) ? raw.hidden : []
        const out = []
        for (const id of list)
            if (known.includes(id) && !out.includes(id)) out.push(id)
        return out
    }

    // Whether this MACHINE can draw `id` at all - as opposed to whether the
    // user wants it, which is enabled(). Moved here from Bar.qml so the
    // settings panel can ask the same question without a second copy of the
    // test: a switch for hardware that is not present is worse than no switch.
    function available(id: string): bool {
        if (id === "couch")   return Couch.available
        // No battery on the desktop, so the plugin simply is not there.
        if (id === "battery") return Battery.present
        return true
    }

    function enabled(id: string): bool { return !layout.hidden.includes(id) }

    function setEnabled(id: string, on: bool): void {
        if (layout.enabled(id) === on) return
        layout.hidden = on ? layout.hidden.filter(i => i !== id)
                           : layout.hidden.concat([id])
        layout.save()
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

    // Back to the repository's arrangement AND everything visible again:
    // "reset" that left a plugin switched off would be a puzzle, since the
    // thing you reset to get back is the thing still missing.
    function reset(): void {
        layout.current = layout.normalise(layout.defaults)
        layout.hidden = []
        layout.save()
    }

    function save(): void {
        const out = {}
        for (const z of layout.zones) out[z] = layout.current[z]
        out.hidden = layout.hidden
        file.setText(JSON.stringify(out, null, 2) + "\n")
    }
}
