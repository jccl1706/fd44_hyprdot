// =========================================================================
// LauncherFrecency - what you actually launch, remembered
// =========================================================================
//
// The launcher used to rank by match quality and then alphabetically, so the
// order never changed: typing "k" put every k-word in the same sequence on the
// thousandth launch as on the first, however many times kitty had been chosen
// over the others. This keeps a count per desktop entry and lets the launcher
// break ties with it.
//
// FRECENCY, NOT FREQUENCY. A raw count never forgets, so something used daily
// two years ago outranks what you have been living in this week, permanently.
// Each entry's count is weighted by how long ago it was last used, halving
// every `halfLifeDays`:
//
//     score = count * 0.5 ^ (ageInDays / halfLife)
//
// Ten days is a deliberate middle: short enough that a tool picked up this week
// climbs fast, long enough that a fortnight's holiday does not reset the
// launcher to alphabetical order.
//
// IT ONLY BREAKS TIES. Match quality still decides first - typing "fi" puts
// Files above something that merely mentions "profile", no matter what has been
// launched more. Frecency orders equally good matches, and orders the whole
// list when the query is empty, which is the case that matters most: Super and
// Space should show what you use, not what starts with A.
//
// The store is a JSON object keyed by desktop entry id - the same id
// AppLaunch.qml hands to uwsm - so it survives entries appearing and
// disappearing without needing to be reconciled against anything.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: freq

    // id -> { n: launch count, t: last launch, epoch seconds }
    property var data: ({})

    // Bumped on every record. The launcher's results binding reads this so
    // that a launch reorders the list for next time - QML would not otherwise
    // see a change, because mutating a JavaScript object in place is invisible
    // to it and the reassignment below happens inside a function call.
    property int revision: 0

    readonly property real halfLifeDays: 10

    property bool dirty: false

    function score(id: string): real {
        if (!id) return 0
        const e = freq.data[id]
        if (!e || !e.n) return 0
        const ageDays = (Date.now() / 1000 - (e.t || 0)) / 86400
        // Guard a clock that has gone backwards - a future timestamp would
        // otherwise score arbitrarily high forever.
        const age = ageDays > 0 ? ageDays : 0
        return e.n * Math.pow(0.5, age / freq.halfLifeDays)
    }

    function record(id: string): void {
        if (!id) return
        const prev = freq.data[id]
        const next = {
            n: (prev && prev.n ? prev.n : 0) + 1,
            t: Math.floor(Date.now() / 1000)
        }
        // A NEW OBJECT, not a mutation. QML compares by reference, so
        // `freq.data[id] = next` changes nothing it can observe.
        const copy = {}
        for (const k in freq.data) copy[k] = freq.data[k]
        copy[id] = next
        freq.data = copy
        freq.revision++
        freq.dirty = true
        saveTimer.restart()
    }

    // Debounced, like the notes scratchpad: a launch is followed by the
    // launcher closing and an application starting, and neither wants to wait
    // on a disk write.
    Timer {
        id: saveTimer
        interval: 600
        onTriggered: {
            if (!freq.dirty) return
            file.setText(JSON.stringify(freq.data))
            freq.dirty = false
        }
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
              + "/fd44-hyprdot/launcher-frecency.json"
        // Absent until the first launch, which is not worth a warning on every
        // start.
        printErrors: false
        onLoaded: {
            // Only on the way in, and never over our own pending write.
            if (freq.dirty) return
            try {
                const parsed = JSON.parse(file.text())
                if (parsed && typeof parsed === "object") freq.data = parsed
            } catch (e) {
                // A truncated or hand-edited file is not worth losing the
                // session over - start fresh and let the next launch rewrite
                // it. The launcher still works, just alphabetically.
                console.warn("launcher-frecency: ignoring unreadable store:", e)
            }
        }
        onSaveFailed: err => console.warn("launcher-frecency: could not save:",
                                          FileViewError.toString(err))
    }
}
