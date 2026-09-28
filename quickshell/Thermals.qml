// =========================================================================
// Thermals - what the graphics card is doing, while it is doing it
// =========================================================================
//
// A singleton, like the other three services, and the odd one out among them:
// Updates, Backups and Units all answer "is something wrong", and appear only
// when the answer is yes. This one is a READOUT. It is on screen whenever
// there is a card to read, because the question it answers - how hot is it
// under this load - is asked WHILE something is happening, and an indicator
// that only appears once a machine is already too hot has missed the part
// worth watching.
//
// SO IT IS ABSENT ON THE LAPTOP, which has no discrete card: bin/thermal.sh
// answers ok:false there and nothing is drawn. Per-machine behaviour with no
// per-machine configuration - the same shape as the backup icon, which is
// silent on the desktop because no backup is set up there.
//
// FIVE SECONDS, AND IT COSTS 43ms. That is one nvidia-smi call, measured: the
// NVIDIA driver publishes nothing in hwmon, so there is no cheaper source.
// Everything else in the line - CPU temperature, case fans - IS read straight
// from sysfs and costs nothing.
//
// IT DOES NOT POLL WHILE IT CANNOT BE SEEN. A bar hidden behind a fullscreen
// game is exactly when someone wants this number, so `visible` is not the
// test; what is skipped is the case with no card at all, where the first
// answer settles it for the session.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: thermals

    // Degrees, percent, watts, MHz. -1 where there is no answer yet.
    property int gpuTemp: -1
    property int gpuUtil: -1
    property real gpuPower: -1
    property int gpuClock: -1
    property int cpuTemp: -1
    property int fanRpm: -1

    // Whether this machine has a card worth reading at all.
    property bool present: false
    property string error: ""

    // Whether a check has come back at all. Distinct from `present`, and the
    // difference is what stops the laptop polling: "no card" and "not asked
    // yet" both leave present false, so the timer needs to tell them apart or
    // it runs forever on the machine it was meant to stay quiet on.
    property bool answered: false

    readonly property string script:
        "\"$(dirname \"$(readlink -f '" + Quickshell.shellDir + "')\")/bin/thermal.sh\""

    function check(): void {
        if (checker.running) return
        checker.command = ["sh", "-c", thermals.script + " check"]
        checker.running = true
    }

    function open(): void {
        opener.command = ["sh", "-c", thermals.script + " open >/dev/null 2>&1 &"]
        opener.running = true
    }

    // A number, or -1 when the script reported null - which JSON.parse turns
    // into null and arithmetic would turn into a silent 0. A GPU at 0 degrees
    // is a lie; -1 is an absence.
    function num(v): int {
        return (typeof v === "number" && !isNaN(v)) ? Math.round(v) : -1
    }

    Process {
        id: checker
        stdout: StdioCollector {
            onStreamFinished: {
                const line = (text || "").trim()
                if (!line) {
                    thermals.error = "no output from thermal.sh"
                    thermals.present = false
                    thermals.answered = true
                    return
                }
                try {
                    const j = JSON.parse(line)
                    thermals.present = !!j.ok
                    thermals.answered = true
                    thermals.gpuTemp = thermals.num(j.gpu_temp)
                    thermals.gpuUtil = thermals.num(j.gpu_util)
                    thermals.gpuPower = (typeof j.gpu_power === "number") ? j.gpu_power : -1
                    thermals.gpuClock = thermals.num(j.gpu_clock)
                    thermals.cpuTemp = thermals.num(j.cpu_temp)
                    thermals.fanRpm = thermals.num(j.fan)
                    thermals.error = ""
                } catch (e) {
                    thermals.error = "unparseable: " + line
                    thermals.present = false
                    thermals.answered = true
                }
            }
        }
    }

    Process { id: opener }

    Timer {
        interval: 5 * 1000
        repeat: true
        // Once it is known there is no card, stop asking: that answer cannot
        // change without a reboot, and a laptop should not spawn a process
        // every five seconds to be told so again.
        running: !thermals.answered || thermals.present
        onTriggered: thermals.check()
    }

    Component.onCompleted: thermals.check()
}
