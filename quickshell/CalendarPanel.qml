// =========================================================================
// CalendarPanel - the month, from the clock
// =========================================================================
//
// Four parts, in the order the questions get asked:
//
//   what is today    the date as a tile, beside the day it names
//   which month      the title, a way back to today, and the way through
//   the grid         ISO weeks down the left, weekends tinted, today filled
//
// Taken from the sway laptop's calendar, which is the design this is: a tile
// for today rather than a line of text under the grid, pill day cells, and a
// week-number column. What it replaced was flatter - no tile, no week
// numbers, blanks where the neighbouring months are - and the parts of that
// design worth keeping are kept and noted below.
//
// THE WEEK STARTS ON MONDAY, which does not follow the locale and is the
// price of the week-number column. ISO weeks run Monday to Sunday; this
// machine's en_US locale starts the week on Sunday, so every row would
// straddle two ISO weeks and the number beside it would be right for six
// cells and wrong for the seventh. Starting on Monday makes the row and the
// week the same object. Set weekStart to Qt.locale().firstDayOfWeek to follow
// the locale again, and drop the column if you do.
//
// NEIGHBOURING MONTHS ARE DRAWN, dimmed, where the previous panel left blanks
// - and that was a considered choice there, on the grounds that a filled
// leading cell puts two answers to "what is the 3rd" on one grid. It is a
// real trade and the dimming carries it: those days are pitched well below
// the in-month ones rather than just slightly under.
//
// COLOUR ONLY WHERE IT MEANS SOMETHING, which is the rule the rest of the bar
// follows. Today is the accent, filled, and it is the only saturated thing on
// the grid. The weekends are tinted because they are a different kind of day,
// and that tint is pulled almost half way to the foreground: at full strength
// this palette's warm tone shouted louder than today's disc, which defeats
// the point of marking today at all.
//
// HUES FROM THE PALETTE, not from the original's Catppuccin names, so the
// card follows bin/theme.sh like everything else: term_color13 for the mauve
// of the month title, term_color3 for the warm of the weekends. Deliberately
// NOT Theme.danger for those, which is this theme's nearest match to the
// original's peach and is also what the bar uses for a battery about to die.

import Quickshell
import QtQuick

