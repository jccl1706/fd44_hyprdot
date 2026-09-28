// =========================================================================
// Units - whether anything on this machine has failed
// =========================================================================
//
// A singleton, like Updates.qml and Backups.qml, and the general case of
// both: those two answer a specific question - are packages waiting, is the
// backup old - and this one answers "is anything broken".
//
// WHY IT MATTERS HERE PARTICULARLY. Everything careful in this repository
// reports trouble by FAILING A UNIT. backup.service fails once a backup is a
// fortnight overdue; btrfs-scrub.service fails when a scrub finds errors;
// btrfs-patrol fails when a snapshot cannot be taken. That is the right
// design - a failed unit is durable, timestamped, and sits in
// `systemctl --failed` where a sweep of the machine looks first - and it has
// exactly one gap: somebody has to run the sweep. Every failure found on
// these machines this week was found by hand.
//
// BOTH MANAGERS, because a user unit failing is as real as a system one:
// backup.timer and daylight.timer are user units, and `systemctl --failed`
// alone shows only the system manager.
//
// EVERY TWO MINUTES. The check is two read-only dbus calls, about 55ms, so
// the interval is about not waking the machine rather than about cost - and
// something breaking is worth hearing about sooner than a package update is.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: units

    // How many units have failed, across both managers. -1 before the first
    // answer and after any failure to get one - never 0, because "I could not
    // ask" and "nothing is wrong" must not look alike.
    property int total: -1
    property int system: 0
    property int user: 0

    // "backup, btrfs-scrub and 2 more" - what the terminal will expand on.
    property string names: ""
    property string error: ""

    readonly property bool failing: units.total > 0

    readonly property string script:
        "\"$(dirname \"$(readlink -f '" + Quickshell.shellDir + "')\")/bin/units.sh\""

    function check(): void {
        if (checker.running) return
        checker.command = ["sh", "-c", units.script + " check"]
        checker.running = true
    }

    // The failures with their logs. Detached: reading why something broke
    // takes as long as it takes.
    function open(): void {
        opener.command = ["sh", "-c", units.script + " open >/dev/null 2>&1 &"]
        opener.running = true
        // Long enough to have read one and cleared it, without being so long
        // that the icon lingers after the machine is healthy again.
        recheck.restart()
    }

    Process {
        id: checker
        stdout: StdioCollector {
            onStreamFinished: {
                const line = (text || "").trim()
                if (!line) { units.error = "no output from units.sh"; units.total = -1; return }
                try {
                    const j = JSON.parse(line)
                    units.total = typeof j.total === "number" ? j.total : -1
                    units.system = j.system || 0
                    units.user = j.user || 0
                    units.names = j.names || ""
                    units.error = ""
                } catch (e) {
                    units.error = "unparseable: " + line
                    units.total = -1
                }
            }
        }
    }

    Process { id: opener }

    Timer {
        interval: 2 * 60 * 1000
        repeat: true
        running: true
        onTriggered: units.check()
    }

    // Soon after the shell starts, and before the update and backup checks,
    // because this is the one that might already be true at login.
    Timer {
        interval: 15 * 1000
        running: true
        onTriggered: units.check()
    }

    Timer {
        id: recheck
        interval: 60 * 1000
        onTriggered: units.check()
    }
}
