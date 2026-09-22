// =========================================================================
// SettingsPanel - one window for the things that can be changed
// =========================================================================
//
// A sidebar of sections on the left, their controls on the right, and a search
// that filters across both. The shape is modelled on Noctalia's settings
// panel, which is the same idea taken much further: a registry of descriptors
// rendered by a control factory, rather than a hand-built form per setting.
//
// IT RENDERS Settings.schema AND KNOWS NOTHING ELSE. No setting is named in
// this file. Adding one is an entry in Settings.qml and a property beside it;
// this picks it up with no edit here, which is the whole reason for a schema.
//
// A FULL-SCREEN SURFACE FOR A WINDOW-SIZED CARD, the same arrangement as
// Launcher.qml and for the same reason: click-outside-to-dismiss needs an
// "outside" to click, and a card-sized surface has none. The surface is
// genuinely unmapped when closed rather than transparent, or it would swallow
// every click on the desktop.

import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls

PanelWindow {
    id: root

    property var modelData
    screen: modelData

    property bool revealed: false

    // Which section the sidebar has selected.
    property int section: 0

    // Search text, debounced - see the Timer. Empty means "show the selected
    // section"; non-empty means "show matching rows from every section", which
    // is what makes search worth having in a panel with a sidebar.
    property string query: ""

    // THE WINDOW GROWS WITH THE SCREEN, THE TEXT DOES NOT.
    //
    // 980 was a fixed width, which is about two thirds of both laptops - they
    // are 1440 and 1536 logical pixels wide - and only 38% of the desktop's
    // 2560 at scale 1, where it read as a small floating dialog rather than a
    // settings window. The floor keeps both laptops exactly as they were; the
    // ceiling stops it swallowing an ultrawide.
    readonly property int cardWidth: Math.min(root.width - 120,
                                              Math.min(1280, Math.max(980, root.width * 0.55)))

    // ...and the rows inside are clamped separately, because a window that is
    // wider is not an invitation to set a subtitle across 1100 pixels. This is
    // the same split libadwaita makes between the window and its content
    // column. 860 is above what either laptop can give a row today, so this
    // only ever widens a page - the wallpaper grid included, which gains
    // thumbnails on the desktop rather than losing them.
    readonly property int rowMaxWidth: 860
    // 690, NOT 600, and the wallpaper grid is why. Four rows of thumbnails at
    // this card's width come to ~476px, and with the search bar, the theme row
    // and the grid's own label above them the old 600 clipped the fourth row
    // to a sliver - the grid scrolled, so nothing was unreachable, but "four
    // across and four down" is the point of it and it only showed three and a
    // bit. The other pages simply have more empty space below their rows,
    // which they already did.
    readonly property int cardHeight: Math.min(root.height - 120,
                                               Math.min(900, Math.max(690, root.height * 0.62)))

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-settings"
    WlrLayershell.keyboardFocus: root.revealed ? WlrKeyboardFocus.Exclusive
                                               : WlrKeyboardFocus.None
    color: "transparent"
    visible: false

    function open(): void {
        root.query = ""
        searchField.text = ""
        root.visible = true
        root.revealed = true
        searchField.forceActiveFocus()
    }
    function close(): void { root.revealed = false }
    function toggle(): void { root.revealed ? root.close() : root.open() }

    // Open straight onto a named section, matched case-insensitively against
    // the sidebar names. The name of a section is its `section` field - there
    // is no `title` - and reading the wrong one threw on every call here. An unknown name opens on the first section rather
    // than failing, so a stale bind degrades to plain `open` instead of doing
    // nothing visible.
    function openAt(name: string): void {
        root.open()
        const want = (name || "").toLowerCase()
        for (let i = 0; i < root.sections.length; i++) {
            if (String(root.sections[i].section).toLowerCase() === want) { root.section = i; return }
        }
        root.section = 0
    }

    onRevealedChanged: if (!revealed) hideTimer.restart()
    Timer { id: hideTimer; interval: Theme.animReveal; onTriggered: if (!root.revealed) root.visible = false }

    // Noctalia debounces at 120ms; the same reasoning applies here. Rebuilding
    // the pane on every keystroke makes typing feel sticky.
    Timer {
        id: debounce
        interval: 120
        onTriggered: root.query = searchField.text.trim().toLowerCase()
    }

    // Sections this machine actually has. A section whose rows are all
    // inapplicable is dropped entirely rather than shown empty.
    readonly property var sections: {
        const out = []
        for (const s of Settings.schema) {
            if (s.when && !s.when()) continue
            const rows = (s.rows || []).filter(r => !r.when || r.when())
            if (rows.length) out.push({ section: s.section, icon: s.icon, rows: rows })
        }
        return out
    }

    // What the pane shows: one section, or search hits from all of them.
    readonly property var visibleRows: {
        if (root.query === "") {
            const s = root.sections[root.section]
            return s ? s.rows.map(r => ({ row: r, from: "" })) : []
        }
        const out = []
        for (const s of root.sections)
            for (const r of s.rows) {
                const hay = ((r.label || "") + " " + (r.help || "")).toLowerCase()
                if (hay.includes(root.query)) out.push({ row: r, from: s.section })
            }
        return out
    }

    // Dismiss on a click outside the card.
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        id: card
        width: root.cardWidth
        height: root.cardHeight
        anchors.centerIn: parent
        radius: 14
        color: Theme.surface
        border.width: 1
        border.color: Theme.outline

        opacity: root.revealed ? 1 : 0
        scale: root.revealed ? 1 : 0.97
        Behavior on opacity { NumberAnimation { duration: Theme.animReveal; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: Theme.animReveal; easing.type: Easing.OutCubic } }

        // THE CONTENT COLUMN, computed once and used by both the heading and
        // the list. Clamping the LIST rather than each row is deliberate: the
        // first attempt centred every delegate with `x: (pane.width - width)/2`
        // and the wallpaper row ignored it, sitting flush left while the rows
        // above it were centred - a row whose content is itself a view does not
        // keep that binding. Moving the clamp up one level removes the question.
        readonly property int contentWidth: Math.min(card.width - sidebar.width - 36,
                                                     root.rowMaxWidth)
        readonly property int contentX: sidebar.width
                                      + (card.width - sidebar.width - card.contentWidth) / 2

        // Swallow clicks so they do not reach the dismissing area behind.
        MouseArea { anchors.fill: parent }

        // --- sidebar ------------------------------------------------------

        Rectangle {
            id: sidebar
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            width: 190
            radius: 14
            color: Theme.bg
            // Square off the inner edge so the rounded card does not show a
            // seam where the sidebar meets the pane.
            Rectangle {
                anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                width: 14
                color: parent.color
            }

            Column {
                anchors { top: parent.top; left: parent.left; right: parent.right
                          topMargin: 14; leftMargin: 8; rightMargin: 8 }
                spacing: 2

                Text {
                    text: "Settings"
                    color: Theme.fg
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    leftPadding: 10
                    bottomPadding: 10
                }

                Repeater {
                    model: root.sections
                    Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool active: root.query === "" && root.section === index
                        width: parent.width
                        height: 34
                        radius: 8
                        color: active ? Theme.accent
                                      : (hov.containsMouse ? Theme.surfaceHigh : "transparent")
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        Row {
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 10
                            Text {
                                text: modelData.icon || ""
                                font.family: Theme.glyphFont
                                font.pixelSize: 15
                                color: parent.parent.active ? Theme.bg : Theme.dim
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: modelData.section
                                font.pixelSize: 13
                                color: parent.parent.active ? Theme.bg : Theme.fg
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: hov
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.section = index
                                searchField.text = ""
                                root.query = ""
                                searchField.forceActiveFocus()
                            }
                        }
                    }
                }
            }
        }

        // --- search -------------------------------------------------------

        Item {
            id: searchRow
            anchors { top: parent.top; left: sidebar.right; right: parent.right
                      topMargin: 14; leftMargin: 18; rightMargin: 18 }
            height: 34

            Text {
                id: mag
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "\u{F0349}"
                font.family: Theme.glyphFont
                font.pixelSize: 14
                color: Theme.dim
            }

            TextInput {
                id: searchField
                anchors { left: mag.right; leftMargin: 8; right: parent.right
                          verticalCenter: parent.verticalCenter }
                color: Theme.fg
                font.pixelSize: 13
                selectByMouse: true
                selectionColor: Theme.accent
                clip: true
                onTextChanged: debounce.restart()
                Keys.onEscapePressed: root.close()

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: searchField.text === ""
                    text: "Search settings"
                    font: searchField.font
                    color: Theme.dim
                }
            }
        }

        Rectangle {
            id: divider
            anchors { top: searchRow.bottom; topMargin: 12
                      left: sidebar.right; right: parent.right; rightMargin: 0 }
            height: 1
            color: Theme.outline
            opacity: 0.6
        }

        // --- the controls -------------------------------------------------

        // The page's own name, above its rows. The sidebar already says which
        // section is selected, so this is not the only signpost - but a page
        // that starts with a heading reads as a page, and one that starts
        // with a control reads as a list someone forgot to label.
        Text {
            id: pageTitle
            // Lined up with the card below it rather than with the pane, or
            // it floats off to the left on a wide screen.
            anchors { top: divider.bottom; topMargin: 14 }
            x: card.contentX
            width: card.contentWidth
            text: root.query !== "" ? "Results"
                : (root.sections[root.section] ? root.sections[root.section].section : "")
            color: Theme.fg
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }

        ListView {
            id: pane
            anchors { top: pageTitle.bottom; bottom: parent.bottom
                      topMargin: 10; bottomMargin: 16 }
            x: card.contentX
            width: card.contentWidth
            clip: true
            // NO GAP BETWEEN ROWS. They are one card with hairlines between
            // them; a spacing here would break it back into separate tiles.
            spacing: 0
            model: root.visibleRows

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: SettingsRow {
                required property var modelData
                required property int index
                width: pane.width
                row: modelData.row
                fromSection: modelData.from
                first: index === 0
                last: index === pane.count - 1
            }

            // The panel's own namespace, so `hyprctl layers` can tell it apart
            // from the bar and the frame - every other surface here has one.
            Component.onCompleted: {}

            // An empty result is worth saying out loud rather than leaving a
            // blank pane that looks broken.
            Text {
                anchors.centerIn: parent
                visible: pane.count === 0
                text: root.query === "" ? "Nothing to configure here"
                                        : "No setting matches “" + root.query + "”"
                color: Theme.dim
                font.pixelSize: 13
            }
        }
    }
}
