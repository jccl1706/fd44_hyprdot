// =========================================================================
// Caffeine - keep the machine awake while it is switched on
// =========================================================================
//
// A singleton, so every bar's coffee cup shows the same state and the IPC
// handler in shell.qml drives the same switch.
//
// HOW: a logind idle inhibitor, held by `systemd-inhibit --what=idle` for as
// long as it is on. hypridle honours those (it logs "systemd idle inhibit
// active" and "Inhibit locks: 1"), so none of its listeners fire: no lock,
// no screen-off, no idle suspend. Nothing in hypridle.conf changes, and the
// inhibitor shows in `systemd-inhibit --list` for anyone wondering why the
// machine will not sleep.
//
// IDLE ONLY, NOT SLEEP. A sleep inhibitor would also block the power menu's
// Suspend and a plain `systemctl suspend`. Closing the lid still suspends
// (logind ignores inhibitors for the lid switch by default), so a laptop
// left on in a bag still goes to sleep.
//
// OFF AT EVERY START. Nothing is saved: a stay-awake switch that silently
// survives a reboot is how a laptop ends up flat.
//
// IT CANNOT OUTLIVE QUICKSHELL. The held command is a loop that exits as soon
// as quickshell or systemd-inhibit itself is gone, so a crashed or killed
// shell releases the inhibitor within two seconds instead of leaving an
// orphan keeping the machine awake forever. Turning it off sends SIGTERM to
// systemd-inhibit, which releases at once; the loop follows it.
//
// A quickshell config reload recreates this singleton, which turns it off.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: caffeine

    // True only while the inhibitor really is held - if systemd-inhibit
    // fails to start, the cup never shows as on.
    readonly property bool active: holder.running

    function toggle(): void { holder.running = !holder.running }
    function setActive(on: bool): void { holder.running = on }

    Process {
        id: holder

        // `exec` makes the outer sh BECOME systemd-inhibit, so the process
        // this object stops is the one holding the lock. $PPID, read before
        // the exec, is quickshell.
        command: ["sh", "-c",
            "qs=$PPID; exec systemd-inhibit --what=idle --mode=block"
            + " --who='fd44 caffeine' --why='Caffeine is switched on in the bar'"
            + " sh -c 'while kill -0 \"$1\" 2>/dev/null && kill -0 \"$PPID\" 2>/dev/null;"
            + " do sleep 2; done' caffeine \"$qs\""]

        onExited: (code, status) => {
            // Turning it off SIGTERMs systemd-inhibit, and quickshell reports
            // that as code 15 - the signal number, not a shell's 143. Both
            // mean "stopped on purpose"; anything else is a real failure.
            if (code !== 0 && code !== 15 && code !== 143)
                console.warn("caffeine: systemd-inhibit exited with", code)
        }
    }
}
