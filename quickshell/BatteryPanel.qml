// =========================================================================
// BatteryPanel - the numbers behind the glyph
// =========================================================================
//
// Four bands, in the order the questions get asked:
//
//   how full am I    the ring, what the machine is doing, and how long for
//   how worn is it   health against design, with its own gauge
//   the rest         cycles, draw, voltage, mains - as tiles, not a list
//   per pack         only on a machine with more than one battery
//
// A RING RATHER THAN A BAR for the charge, which is the one thing taken from
// the sway laptop's version of this panel: a circle reads as a level without
// being parsed, and it leaves the middle free for the figure. The health
// gauge below it stays linear on purpose - two rings would invite reading one
// as the other, and only one of these is a live level.
//
// COLOUR ONLY WHEN SOMETHING IS WRONG, which is the rule BatteryButton.qml
// states and the whole bar follows. The ring is the accent while things are
// ordinary - charging and the 80% hold are both ordinary - and danger only
// when genuinely low on battery charge. An earlier draft of this panel tinted
// each tile by category, which put the critical colour on "power draw" while
// it read "idle": a panel opened because you were worried should not wear the
// alarm colour on its calmest fact.
//
// HEALTH IS DELIBERATELY NOT THE ACCENT, for the same reason, and its track
// is darker than the charge track's: at 0.4 against a fill of 0.8 the two
// near-white tokens were within a hair of each other and 91% read as 100%.
//
// TILES RATHER THAN ROWS for the third band. Four unrelated facts of similar
// weight, and a label-on-the-left list makes the eye walk all four to find
// one. Side by side with the value above its name, any of them reads alone.
//
// THE PER-PACK CARDS APPEAR ONLY ON A TWO-PACK MACHINE, which is the whole
// reason they exist: there the bands above are the pair and each card is one
// of them. On a single-battery laptop the card restated the panel - charge,
// status, health and draw each appeared twice - so it is not drawn at all.
// The T480 this config also runs on has two; this one has one.
//
// TIME REMAINING IS OFTEN ABSENT, deliberately. It is charge over present
// draw, and while the charge limit holds that draw at a milliamp the answer
// comes out in months - 2610 hours, if asked naively. The line appears only
// while genuinely discharging; otherwise the panel says what it is plugged
// into instead.
//
// THE CHARGE LIMIT GETS A SENTENCE, not a status word. "Not charging" is what
// the kernel says while this laptop sits plugged in at its 80% limit, and
// reading that on a panel you opened because you were worried is the wrong
// answer.

import Quickshell
import QtQuick

