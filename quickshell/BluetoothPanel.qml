// =========================================================================
// BluetoothPanel - the adapter, and the devices it already knows
// =========================================================================
//
// Opened by the Bluetooth glyph in the bar's right pill (BluetoothButton.qml).
// The card, scrim, slide and fillets are DropPanel.qml's; this is only what
// goes inside. Everything comes from bin/bluetooth.sh - see Bluetooth.qml for
// why that rather than Quickshell.Bluetooth.
//
// PAIRED DEVICES ONLY, AND NO SCANNING. A scan turns up every lock, doorbell,
// television and LED strip in the building - twenty-six of them the first time
// this was run here - and none of it belongs in a list whose every row is a
// connect button. Pairing is also the one Bluetooth operation that is
// occasionally interactive: a PIN, a confirmation, a device held in the right
// mode. A panel that offered it would have to handle all of that or lie about
// it, so it does not offer it and says where to do it instead.
//
// A ROW IS A SWITCH, not a menu: connected devices disconnect, disconnected
// ones connect. That is the whole daily operation.
//
// CONNECTING IS SLOW AND SAYS SO. A headset asleep in its case takes several
// seconds to answer, and a row that does nothing visible for that long reads as
// a click that missed - so the row it is working on says "connecting...".

import Quickshell
import QtQuick

DropPanel {
    id: root

    layerNamespace: "quickshell-bluetooth"
    panelWidth: 360

    // Both, because the glyph only needs the summary and this needs the list.
    onOpening: {
        Bluetooth.check()
        Bluetooth.refreshDevices()
    }

    // bluez names an icon for every device it knows - audio-headset, input-mouse,
    // phone - so the row draws what the thing IS rather than guessing from its
    // name, which is whatever its owner typed into a phone once.
    function glyphFor(icon: string): string {
        switch (icon) {
        case "audio-headset":
        case "audio-headphones": return "\u{F02CB}"   // nf-md-headphones
        case "audio-card":       return "\u{F04C3}"   // nf-md-speaker
        case "input-mouse":      return "\u{F037D}"   // nf-md-mouse
        case "input-keyboard":   return "\u{F030C}"   // nf-md-keyboard
        case "input-gaming":     return "\u{F0297}"   // nf-md-gamepad_variant
        case "phone":            return "\u{F011C}"   // nf-md-cellphone
        case "computer":         return "\u{F0322}"   // nf-md-laptop
        default:                 return "\u{F00AF}"   // nf-md-bluetooth
        }
    }

    Column {
        width: parent.width
        spacing: 0

        // --- the adapter -------------------------------------------------

        Item {
            width: parent.width
            height: 44

            Text {
                anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                text: "Bluetooth"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSizeTitle
                font.weight: Theme.weightSemi
            }

            ToggleSwitch {
                anchors { right: parent.right; rightMargin: 16
                          verticalCenter: parent.verticalCenter }
                checked: Bluetooth.powered
                onToggled: Bluetooth.setPowered(!Bluetooth.powered)
            }
        }

        // --- what it knows -------------------------------------------------

        Text {
            x: 16
            width: parent.width - 32
            visible: Bluetooth.powered && Bluetooth.devices.length === 0
            text: "Nothing paired yet"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSizeSmall
            bottomPadding: 10
        }

        Text {
            x: 16
            width: parent.width - 32
            visible: !Bluetooth.powered
            text: "The adapter is switched off"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSizeSmall
            bottomPadding: 10
        }

        Repeater {
            model: Bluetooth.powered ? Bluetooth.devices : []

            delegate: Rectangle {
                id: row

                required property var modelData

                readonly property bool connected: !!row.modelData.connected
                readonly property bool busy: Bluetooth.busyMac === row.modelData.mac

                width: root.panelWidth - 20
                x: 10
                height: 46
                radius: 8
                // The same accent wash the network rows use for "this is the
                // one in use", so the two panels read the same way.
                color: row.connected
                       ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                       : rowHover.hovered ? Theme.surfaceHigh : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                Text {
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    text: root.glyphFor(row.modelData.icon || "")
                    font.family: Theme.glyphFont
                    font.pixelSize: 18
                    color: row.connected ? Theme.accent : Theme.dim
                }

                Column {
                    anchors { left: parent.left; leftMargin: 44; right: parent.right; rightMargin: 12
                              verticalCenter: parent.verticalCenter }
                    spacing: 1

                    Text {
                        width: parent.width
                        text: row.modelData.name || row.modelData.mac
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        font.weight: row.connected ? Theme.weightSemi : Theme.weightMedium
                    }

                    Text {
                        width: parent.width
                        // The battery is the reason to open this panel at all
                        // on a headset that reports one, so it goes where the
                        // eye already is rather than in a tooltip.
                        text: row.busy         ? "connecting..."
                            : row.connected    ? (row.modelData.battery >= 0
                                                  ? "connected · " + row.modelData.battery + "%"
                                                  : "connected")
                            : row.modelData.trusted ? "paired"
                                                    : "paired, not trusted"
                        elide: Text.ElideRight
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSizeSmall
                        font.letterSpacing: Theme.trackingLoose
                    }
                }

                HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }

                TapHandler {
                    onTapped: {
                        if (row.busy) return
                        if (row.connected) Bluetooth.disconnect(row.modelData.mac)
                        else               Bluetooth.connect(row.modelData.mac)
                    }
                }
            }
        }

        // --- where pairing happens -----------------------------------------

        Item { width: 1; height: 8 }

        Text {
            x: 16
            width: parent.width - 32
            wrapMode: Text.WordWrap
            text: "New devices are paired in a terminal:  bluetoothctl"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSizeSmall
            bottomPadding: 12
        }
    }
}
