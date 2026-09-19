// =========================================================================
// BatteryPanel - the numbers behind the glyph
// =========================================================================
//
// Three bands, in the order the questions get asked:
//
//   how full am I      the figure, what the machine is doing, and a gauge
//   how worn is it     health against design, with its own gauge
//   the details        cycles, draw, mains - as tiles, not a list
//
// GAUGES RATHER THAN MORE NUMBERS. A percentage tells you where you are; a
// bar tells you without being read, and the eye gets it before the words
// arrive. Both use the audio panel's track - 4px, dim at 40%, accent fill -
// because a second visual idiom for the same thing would be one too many.
//
// TILES RATHER THAN ROWS for the last band. Cycles, draw and mains are three
// unrelated facts of similar weight, and a label-on-the-left list makes the
// eye walk all three to find one. Side by side with the value above its
// name, any of them can be read on its own.
//
// THE CHARGE LIMIT GETS A SENTENCE, not a status word. "Not charging" is
// what the kernel says while this laptop sits plugged in at its 80% limit,
// and reading that on a panel you opened because you were worried is the
// wrong answer.
//
// TIME REMAINING IS OFTEN ABSENT, deliberately. It is charge over present
// draw, and while the limit holds that draw at a milliamp the answer comes
// out in months - 2610 hours, if asked naively. The line appears only while
// genuinely discharging.

import Quickshell
import QtQuick

DropPanel {
    id: root

    layerNamespace: "quickshell-battery"
    panelWidth: 320

    readonly property color chargeColor: (Battery.critical || Battery.low)
                                         ? Theme.danger : Theme.accent

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
        return whole <= 0 ? mins + " min"
                          : whole + " h " + (mins < 10 ? "0" : "") + mins + " m"
    }

    Column {
        width: parent.width

        // ---- band one: charge ------------------------------------------------

        Item {
            width: parent.width
            height: 92

            Text {
                id: bigGlyph
                anchors { left: parent.left; leftMargin: 16; top: parent.top; topMargin: 16 }
                text: Battery.charging ? "\u{F0084}" : "\u{F0079}"
                font.family: Theme.glyphFont
                font.pixelSize: 22
                color: root.chargeColor
                Behavior on color { ColorAnimation { duration: Theme.animNormal } }
            }

            Text {
                id: bigNumber
                anchors { left: bigGlyph.right; leftMargin: 10; verticalCenter: bigGlyph.verticalCenter }
                text: Battery.ready ? Battery.percent + "%" : "--"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSizeDisplay
                font.weight: Theme.weightSemi
                font.letterSpacing: Theme.trackingTight
            }

            Text {
                anchors {
                    right: parent.right; rightMargin: 16
                    verticalCenter: bigGlyph.verticalCenter
                }
                width: parent.width - bigNumber.x - bigNumber.width - 28
                horizontalAlignment: Text.AlignRight
                text: {
                    const t = root.hoursText(Battery.hoursLeft)
                    return t !== "" ? root.headline + "\n" + t + " left" : root.headline
                }
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSizeSmall
                lineHeight: 1.3
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 2
            }

            // The gauge. Ends flush with the text above it on both sides so
            // the band reads as one block rather than a bar with captions.
            Rectangle {
                anchors {
                    left: parent.left; leftMargin: 16
                    right: parent.right; rightMargin: 16
                    bottom: parent.bottom; bottomMargin: 18
                }
                height: 4
                radius: 2
                color: Qt.rgba(Theme.dim.r, Theme.dim.g, Theme.dim.b, 0.4)

                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    width: parent.width * Math.max(0, Math.min(1, Battery.percent / 100))
                    color: root.chargeColor
                    Behavior on width { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: Theme.animNormal } }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.outline }

        // ---- band two: wear --------------------------------------------------

        Item {
            width: parent.width
            height: 62
            visible: Battery.healthPercent > 0

            Text {
                id: healthLabel
                anchors { left: parent.left; leftMargin: 16; top: parent.top; topMargin: 14 }
                text: "Health"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }

            Text {
                anchors { right: parent.right; rightMargin: 16; verticalCenter: healthLabel.verticalCenter }
                text: Battery.healthPercent + "% of design"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.weight: Theme.weightMedium
            }

            // Deliberately NOT the accent: health is a fixed property of the
            // pack, not a live level, and colouring it like the charge gauge
            // invites reading one as the other.
            Rectangle {
                anchors {
                    left: parent.left; leftMargin: 16
                    right: parent.right; rightMargin: 16
                    bottom: parent.bottom; bottomMargin: 16
                }
                height: 4
                radius: 2
                // A DARKER TRACK THAN THE CHARGE GAUGE'S, because this fill
                // is a neutral rather than the accent: at 0.4 against a fill
                // of 0.55 the two near-white tokens were within a hair of
                // each other and 91% read as 100%.
                color: Qt.rgba(Theme.dim.r, Theme.dim.g, Theme.dim.b, 0.22)

                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    width: parent.width * Math.max(0, Math.min(1, Battery.healthPercent / 100))
                    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.8)
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.outline
            visible: Battery.healthPercent > 0
        }

        // ---- band three: the rest, as tiles ----------------------------------

        Row {
            width: parent.width
            height: 64

            Repeater {
                model: [
                    { v: Battery.cycleCount > 0 ? String(Battery.cycleCount) : "-",
                      k: "cycles" },
                    { v: Battery.watts > 0.05 ? Battery.watts.toFixed(1) + " W" : "idle",
                      k: "draw" },
                    { v: Battery.onAc ? "Mains" : "Battery",
                      k: "power" }
                ]

                Item {
                    required property var modelData
                    required property int index

                    width: parent.width / 3
                    height: parent.height

                    // Hairlines between the tiles, not around them: a border
                    // would box three small things that belong to one band.
                    Rectangle {
                        visible: index > 0
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom
                                  topMargin: 14; bottomMargin: 14 }
                        width: 1
                        color: Theme.outline
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: parent.parent.modelData.v
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSizeTitle
                            font.weight: Theme.weightMedium
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: parent.parent.modelData.k
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSizeSmall
                            font.letterSpacing: Theme.trackingLoose
                        }
                    }
                }
            }
        }

        // ---- per pack, only when there is more than one -----------------------

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
                height: 32

                Text {
                    anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                    text: parent.modelData.name
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSizeSmall
                }

                Text {
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    text: parent.modelData.percent + "%   "
                          + parent.modelData.health + "% health   "
                          + parent.modelData.cycles + " cycles"
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }
    }
}