DropPanel {
    id: root

    layerNamespace: "quickshell-battery"
    // 340 rather than the ring panel's 380: without the tinted chips, the
    // widest row is the ring beside its status, which does not need 380.
    panelWidth: 340

    // ONE COLOUR WITH A MEANING, as the flat panel has it: the accent while
    // things are ordinary - charging and the 80% hold are both ordinary - and
    // danger only when genuinely low on battery.
    readonly property color chargeColor: (Battery.critical || Battery.low)
                                         ? Theme.danger : Theme.accent

    function tint(c, a): color { return Qt.rgba(c.r, c.g, c.b, a) }

    readonly property string headline: {
        if (!Battery.ready)    return "Reading"
        if (Battery.charging)  return "Charging"
        if (Battery.full)      return "Full"
        if (Battery.limited)   return "At charge limit"
        if (Battery.onAc)      return "On mains"
        return "On battery"
    }

    // Time remaining when there is an honest one, otherwise what it is
    // plugged into. Never a figure derived from a draw of nothing: at the
    // charge limit this machine draws a milliamp, and that asks naively for
    // an answer in months.
    readonly property string bigLine: {
        if (!Battery.ready) return "..."
        const h = Battery.hoursLeft
        if (h > 0) {
            const whole = Math.floor(h)
            const mins = Math.round((h - whole) * 60)
            const t = whole <= 0 ? mins + "m" : whole + "h " + (mins < 10 ? "0" : "") + mins + "m"
            return t + (Battery.charging ? " to full" : " left")
        }
        return Battery.onAc ? "On AC power" : "—"
    }

    Column {
        id: stack
        width: parent.width
        topPadding: 14
        spacing: 0

        // ---- band one: the ring, and what it means ------------------------

        Row {
            x: 16
            width: parent.width - 32
            height: 104
            spacing: 16

            Item {
                width: 88
                height: 88
                anchors.verticalCenter: parent.verticalCenter

                Canvas {
                    id: ring
                    anchors.fill: parent
                    readonly property real p: Battery.ready ? Battery.percent / 100 : 0
                    readonly property color c: root.chargeColor
                    // The flat panel's charge track, at the same 0.4: this is
                    // the same gauge in a different shape, not a new idiom.
                    readonly property color track: root.tint(Theme.dim, 0.4)
                    onPChanged: requestPaint()
                    onCChanged: requestPaint()
                    onTrackChanged: requestPaint()
                    onPaint: {
                        const g = getContext("2d")
                        g.reset()
                        const r = width / 2 - 5
                        g.lineWidth = 9
                        g.lineCap = "round"
                        g.strokeStyle = ring.track
                        g.beginPath()
                        g.arc(width / 2, height / 2, r, 0, 2 * Math.PI)
                        g.stroke()
                        // From twelve, clockwise: a ring that starts at three
                        // reads as a pie chart.
                        g.strokeStyle = ring.c
                        g.beginPath()
                        g.arc(width / 2, height / 2, r, -Math.PI / 2,
                              -Math.PI / 2 + 2 * Math.PI * ring.p)
                        g.stroke()
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Battery.ready ? Battery.percent + "%" : "--"
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: 21
                        font.weight: Theme.weightSemi
                        font.letterSpacing: Theme.trackingTight
                        // Fixed-width figures, so the ring does not twitch as
                        // the number changes.
                        font.features: ({ "tnum": 1 })
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Battery.charging ? "\u{F0084}" : "\u{F0079}"
                        color: root.chargeColor
                        font.family: Theme.glyphFont
                        font.pixelSize: 13
                        Behavior on color { ColorAnimation { duration: Theme.animNormal } }
                    }
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Text {
                    text: root.headline
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Theme.weightSemi
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1
                }

                Text {
                    text: root.bigLine
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 19
                    font.weight: Theme.weightSemi
                    font.letterSpacing: Theme.trackingTight
                }

                // The one thing the ring panel said that no panel here said
                // before. Hidden rather than drawn as "0.0 of 0.0 Wh" on a
                // machine whose packs report neither energy nor voltage.
                Text {
                    visible: Battery.energyFullWh > 0
                    text: Battery.energyNowWh.toFixed(1) + " of "
                          + Battery.energyFullWh.toFixed(1) + " Wh"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.outline }

        // ---- band two: wear ------------------------------------------------
        //
        // Kept from the flat panel, including its colour reasoning: health is
        // a fixed property of the pack, not a live level, so it is deliberately
        // NOT the accent - colouring it like the charge ring invites reading
        // one as the other.

        Item {
            width: parent.width
            height: 58
            visible: Battery.healthPercent > 0

            Text {
                id: healthLabel
                anchors { left: parent.left; leftMargin: 16; top: parent.top; topMargin: 12 }
                text: "Health"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }

            Text {
                anchors { right: parent.right; rightMargin: 16
                          verticalCenter: healthLabel.verticalCenter }
                text: Battery.healthPercent + "% of design"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.weight: Theme.weightMedium
            }

            Rectangle {
                anchors { left: parent.left; leftMargin: 16
                          right: parent.right; rightMargin: 16
                          bottom: parent.bottom; bottomMargin: 14 }
                height: 4
                radius: 2
                // Darker than the charge track, because this fill is a neutral
                // rather than the accent: at 0.4 against a fill of 0.8 the two
                // near-white tokens were within a hair of each other and 91%
                // read as 100%.
                color: root.tint(Theme.dim, 0.22)

                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    width: parent.width * Math.max(0, Math.min(1, Battery.healthPercent / 100))
                    color: root.tint(Theme.fg, 0.8)
                }
            }
        }

        Rectangle {
            width: parent.width; height: 1; color: Theme.outline
            visible: Battery.healthPercent > 0
        }

        // ---- band three: the rest, as tiles ---------------------------------
        //
        // The flat panel's tiles, with voltage added - four unrelated facts of
        // similar weight, side by side so any one can be read on its own
        // instead of walking a list of labels to find it.

        Row {
            width: parent.width
            height: 60

            Repeater {
                model: [
                    { v: Battery.cycleCount > 0 ? String(Battery.cycleCount) : "—",
                      k: "cycles" },
                    { v: Battery.watts > 0.05 ? Battery.watts.toFixed(1) + " W" : "idle",
                      k: "draw" },
                    { v: Battery.details.length > 0 && Battery.details[0].volts > 0
                         ? Battery.details[0].volts.toFixed(1) + " V" : "—",
                      k: "voltage" },
                    { v: !Battery.acKnown ? "—" : Battery.onAc ? "Mains" : "Battery",
                      k: "power" }
                ]

                Item {
                    required property var modelData
                    required property int index

                    width: parent.width / 4
                    height: parent.height

                    // Hairlines between the tiles, not around them: a border
                    // would box four small things that belong to one band.
                    Rectangle {
                        visible: parent.index > 0
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom
                                  topMargin: 13; bottomMargin: 13 }
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
                            font.features: ({ "tnum": 1 })
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

        // ---- per pack, only when there is more than one ---------------------
        //
        // Where the sway laptop's sub-card belongs: on its own two-pack
        // machine, where the ring is the pair and each card is one of them.
        // On a single-pack laptop every line of it would already be above.

        Rectangle {
            width: parent.width; height: 1; color: Theme.outline
            visible: Battery.details.length > 1
        }

        Item {
            width: parent.width
            height: packs.implicitHeight + 14
            visible: Battery.details.length > 1

            Column {
                id: packs
                y: 14
                x: 16
                width: parent.width - 32
                spacing: 8

                Repeater {
                    model: Battery.details.length > 1 ? Battery.details : []

                    Rectangle {
                        id: pack
                        required property var modelData
                        readonly property var b: modelData

                        width: packs.width
                        height: packCol.implicitHeight + 22
                        radius: 14
                        color: root.tint(Theme.surfaceHigh, 0.55)

                        Column {
                            id: packCol
                            x: 11; y: 11
                            width: parent.width - 22
                            spacing: 7

                            Item {
                                width: parent.width
                                height: 18

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pack.b.name
                                    color: Theme.fg
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSizeTitle
                                    font.weight: Theme.weightSemi
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    // Joined only where there is something to
                                    // join: model_name is absent on many packs.
                                    text: [pack.b.maker, pack.b.model].filter(s => s !== "").join(" ")
                                          + (pack.b.tech !== "" ? " · " + pack.b.tech : "")
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideRight
                                    width: Math.min(implicitWidth, parent.width * 0.62)
                                    horizontalAlignment: Text.AlignRight
                                }
                            }

                            Gauge {
                                label: "Charge"
                                value: pack.b.percent
                                fill: root.chargeColor
                                detail: pack.b.percent + "%  ·  " + pack.b.status
                            }

                            Gauge {
                                label: "Health"
                                value: pack.b.health
                                fill: root.tint(Theme.fg, 0.8)
                                detail: pack.b.health > 0
                                        ? pack.b.energyFull.toFixed(1) + " of "
                                          + pack.b.energyDesign.toFixed(1) + " Wh new"
                                        : "—"
                            }

                            Row {
                                width: parent.width
                                readonly property int cell: width / 3

                                Mini { w: parent.cell; label: "cycles"
                                       value: pack.b.cycles > 0 ? String(pack.b.cycles) : "—" }
                                Mini { w: parent.cell; label: "draw"
                                       value: pack.b.watts > 0.05 ? pack.b.watts.toFixed(1) + " W" : "idle" }
                                Mini { w: parent.cell; label: "energy"
                                       value: pack.b.energyNow > 0 ? pack.b.energyNow.toFixed(1) + " Wh" : "—" }
                            }
                        }
                    }
                }
            }
        }

        // The panel's own bottom padding. DropPanel adds its card padding
        // around this, so this is only what the last band needs under it.
        Item { width: 1; height: 14 }
    }

    // --- the two repeated shapes -------------------------------------------

    component Gauge: Column {
        id: gauge
        property string label
        property real value
        property color fill: Theme.accent
        property string detail

        width: parent ? parent.width : 280
        spacing: 4

        Item {
            width: parent.width
            height: 13

            Text {
                text: gauge.label
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSizeSmall
            }

            Text {
                anchors.right: parent.right
                text: gauge.detail
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        Rectangle {
            width: parent.width
            height: 4
            radius: 2
            color: root.tint(Theme.dim, 0.22)

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, gauge.value / 100))
                height: parent.height
                radius: parent.radius
                color: gauge.fill
                Behavior on width { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: Theme.animNormal } }
            }
        }
    }

    component Mini: Column {
        id: mini
        property int w: 90
        property string label
        property string value

        width: mini.w
        spacing: 1

        Text {
            text: mini.value
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            font.weight: Theme.weightMedium
            font.features: ({ "tnum": 1 })
            elide: Text.ElideRight
            width: parent.width
        }

        Text {
            text: mini.label
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSizeSmall
            font.letterSpacing: Theme.trackingLoose
        }
    }
}
