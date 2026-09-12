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
// so a save is usually enough. To restart by hand:  pkill -x qs && qs -d
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
        Bar {}
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
            onApplyRequested: (path, script) => shell.eachFade(f => {
                f.setterScript = script
                f.fadeTo(path)
            })
        }
    }

    // Session actions, sliding out of the right frame.
    Variants {
        id: powerVariants
        model: Quickshell.screens
        PowerMenu {}
    }

    // The crossfade surface. Unmapped except during a wallpaper change, and
    // click-through even then.
    Variants {
        id: fadeVariants
        model: Quickshell.screens
        WallpaperFade {}
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
        onPressed: shell.eachLauncher(l => l.toggle())
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "wallpaper"
        onPressed: shell.eachWallpaper(w => w.toggle())
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "power"
        onPressed: shell.eachPower(p => p.toggle())
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

        function toggle(): void { shell.eachPower(p => p.toggle()) }
        function open(): void   { shell.eachPower(p => p.open())   }
        function close(): void  { shell.eachPower(p => p.close())  }
    }

    IpcHandler {
        target: "wallpaper"

        function toggle(): void { shell.eachWallpaper(w => w.toggle()) }
        function open(): void   { shell.eachWallpaper(w => w.open())   }
        function close(): void  { shell.eachWallpaper(w => w.close())  }

        // Step the selection without the keyboard - scriptable, and the only
        // way to trigger the transition reproducibly for measurement.
        function next(): void   { shell.eachWallpaper(w => w.move(1))  }
        function prev(): void   { shell.eachWallpaper(w => w.move(-1)) }

        // Apply whatever is currently centred - the same thing Return does.
        function apply(): void  { shell.eachWallpaper(w => w.applySelected()) }
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void { shell.eachLauncher(l => l.toggle()) }
        function open(): void   { shell.eachLauncher(l => l.open())   }
        function close(): void  { shell.eachLauncher(l => l.close())  }
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

    // Drive every launcher instance - one per monitor, as with the bars.
    // With a single display this is one call; the loop is what keeps a second
    // monitor from silently doing nothing.
    function eachLauncher(fn): void {
        const instances = launcherVariants.instances
        for (let i = 0; i < instances.length; i++) {
            if (instances[i]) fn(instances[i])
        }
    }

    function eachPower(fn): void {
        const instances = powerVariants.instances
        for (let i = 0; i < instances.length; i++) {
            if (instances[i]) fn(instances[i])
        }
    }

    function eachFade(fn): void {
        const instances = fadeVariants.instances
        for (let i = 0; i < instances.length; i++) {
            if (instances[i]) fn(instances[i])
        }
    }

    function eachWallpaper(fn): void {
        const instances = wallpaperVariants.instances
        for (let i = 0; i < instances.length; i++) {
            if (instances[i]) fn(instances[i])
        }
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
