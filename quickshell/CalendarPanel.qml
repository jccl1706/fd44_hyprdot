// =========================================================================
// CalendarPanel - the month, from the clock
// =========================================================================
//
// Material's date grid, in this desktop's palette: a month at a time, the
// weekday initials above it, today marked by a filled circle rather than by
// a colour on the number. Material does it that way because a coloured digit
// competes with the digits around it while a filled shape does not, and at
// 11px that difference decides whether today is findable at a glance.
//
// THE WEEK STARTS WHERE THE LOCALE SAYS. Qt.locale().firstDayOfWeek is
// Sunday here and Monday across most of Europe, and a calendar that starts
// on the wrong day is worse than no calendar - every date lands one column
// out and the error is quiet. The weekday initials come from the same
// locale, so they cannot disagree with the columns beneath them.
//
// ONLY THIS MONTH'S DAYS ARE DRAWN. Filling the leading and trailing cells
// with the neighbouring months is the other common choice, and it puts two
// answers to "what is the 3rd" on one grid. Blanks say "not this month"
// without needing to be read.

import Quickshell
import QtQuick

DropPanel {
    id: root

    layerNamespace: "quickshell-calendar"
    // 420. Seven columns at 57px each, which is what lets the day numbers
    // go up to 15px and still sit clear of their neighbours.
    panelWidth: 420

    // The month on display. Reset to today's whenever the panel opens, so
    // it never comes back showing a month you paged to a week ago.
    property int viewYear: 0
    property int viewMonth: 0

    // TODAY HAS TO KEEP UP WITH THE CLOCK. This was `new Date()`, which a QML
    // property binding evaluates ONCE - when the shell starts - so after
    // midnight the panel still circled yesterday and the line at the bottom
    // still read yesterday's date. A shell that is restarted every day hides
    // it; this one runs for weeks.
    //
    // onOpening already took a fresh date for the MONTH, which is why the
    // grid was right and only the highlight and the date line were wrong -
    // the two things that come from `today`.
    //
    // HOURS, NOT MINUTES. SystemClock ticks on the boundary, and the only
    // thing read from it here is which day it is, which changes on an hour
    // boundary and no other: 24 wakes a day instead of 1440 for the same
    // answer. Clock.qml asks for Minutes because it shows minutes.
    SystemClock {
        id: dayClock
        precision: SystemClock.Hours
    }

    readonly property date today: dayClock.date

    // Opened without a position - from IPC or a keybind rather than from a
    // click - it centres on the screen, which is where the clock is. The
    // bar's other panels default to the right edge because their glyphs live
    // there; this one's does not.
    function openUnderClock(): void {
        root.open(root.screen ? root.screen.width / 2 : -1)
    }

    function toggleUnderClock(): void {
        if (root.revealed) root.close()
        else root.openUnderClock()
    }

    onOpening: {
        const now = new Date()
        root.viewYear = now.getFullYear()
        root.viewMonth = now.getMonth()
    }

    readonly property var loc: Qt.locale()

    // 0 = Sunday. Qt's Locale.Sunday is 0 too, so no translation needed.
    readonly property int weekStart: root.loc.firstDayOfWeek

    readonly property var dayNames: {
        const out = []
        for (let i = 0; i < 7; i++) {
            const d = (root.weekStart + i) % 7
            // NarrowFormat is the single letter Material uses. Some locales
            // repeat letters across days - T for Tuesday and Thursday - and
            // that is the convention, not a bug.
            out.push(root.loc.dayName(d, Locale.NarrowFormat))
        }
        return out
    }

    // 0 for a blank, otherwise the day of the month - and only as many rows
    // as the month actually occupies.
    //
    // THIS USED TO BE A FIXED 42, so the panel never changed height as you
    // paged. It cost an empty row under most months: 42px of nothing between
    // the last week and the rule below it, which read as a mistake rather
    // than as stability. The card's height already follows its contents on a
    // curve, so a month that needs a sixth row grows into it smoothly.
    readonly property var cells: {
        const first = new Date(root.viewYear, root.viewMonth, 1)
        const lead = (first.getDay() - root.weekStart + 7) % 7
        const length = new Date(root.viewYear, root.viewMonth + 1, 0).getDate()
        const rows = Math.ceil((lead + length) / 7)
        const out = []
        for (let i = 0; i < rows * 7; i++) {
            const day = i - lead + 1
            out.push(day >= 1 && day <= length ? day : 0)
        }
        return out
    }

    function isToday(day): bool {
        return day > 0
            && day === root.today.getDate()
            && root.viewMonth === root.today.getMonth()
            && root.viewYear === root.today.getFullYear()
    }

    function step(months): void {
        let m = root.viewMonth + months
        let y = root.viewYear
        while (m < 0)  { m += 12; y-- }
        while (m > 11) { m -= 12; y++ }
        root.viewMonth = m
        root.viewYear = y
    }

    Column {
        width: parent.width
        spacing: 0

        // --- month, and the way through the year ---------------------------

        Item {
            width: parent.width
            height: 48

            Text {
                anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                text: root.loc.standaloneMonthName(root.viewMonth, Locale.LongFormat)
                      + " " + root.viewYear
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: 16
                font.weight: Theme.weightSemi
            }

            // Only once paged away from this month - otherwise it is a
            // button that does nothing.
            Text {
                id: backToToday
                anchors { right: arrows.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                visible: root.viewMonth !== root.today.getMonth()
                         || root.viewYear !== root.today.getFullYear()
                text: "Today"
                color: backHover.hovered ? Theme.fg : Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.weightMedium
                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                HoverHandler { id: backHover }
                TapHandler {
                    onTapped: {
                        root.viewYear = root.today.getFullYear()
                        root.viewMonth = root.today.getMonth()
                    }
                }
            }

            Row {
                id: arrows
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 2

                Repeater {
                    model: [{ g: "\u{F0141}", d: -1 }, { g: "\u{F0142}", d: 1 }]

                    Item {
                        required property var modelData
                        width: 28
                        height: 28

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Theme.fg
                            opacity: arrowHover.hovered ? 0.1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData.g
                            font.family: Theme.glyphFont
                            font.pixelSize: 16
                            color: arrowHover.hovered ? Theme.fg : Theme.dim
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        }

                        HoverHandler { id: arrowHover }
                        TapHandler { onTapped: root.step(parent.modelData.d) }
                    }
                }
            }
        }

        // --- weekday initials ----------------------------------------------

        Row {
            width: parent.width - 24
            x: 12
            height: 32

            Repeater {
                model: root.dayNames

                Item {
                    required property string modelData
                    width: parent.width / 7
                    height: parent.height

                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData
                        // Bigger, heavier and brighter than the usual
                        // caption. These are the column headings for
                        // everything under them, and at 12px medium in `dim`
                        // they sat quieter than the 15px numbers they label -
                        // the eye read the grid and skipped the key to it.
                        //
                        // `fg`, the same as the dates. A heading in the same
                        // ink as its column is what makes the two read as one
                        // table; the weight alone separates them, and the
                        // letterSpacing keeps single letters from looking
                        // like a word.
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: 14
                        font.weight: Theme.weightSemi
                        font.letterSpacing: Theme.trackingLoose
                    }
                }
            }
        }

        // --- the grid --------------------------------------------------------

        Grid {
            x: 12
            width: parent.width - 24
            columns: 7

            Repeater {
                model: root.cells

                Item {
                    required property int modelData
                    // From the Grid's own width, not from panelWidth: the
                    // card is panelWidth PLUS the frame thickness when it is
                    // docked to an edge, so the two disagree by 4px and the
                    // weekday initials stop sitting over their columns.
                    width: parent.width / 7
                    height: 44

                    // Today: a filled disc, not a coloured number.
                    Rectangle {
                        anchors.centerIn: parent
                        width: 38
                        height: 38
                        radius: width / 2
                        color: Theme.accent
                        visible: root.isToday(parent.modelData)
                    }

                    // Hover, for every real day. A blank cell is not a target.
                    Rectangle {
                        anchors.centerIn: parent
                        width: 38
                        height: 38
                        radius: width / 2
                        color: Theme.fg
                        opacity: dayHover.hovered && parent.modelData > 0
                                 && !root.isToday(parent.modelData) ? 0.08 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData > 0 ? parent.modelData : ""
                        color: root.isToday(parent.modelData) ? Theme.accentFg : Theme.fg
                        font.family: Theme.font
                        font.pixelSize: 15
                        font.weight: root.isToday(parent.modelData) ? Theme.weightSemi
                                                                    : Theme.weightNormal
                        font.features: { "tnum": 1 }
                    }

                    HoverHandler { id: dayHover; enabled: parent.modelData > 0 }
                }
            }
        }

        Item { width: 1; height: 4 }

        // --- today, spelled out ----------------------------------------------
        //
        // NO CLOCK HERE, and that is deliberate rather than an omission. A
        // large time in this panel sat a couple of centimetres under the
        // bar's own clock, which is what the panel drops from - two readings
        // of the same thing, one of them redundant by construction.
        //
        // The date is a different matter: the grid says which square today
        // is, and this says what today is, which is the other half of why
        // anyone opens a calendar.

        Rectangle { width: parent.width; height: 1; color: Theme.outline }

        Item {
            width: parent.width
            height: 40

            Text {
                anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                text: Qt.formatDateTime(root.today, "dddd d MMMM yyyy")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 13
            }
        }
    }
}
