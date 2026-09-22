// =========================================================================
// Settings - the values a person might want to change, in one place
// =========================================================================
//
// A singleton store plus the schema that describes it. SettingsPanel renders
// the schema; nothing else needs to know the panel exists.
//
// WHY A SCHEMA rather than a hand-built form per setting. There are forty-odd
// modules here and a form per setting rots the moment one is added: the value,
// its default, its label and its bounds end up in four places that drift. A
// descriptor keeps them in one, and adding a setting is one entry here plus one
// property above it.
//
// WHAT IS DELIBERATELY NOT HERE:
//
//   theme                bin/theme.sh owns it; the row here runs the script.
//   wallpaper            the grid on Appearance sets it directly. The
//                        full-screen picker on SUPER+, is the other view of
//                        the same set - both go through WallpaperLibrary.
//   do not disturb       already a toggle in NotificationPanel, already saved.
//   bar arrangement      already drag-and-drop between the bar's four zones.
//                        WHICH plugins are shown does live here - that had no
//                        control at all - but WHERE they go stays a drag.
//   anything in Theme    those 44 properties are derived from the palette
//                        rather than set - they belong to the theme file.
//
// So the list is short today, and that is the honest state of it: most of what
// could be configured already can be. The value is having somewhere for the
// next one to go, and a store that persists it.
//
// DEFAULTS ARE WHAT THE SHELL DID BEFORE THIS EXISTED. Every number below was
// read out of the module it replaces, so a fresh machine with no settings file
// behaves exactly as it did.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: settings

    // --- the values ------------------------------------------------------

    // Notifications. Critical is always sticky and is not settable: a
    // notification that says the disk is full should not vanish on a timer.
    property int  notifyLowMs:    5000
    property int  notifyNormalMs: 8000
    property int  notifyMaxMs:   30000

    // How long the volume/brightness OSD stays after the last keypress.
    property int  osdHideMs: 1500

    // Launcher ranking: how quickly a launch stops counting. See
    // LauncherFrecency for what the number means.
    property real frecencyHalfLifeDays: 10

    // THE THEME IS NOT STORED HERE, and neither are the bar's plugin
    // switches. bin/theme.sh owns the theme and BarLayout owns the bar; their
    // schema rows below carry `get`/`set` and reach the real owner directly,
    // so there is no copy here to drift out of step. Two sources of truth for
    // the theme is how the bar ends up disagreeing with kitty.

    // --- the schema ------------------------------------------------------
    //
    // SECTIONS become the sidebar; ROWS become the controls in the pane. The
    // panel knows nothing about any particular setting - it renders this.
    //
    // Control types:
    //   "ms"      integer milliseconds, shown and edited in seconds
    //   "days"    real days
    //   "toggle"  boolean
    //   "select"  one of `options`, each { value, label }
    //   "action"  a button; `run` is called on click
    //   "wallpapers"  the thumbnail grid; owns its own value, see `wide` in
    //                 SettingsRow - it is drawn under the label, full width
    //
    // WHERE A VALUE LIVES is the row's business. Most sit in this store and are
    // addressed by `key`. A few belong to a singleton that already owns them -
    // the theme, the bar's plugin switches - and those carry `get` and `set`
    // instead of a key. The panel renders both the same way.
    //
    // `when` is an optional predicate. A row or section that does not apply to
    // this machine is not drawn at all - the same rule the bar follows for the
    // couch button and the launcher for its Games tab. A control for hardware
    // that is not here is worse than no control.
    //
    // `help` is shown under the label rather than in a tooltip: a setting whose
    // effect you have to hover to learn is a setting you will not touch.
    readonly property var schema: [
        {
            section: "Appearance",
            icon: "\u{F03D8}",                       // palette
            rows: [
                { label: "Theme", type: "select",
                  help: "runs bin/theme.sh, which restyles the bar, kitty, GTK and Chromium together",
                  get: function() { return Theme.name },
                  set: function(v) { Settings.applyTheme(v) },
                  options: [ { value: "dark", label: "Dark" },
                             { value: "cream", label: "Cream" } ] },
                { label: "Wallpaper", type: "wallpapers",
                  help: "click one to set it; the ring marks the one in use. SUPER+, opens the full-screen picker, which shows them one at a time and larger" }
            ]
        },
        {
            section: "Display",
            icon: "\u{F0379}",                       // monitor
            // Nothing to show on a machine hyprctl has not answered for yet,
            // and nothing to choose on a panel that will not say how big it
            // is - the same rule the rest of this schema follows: a control
            // for hardware that is not here is worse than no control.
            when: function() { return settings.displayRows.length > 0 },
            rows: settings.displayRows
        },
        {
            section: "Notifications",
            icon: "\u{F009A}",                       // bell
            rows: [
                { key: "notifyNormalMs", label: "Normal notification",
                  type: "ms", min: 2000, max: 30000, step: 1000,
                  help: "how long an ordinary notification stays" },
                { key: "notifyLowMs", label: "Low priority",
                  type: "ms", min: 1000, max: 30000, step: 1000,
                  help: "battery notices, volume changes and the like" },
                { key: "notifyMaxMs", label: "Maximum",
                  type: "ms", min: 5000, max: 120000, step: 5000,
                  help: "the longest a sender may ask for. Critical ignores this and stays until dismissed" }
            ]
        },
        {
            section: "Launcher",
            icon: "\u{F0349}",                       // magnify
            rows: [
                { key: "frecencyHalfLifeDays", label: "Ranking half-life",
                  type: "days", min: 1, max: 60, step: 1,
                  help: "how quickly a launch stops counting. Lower follows this week, higher remembers longer" },
                { label: "Clear launch history", type: "action",
                  help: "the launcher goes back to alphabetical",
                  run: function() { LauncherFrecency.clear() } }
            ]
        },
        {
            section: "Desktop",
            icon: "\u{F0493}",                       // cog
            rows: [
                { key: "osdHideMs", label: "OSD hide delay",
                  type: "ms", min: 500, max: 5000, step: 250,
                  help: "the volume and brightness popup" }
            ]
        },
        {
            section: "Bar",
            icon: "\u{F0309}",                       // dock-top
            rows: settings.barRows
        }
    ]

    // One scale row per attached screen.
    //
    // NAMED PRESETS AND NOT A NUMBER, which is the idea worth taking from
    // omarchy-monitor-settings: nobody knows what 1.5666667 means, everybody
    // knows whether the text is too small. Monitors.qml computes them from
    // the panel's real pixel density - Hyprland reports its physical size in
    // millimetres - so "Standard" reproduces what hypr/monitors.lua measured
    // by hand for the two panels it knows, and works out the same answer for
    // a panel nobody has measured.
    //
    // The label under each row names the screen, because on a docked machine
    // "Scale" three times over says nothing about which is which.
    readonly property var displayRows: {
        const out = []
        for (const monitor of Monitors.list) {
            if (!monitor.options.length) continue
            out.push({
                label: monitor.title,
                type: "select",
                help: monitor.description + ", " + monitor.width + "x" + monitor.height + " on a "
                      + monitor.inches.toFixed(1) + "\" panel, "
                      + Math.round(monitor.ppi) + " ppi. Now "
                      + (Monitors.currentDetail(monitor) || "a scale with no preset")
                      + ". Applies at once, and is remembered in "
                      + "hypr/monitors_local.lua, which monitors.lua reads last",
                options: monitor.options,
                get: function() { return Monitors.currentOption(monitor) },
                set: function(v) { Monitors.setScale(monitor, v) }
            })
        }
        return out
    }

    // One switch per bar plugin, then the reset.
    //
    // IN THE ORDER THEY SIT IN THE BAR, left to right, read from the live
    // arrangement rather than the defaults so the list matches what you are
    // looking at on a machine where things have been dragged about. The panel
    // covers the screen and holds the keyboard, so the bar cannot be
    // rearranged underneath it and this cannot reorder while it is open.
    //
    // A plugin this machine cannot draw at all is left out by `when` - there
    // is no couch button to switch off on a machine with no television.
    readonly property var barRows: {
        const out = []
        for (const z of BarLayout.zones)
            for (const id of BarLayout.current[z]) {
                const m = BarLayout.meta[id]
                if (!m) continue
                out.push({
                    label: m.label, help: m.help, type: "toggle",
                    when: function() { return BarLayout.available(id) },
                    get:  function() { return BarLayout.enabled(id) },
                    set:  function(v) { BarLayout.setEnabled(id, v) }
                })
            }
        out.push({ label: "Reset layout", type: "action",
                   help: "every plugin back where the repository's defaults have it, and every one of them shown again. Drag to rearrange them in the bar itself",
                   run: function() { BarLayout.reset() } })
        return out
    }

    // --- persistence -----------------------------------------------------

    property bool dirty: false

    // Runs bin/theme.sh and lets Theme.qml pick the change up from the state
    // file, so the bar, kitty, GTK and Chromium all move together. Nothing is
    // stored here - the script's state file is the only record.
    function applyTheme(v: string): void {
        if (v === Theme.name) return
        themeProc.command = ["sh", "-c",
            "\"$(dirname \"$(readlink -f '" + Quickshell.shellDir + "')\")/bin/theme.sh\" set " + v]
        themeProc.running = true
    }

    function setValue(key: string, v): void {
        if (settings[key] === undefined) {
            console.warn("Settings: no such key", key)
            return
        }
        if (settings[key] === v) return
        settings[key] = v
        settings.dirty = true
        saveTimer.restart()
    }

    // Back to the defaults above, which are the shell's original behaviour.
    function resetAll(): void {
        settings.notifyLowMs = 5000
        settings.notifyNormalMs = 8000
        settings.notifyMaxMs = 30000
        settings.osdHideMs = 1500
        settings.frecencyHalfLifeDays = 10
        settings.dirty = true
        saveTimer.restart()
    }

    Process {
        id: themeProc
        onExited: (code, status) => {
            if (code !== 0) console.warn("Settings: theme.sh failed with", code)
        }
    }

    Timer {
        id: saveTimer
        interval: 500
        onTriggered: {
            if (!settings.dirty) return
            file.setText(JSON.stringify({
                notifyLowMs: settings.notifyLowMs,
                notifyNormalMs: settings.notifyNormalMs,
                notifyMaxMs: settings.notifyMaxMs,
                osdHideMs: settings.osdHideMs,
                frecencyHalfLifeDays: settings.frecencyHalfLifeDays
            }, null, 1))
            settings.dirty = false
        }
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
              + "/fd44-hyprdot/settings.json"
        // Absent until something is changed, which is the normal state.
        printErrors: false
        onLoaded: {
            if (settings.dirty) return
            try {
                const d = JSON.parse(file.text())
                if (!d || typeof d !== "object") return
                // KEY BY KEY, not Object.assign: a stale file naming a setting
                // that no longer exists would otherwise add a property nothing
                // reads, and a hand-edited one could set a string where a
                // number is expected.
                for (const k in d) {
                    if (settings[k] === undefined) continue
                    if (typeof settings[k] !== typeof d[k]) continue
                    settings[k] = d[k]
                }
            } catch (e) {
                console.warn("Settings: ignoring unreadable file:", e)
            }
        }
        onSaveFailed: err => console.warn("Settings: could not save:",
                                          FileViewError.toString(err))
    }
}
