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
import Quickshell.Networking
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

    // TWO SHAPES FOR THE BAR, and the only thing it changes is whether the
    // bar paints a background and whether Frame.qml draws the other three
    // edges. Everything inside is the same three rounded regions either way -
    // "frame" puts them on an opaque strip welded to a border round the
    // screen, "pill" lets them float on the wallpaper with a gap all round.
    property string barStyle: "frame"   // "frame" | "pill" | "focus"

    // WHAT FOCUS GOES BACK TO. Focus mode hides everything on the bar except
    // a button to leave it, so the shell has to remember what it was showing
    // before - "back to the default" would silently undo a choice the user
    // made once and expected to keep. Written whenever focus is entered and
    // read by the exit button; never by anything else.
    property string barStylePrev: "frame"

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
    // Asked for by the Wallpaper row, answered by shell.qml, which owns the
    // surfaces. DECLARED HERE, which is the part that was missing before: a
    // Connections handler for a signal nobody declares is silently dead, and
    // that is exactly how the old "choose a wallpaper" button did nothing.
    signal requestWallpaperPicker()

    readonly property var schema: [
        {
            section: "Appearance",
            icon: "\u{F03D8}",                       // palette
            rows: [
                { label: "Bar style", type: "select",
                  help: "frame welds the bar to a border round the whole screen; pill floats it on the wallpaper; focus hides it but for a button to come back",
                  get: function() { return Settings.barStyle },
                  set: function(v) { Settings.setBarStyle(v) },
                  options: [ { value: "frame", label: "Frame" },
                             { value: "pill",  label: "Floating pill" },
                             { value: "focus", label: "Focus" } ] },
                { label: "Theme", type: "select",
                  help: "runs bin/theme.sh, which restyles the bar, kitty, GTK and Chromium together",
                  get: function() { return Theme.name },
                  set: function(v) { Settings.applyTheme(v) },
                  options: [ { value: "dark", label: "Dark" },
                             { value: "cream", label: "Cream" } ] },
                { label: "Wallpaper", type: "wallpapers",
                  help: WallpaperLibrary.files.count === 0
                      ? "nothing in wallpapers/"
                      : (WallpaperLibrary.currentCaption || "none set")
                        + " · " + WallpaperLibrary.files.count + " available"
                          + " · click a neighbour to step to it",
                  // A wide row with an action: the strip goes underneath, the
                  // button sits where every other row's control sits.
                  run: function() { settings.requestWallpaperPicker() },
                  runLabel: "Browse…" }
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
            section: "Network",
            icon: "\u{F0928}",                       // wifi_strength_4
            // A machine with no wireless card has nothing here. The desktop
            // is on ethernet and its Wi-Fi row would be a switch for hardware
            // that is not in it.
            when: function() { return settings.wifiDevice !== null },
            rows: settings.networkRows
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
        // With one screen "Resolution" is unambiguous. With two it is not, so
        // the sub-rows carry the screen's name as well - the scale row is
        // already labelled with it.
        const many = Monitors.list.length > 1
        for (const monitor of Monitors.list) {
            const prefix = many ? monitor.title + " · " : ""
            if (!monitor.options.length) continue
            out.push({
                label: monitor.title,
                type: "select",
                // ONE LINE. The whole page is a boxed list, and a row whose
                // subtitle wraps is taller than the rows either side of it,
                // which is most of what made this look untidy. Where it was
                // written is in the README; it does not belong under every
                // screen's name.
                help: monitor.description + " · "
                      + monitor.width + "x" + monitor.height + ", "
                      + monitor.inches.toFixed(1) + "\", "
                      + Math.round(monitor.ppi) + " ppi · now "
                      + (Monitors.currentDetail(monitor) || "a scale with no preset"),
                options: monitor.options,
                get: function() { return Monitors.currentOption(monitor) },
                set: function(v) { Monitors.setScale(monitor, v) }
            })

            // Resolution, as a menu rather than a row of chips: this panel
            // offers twelve and they will not fit across the pane.
            //
            // BELOW THE SCALE ROW ON PURPOSE. Scale is the setting that gets
            // changed; resolution on a flat panel is almost always a mistake,
            // because anything but the native mode is interpolated and soft.
            // It is here because sometimes it is genuinely wanted, not
            // because it is the first thing to reach for.
            if (monitor.resolutionOptions.length > 1)
                out.push({
                    label: prefix + "Resolution", type: "menu",
                    help: "native is the sharp one; anything else the panel scales up",
                    options: monitor.resolutionOptions,
                    get: function() { return monitor.currentResolution },
                    set: function(v) { Monitors.setResolution(monitor, v) }
                })

            // Refresh rate, only where the chosen resolution has more than
            // one. On this panel exactly one of the twelve does - 2256x1504
            // advertises 48 Hz as well as 60, for power saving - so on every
            // other resolution this row is correctly absent rather than
            // showing a single button that does nothing.
            if (monitor.refreshOptions.length > 1)
                out.push({
                    label: prefix + "Refresh rate", type: "select",
                    help: "rates " + monitor.currentResolution + " offers"
                          + (monitor.internal ? " · a lower one saves battery" : ""),
                    options: monitor.refreshOptions,
                    get: function() { return monitor.currentRefresh },
                    set: function(v) { Monitors.setRefresh(monitor, v) }
                })
        }
        return out
    }

    // --- network ----------------------------------------------------------
    //
    // TWO ROWS, NOT A SECOND NETWORK PANEL. NetworkPanel is eight hundred
    // lines that already scan, sort, ask for a password, report why a join
    // failed and show the addresses; writing any of that again here would be
    // two implementations of the same thing, drifting. This is the settings
    // that belong in settings - the radio switch - plus a door to the surface
    // that does the rest, which is the same shape as the Wallpaper row.

    readonly property var wifiDevice: {
        for (const d of Networking.devices.values)
            if (d.type === DeviceType.Wifi) return d
        return null
    }

    readonly property string wifiStatus: {
        if (!settings.wifiDevice) return "no wireless card"
        if (!Networking.wifiEnabled) return "the radio is off"
        const joined = settings.wifiDevice.networks.values.find(n => n.connected)
        return joined && joined.name ? "connected to " + joined.name : "not connected"
    }

    readonly property var networkRows: [
        { label: "Wi-Fi", type: "toggle",
          help: "the radio itself · off saves power and drops any connection",
          get: function() { return Networking.wifiEnabled },
          set: function(v) { Networking.wifiEnabled = v } },

        { label: "Networks", type: "networks",
          help: settings.wifiStatus + " · click one to join; it asks for a password if it needs one",
          // Nothing to list while the radio is off.
          when: function() { return Networking.wifiEnabled } }
    ]

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
                   help: "defaults restored and every plugin shown again · drag in the bar to rearrange",
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

    // THE ONE WAY IN, so that barStylePrev cannot be forgotten. Entering
    // focus from focus would otherwise overwrite the way back with "focus"
    // and strand the bar there with a button that does nothing.
    function setBarStyle(v: string): void {
        if (v === settings.barStyle) return
        if (v === "focus") settings.setValue("barStylePrev", settings.barStyle)
        settings.setValue("barStyle", v)
    }

    // Leave focus mode for whatever was showing before it.
    function leaveFocus(): void {
        settings.setValue("barStyle", settings.barStylePrev || "frame")
    }

    // In from wherever, or back out. What the keybind and the IPC call - the
    // button on the bar only ever leaves, because it only exists while focus
    // is on.
    function toggleFocus(): void {
        if (settings.barStyle === "focus") settings.leaveFocus()
        else settings.setBarStyle("focus")
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
        settings.barStyle = "frame"
        settings.barStylePrev = "frame"
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
                frecencyHalfLifeDays: settings.frecencyHalfLifeDays,
                barStyle: settings.barStyle,
                barStylePrev: settings.barStylePrev
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
