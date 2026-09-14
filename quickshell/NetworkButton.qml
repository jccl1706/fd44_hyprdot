// =========================================================================
// NetworkButton - the network glyph in the bar's right pill
// =========================================================================
//
// Opens NetworkPanel. Built the same way as AudioButton: it draws, and
// Bar.qml handles the click (and the drag that moves it along the bar).
//
// WHAT IT SHOWS, in order of precedence:
//   wired and connected       the ethernet port
//   Wi-Fi connected           signal bars, one to four
//   not connected, Wi-Fi on   empty bars
//   not connected, Wi-Fi off  struck-through bars
// Ethernet wins when both are up, because that is the route traffic takes.
//
// Red when the machine is offline - nothing connected and nothing trying to
// connect - the same "something is off" red as the muted speaker beside it.

import Quickshell
import Quickshell.Networking
import QtQuick

Item {
    id: root

    // Same footprint as AudioButton, so the two glyphs read as a pair.
    implicitWidth: 22
    implicitHeight: 22

    readonly property var devices: Networking.devices.values

    readonly property bool wired: devices.some(d => d.type === DeviceType.Wired && d.connected)

    readonly property var wifiDevice: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property bool wifiConnected: wifiDevice?.connected ?? false

    // The connected network carries the signal strength. It may be missing
    // from the list while nothing is scanning; full bars are the honest
    // fallback for "connected, strength unknown".
    readonly property var wifiNetwork:
        wifiDevice ? (wifiDevice.networks.values.find(n => n.connected) ?? null) : null

    readonly property bool connecting: devices.some(d => d.state === ConnectionState.Connecting)

    // `devices` is empty for a moment at startup, before NetworkManager has
    // answered. That is "not known yet", not offline, so it stays neutral.
    readonly property bool offline: devices.length > 0 && !wired && !wifiConnected && !connecting

    readonly property string glyph: {
        if (wired) return "\u{F0200}"                            // nf-md-ethernet
        if (wifiConnected) {
            const s = wifiNetwork ? wifiNetwork.signalStrength : 1
            return s < 0.25 ? "\u{F091F}"                        // nf-md-wifi_strength_1
                 : s < 0.5  ? "\u{F0922}"                        // nf-md-wifi_strength_2
                 : s < 0.75 ? "\u{F0925}"                        // nf-md-wifi_strength_3
                            : "\u{F0928}"                        // nf-md-wifi_strength_4
        }
        if (Networking.wifiEnabled || devices.length === 0)
            return "\u{F092F}"                                   // nf-md-wifi_strength_outline
        return "\u{F092E}"                                       // nf-md-wifi_strength_off_outline
    }

    // Hover backdrop, behind the glyph so hovering never resizes the pill.
    Rectangle {
        anchors.centerIn: parent
        width: 22
        height: 22
        radius: width / 2
        color: Theme.surfaceHigh
        opacity: hover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    Text {
        anchors.centerIn: parent
        text: root.glyph
        font.family: Theme.glyphFont
        // 16, not AudioButton's 20: the Wi-Fi fan fills far more of its em box
        // than the speaker does. At 20 it measured 19.2 px wide beside the
        // speaker's 15.0 and read as the bigger icon. The ethernet port is a
        // filled shape and reads heavier still, which is fine: it is also the
        // state that least needs attention.
        font.pixelSize: 16
        color: root.offline     ? Theme.danger
             : hover.hovered    ? Theme.fg
                                : Theme.pluginIcon
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
}
