pragma Singleton

// =========================================================================
// Battery - charge, and what the machine is doing about it
// =========================================================================
//
// Read straight from /sys/class/power_supply with FileView. No upower, no
// polling a shell script: the same rule that has Media.qml speak MPRIS
// rather than fork playerctl. After a single probe to find which batteries
// exist, this costs one file read per battery every ten seconds and no
// processes at all.
//
// THE 80% THAT IS NOT A FAULT. This laptop's BIOS stops charging at 80%, so
// plugged in and settled it reports:
//
//     capacity 80   status "Not charging"   ACAD online 1
//
// "Not charging" while on mains looks alarming and is the charge limit
// working exactly as asked. `limited` exists to say so, and the button draws
// it as plugged-in-and-content rather than as a problem. Without that this
// module would spend most of its life crying wolf.
//
// SEVERAL BATTERIES ARE SUMMED, not averaged. The ThinkPad T480 this config
// also runs on has two, and two batteries at 50% and 100% are not "75%" -
// they are three quarters of the pair's capacity only if the packs are the
// same size, which they are not on that machine. charge_now over charge_full
// across every pack is the honest number. Same reasoning as
// bin/lock-battery.sh, which does this for the lock screen and tmux.

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: battery

    // Absent on the desktop, where this module simply never appears.
    readonly property bool present: battery.dirs.length > 0

    // False until a pack has actually been read. The difference between
    // "this battery is empty" and "we have not looked yet" matters when the
    // answer is drawn in the danger colour.
    property bool ready: false

    property int percent: 0
    property string status: "Unknown"
    property bool onAc: false

    readonly property bool charging:    battery.status === "Charging"
    readonly property bool full:        battery.status === "Full"

    // Plugged in, below full, and deliberately not charging: the BIOS limit.
    readonly property bool limited: battery.onAc && !battery.charging
                                    && battery.percent < 100

    // One entry per pack, for the panel. Aggregates below are for the glyph.
    property var details: []

    // Worn-ness: what the pack can still hold against what it shipped with.
    property int healthPercent: 0

    // Watts in or out right now. Negative is not used - `charging` says which
    // direction it is going.
    property real watts: 0

    // Hours at the present draw, or 0 when that cannot be said. It usually
    // cannot: sitting at the charge limit this machine draws a milliamp, and
    // dividing by that gives an answer in months.
    property real hoursLeft: 0

    property int cycleCount: 0

    readonly property bool low:      battery.ready && !battery.onAc && battery.percent <= 15
    readonly property bool critical: battery.ready && !battery.onAc && battery.percent <= 5

    // --- discovery ---------------------------------------------------------
    //
    // Once, at startup. FileView needs a literal path and there is no way to
    // glob from QML, so the shell finds the packs and everything after this
    // is file reads. The same shape as Osd.qml finding its backlight.

    property var dirs: []

    Process {
        running: true
        command: ["sh", "-c",
                  "for d in /sys/class/power_supply/BAT*; do [ -d \"$d\" ] && echo \"$d\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = text.trim()
                battery.dirs = found === "" ? [] : found.split("\n")
            }
        }
    }

    // The mains adapter. ACAD on the Framework, AC or ADP1 elsewhere - all
    // three are tried because a missing file reads as empty rather than
    // failing, so guessing costs nothing.
    property var acPaths: ["/sys/class/power_supply/ACAD/online",
                           "/sys/class/power_supply/AC/online",
                           "/sys/class/power_supply/ADP1/online"]

    // --- reading -----------------------------------------------------------

    Instantiator {
        id: packs
        model: battery.dirs

        delegate: QtObject {
            required property string modelData

            // onLoaded, not just the timer: FileView.reload() is asynchronous,
            // so the tick that asks for a reload reads the PREVIOUS contents.
            // Without this the bar showed 0% for the first ten seconds after
            // every shell restart - a flat battery, on mains, which is
            // exactly the sort of false alarm this module exists to avoid.
            readonly property FileView capFile:  FileView { path: modelData + "/capacity";    printErrors: false; onLoaded: battery.refresh() }
            readonly property FileView statFile: FileView { path: modelData + "/status";      printErrors: false; onLoaded: battery.refresh() }
            // charge_* on this laptop, energy_* on some others. Whichever
            // pair is present is the one used; both are read because asking
            // is cheaper than working out which the machine has.
            readonly property FileView nowC:     FileView { path: modelData + "/charge_now";  printErrors: false; onLoaded: battery.refresh() }
            readonly property FileView fullC:    FileView { path: modelData + "/charge_full"; printErrors: false; onLoaded: battery.refresh() }
            readonly property FileView nowE:     FileView { path: modelData + "/energy_now";  printErrors: false }
            readonly property FileView fullE:    FileView { path: modelData + "/energy_full"; printErrors: false }

            // For the panel rather than the glyph: how worn the pack is, how
            // many times it has been round, and what it is doing in watts.
            readonly property FileView designC:  FileView { path: modelData + "/charge_full_design"; printErrors: false }
            readonly property FileView designE:  FileView { path: modelData + "/energy_full_design"; printErrors: false }
            readonly property FileView cycles:   FileView { path: modelData + "/cycle_count";        printErrors: false }
            readonly property FileView currentF: FileView { path: modelData + "/current_now";        printErrors: false }
            readonly property FileView powerF:   FileView { path: modelData + "/power_now";          printErrors: false }
            readonly property FileView voltageF: FileView { path: modelData + "/voltage_now";        printErrors: false }
            readonly property FileView techF:    FileView { path: modelData + "/technology";         printErrors: false }

            function reload(): void {
                capFile.reload(); statFile.reload()
                nowC.reload(); fullC.reload(); nowE.reload(); fullE.reload()
                designC.reload(); designE.reload(); cycles.reload()
                currentF.reload(); powerF.reload(); voltageF.reload()
            }
        }

        onObjectAdded: battery.refresh()
    }

    Instantiator {
        id: mains
        model: battery.acPaths
        delegate: QtObject {
            required property string modelData
            readonly property FileView file: FileView { path: modelData; printErrors: false; onLoaded: battery.refresh() }
            function reload(): void { file.reload() }
        }
    }

    function num(view, fallback) {
        if (!view) return fallback
        const t = String(view.text()).trim()
        if (t === "") return fallback
        const v = parseInt(t, 10)
        return isNaN(v) ? fallback : v
    }

    function refresh(): void {
        if (battery.dirs.length === 0) return

        let now = 0, cap = 0, capSum = 0, n = 0
        let anyCharging = false, anyDischarging = false, seen = ""
        let design = 0, watts = 0, cycles = 0
        const rows = []

        for (let i = 0; i < packs.count; i++) {
            const p = packs.objectAt(i)
            if (!p) continue
            n++
            capSum += battery.num(p.capFile, 0)

            const nowV  = battery.num(p.nowC, -1) >= 0 ? battery.num(p.nowC, 0)
                                                       : battery.num(p.nowE, 0)
            const fullV = battery.num(p.fullC, -1) >= 0 ? battery.num(p.fullC, 0)
                                                        : battery.num(p.fullE, 0)
            now += nowV
            cap += fullV

            const st = String(p.statFile.text()).trim()
            if (st === "Charging") anyCharging = true
            else if (st === "Discharging") anyDischarging = true
            if (seen === "" && st !== "") seen = st

            const desV = battery.num(p.designC, -1) >= 0 ? battery.num(p.designC, 0)
                                                         : battery.num(p.designE, 0)
            design += desV

            // power_now is already watts-in-microwatts where a machine has
            // it. Where it does not, current x voltage is the same thing:
            // microamps times microvolts, hence the 1e12.
            const pw = battery.num(p.powerF, -1)
            const packW = pw >= 0 ? pw / 1e6
                        : (battery.num(p.currentF, 0) * battery.num(p.voltageF, 0)) / 1e12
            watts += packW

            const c = battery.num(p.cycles, 0)
            if (c > cycles) cycles = c

            rows.push({
                name:    String(p.modelData).split("/").pop(),
                percent: fullV > 0 ? Math.round(nowV * 100 / fullV)
                                   : battery.num(p.capFile, 0),
                status:  st === "" ? "Unknown" : st,
                cycles:  c,
                health:  desV > 0 ? Math.round(fullV * 100 / desV) : 0,
                watts:   packW,
                tech:    String(p.techF.text()).trim()
            })
        }

        if (n === 0) return

        // CHARGE OVER CAPACITY WHEN THE PACKS REPORT IT, averaged capacity
        // only as a fallback - see the note at the top about why averaging
        // two packs is wrong.
        if (cap <= 0 && capSum <= 0) return      // nothing readable yet
        let pct = cap > 0 ? Math.round(now * 100 / cap) : Math.round(capSum / n)
        battery.percent = Math.max(0, Math.min(100, pct))
        battery.ready = true

        // ANY pack charging means the machine is charging; any discharging
        // with none charging means it is running down. Otherwise whatever
        // the first pack said - "Full", "Not charging", or "Unknown".
        battery.status = anyCharging ? "Charging"
                       : anyDischarging ? "Discharging"
                       : (seen !== "" ? seen : "Unknown")

        let ac = false
        for (let i = 0; i < mains.count; i++) {
            const m = mains.objectAt(i)
            if (m && battery.num(m.file, 0) === 1) ac = true
        }
        battery.onAc = ac

        battery.details = rows
        battery.cycleCount = cycles
        battery.watts = watts
        battery.healthPercent = design > 0 ? Math.round(cap * 100 / design) : 0

        // Only when it means something: a reading taken while the charge
        // limit holds the draw near zero would say "1400 hours".
        const amps = battery.num(packs.count > 0 ? packs.objectAt(0).currentF : null, 0)
        battery.hoursLeft = (anyDischarging && watts > 0.5 && amps > 0)
                            ? (now / amps) : 0
    }

    // Ten seconds. A battery does not move faster than that, and the point
    // of reading files rather than running a program is that this costs
    // nothing worth measuring.
    Timer {
        interval: 10000
        repeat: true
        running: battery.present
        triggeredOnStart: true
        onTriggered: {
            for (let i = 0; i < packs.count; i++) {
                const p = packs.objectAt(i)
                if (p) p.reload()
            }
            for (let i = 0; i < mains.count; i++) {
                const m = mains.objectAt(i)
                if (m) m.reload()
            }
            battery.refresh()
        }
    }
}
