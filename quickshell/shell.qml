//@ pragma IconTheme Reversal-grey
// ^ Keep that the FIRST line: quickshell reads pragmas from the top of the
//   root file, and only at launch - a change needs a restart, not a reload.
//   It picks the icon theme the launcher's app icons come from: Reversal,
//   installed by bin/icon-theme.sh. Measured with Quickshell.iconPath - under
//   Qt's default hicolor theme firefox resolved to nothing; under this every
//   probed app resolved.
//   Fixed, not following the palette, and it does not need to: Reversal's
//   colour sets share one set of app icons and differ only in folders and
//   symbolic icons, which the launcher never draws. On a machine without
//   Reversal, Qt falls back to hicolor - exactly as before this line.
//
//   WHICH COLOUR SET IS ARBITRARY, but it should be one a palette names.
//   It should be one a palette names, or icon-theme.sh keeps installing a
//   colour set nothing else wants - 162 MB that differs from the named one
//   only in folders this never draws. Both palettes name grey now.
// =========================================================================
// Quickshell - entry point
// =========================================================================
//
// Quickshell looks for ~/.config/quickshell/shell.qml and runs it with `qs`.
// That path is a symlink to this directory in the dotfiles repo, the same
// arrangement as ~/.config/hypr.
//
// Quickshell is a QtQuick toolkit, not a bar: nothing appears on screen
// unless this file creates it. Everything here is built one piece at a time.
//
// Reload after editing: quickshell watches its config and reloads by itself,
// so a save is usually enough. To restart by hand:  bin/qs-restart.sh
// (not `qs kill` - quickshell 0.3.1 can segfault on exit and relaunch
// itself, leaving two shells; the script explains)
//
// Inspect what it actually created:  hyprctl layers
// (look for namespace "quickshell")

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

