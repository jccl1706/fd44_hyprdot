// =========================================================================
// Bluetooth - the adapter, and what is connected to it
// =========================================================================
//
// A singleton like Updates, Backups and Thermals, and backed the same way: by
// a script in bin/ rather than by a QML service.
//
// WHY NOT Quickshell.Bluetooth. The module exists in quickshell 0.3.1 - the
// import resolves and the singleton carries defaultAdapter, adapters and
// devices - but measured on the Framework it reports defaultAdapter = null and
// zero adapters at the same moment bluetoothctl shows hci0 powered, paired and
// connected. An icon fed by that would be confidently wrong, which is worse
// than an icon fed by a fork every ten seconds.
//
// TEN SECONDS, AND IT COSTS ONE PROCESS. bluetoothctl answers in about 60ms
// here. Nothing about Bluetooth changes faster than a person can notice, and
// the panel refreshes on its own when it opens - so this is the "is anything
// connected" heartbeat, not a live feed.
//
// ABSENT ENTIRELY ON A MACHINE WITH NO ADAPTER, which is how it stays off a
// desktop that has none: `present` is false there and the button draws nothing.
// The same shape as the thermal readout, which is absent on the laptop.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: bt

    property bool present: false        // is there an adapter at all
    property bool powered: false        // is it switched on
    property int  connected: 0          // how many devices are connected
    property string name: ""            // the first connected device
    property string mac: ""
    property int  battery: -1           // -1 when the device does not report it
    property string error: ""

    // Distinct from `present`, and the difference is what stops a machine with
    // no adapter polling forever: "no adapter" and "not asked yet" both leave
    // present false, so the timer needs to tell them apart.
    property bool answered: false

    // The paired devices, for the panel. Empty until something asks.
    property var devices: []

    readonly property string script:
        "\"$(dirname \"$(readlink -f '" + Quickshell.shellDir + "')\")/bin/bluetooth.sh\""

    function check(): void {
        if (checker.running) return
        checker.command = ["sh", "-c", bt.script + " status"]
        checker.running = true
    }

    function refreshDevices(): void {
        if (lister.running) return
        lister.command = ["sh", "-c", bt.script + " devices"]
        lister.running = true
    }

    // The actions the panel offers. Each one answers with a fresh status, so
    // the glyph is right the moment the command returns rather than up to ten
    // seconds later.
    function connect(mac: string): void   { act("connect", mac) }
    function disconnect(mac: string): void { act("disconnect", mac) }
    function setPowered(on: bool): void    { act("power", on ? "on" : "off") }

    // Busy while a connect is in flight: a headset asleep in its case takes
    // several seconds to answer, and a row that does nothing visible for that
    // long reads as a click that missed.
    property string busyMac: ""

    function act(verb: string, arg: string): void {
        if (actor.running) return
        bt.busyMac = (verb === "connect" || verb === "disconnect") ? arg : ""
        actor.command = ["sh", "-c", bt.script + " " + verb + " '" + arg + "'"]
        actor.running = true
    }

    function apply(text: string): void {
        const line = (text || "").trim()
        if (!line) {
            bt.error = "no output from bluetooth.sh"
            bt.present = false
            bt.answered = true
            return
        }
        try {
            const j = JSON.parse(line)
            bt.present = !!j.present
            bt.powered = !!j.powered
            bt.connected = j.connected || 0
            bt.name = j.name || ""
            bt.mac = j.mac || ""
            bt.battery = (typeof j.battery === "number") ? j.battery : -1
            bt.error = j.error || ""
        } catch (e) {
            bt.error = "unparseable: " + line
            bt.present = false
        }
        bt.answered = true
    }

    Process {
        id: checker
        stdout: StdioCollector { onStreamFinished: bt.apply(text) }
    }

    Process {
        id: actor
        stdout: StdioCollector {
            onStreamFinished: {
                bt.busyMac = ""
                bt.apply(text)
                bt.refreshDevices()      // the row's state changed too
            }
        }
    }

    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    bt.devices = JSON.parse((text || "[]").trim() || "[]")
                } catch (e) {
                    bt.devices = []
                }
            }
        }
    }

    Timer {
        interval: 10 * 1000
        repeat: true
        // Once it is known there is no adapter, stop asking: that cannot change
        // without plugging one in, and a machine without Bluetooth should not
        // fork a process every ten seconds to be told so again.
        running: !bt.answered || bt.present
        onTriggered: bt.check()
    }

    Component.onCompleted: bt.check()
}
