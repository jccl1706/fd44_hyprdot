// =========================================================================
// NetworkPanel - Ethernet status and Wi-Fi, sliding down out of the bar
// =========================================================================
//
// Opened by the network glyph in the bar's right pill (NetworkButton.qml).
// The card, scrim, slide and fillets are DropPanel.qml's; this is only what
// goes inside. Everything comes from Quickshell.Networking, which talks to
// NetworkManager over D-Bus - no nmcli processes.
//
// ETHERNET has a switch of its own now, per device. It was status only, on
// the reasoning that a misplaced click dropping the wired connection was
// worse than opening a terminal for the rare case of wanting to - and then
// the rare case turned up: a USB-C adapter plugged in beside live Wi-Fi,
// both connected, and no way from here to say which one should carry the
// traffic.
//
// TURNING IT OFF IS TWO OPERATIONS, not one. Disconnecting alone achieves
// nothing: the connection is set to autoconnect, so NetworkManager brings it
// straight back up and the switch appears to do nothing at all. Autoconnect
// is cleared first and the device disconnected after. Turning it back on
// takes two as well: autoconnect back on, and then an explicit connect
// through the device's connection profile, because NetworkManager remembers
// that the disconnect was asked for and will not undo it by itself.
//
// SO THE SWITCH TRACKS `autoconnect`, NOT `connected`. Those differ exactly
// when the cable is out: the device is off the network but nobody asked for
// it to be, and a switch that flipped itself when a cable was pulled would
// be reporting the wrong thing. It reads as "may this device be used", which
// is the same question the Wi-Fi switch above it answers.
//
// WI-FI has an on/off switch and the networks in range. Clicking a network
// opens it in place with what can be done to it:
//   new, password-protected   password field + Connect
//   new, open                 Connect
//   saved                     Connect, Forget
//   connected                 Disconnect, Forget
//   enterprise / WEP          a note - that needs more than a password
//
// SCANNING runs only while the panel is open. A scan every few seconds costs
// battery on the laptop, and nothing else wants the list.
//
// THE LIST HOLDS STILL while a network is open. It is sorted by signal, and
// signal wobbles from scan to scan; re-sorting would rebuild the rows and
// throw away a half-typed password.

import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick

DropPanel {
    id: root

    layerNamespace: "quickshell-network"


    // --- devices ---------------------------------------------------------

    readonly property var devices: Networking.devices.values
    readonly property var wiredDevices: devices.filter(d => d.type === DeviceType.Wired)


    onOpening: {
        wifiList.reset()
        addrProc.running = true
    }

    // --- addresses -----------------------------------------------------
    //
    // ASKED FOR, NOT SUBSCRIBED TO, because Quickshell's networking service
    // does not carry it. A device object has `address`, which is the MAC -
    // 0A:6F:71:D5:63:51 here, the locally-administered prefix showing wifi
    // MAC randomisation at work - and nothing for the assigned one.
    //
    // So `ip` is asked, once, when the panel opens. That is a fork, which
    // this shell avoids in the places that matter: a keypress, a pointer
    // move, a frame. Opening a panel is none of those, and the wifi scan
    // this same handler kicks off costs incomparably more.
    //
    // -j for JSON rather than parsing columns out of human output, which
    // changes between iproute2 versions and localises.

    property var addresses: ({})     // interface -> { v4, v6, prefix }
    property string gateway: ""

    Process {
        id: addrProc
        command: ["sh", "-c", "ip -j addr show; echo '---'; ip -j route show default"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = String(text).split("---")
                const map = {}
                try {
                    const links = JSON.parse(parts[0])
                    for (let i = 0; i < links.length; i++) {
                        const l = links[i]
                        if (l.ifname === "lo") continue
                        const info = l.addr_info || []
                        const v4 = info.find(a => a.family === "inet")
                        const v6 = info.find(a => a.family === "inet6" && a.scope === "global")
                        map[l.ifname] = {
                            v4: v4 ? v4.local : "",
                            prefix: v4 ? v4.prefixlen : 0,
                            v6: v6 ? v6.local : ""
                        }
                    }
                } catch (e) {
                    console.warn("network: could not parse ip addr:", e)
                }
                root.addresses = map

                let gw = ""
                try {
                    const routes = JSON.parse(parts[1] || "[]")
                    if (routes.length > 0) gw = String(routes[0].gateway || "")
                } catch (e) { }
                root.gateway = gw
            }
        }
    }

    // The interface actually carrying traffic: the wired one if it is up,
    // otherwise the wifi. Matches how the panel itself is ordered.
    readonly property var activeAddress: {
        const wired = root.wiredDevices.find(d => d.connected)
        // The wifi device lives on the list component now; this is the only
        // thing left up here that still needs it.
        const wifi = wifiList.wifiDevice
        const pick = wired ? wired : (wifi && wifi.connected ? wifi : null)
        if (!pick || !pick.name) return null
        const a = root.addresses[pick.name]
        return a ? { iface: pick.name, v4: a.v4, prefix: a.prefix, v6: a.v6 } : null
    }

    // Upload against the accent's download. term_color13 is the palette's
    // mauve; deliberately not Theme.danger, which this bar uses for things
    // that are wrong rather than for a second series on a chart.
    readonly property color upColour: Theme.palette.term_color13 || "#c061cb"

    // --- throughput --------------------------------------------------
    //
    // FROM /sys, NOT FROM A PROGRAM. The interface's byte counters are two
    // files; reading them is the same trick Battery.qml uses on the power
    // supply, and it means a graph that updates every second costs no
    // processes at all. The sway laptop's version of this card shells out to
    // a Python script once a second to get the same two numbers.
    //
    // ONLY WHILE THE PANEL IS OPEN. A rate needs two samples a known time
    // apart, so this is a poll rather than a subscription, and nothing reads
    // it while the card is shut.

    property real rxRate: 0          // bytes/second
    property real txRate: 0
    property var  rates: []          // [{rx, tx}], the last 60 seconds
    property var  lastSample: null   // { t, iface, rx, tx }

    readonly property string rateIface: root.activeAddress ? root.activeAddress.iface : ""

    FileView {
        id: rxFile
        path: root.rateIface !== "" ? "/sys/class/net/" + root.rateIface + "/statistics/rx_bytes" : ""
        printErrors: false
    }

    FileView {
        id: txFile
        path: root.rateIface !== "" ? "/sys/class/net/" + root.rateIface + "/statistics/tx_bytes" : ""
        printErrors: false
    }

    function counter(view): real {
        const t = String(view.text()).trim()
        if (t === "") return -1
        const v = parseFloat(t)
        return isNaN(v) ? -1 : v
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.revealed && root.rateIface !== ""
        onTriggered: {
            rxFile.reload()
            txFile.reload()
            const rx = root.counter(rxFile), tx = root.counter(txFile)
            if (rx < 0 || tx < 0) return
            const now = Date.now()
            const prev = root.lastSample
            // A DIFFERENT INTERFACE IS NOT A BURST OF TRAFFIC. Switching from
            // wifi to a cable swaps the counters for another card's, and the
            // difference between them is meaningless - and enormous.
            if (prev && prev.iface === root.rateIface && now > prev.t) {
                const dt = (now - prev.t) / 1000
                // Counters only climb; a drop means they were reset.
                root.rxRate = Math.max(0, (rx - prev.rx) / dt)
                root.txRate = Math.max(0, (tx - prev.tx) / dt)
                root.rates = root.rates.concat([{ rx: root.rxRate, tx: root.txRate }]).slice(-60)
            }
            root.lastSample = { t: now, iface: root.rateIface, rx: rx, tx: tx }
        }
    }

    function humanRate(b: real): string {
        const u = ["B", "kB", "MB", "GB"]
        let i = 0, v = b
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++ }
        return (i === 0 ? Math.round(v) : v.toFixed(1)) + " " + u[i] + "/s"
    }

    // Closing collapses the open network, which clears a half-typed password
    // (see row.onExpandedChanged) instead of leaving it in the hidden window.
    onClosing: wifiList.expanded = ""

    // Esc closes an opened network first, then the panel.
    onKeyPressed: event => {
        if (event.key === Qt.Key_Escape && wifiList.expanded !== "") {
            wifiList.expanded = ""
            root.focusCard()
            event.accepted = true
        }
    }


    function speedText(mbps: int): string {
        if (!mbps || mbps <= 0) return ""
        return mbps >= 1000 ? (mbps / 1000) + " Gb/s" : mbps + " Mb/s"
    }

    // --- contents --------------------------------------------------------

    Column {
        width: parent.width

        // --- ethernet -----------------------------------------------------

        Column {
            id: ethernet
            visible: root.wiredDevices.length > 0
            width: parent.width
            spacing: 2

            Text {
                leftPadding: 4
                height: 20
                verticalAlignment: Text.AlignVCenter
                text: "Ethernet"
                font.family: Theme.font
                font.weight: Theme.weightSemi
                font.pixelSize: Theme.fontSizeSmall
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.8
                color: Theme.dim
            }

            Repeater {
                model: root.wiredDevices

                delegate: Rectangle {
                    id: wiredRow

                    required property var modelData

                    readonly property bool connected: modelData.connected

                    width: ethernet.width
                    height: 44
                    radius: 8

                    // The same wash and marker as a current audio device.
                    color: wiredRow.connected
                           ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                           : "transparent"

                    Rectangle {
                        anchors { left: parent.left; leftMargin: 2
                                  verticalCenter: parent.verticalCenter }
                        width: 3
                        height: wiredRow.connected ? 18 : 0
                        radius: 1.5
                        color: Theme.accent
                    }

                    Text {
                        id: wiredGlyph
                        anchors { left: parent.left; leftMargin: 12
                                  verticalCenter: parent.verticalCenter }
                        width: 20
                        horizontalAlignment: Text.AlignHCenter
                        text: wiredRow.modelData.hasLink ? "\u{F0200}"   // nf-md-ethernet
                                                         : "\u{F0202}"   // nf-md-ethernet_cable_off
                        font.family: Theme.glyphFont
                        font.pixelSize: 16
                        color: wiredRow.connected ? Theme.accent : Theme.dim
                    }

                    ToggleSwitch {
                        id: wiredSwitch
                        anchors { right: parent.right; rightMargin: 10
                                  verticalCenter: parent.verticalCenter }
                        checked: wiredRow.modelData.autoconnect
                        // A device NetworkManager does not manage is not ours
                        // to switch - something else owns it.
                        interactive: wiredRow.modelData.nmManaged
                        onToggled: {
                            const d = wiredRow.modelData
                            if (d.autoconnect) {
                                // Order matters: clear autoconnect FIRST, or
                                // NetworkManager reconnects the device before
                                // the second call lands and the switch looks
                                // broken.
                                d.requestSetAutoconnect(false)
                                d.requestDisconnect()
                            } else {
                                // RESTORING AUTOCONNECT IS NOT ENOUGH.
                                // Measured: the device sat disconnected five
                                // seconds after autoconnect went back to
                                // true. NetworkManager remembers that the
                                // disconnect was asked for and will not
                                // bring the device up again by itself until
                                // something like a carrier bounce happens.
                                // The connection profile on the device has
                                // requestConnect(), which is the explicit
                                // ask - no nmcli fork needed for it.
                                d.requestSetAutoconnect(true)
                                if (d.network) d.network.requestConnect()
                            }
                        }
                    }

                    Column {
                        anchors {
                            left: wiredGlyph.right; leftMargin: 10
                            right: wiredSwitch.left; rightMargin: 10
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 1

                        Text {
                            width: parent.width
                            text: !wiredRow.modelData.autoconnect ? "Turned off"
                                : wiredRow.connected ? "Connected"
                                : wiredRow.modelData.state === ConnectionState.Connecting ? "Connecting…"
                                : wiredRow.modelData.hasLink ? "Not connected"
                                : "Cable unplugged"
                            font.family: Theme.font
                            font.weight: wiredRow.connected ? Theme.weightSemi : Theme.weightMedium
                            font.pixelSize: Theme.fontSize
                            color: Theme.fg
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: [wiredRow.modelData.name,
                                   wiredRow.connected ? root.speedText(wiredRow.modelData.linkSpeed) : ""]
                                  .filter(s => s).join("  ·  ")
                            font.family: Theme.font
                            font.weight: Theme.weightNormal
                            font.pixelSize: Theme.fontSizeSmall
                            font.letterSpacing: Theme.trackingLoose
                            color: Theme.dim
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        Item {
            // The rule between the two sections, so it is there only when both
            // are. `wifi` used to be the Column that moved into NetworkList;
            // this asks the component the same question that Column asked.
            //
            // IT ONLY THREW ON THE DESKTOP. On a laptop with no wired device
            // ethernet.visible is false and && never evaluates the other half,
            // so the stale reference sat there silently until a machine with
            // ethernet loaded it.
            visible: ethernet.visible && wifiList.wifiDevice !== null
            width: parent.width
            height: 17
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 1
                color: Theme.dim
                opacity: 0.25
            }
        }

        // --- wi-fi --------------------------------------------------------

        // The Wi-Fi switch and the network list, shared with the settings
        // window - see NetworkList.qml.
        NetworkList {
            id: wifiList
            width: parent.width
            active: root.revealed
            // The dropdown takes the keyboard back when a row collapses.
            onNeedsFocus: root.focusCard()
        }


        Text {
            visible: root.devices.length === 0
            leftPadding: 4
            height: 36
            verticalAlignment: Text.AlignVCenter
            text: "No network devices"
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            color: Theme.dim
        }


        // --- throughput ------------------------------------------------
        //
        // Above the address and under the same rule, because both answer
        // "how is this connection doing" rather than "what can I join".

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.outline
            visible: root.activeAddress !== null
        }

        Item {
            width: parent.width
            height: 92
            visible: root.activeAddress !== null

            Row {
                id: rateRow
                anchors { left: parent.left; leftMargin: 4; top: parent.top; topMargin: 10 }
                spacing: 18

                Repeater {
                    model: [
                        { g: "\u{F0045}", label: "down", v: root.rxRate, c: Theme.accent },
                        { g: "\u{F005D}", label: "up",   v: root.txRate, c: root.upColour }
                    ]

                    Row {
                        required property var modelData
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.g
                            font.family: Theme.glyphFont
                            font.pixelSize: 13
                            color: parent.modelData.c
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.humanRate(parent.modelData.v)
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize
                            font.weight: Theme.weightMedium
                            font.features: ({ "tnum": 1 })
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.label
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSizeSmall
                            font.letterSpacing: Theme.trackingLoose
                        }
                    }
                }
            }

            Text {
                anchors { right: parent.right; rightMargin: 4
                          verticalCenter: rateRow.verticalCenter }
                text: "last 60s"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSizeSmall
            }

            Canvas {
                id: graph
                anchors { left: parent.left; leftMargin: 4
                          right: parent.right; rightMargin: 4
                          bottom: parent.bottom; bottomMargin: 10 }
                height: 46

                readonly property var pts: root.rates
                onPtsChanged: requestPaint()

                onPaint: {
                    const g = getContext("2d")
                    g.reset()
                    const pts = graph.pts
                    if (pts.length < 2) return

                    // A FLOOR ON THE SCALE, or an idle link draws its own noise as
                    // mountains: a few hundred bytes of background chatter fills
                    // the whole height when the maximum is a few hundred bytes.
                    let max = 16 * 1024
                    for (const p of pts) max = Math.max(max, p.rx, p.tx)

                    const X = i => graph.width - (pts.length - 1 - i) * (graph.width / 59)
                    const Y = v => graph.height - 1 - (graph.height - 2) * (v / max)

                    function trace(key, colour, fillAlpha) {
                        g.beginPath()
                        g.moveTo(X(0), Y(pts[0][key]))
                        for (let i = 1; i < pts.length; i++) g.lineTo(X(i), Y(pts[i][key]))
                        g.strokeStyle = colour
                        g.lineWidth = 1.5
                        g.lineJoin = "round"
                        g.stroke()
                        g.lineTo(X(pts.length - 1), graph.height)
                        g.lineTo(X(0), graph.height)
                        g.closePath()
                        g.fillStyle = Qt.rgba(colour.r, colour.g, colour.b, fillAlpha)
                        g.fill()
                    }

                    trace("rx", Theme.accent, 0.16)
                    trace("tx", root.upColour, 0.10)
                }
            }
        }

        // --- this machine's address ------------------------------------
        //
        // At the foot, under a rule, because it answers a different question
        // from everything above it: those are "what can I join", this is
        // "where am I". Small and dim - it is looked up occasionally and
        // read once, not scanned.

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.outline
            visible: root.activeAddress !== null
        }

        Item {
            width: parent.width
            // 56 rather than 46: two lines of type want more than the card's
            // own padding underneath them, or the gateway sits on the edge.
            height: 56
            visible: root.activeAddress !== null

            Column {
                anchors {
                    left: parent.left; leftMargin: 4
                    right: parent.right; rightMargin: 4
                    verticalCenter: parent.verticalCenter
                }
                spacing: 4

                Row {
                    width: parent.width
                    spacing: 6

                    Text {
                        anchors.baseline: parent.children[1].baseline
                        text: root.activeAddress ? root.activeAddress.iface : ""
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    Text {
                        text: root.activeAddress && root.activeAddress.v4 !== ""
                              ? root.activeAddress.v4 + "/" + root.activeAddress.prefix
                              : "no address"
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        font.weight: Theme.weightMedium
                    }
                }

                Text {
                    width: parent.width
                    text: root.gateway !== "" ? "via " + root.gateway : ""
                    visible: text !== ""
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideRight
                }
            }
        }
    }
}