ShellRoot {
    id: shell

    // Bars are created per monitor below; keep a handle on them so IPC can
    // reach the OSD without caring how many there are.
    property var bars: []

    // Variants creates one copy of its delegate per item in `model`. Feeding
    // it Quickshell.screens means one bar per monitor, created and destroyed
    // as monitors come and go - rather than hardcoding a single output. Only
    // eDP-1 exists on this laptop today, but plugging in a display should not
    // need a config change.
    Variants {
        id: barVariants
        model: Quickshell.screens

        // Variants injects each model item into the delegate as `modelData`.
        // That name is fixed by Variants - declaring some other name and
        // assigning to it here fails with "Bar does not have a property
        // called modelData".
        //
        // A plugin glyph opens its panel on the bar's OWN monitor only - a
        // click is about the screen you clicked on, unlike a keybind - and
        // under the glyph, wherever it has been dragged to.
        Bar {
            id: bar
            onAudioRequested: x => shell.eachAudio(a => {
                if (a.modelData === bar.modelData) a.toggle(x)
            })
            onNetworkRequested: x => shell.eachNetwork(n => {
                if (n.modelData === bar.modelData) n.toggle(x)
            })
        }
    }

    // The three remaining edges of the frame. The Bar is the top edge.
    // A separate Variants per edge, because Variants passes exactly one model
    // item and the edge has to be fixed per instance.
    Variants {
        model: Quickshell.screens
        Frame { edge: "left" }
    }
    Variants {
        model: Quickshell.screens
        Frame { edge: "right" }
    }
    Variants {
        model: Quickshell.screens
        Frame { edge: "bottom" }
    }

    // The application launcher. Hidden until IPC opens it, so this costs an
    // unmapped surface per monitor and nothing else.
    Variants {
        id: launcherVariants
        model: Quickshell.screens
        Launcher {}
    }

    // The wallpaper picker, same arrangement.
    Variants {
        id: wallpaperVariants
        model: Quickshell.screens
        WallpaperPicker {
            onApplyRequested: (path, script) => WallpaperState.apply(path, script)
        }
    }

    // Session actions, sliding out of the right frame.
    Variants {
        id: powerVariants
        model: Quickshell.screens
        PowerMenu {}
    }

    // Volume and device selection, sliding down out of the bar's top-right
    // corner. Opened from the speaker glyph in the bar.
    Variants {
        id: audioVariants
        model: Quickshell.screens
        AudioPanel {}
    }

    // Wi-Fi and Ethernet, the same kind of panel. Opened from the network
    // glyph beside the speaker.
    Variants {
        id: networkVariants
        model: Quickshell.screens
        NetworkPanel {}
    }

    // The wallpaper itself, on the Background layer - there is no wallpaper
    // daemon. Click-through, and it crossfades when the choice changes.
    Variants {
        model: Quickshell.screens
        Wallpaper {}
    }

    // -----------------------------------------------------------------------
    // IPC - lets Hyprland's keybinds drive the OSD
    // -----------------------------------------------------------------------
    //
    // Called from binds.lua, e.g.
    //     qs ipc call osd volume
    //     qs ipc call osd brightness
    //
    // The keybind changes the value first (wpctl / brightnessctl) and then
    // announces it; the OSD reads the real value from PipeWire or sysfs when
    // it displays, so the two cannot disagree.
    //
    // List what a running instance exposes with:  qs ipc show
    // --- global shortcuts --------------------------------------------------
    //
    // These register with Hyprland's global-shortcuts protocol, so a keypress
    // is delivered straight into this running process.
    //
    // The IPC handlers below still exist and still work - they are the way to
    // drive this from a script or a terminal. But they are the WRONG way to
    // bind a key: `qs ipc call ...` spawns an entire quickshell process just
    // to connect to the one already running, and that cost lands on every
    // press. Measured at 113ms before the panel had even begun to appear,
    // against a 60ms image decode - the dead time was nearly twice the work.
    //
    // Bound in hypr/binds.lua as:  hl.dsp.global("quickshell:launcher")
    GlobalShortcut {
        appid: "quickshell"
        name: "launcher"
        onPressed: shell.toggleFocused(launcherVariants.instances)
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "wallpaper"
        onPressed: shell.toggleFocused(wallpaperVariants.instances)
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "power"
        onPressed: shell.toggleFocused(powerVariants.instances)
    }

    // Media transport. One shortcut per key, all reaching Media.qml, which
    // speaks MPRIS directly - so a media key spawns no process at all, where
    // it used to fork playerctl on every press.
    GlobalShortcut {
        appid: "quickshell"
        name: "media-toggle"
        onPressed: Media.togglePlaying()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "media-next"
        onPressed: Media.next()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "media-prev"
        onPressed: Media.previous()
    }

    IpcHandler {
        target: "media"

        function toggle(): void   { Media.togglePlaying() }
        function next(): void     { Media.next() }
        function previous(): void { Media.previous() }
        function status(): string {
            const p = Media.active
            return p ? (p.identity + " playing=" + p.isPlaying
                        + " next=" + p.canGoNext + " prev=" + p.canGoPrevious)
                     : "no player"
        }
    }

    IpcHandler {
        target: "power"

        function toggle(): void { shell.toggleFocused(powerVariants.instances) }
        function open(): void   { shell.openFocused(powerVariants.instances)   }
        function close(): void  { shell.closeAll(powerVariants.instances)      }
    }

    IpcHandler {
        target: "audio"

        function toggle(): void { shell.eachAudio(a => a.toggle()) }
        function open(): void   { shell.eachAudio(a => a.open())   }
        function close(): void  { shell.eachAudio(a => a.close())  }
    }

    // The movable plugins' arrangement (BarLayout.qml).
    IpcHandler {
        target: "bar"

        function resetLayout(): void { BarLayout.reset() }
        function layout(): string    { return JSON.stringify(BarLayout.current) }

        // Click a plugin by id - "audio", "network", "theme", "caffeine",
        // "couch" or "power" - wherever it sits, so its panel opens under it:
        //   qs ipc call bar activate audio
        //
        // IT IS A CLICK, INCLUDING ON THE TWO THAT NEED TWO OF THEM. One call
        // to "couch" or "power" only arms the button; a second within four
        // seconds hands the machine to Steam or switches it off. Useful for
        // testing the armed state from a script - and worth knowing before
        // putting either in a loop.
        function activate(id: string): void { shell.eachBar(b => b.activateId(id)) }
    }

    // The stay-awake switch (Caffeine.qml), for scripts and keybinds:
    //   qs ipc call caffeine toggle | on | off | status
    IpcHandler {
        target: "caffeine"

        function toggle(): void   { Caffeine.toggle() }
        function on(): void       { Caffeine.setActive(true) }
        function off(): void      { Caffeine.setActive(false) }
        function status(): string { return Caffeine.active ? "on" : "off" }
    }

    IpcHandler {
        target: "network"

        function toggle(): void { shell.eachNetwork(n => n.toggle()) }
        function open(): void   { shell.eachNetwork(n => n.open())   }
        function close(): void  { shell.eachNetwork(n => n.close())  }
    }

    IpcHandler {
        target: "wallpaper"

        function toggle(): void { shell.toggleFocused(wallpaperVariants.instances) }
        function open(): void   { shell.openFocused(wallpaperVariants.instances)   }
        function close(): void  { shell.closeAll(wallpaperVariants.instances)      }

        // Step the selection without the keyboard - scriptable, and the only
        // way to trigger the transition reproducibly for measurement.
        function next(): void   { shell.eachRevealed(wallpaperVariants.instances, w => w.move(1))  }
        function prev(): void   { shell.eachRevealed(wallpaperVariants.instances, w => w.move(-1)) }

        // Apply whatever is currently centred - the same thing Return does.
        function apply(): void  { shell.eachRevealed(wallpaperVariants.instances, w => w.applySelected()) }
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void { shell.toggleFocused(launcherVariants.instances) }
        function open(): void   { shell.openFocused(launcherVariants.instances)   }
        function close(): void  { shell.closeAll(launcherVariants.instances)      }
    }

    IpcHandler {
        target: "osd"

        function volume(): void {
            shell.showOsd("volume")
        }

        function brightness(): void {
            shell.showOsd("brightness")
        }
    }

    function eachAudio(fn): void {
        const instances = audioVariants.instances
        for (let i = 0; i < instances.length; i++) {
            if (instances[i]) fn(instances[i])
        }
    }

    function eachBar(fn): void {
        const instances = barVariants.instances
        for (let i = 0; i < instances.length; i++) {
            if (instances[i]) fn(instances[i])
        }
    }

    function eachNetwork(fn): void {
        const instances = networkVariants.instances
        for (let i = 0; i < instances.length; i++) {
            if (instances[i]) fn(instances[i])
        }
    }

    // -----------------------------------------------------------------------
    // One monitor at a time
    // -----------------------------------------------------------------------
    //
    // Variants creates one Launcher and one PowerMenu PER MONITOR, and the
    // obvious way to drive them from a keybind - call toggle() on every
    // instance - opens the panel on all of them at once. With a single
    // display that is invisible and indistinguishable from correct. With two
    // it is a bug, and it was reported as one.
    //
    // A keypress is about the screen you are looking at, the same way a click
    // on a bar glyph is about the screen you clicked on. So these open on the
    // monitor that has focus, and only there.
    //
    // Hyprland.focusedMonitor RATHER THAN THE CURSOR POSITION, and the two
    // agree: Hyprland's focus follows the mouse. This one is a live property
    // fed by the compositor's `focusedmon` event, so it costs nothing to
    // read - where asking for the pointer would mean forking hyprctl on
    // every press, which is the cost the global shortcuts above exist to
    // avoid. Measured: it is null for about a second after the shell starts,
    // then tracks every focus change exactly.
    //
    // monitorFor() is what makes the comparison possible. A ShellScreen and
    // a HyprlandMonitor are different objects describing the same output, so
    // the instance's `modelData` cannot be compared to focusedMonitor
    // directly.

    // The instance on the focused monitor.
    //
    // FALLS BACK TO THE FIRST INSTANCE, NEVER TO ALL OF THEM. focusedMonitor
    // is null for about a second after a shell restart, before the first
    // event arrives. Acting on every instance during that window would be
    // precisely the bug this replaces, so one arbitrary monitor is the better
    // wrong answer.
    function focusedOne(instances) {
        const mon = Hyprland.focusedMonitor
        let first = null
        for (let i = 0; i < instances.length; i++) {
            const inst = instances[i]
            if (!inst) continue
            if (!first) first = inst
            if (mon && Hyprland.monitorFor(inst.modelData) === mon) return inst
        }
        return first
    }

    function closeAll(instances): void {
        for (let i = 0; i < instances.length; i++) {
            if (instances[i]) instances[i].close()
        }
    }

    // Open on the focused monitor; close on every one.
    //
    // THE CLOSE REACHES ALL OF THEM, and that asymmetry is the point. Open
    // the launcher on one screen, move to the other, press the key again: if
    // "close" only reached the focused monitor, it would open a second copy
    // and strand the first with no key that shuts it. Treating any revealed
    // instance as "the panel is open" keeps it one thing with one key.
    function toggleFocused(instances): void {
        for (let i = 0; i < instances.length; i++) {
            if (instances[i] && instances[i].revealed) {
                shell.closeAll(instances)
                return
            }
        }
        const one = shell.focusedOne(instances)
        if (one) one.open()
    }

    // The instances that are actually on screen.
    //
    // Stepping or applying a selection has to reach the picker that is UP,
    // which is not always the one on the focused monitor. Unlike the bar's
    // drop-down panels, the picker has no rule closing it when the pointer
    // leaves its screen, so the open one and the focused one can differ.
    function eachRevealed(instances, fn): void {
        for (let i = 0; i < instances.length; i++) {
            if (instances[i] && instances[i].revealed) fn(instances[i])
        }
    }

    function openFocused(instances): void {
        const one = shell.focusedOne(instances)
        if (one) one.open()
    }

    // Show the OSD on every bar. With one monitor that is one bar; with two,
    // the indicator appears on both rather than only where the pointer is.
    function showOsd(which: string): void {
        const instances = barVariants.instances
        for (let i = 0; i < instances.length; i++) {
            if (instances[i] && instances[i].osd) {
                instances[i].osd.show(which)
            }
        }
    }
}
