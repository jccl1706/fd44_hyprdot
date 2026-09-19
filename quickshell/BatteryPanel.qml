// =========================================================================
// BatteryPanel - the numbers behind the glyph
// =========================================================================
//
// Drops out of the battery icon, the same way audio and network drop out of
// theirs. The glyph in the bar answers "am I fine"; this answers the
// questions that need a number - how long, how worn, how many times round.
//
// THE CHARGE LIMIT GETS A SENTENCE, not a status word. "Not charging" is
// what the kernel says when this laptop is plugged in and holding at 80%,
// and reading that on a panel would worry anyone. It says what is actually
// happening instead.
//
// TIME REMAINING IS OFTEN ABSENT, deliberately. It is charge divided by the
// present draw, and while the charge limit holds that draw near zero the
// answer comes out in months. A missing row is better than a confident
// wrong one, so it appears only while genuinely discharging.

import Quickshell
import QtQuick

DropPanel {
    id: root

    layerNamespace: "quickshell-battery"
    panelWidth: 300

    // "Charging" and "Discharging" are the kernel's own words and fine. The
    // rest need saying properly.
    readonly property string headline: {
        if (!Battery.ready)    return "Reading..."
        if (Battery.charging)  return "Charging"
        if (Battery.full)      return "Full"
        if (Battery.limited)   return "Holding at charge limit"
        if (Battery.onAc)      return "On mains"
        return "On battery"
    }

    function hoursText(h): string {
        if (h <= 0) return ""
        const whole = Math.floor(h)
        const mins = Math.round((h - whole) * 60)
        if (whole <= 0) return mins + " min"
        return whole + " h " + (mins < 10 ? "0" : "") + mins + " m"
    }

    Column {
        width: parent.width
        spacing: 0

        // --- headline --------------------------------------------------------

        Item {
            width: parent.width
            height: 66

            Text {
                id: bigNumber
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: Battery.ready ? Battery.percent + "%" : "--"
                color: (Battery.critical || Battery.low) ? Theme.danger : Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSizeDisplay
                font.weight: Theme.weightSemi
                font.letterSpacing: Theme.trackingTight
            }

            Column {
                anchors {
                    left: bigNumber.right; leftMargin: 12
                    right: parent.right; rightMargin: 14
                    verticalCenter: parent.verticalCenter
                }
                spacing: 1

                Text {
                    width: parent.width
                    text: root.headline
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.weight: Theme.weightMedium
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: {
                        const t = root.hoursText(Battery.hoursLeft)
                        return t !== "" ? t + " remaining" : ""
                    }
                    visible: text !== ""
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideRight
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.outline }

        // --- the numbers ------------------------------------------------------

        Repeater {
            model: [
                { k: "Draw",   v: Battery.watts > 0.05 ? Battery.watts.toFixed(1) + " W" : "idle" },
                { k: "Health", v: Battery.healthPercent > 0 ? Battery.healthPercent + "% of design" : "-" },
                { k: "Cycles", v: Battery.cycleCount > 0 ? String(Battery.cycleCount) : "-" },
                { k: "Power",  v: Battery.onAc ? "Mains connected" : "On battery" }
            ]

            Item {
                required property var modelData
                width: parent.width
                height: 34

                Text {
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    text: parent.modelData.k
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }

                Text {
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: parent.modelData.v
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.weight: Theme.weightMedium
                }
            }
        }

        // --- per pack, only when there is more than one ------------------------
        //
        // The ThinkPad has two and they wear differently, so one combined
        // figure hides the one that is dying. On a single-battery machine
        // this section is simply not there.

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.outline
            visible: Battery.details.length > 1
        }

        Repeater {
            model: Battery.details.length > 1 ? Battery.details : []

            Item {
                required property var modelData
                width: parent.width
                height: 34

                Text {
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    text: parent.modelData.name
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSizeSmall
                }

                Text {
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: parent.modelData.percent + "%  -  "
                          + parent.modelData.health + "% health  -  "
                          + parent.modelData.cycles + " cycles"
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }
    }
}
