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
        centerRight: ["theme", "caffeine", "updates", "backup", "units", "thermal"],
        right: ["tray", "notes", "clipboard", "notify", "claude", "bluetooth", "network", "audio", "battery", "couch", "power", "compositor"]
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
        claude: { label: "Claude usage",
                  help: "tokens Claude Code has spent, counted from its own transcripts in ~/.claude. Hidden, the same figures are in bin/claude-usage.py show" },
        caffeine: { label: "Caffeine",
                    help: "holds off the idle lock. Hidden, there is no other way to switch it on" },
        thermal:  { label: "Graphics temperature",
                    help: "the card's temperature while it is working, and a click opens a live view of everything the machine measures - fans, CPU, clocks" },
        units:    { label: "Failure warning",
                    help: "appears only when a systemd unit has failed - a backup gone stale, a scrub that found errors - and opens a terminal with the logs. Hidden, nothing says the machine is broken until someone runs systemctl --failed" },
        backup:   { label: "Backup reminder",
                    help: "appears only when the last backup is getting old, and opens a terminal that runs one. Hidden, nothing on screen says the machine has stopped backing up - bin/backup.sh status still answers from a terminal" },
        updates:  { label: "Updates",
                    help: "appears only when packages are waiting, and opens a terminal to install them. Hidden, nothing tells you the machine is behind - bin/updates.py status still answers from a terminal" },
        tray:     { label: "System tray",
                    help: "icons from applications that publish one - Steam, Discord, Nextcloud. Empty until such a program runs, and hidden it takes away the only way to reach their menus" },
        notes:    { label: "Notes",
                    help: "the scratch pad. Hidden, what you wrote is kept but cannot be opened" },
        clipboard:{ label: "Clipboard history",
                    help: "what you have copied, and the panel that pastes or saves it. The only plugin with a keybind of its own - Mod+Shift+C opens it either way" },
        notify:   { label: "Notifications",
                    help: "the history panel and the unread count. Toasts still appear either way" },
        network:  { label: "Network",
                    help: "signal strength, and the panel that joins a network. Hidden, there is no other way to change network" },
        bluetooth:{ label: "Bluetooth",
                    help: "whether anything is connected, and the panel that connects or disconnects a paired device - with its battery where the device reports one. Only ever drawn on a machine with an adapter. Hidden, bluetoothctl is the way, and pairing a NEW device is a terminal job either way" },
        audio:    { label: "Audio",
                    help: "the panel that picks an output device. The volume keys and the OSD work either way" },
        battery:  { label: "Battery",
                    help: "charge and time remaining. The low-battery warnings still arrive when hidden" },
        couch:    { label: "Couch mode",
                    help: "moves the session to the television" },
        compositor: { label: "Compositor mark",
                    help: "which compositor is drawing this session - niri's mark, or nothing where there is no vendored one. Decoration: it does nothing when clicked" },
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
        // NOT JUST `present`, WHICH IS FALSE BEFORE THE PROBE HAS RUN AS WELL
        // AS ON A MACHINE WITH NO BATTERY. Battery.present is dirs.length > 0,
        // and dirs is filled by a Process that globs /sys/class/power_supply -
        // so for the span between the shell starting and that returning, a
        // laptop looks exactly like a desktop and the icon is dropped from the
        // pill. The binding does recover when the probe lands (measured: absent
        // at 2s with the probe artificially slowed, back at 9s), which is why
        // this reads as a flicker at every restart rather than a missing plugin.
        //
        // Battery.qml already draws the distinction this needs and says so in
        // its own comment - "we have not looked yet" is not an answer - it just
        // was not asked here. Unknown keeps the slot; only a probe that has run
        // and found nothing takes it away.
        if (id === "battery") return !Battery.probed || Battery.present

        // THE SAME SHAPE, FOR THE SAME REASON. The thermal plugin is drawn only
        // where there is a discrete card to read - bin/thermal.sh answers
        // ok:false on this laptop and nothing appears - but `available` said yes
        // regardless, so the Bar page offered a toggle for a plugin that could
        // not be shown whichever way it was set. Its own help text admitted as
        // much, ending "it is absent on the laptop whether this is on or off":
        // a settings row describing its own uselessness instead of not being
        // there. That sentence is gone with this, since the row now appears
        // only where the toggle does something.
        //
        // `answered` AND NOT `present` ALONE, for the reason written above:
        // present is false before the probe has run as well as on a machine
        // with no card, so the row would be dropped at startup and appear a
        // moment later. Thermals already drew that distinction and was simply
        // never asked.
        if (id === "thermal") return !Thermals.answered || Thermals.present

        // Only niri has a vendored mark. On Hyprland the slot would draw
        // nothing, so it is not offered as a toggle either - the same rule as
        // the thermal plugin above.
        if (id === "compositor") return Compositor.backend === "niri"

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
