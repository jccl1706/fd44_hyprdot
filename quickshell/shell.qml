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
    IpcHandler {
        target: "osd"

        function volume(): void {
            shell.showOsd("volume")
        }

        function brightness(): void {
            shell.showOsd("brightness")
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
