// =========================================================================
// BluetoothPanel - the adapter, and the devices it already knows
// =========================================================================
//
// Opened by the Bluetooth glyph in the bar's right pill (BluetoothButton.qml).
// The card, scrim, slide and fillets are DropPanel.qml's; this is only what
// goes inside. Everything comes from bin/bluetooth.sh - see Bluetooth.qml for
// why that rather than Quickshell.Bluetooth.
//
// SCANNING IS OFF UNTIL ASKED FOR, AND STOPS BY ITSELF. This panel first shipped
// with no discovery at all, on the reasoning that a scan turns up every lock,
// doorbell, television and LED strip in the building - twenty-six of them the
// first time it ran here - and that none of that belongs in a list whose every
// row is a "pair with this" button.
//
// What that missed is the case that then happened: a headset dropped out of
// bluez entirely, and a panel listing only PAIRED devices showed an empty list
// and offered nothing at all - at exactly the moment something was needed. So
// discovery is here, but on a button rather than always: nothing scans while
// you are only turning a headset on, the list shows named devices only, and the
// scan stops after two minutes whatever anyone does with the panel.
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

    // Nothing should be scanning because a panel was left open behind something
    // else. The script's own timeout is the backstop; this is the manners.
    onClosing: if (Bluetooth.scanning) Bluetooth.stopScan()

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

        // --- finding something new -----------------------------------------

        Item { width: 1; height: 6 }

        Rectangle {
            width: root.panelWidth - 20
            x: 10
            height: 40
            radius: 8
            visible: Bluetooth.powered
            color: scanHover.hovered ? Theme.surfaceHigh : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.animFast } }

            Text {
                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                text: Bluetooth.scanning ? "\u{F00B3}" : "\u{F0349}"   // bluetooth searching / magnify
                font.family: Theme.glyphFont
                font.pixelSize: 18
                color: Bluetooth.scanning ? Theme.accent : Theme.dim
            }

            Text {
                anchors { left: parent.left; leftMargin: 44; verticalCenter: parent.verticalCenter }
                text: Bluetooth.scanning ? "Looking for devices..." : "Scan for devices"
                color: Bluetooth.scanning ? Theme.fg : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }

            HoverHandler { id: scanHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: Bluetooth.scanning ? Bluetooth.stopScan() : Bluetooth.startScan()
            }
        }

        // PUT THE THING IN PAIRING MODE. Every headset needs it and none of them
        // says so, and a panel that finds nothing is indistinguishable from one
        // that is broken - so the instruction is on screen while it looks.
        Text {
            x: 16
            width: parent.width - 32
            visible: Bluetooth.scanning && Bluetooth.discovered.length === 0
            wrapMode: Text.WordWrap
            text: "Hold the device's button until it flashes - it has to be in pairing mode to appear."
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSizeSmall
            topPadding: 4
            bottomPadding: 6
        }

        Repeater {
            model: Bluetooth.scanning ? Bluetooth.discovered : []

            delegate: Rectangle {
                id: found

                required property var modelData
                readonly property bool busy: Bluetooth.busyMac === found.modelData.mac

                width: root.panelWidth - 20
                x: 10
                height: 44
                radius: 8
                color: foundHover.hovered ? Theme.surfaceHigh : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                Text {
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    text: root.glyphFor(found.modelData.icon || "")
                    font.family: Theme.glyphFont
                    font.pixelSize: 18
                    color: Theme.dim
                }

                Column {
                    anchors { left: parent.left; leftMargin: 44; right: parent.right; rightMargin: 12
                              verticalCenter: parent.verticalCenter }
                    spacing: 1

                    Text {
                        width: parent.width
                        text: found.modelData.name || found.modelData.mac
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                    }
                    Text {
                        width: parent.width
                        text: found.busy ? "pairing..." : "tap to pair"
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSizeSmall
                        font.letterSpacing: Theme.trackingLoose
                    }
                }

                HoverHandler { id: foundHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: if (!found.busy) Bluetooth.pair(found.modelData.mac)
                }
            }
        }

        Item { width: 1; height: 6 }

        // A device that wants a PIN is still a terminal job, and saying so is
        // better than a row that fails without explaining itself.
        Text {
            x: 16
            width: parent.width - 32
            wrapMode: Text.WordWrap
            text: "A device that asks for a PIN needs bluetoothctl."
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSizeSmall
            bottomPadding: 12
        }
    }
}
