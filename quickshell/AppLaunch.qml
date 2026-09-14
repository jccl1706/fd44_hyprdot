// =========================================================================
// AppLaunch - start an application from a desktop entry
// =========================================================================
//
// One place every part of the shell launches apps through - the launcher
// today, anything else (a dock, pinned apps in the bar) later.
//
// THROUGH UWSM, AS A SERVICE. `uwsm app -t service` starts the app as its own
// transient systemd service under app.slice and returns at once (~0.1s). The
// app is not a child of quickshell, so restarting or reloading the shell does
// not take it down.
//
// NOT uwsm's default scope mode. A scope runs the app IN the calling process,
// so the Process that launched it stayed "running" for as long as the app was
// open - and a Process that is already running ignores `running = true`. With
// one shared Process, the first app opened from the launcher silently blocked
// every launch after it until that app quit. Measured: Chromium opened from the
// launcher at 15:54 was still quickshell's child hours later, and Steam would
// not start. A fresh Process per launch, which exits in a moment, avoids both.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    function launch(entry): void {
        if (!entry) return
        const proc = launcher.createObject(root, { entry: entry })
        proc.command = ["uwsm", "app", "-t", "service", "--", entry.id + ".desktop"]
        proc.running = true
    }

    Component {
        id: launcher

        Process {
            id: proc

            property var entry: null

            onExited: (code, status) => {
                // uwsm can refuse an entry it cannot resolve. Rather than leave
                // the user staring at nothing, fall back to Quickshell's own
                // launcher, which loses the systemd unit but does start the app.
                if (code !== 0 && proc.entry) {
                    console.warn("AppLaunch: uwsm failed for", proc.entry.id,
                                 "with", code, "- falling back to direct execute")
                    proc.entry.execute()
                }
                proc.destroy()
            }
        }
    }
}
