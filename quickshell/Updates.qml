// =========================================================================
// Updates - whether packages are waiting, and the terminal that installs them
// =========================================================================
//
// A singleton, so every bar on every monitor shows the same count and one
// timer answers for all of them.
//
// IT KNOWS NOTHING ABOUT DNF OR NIX. bin/updates.sh answers "what is
// pending" on whichever distro this is and prints one line of JSON; this
// reads the number. That is the whole division: the bar would otherwise need
// a branch per machine in QML, where it could not be run or tested from a
// terminal. `bin/updates.sh check` prints exactly what this parses.
//
// -1 IS "I DO NOT KNOW", and it is not the same as zero. A failed check - no
// network, a repo timing out, a machine that is neither Fedora nor NixOS -
// leaves the count at -1 and the icon hidden. The alternative is an icon that
// appears because the wifi dropped, which teaches you to ignore it.
//
// HOURLY, AND NOT MORE. A dnf check with --refresh is a metadata download and
// the nix check is a network round trip to GitHub; neither is free, and
// nothing about a package list changes in five minutes in a way anyone acts
// on. The first check waits 20 seconds after the shell starts so it is not
// competing with everything else a login does.
//
// AND AGAIN AFTER THE TERMINAL CLOSES, which is what makes the icon
// disappear when you have just finished an update, rather than up to an hour
// later. The terminal is not watched for success: what the next check finds
// is the only thing worth believing.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: updates

    // How many packages are waiting - or, on NixOS, how many days behind the
    // pinned nixpkgs is. -1 until the first answer arrives, and again after
    // any failure.
    property int count: -1

    // "chromium, vim-enhanced and 4 more", or "nixpkgs 11 days behind".
    property string summary: ""

    // "dnf" or "nix", so the tooltip can name what it is talking about.
    property string kind: ""

    // The last failure, empty when the last check succeeded.
    property string error: ""

    // Unix seconds of the last successful check, 0 before the first.
    property real checked: 0

    // The only thing the bar asks. A count of 0 or -1 draws nothing.
    readonly property bool pending: updates.count > 0

    readonly property string script:
        "\"$(dirname \"$(readlink -f '" + Quickshell.shellDir + "')\")/bin/updates.sh\""

    function check(): void {
        if (checker.running) return
        checker.command = ["sh", "-c", updates.script + " check"]
        checker.running = true
    }

    // Opens the terminal that does the update. It detaches: quickshell is not
    // the parent of a window someone may leave open for ten minutes while a
    // kernel builds.
    function open(): void {
        opener.command = ["sh", "-c", updates.script + " open >/dev/null 2>&1 &"]
        opener.running = true
        // The window takes a moment to appear and the update takes as long as
        // it takes; this is the earliest point it could possibly be finished.
        recheck.restart()
    }

    Process {
        id: checker
        stdout: StdioCollector {
            onStreamFinished: {
                const line = (text || "").trim()
                if (!line) { updates.error = "no output from updates.sh"; updates.count = -1; return }
                try {
                    const j = JSON.parse(line)
                    updates.kind = j.kind || ""
                    updates.summary = j.summary || ""
                    updates.error = j.error || ""
                    updates.count = typeof j.count === "number" ? j.count : -1
                    if (updates.count >= 0) updates.checked = j.checked || 0
                } catch (e) {
                    updates.error = "unparseable: " + line
                    updates.count = -1
                }
            }
        }
    }

    Process { id: opener }

    // Hourly. `triggeredOnStart` is deliberately not used - see the 20s below.
    Timer {
        interval: 60 * 60 * 1000
        repeat: true
        running: true
        onTriggered: updates.check()
    }

    Timer {
        id: firstCheck
        interval: 20 * 1000
        running: true
        onTriggered: updates.check()
    }

    // After the update terminal has been open long enough to have finished a
    // small transaction. If it has not, the hourly check catches up later.
    Timer {
        id: recheck
        interval: 90 * 1000
        onTriggered: updates.check()
    }
}
