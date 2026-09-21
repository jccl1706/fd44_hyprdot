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
//   theme, wallpaper     they have their own pickers, which work. A second
//                        door to the same room is not consolidation.
//   do not disturb       already a toggle in NotificationPanel, already saved.
//   bar arrangement      already drag-and-drop between the bar's four zones.
//                        Only the RESET lives here, because that had no button.
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

    // THE THEME IS NOT STORED HERE. bin/theme.sh owns it and writes
    // ~/.local/state/fd44-hyprdot/theme; Theme.qml watches that file. This
    // mirrors it so the panel can show which is active, and setting it runs the
    // script rather than writing the value - two sources of truth for the
    // theme is how the bar ends up disagreeing with kitty.
    property string theme: Theme.name

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
                { key: "theme", label: "Theme", type: "select",
                  help: "runs bin/theme.sh, which restyles the bar, kitty, GTK and Chromium together",
                  options: [ { value: "dark", label: "Dark" },
                             { value: "cream", label: "Cream" } ] },
                { label: "Choose wallpaper", type: "action",
                  help: "opens the picker, which previews all 63",
                  run: function() { Settings.requestWallpaperPicker() } }
            ]
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
            rows: [
                { label: "Reset layout", type: "action",
                  help: "puts every plugin back where the repository's defaults have it. Drag to rearrange them in the bar itself",
                  run: function() { BarLayout.reset() } }
            ]
        }
    ]

    // The wallpaper picker is its own surface with its own IPC; the panel asks
    // for it rather than embedding it, so there is one implementation of a
    // thing that already works well.
    signal requestWallpaperPicker()

    // --- persistence -----------------------------------------------------

    property bool dirty: false

    function setValue(key: string, v): void {
        // The theme is the one setting this store does not own - see the
        // property above. Setting it runs bin/theme.sh and lets Theme.qml pick
        // the change up from the state file, so the bar, kitty, GTK and
        // Chromium all move together.
        if (key === "theme") {
            if (v === Theme.name) return
            themeProc.command = ["sh", "-c",
                "\"$(dirname \"$(readlink -f '" + Quickshell.shellDir + "')\")/bin/theme.sh\" set " + v]
            themeProc.running = true
            return
        }
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
