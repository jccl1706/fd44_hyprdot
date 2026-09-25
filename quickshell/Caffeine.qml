// =========================================================================
// Caffeine - keep the machine awake while it is switched on
// =========================================================================
//
// A singleton, so every bar's coffee cup shows the same state and the IPC
// handler in shell.qml drives the same switch.
//
// HOW: a logind inhibitor, held by `systemd-inhibit` for as long as it is on.
// hypridle honours idle inhibitors (it logs "systemd idle inhibit active" and
// "Inhibit locks: 1"), so none of its listeners fire: no lock, no screen-off,
// no idle suspend. Nothing in hypridle.conf changes, and the inhibitor shows
// in `systemd-inhibit --list` for anyone wondering why the machine will not
// sleep.
//
// AND THE LID, which is a second `what` and not a stronger one.
// HandleLidSwitch=suspend is set in /etc/systemd/logind.conf.d, and logind
// pays no attention to an IDLE inhibitor when the lid shuts - that is stated
// in logind.conf(5) and was the behaviour here until now: caffeine on, lid
// closed, machine asleep. `handle-lid-switch` is the lock that actually
// stops it, so caffeine now holds `idle:handle-lid-switch`.
//
// The screen still goes off when the lid shuts - hypr/binds.lua blanks it on
// the switch event - so a closed laptop is dark either way. What changes is
// that with caffeine on it keeps running underneath, which is the point of a
// machine downloading something with its lid shut.
//
// STILL NOT `sleep`, deliberately. A sleep inhibitor would block the power
// menu's Suspend and a plain `systemctl suspend`, which are things you asked
// for out loud. This blocks only what the lid does on its own.
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
            "qs=$PPID; exec systemd-inhibit --what=idle:handle-lid-switch --mode=block"
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
