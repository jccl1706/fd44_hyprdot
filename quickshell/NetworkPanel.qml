// =========================================================================
// NetworkPanel - Ethernet status and Wi-Fi, sliding down out of the bar
// =========================================================================
//
// Opened by the network glyph in the bar's right pill (NetworkButton.qml).
// The card, scrim, slide and fillets are DropPanel.qml's; this is only what
// goes inside. Everything comes from Quickshell.Networking, which talks to
// NetworkManager over D-Bus - no nmcli processes.
//
// ETHERNET is status only: connected, link speed, cable unplugged. There is
// deliberately nothing to click. A misplaced click that drops the wired
// connection is worse than having to open a terminal for the rare case of
// wanting to.
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

                    Column {
                        anchors {
                            left: wiredGlyph.right; leftMargin: 10
                            right: parent.right;    rightMargin: 10
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 1

                        Text {
                            width: parent.width
                            text: wiredRow.connected ? "Connected"
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
            visible: ethernet.visible && wifi.visible
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
