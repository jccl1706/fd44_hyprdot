// =========================================================================
// AppLaunch - start an application from a desktop entry
// =========================================================================
//
// One place every part of the shell launches apps through - the launcher
// today, anything else (a dock, pinned apps in the bar) later.
//
// AS A TRANSIENT SYSTEMD SERVICE. The app gets its own unit under app.slice
// and is not a child of quickshell, so restarting or reloading the shell does
// not take it down, and the app's memory and CPU are accounted separately
// rather than landing on the shell's cgroup.
//
// NOT AS A SCOPE, which is the other way systemd can do this. A scope runs
// the app IN the calling process, so the Process that launched it stayed
// "running" for as long as the app was open - and a Process that is already
// running ignores `running = true`. With one shared Process, the first app
// opened from the launcher silently blocked every launch after it until that
// app quit. Measured: Chromium opened from the launcher at 15:54 was still
// quickshell's child hours later, and Steam would not start. A fresh Process
// per launch, which exits in a moment, avoids both.
//
// SYSTEMD-RUN DIRECTLY RATHER THAN `uwsm app -t service`, which is what this
// used to call and which produced exactly the same unit. uwsm is a Python
// program, so every launch paid for an interpreter starting before anything
// else happened. Measured to the compositor's openwindow event, spawning
// kitty:
//
//     direct exec (what Super+Return does)      218 ms
//     systemd-run --user                        255 ms
//     uwsm app -t service                       462 ms
//
// So the systemd unit costs about 37ms and uwsm's Python costs about 207ms on
// top of it. The unit was worth having; the interpreter was not. The app's
// environment survives the change because uwsm still sets up the SESSION -
// `systemctl --user show-environment` already carries WAYLAND_DISPLAY,
// XDG_CURRENT_DESKTOP and the rest, and a transient unit inherits it.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    function launch(entry): void {
        if (!entry) return

        // TERMINAL=TRUE ENTRIES KEEP THE OLD PATH. They need a terminal
        // wrapped round them and uwsm knows which one to use; this does not,
        // and guessing wrong means the app starts with nowhere to draw. They
        // are a handful of tools like htop and nobody is timing those, so
        // they pay uwsm's startup and everything else does not.
        const cmd = entry.command
        const direct = !entry.runInTerminal && cmd && cmd.length > 0

        const proc = launcher.createObject(root, { entry: entry })
        proc.command = direct ? root.unitCommand(entry, cmd)
                              : ["uwsm", "app", "-t", "service", "--",
                                 entry.id + ".desktop"]
        proc.running = true
    }

    // A RANDOM SUFFIX ON THE UNIT NAME, because the name has to be unique
    // among units that are still running and an app can perfectly well be
    // opened twice. --collect reaps the unit once the app exits, so these do
    // not accumulate. Anything outside systemd's allowed characters is
    // replaced rather than stripped, so two entries cannot collapse onto one
    // name.
    function unitCommand(entry, cmd): var {
        const tag = String(entry.id).replace(/[^A-Za-z0-9_.\-]/g, "_")
        const unit = "app-" + tag + "-"
                   + Math.random().toString(36).slice(2, 8) + ".service"

        let out = ["systemd-run", "--user", "--collect", "--quiet",
                   "--slice=app.slice", "--unit=" + unit,
                   "--description=" + (entry.name || entry.id)]
        if (entry.workingDirectory)
            out.push("--working-directory=" + entry.workingDirectory)
        out.push("--")
        return out.concat(cmd)
    }

    Component {
        id: launcher

        Process {
            id: proc

            property var entry: null

            onExited: (code, status) => {
                // systemd-run refuses a unit it cannot start, and uwsm can
                // refuse an entry it cannot resolve. Rather than leave the
                // user staring at nothing, fall back to Quickshell's own
                // launcher, which loses the systemd unit but does start the
                // app.
                if (code !== 0 && proc.entry) {
                    console.warn("AppLaunch: launch failed for", proc.entry.id,
                                 "with", code, "- falling back to direct execute")
                    proc.entry.execute()
                }
                proc.destroy()
            }
        }
    }
}
