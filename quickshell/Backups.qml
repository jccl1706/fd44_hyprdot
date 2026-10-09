// =========================================================================
// Backups - how long it has been, and whether anyone should care yet
// =========================================================================
//
// A singleton, like Updates.qml and for the same reason: one timer answers
// for every bar on every monitor.
//
// WHY THE BAR NEEDS THIS AT ALL. bin/backup.sh already knows when a backup is
// overdue - the unit FAILS past STALE_DAYS, which puts it in
// `systemctl --failed` where a sweep looks first. But nothing on screen ever
// said so, and the disk lives in a drawer: the laptop went days without a
// backup and the only reason anyone noticed was a sweep run by hand. A
// machine that fails silently for a fortnight is not backed up, it is
// hoping.
//
// IT ASKS bin/backup.sh, which answers in JSON and cannot prompt for
// anything: no disk is mounted and no repository password is read to say how
// many days it has been. The script is the one place that knows where the
// state file is and what counts as stale.
//
// HALF-HOURLY, WHICH IS OFTEN ENOUGH FOR A NUMBER OF DAYS. It is also cheap -
// a stat of one file and a look for a disk by UUID - so the interval is about
// not waking the machine for nothing rather than about cost.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: backups

    // Days since the last successful backup. -1 when nothing is known yet,
    // and also when this machine has no backup configured at all - the gaming
    // desktop, where the icon must never appear.
    property int days: -1

    // True when the machine has never backed up. Different from "a long time
    // ago" and worth saying differently: there is nothing to restore.
    property bool never: false

    // Whether the backup disk is plugged in right now. A machine that is
    // overdue BUT has the disk connected is about to fix itself on the next
    // timer tick, so the icon says something milder.
    property bool connected: false

    property bool configured: false
    property int staleDays: 14
    property string error: ""

    // WHEN IT APPEARS. Not at one day - the timer is daily and the disk is
    // not always plugged in, so a nag every morning is a nag people learn to
    // ignore. Half of the script's own stale threshold is the point at which
    // drift has stopped being ordinary: a week on a fortnight's patience.
    readonly property int warnDays: Math.max(2, Math.floor(backups.staleDays / 2))

    readonly property bool overdue:
        backups.configured && (backups.never || backups.days >= backups.warnDays)

    // Past the threshold the script itself fails on, this is no longer a
    // reminder. Never having backed up counts as the same thing.
    readonly property bool critical:
        backups.configured && (backups.never || backups.days >= backups.staleDays)

    readonly property string script:
        "\"$(dirname \"$(readlink -f '" + Quickshell.shellDir + "')\")/bin/backup.sh\""

    function check(): void {
        if (checker.running) return
        checker.command = ["sh", "-c", backups.script + " json"]
        checker.running = true
    }

    // The terminal that runs a backup now. Detached, because a backup of a
    // home directory is not a thing to make quickshell the parent of.
    function open(): void {
        opener.command = ["sh", "-c", backups.script + " open >/dev/null 2>&1 &"]
        opener.running = true
        recheck.restart()
    }

    Process {
        id: checker
        stdout: StdioCollector {
            onStreamFinished: {
                const line = (text || "").trim()
                if (!line) { backups.error = "no output from backup.sh"; backups.configured = false; return }
                try {
                    const j = JSON.parse(line)
                    backups.configured = !!j.configured
                    backups.connected = !!j.connected
                    backups.never = !!j.never
                    backups.days = typeof j.days === "number" ? j.days : -1
                    if (typeof j.stale_days === "number") backups.staleDays = j.stale_days
                    backups.error = ""
                } catch (e) {
                    backups.error = "unparseable: " + line
                    backups.configured = false
                }
            }
        }
    }

    Process { id: opener }

    Timer {
        interval: 30 * 60 * 1000
        repeat: true
        running: true
        onTriggered: backups.check()
    }

    // After the shell has finished starting, and after the update check, so
    // two subprocesses are not racing the login.
    Timer {
        interval: 25 * 1000
        running: true
        onTriggered: backups.check()
    }

    // Long enough for a backup of a home directory that has not changed much.
    // A big one is still running and the half-hourly check will catch it.
    Timer {
        id: recheck
        interval: 5 * 60 * 1000
        onTriggered: backups.check()
    }

    // THE STATE FILE, WATCHED, because every timer above can miss.
    //
    // bin/backup.sh writes this the moment a run finishes, whoever started it.
    // The timers only cover the cases they were written for: half-hourly, once
    // at login, and five minutes after the BAR launches one. A backup run from
    // a terminal is invisible to all three, and so is one from the bar that
    // takes longer than five minutes to finish - the recheck fires once, does
    // not repeat, and lands while the run is still going.
    //
    // Found on framework00 the day it was installed: four backups were taken
    // from a shell and the pill went on saying "never" for half an hour, while
    // `backup.sh json` reported never=false the whole time. The data was right
    // and the bar was stale, which is the worst way for this to be wrong -
    // "never" is the one reading that should make somebody act.
    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
              + "/fd44-hyprdot/backup-last"
        watchChanges: true
        // Missing until the first backup, which is exactly when `never` is the
        // correct answer - not a condition to warn about.
        printErrors: false
        onFileChanged: { reload(); backups.check() }
    }
}