DropPanel {
    id: root

    layerNamespace: "quickshell-calendar"
    // 380: the week column plus seven day cells wide enough to be round.
    panelWidth: 380

    readonly property color hueMauve: Theme.palette.term_color13 || "#c061cb"
    readonly property color hueWarm:  Theme.palette.term_color3  || "#f5c211"

    function tint(c, a): color { return Qt.rgba(c.r, c.g, c.b, a) }

    // Pulled toward the foreground, because the original's weekend colour is a
    // soft peach and the nearest thing this palette has is a saturated yellow.
    // At full strength it shouted louder than today's filled disc, which is
    // the one thing on the grid that should carry colour.
    function mix(a, b, t): color {
        return Qt.rgba(a.r + (b.r - a.r) * t,
                       a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, 1)
    }

    readonly property color weekendInk: root.mix(root.hueWarm, Theme.fg, 0.42)

    // --- when "now" is ------------------------------------------------------
    //
    // Both halves kept from the panel next door, because both were bugs there
    // first. HOURS, not minutes: the only thing read from this is which day it
    // is, which changes on an hour boundary and no other - 24 wakes a day
    // instead of 1440 for the same answer.
    SystemClock {
        id: dayClock
        precision: SystemClock.Hours
        onDateChanged: root.today = dayClock.date
    }

    // AND WRITTEN, NOT BOUND, because a binding on dayClock.date goes stale
    // across suspend: SystemClock arms a monotonic timer, which does not
    // advance while the machine sleeps, so a laptop that suspends at 21:29 and
    // wakes at 08:14 reads 21:xx YESTERDAY until the timer fires. Opening the
    // panel takes a fresh date, and opening is the only moment this is seen.
    property date today: new Date()

    property int viewYear: 0
    property int viewMonth: 0

    // HOW THIS PANEL IS OPENED, and it must keep these names: shell.qml calls
    // them by hand rather than open()/close(), because this is the one panel
    // whose glyph is not at the right-hand end of the bar. Opened without a
    // position it centres on the screen, which is where the clock is.
    function openUnderClock(): void {
        root.open(root.screen ? root.screen.width / 2 : -1)
    }

    function toggleUnderClock(): void {
        if (root.revealed) root.close()
        else root.openUnderClock()
    }

    onOpening: {
        const now = new Date()
        root.today = now
        root.viewYear = now.getFullYear()
        root.viewMonth = now.getMonth()
    }

    // 1 = Monday. Qt.locale().firstDayOfWeek here instead to follow the
    // locale, at the cost described at the top.
    readonly property int weekStart: 1

    readonly property var loc: Qt.locale()

    readonly property var dayNames: {
        const out = []
        for (let i = 0; i < 7; i++)
            out.push(root.loc.dayName((root.weekStart + i) % 7, Locale.ShortFormat).slice(0, 2))
        return out
    }

    // ISO 8601: the week containing the year's first Thursday is week 1. The
    // arithmetic is the standard one - step to the Thursday of this week, then
    // count weeks from the first of January.
    function isoWeek(d): int {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
        const day = t.getUTCDay() || 7
        t.setUTCDate(t.getUTCDate() + 4 - day)
        return Math.ceil(((t - Date.UTC(t.getUTCFullYear(), 0, 1)) / 86400000 + 1) / 7)
    }

    function dayOfYear(d): int {
        return Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate())
                         - new Date(d.getFullYear(), 0, 1)) / 86400000) + 1
    }

    // One entry per week on display: its ISO number, and its seven days. Built
    // whole rather than as a flat run of cells, so the week number and the row
    // it labels cannot drift apart.
    readonly property var weeks: {
        const first = new Date(root.viewYear, root.viewMonth, 1)
        const lead = (first.getDay() - root.weekStart + 7) % 7
        const length = new Date(root.viewYear, root.viewMonth + 1, 0).getDate()
        const rows = Math.ceil((lead + length) / 7)
        const out = []
        for (let r = 0; r < rows; r++) {
            const days = []
            for (let c = 0; c < 7; c++) {
                const d = new Date(root.viewYear, root.viewMonth, r * 7 + c - lead + 1)
                days.push({
                    n: d.getDate(),
                    inMonth: d.getMonth() === root.viewMonth,
                    // Saturday and Sunday, whatever column they landed in.
                    weekend: d.getDay() === 0 || d.getDay() === 6,
                    today: d.toDateString() === root.today.toDateString()
                })
            }
            out.push({
                week: root.isoWeek(new Date(root.viewYear, root.viewMonth, r * 7 - lead + 1)),
                days: days
            })
        }
        return out
    }

    function step(months): void {
        let m = root.viewMonth + months
        let y = root.viewYear
        while (m < 0)  { m += 12; y-- }
        while (m > 11) { m -= 12; y++ }
        root.viewMonth = m
        root.viewYear = y
    }

    readonly property bool onThisMonth: root.viewMonth === root.today.getMonth()
                                        && root.viewYear === root.today.getFullYear()

    function backToToday(): void {
        root.viewYear = root.today.getFullYear()
        root.viewMonth = root.today.getMonth()
    }

    Column {
        id: stack
        width: parent.width
        topPadding: 16
        spacing: 14

        // ---- today ---------------------------------------------------------

        Row {
            x: 16
            spacing: 14

            Rectangle {
                width: 64
                height: 64
                radius: 20
                color: root.tint(Theme.accent, 0.16)

                Column {
                    anchors.centerIn: parent
                    spacing: 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.loc.standaloneMonthName(root.today.getMonth(),
                                                           Locale.ShortFormat).toUpperCase()
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 10
                        font.weight: Theme.weightSemi
                        font.letterSpacing: 1
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.today.getDate()
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: 26
                        font.weight: Theme.weightSemi
                        font.letterSpacing: Theme.trackingTight
                        font.features: ({ "tnum": 1 })
                    }
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Text {
                    text: Qt.formatDate(root.today, "dddd")
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 18
                    font.weight: Theme.weightSemi
                    font.letterSpacing: Theme.trackingTight
                }

                Text {
                    text: Qt.formatDate(root.today, "d MMMM yyyy")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }

                Text {
                    text: "Week " + root.isoWeek(root.today)
                          + "  ·  day " + root.dayOfYear(root.today)
                    color: root.tint(Theme.dim, 0.75)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }

        // ---- the month, and the way through the year ------------------------

        Item {
            width: parent.width
            height: 30

            Text {
                anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                text: root.loc.standaloneMonthName(root.viewMonth, Locale.LongFormat)
                      + " " + root.viewYear
                color: root.hueMauve
                font.family: Theme.font
                font.pixelSize: 15
                font.weight: Theme.weightSemi
            }

            Row {
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                spacing: 4

                // Only once paged away - otherwise a button that does nothing.
                Rectangle {
                    visible: !root.onThisMonth
                    width: todayLabel.implicitWidth + 20
                    height: 28
                    radius: 14
                    color: todayHover.hovered ? Theme.accent : Theme.surfaceHigh
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        id: todayLabel
                        anchors.centerIn: parent
                        text: "Today"
                        color: todayHover.hovered ? Theme.accentFg : Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.weightSemi
                    }

                    HoverHandler { id: todayHover }
                    TapHandler { onTapped: root.backToToday() }
                }

                Repeater {
                    model: [{ g: "\u{F0141}", d: -1 }, { g: "\u{F0142}", d: 1 }]

                    Rectangle {
                        required property var modelData
                        width: 28
                        height: 28
                        radius: 14
                        color: arrowHover.hovered ? Theme.surfaceTop : Theme.surfaceHigh
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData.g
                            color: arrowHover.hovered ? Theme.fg : Theme.dim
                            font.family: Theme.glyphFont
                            font.pixelSize: 16
                        }

                        HoverHandler { id: arrowHover }
                        TapHandler { onTapped: root.step(parent.modelData.d) }
                    }
                }
            }
        }

        // ---- the grid --------------------------------------------------------

        Column {
            x: 16
            width: parent.width - 32
            spacing: 2

            // The week column is narrow on purpose: it labels the row, it is
            // not one of the seven.
            readonly property int weekW: 26
            readonly property int cellW: (width - weekW) / 7

            // Column headings.
            Row {
                width: parent.width
                height: 22

                Text {
                    width: parent.parent.weekW
                    height: parent.height
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "Wk"
                    color: root.tint(Theme.dim, 0.55)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Theme.weightSemi
                }

                Repeater {
                    model: root.dayNames

                    Text {
                        required property string modelData
                        required property int index
                        width: parent.parent.cellW
                        height: parent.height
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: modelData
                        // The last two columns are the weekend, because the
                        // week starts on Monday here.
                        color: index >= 5 ? root.weekendInk : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.weightSemi
                        font.letterSpacing: Theme.trackingLoose
                    }
                }
            }

            Repeater {
                model: root.weeks

                Row {
                    id: weekRow
                    required property var modelData
                    width: parent.width
                    height: 32
                    spacing: 0

                    Text {
                        width: weekRow.parent.weekW
                        height: parent.height
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: weekRow.modelData.week
                        color: root.tint(Theme.dim, 0.55)
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSizeSmall
                        font.features: ({ "tnum": 1 })
                    }

                    Repeater {
                        model: weekRow.modelData.days

                        Item {
                            id: cell
                            required property var modelData
                            width: weekRow.parent.cellW
                            height: 32

                            Rectangle {
                                anchors.centerIn: parent
                                width: Math.min(parent.width - 2, 34)
                                height: 30
                                radius: 15
                                color: cell.modelData.today ? Theme.accent
                                     : dayHover.hovered && cell.modelData.inMonth ? Theme.surfaceHigh
                                     : cell.modelData.weekend && cell.modelData.inMonth
                                       ? root.tint(root.hueWarm, 0.07)
                                     : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: cell.modelData.n
                                color: cell.modelData.today      ? Theme.accentFg
                                     : !cell.modelData.inMonth   ? root.tint(Theme.dim, 0.38)
                                     : cell.modelData.weekend    ? root.weekendInk
                                                                 : Theme.fg
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize
                                font.weight: cell.modelData.today ? Theme.weightSemi
                                                                  : Theme.weightNormal
                                font.features: ({ "tnum": 1 })
                            }

                            HoverHandler { id: dayHover; enabled: cell.modelData.inMonth }
                        }
                    }
                }
            }
        }

        Item { width: 1; height: 14 }

        // Scroll anywhere on the card to page the month, as the original does.
        // ON THE COLUMN, NOT ON THE PANEL: DropPanel is not an Item, so a
        // handler attached to it cannot fire - which is also what qs-check
        // reported about the arrow keys that used to be here. Keyboard paging
        // would need the focus item inside DropPanel and is not worth it; the
        // arrows and the wheel both work.
        WheelHandler {
            onWheel: event => root.step(event.angleDelta.y > 0 ? -1 : 1)
        }
    }
}
