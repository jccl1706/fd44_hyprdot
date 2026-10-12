// =========================================================================
// Keybinds - a keyboard cheatsheet, themed like the rest of the bar
// =========================================================================
//
// Super+Shift+Slash. Replaces niri's own "Important Hotkeys" overlay, which has
// exactly two settings - skip-at-startup and hide-not-bound - and NO styling of
// any kind: no colour, no font, no radius. Checked, not assumed. Hyprland has no
// such overlay at all, so on that side this is new rather than a replacement.
//
// IT READS THE REAL BINDS. bin/keybinds.py prints them as JSON, from niri's own
// config files on niri and from `hyprctl binds -j` on Hyprland. A cheatsheet kept
// by hand drifts, and a cheatsheet that lies about which keys exist is worse than
// none - so nothing here is a list of keys, only a way of drawing them.
//
// GROUPS COME FROM THE CONFIG'S OWN SECTION COMMENTS, so the panel's organisation
// and the config's cannot disagree. Rename a `// --- section ---` line in
// niri/apps.kdl and this follows.
//
// SAME SHAPE AS PowerMenu AND Launcher: an overlay layer the size of the screen
// with its input region limited to the area below the bar, a scrim, and a card
// that stops clicks reaching the dismissing MouseArea underneath. Escape closes
// it, which matters more here than elsewhere - niri does not implement the
// focus-grab protocol Hyprland uses to dismiss these on an outside click.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: root

    // WHAT A SCREENSHOT OF THIS PANEL SHOULD CONTAIN - see bin/qs-shot.sh.
    //
    // Every one of these windows is anchored to all four edges so it can place
    // its contents freely, which means the WINDOW's geometry is the whole
    // output and describes nothing. This names the item that is actually the
    // panel, and shell.qml maps it to the screen.
    readonly property Item shotTarget: card

    // ONE PANEL PER SCREEN, handed its own by Variants - the same arrangement as
    // PowerMenu. Without declaring it, quickshell warns that the type has no
    // modelData property and the panel has no screen to live on.
    required property var modelData
    screen: modelData

    property bool revealed: false

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-keybinds"
    WlrLayershell.keyboardFocus: revealed ? WlrKeyboardFocus.OnDemand
                                          : WlrKeyboardFocus.None

    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: revealed

    // Below the bar only, so a click on the bar stays the bar's.
    Item {
        id: hitArea
        anchors { fill: parent; topMargin: BarStyle.barBottom }
    }
    mask: Region { item: hitArea }

    property var groups: []
    property string query: ""

    // WHAT THE FLOW ACTUALLY DRAWS. Seventy-one binds across eleven groups is
    // past the point where reading them all is faster than finding one, so the
    // card filters as you type.
    //
    // A GROUP DISAPPEARS WHEN NOTHING IN IT MATCHES rather than staying as an
    // empty heading: the layout is columns of groups, and empty headings would
    // keep the columns the shape they are now while saying nothing.
    //
    // Key and label both, so "shot" finds the screenshot binds by their
    // description and "Mod+Alt" finds a whole modifier's worth by their keys.
    readonly property var visibleGroups: {
        const q = root.query.trim().toLowerCase()
        if (q === "") return root.groups
        const out = []
        for (const g of root.groups) {
            // MATCHED AGAINST WHAT THE ROW SHOWS, not only against what the
            // config says. The key is stored as "Mod+Shift+C" and drawn as
            // "Super+Shift+C" - the same replace() the Text below does - so a
            // filter over the raw value alone would find nothing for "super",
            // which is the word actually on the screen in front of you.
            //
            // Both forms are searched, so "mod" keeps working for anyone
            // thinking in terms of the config file.
            const hits = g.binds.filter(b => {
                const raw = String(b.key).toLowerCase()
                const shown = raw.replace(/\bmod\b/, "super")
                return raw.indexOf(q) !== -1
                    || shown.indexOf(q) !== -1
                    || String(b.label).toLowerCase().indexOf(q) !== -1
            })
            if (hits.length > 0) out.push({ name: g.name, binds: hits })
        }
        return out
    }

    readonly property int matchCount: {
        let n = 0
        for (const g of root.visibleGroups) n += g.binds.length
        return n
    }

    function open(): void {
        reader.running = true          // re-read every time: binds change
        root.query = ""                // a stale filter would hide most of it
        root.revealed = true
        filter.forceActiveFocus()      // type immediately, no click first
    }

    function close(): void {
        root.revealed = false
    }

    // Open with the filter already set. `qs ipc call keybinds find screenshot`
    // is a reasonable thing to want from a script, and it is also the only way
    // to exercise the filter without a keyboard - there is no wtype or ydotool
    // on this machine, and every real UI bug this session came from looking at
    // a picture rather than reasoning about the code.
    function search(q: string): void {
        root.open()
        root.query = q
    }

    function toggle(): void {
        if (root.revealed) root.close()
        else root.open()
    }

    // ONE PROCESS PER OPEN, not a timer. The binds only change when a config file
    // does, and that is not something to poll for - re-reading on open is both
    // cheaper and never stale.
    Process {
        id: reader
        command: [Quickshell.env("HOME") + "/Work/fd44_hyprdot/bin/keybinds.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                let binds = []
                try {
                    binds = JSON.parse((text || "[]").trim() || "[]")
                } catch (e) {
                    binds = []
                }
                // Group in the order the config lists them, which is the order
                // the sections appear in the files.
                const order = []
                const byName = ({})
                for (const b of binds) {
                    if (!byName[b.group]) { byName[b.group] = []; order.push(b.group) }
                    byName[b.group].push(b)
                }
                root.groups = order.map(name => ({ name: name, binds: byName[name] }))
            }
        }
    }

    // Dismiss. The card above swallows its own clicks.
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        opacity: root.revealed ? 0.30 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    // --- the card ---------------------------------------------------------
    // THE CARD IS SIZED BY THE CONTENT, BUT ONLY IN ONE DIRECTION, and getting
    // that wrong is what the first version did: the width came from the Flow's
    // implicitWidth while the Flow wrapped against the card's width. Circular -
    // it settled on a single narrow column and then grew downwards off the bottom
    // of the screen.
    //
    // The constraint is now the HEIGHT: the Flow is told how tall it may be, fills
    // a column, wraps into the next, and reports the width it ended up needing.
    // Nothing reads back the other way.
    Rectangle {
        id: card
        anchors.centerIn: parent
        // A FLOOR, BECAUSE THE CONTENT CAN BE NOTHING. The width comes from the
        // Flow, and a filter that matches no bind leaves the Flow empty - which
        // collapsed the card to a sliver with its own heading, filter field and
        // "no key matches" message hanging out of it, clipped.
        //
        // The floor is the header's own width: title, filter field and the
        // compositor mark are there whatever the list does.
        readonly property real minWidth: 24 + heading.implicitWidth + 20
                                         + filterRow.width + 24 + 70
        width: Math.min(parent.width - Theme.barPadding * 4,
                        Math.max(columns.implicitWidth + 48, card.minWidth))
        // HUGS THE CONTENT, NOT THE ALLOWANCE. columns.height is the height the
        // Flow is ALLOWED to use before wrapping into another column; the tallest
        // column it actually produced is implicitHeight. Using the former left a
        // strip of empty card below the last group.
        // Same reasoning vertically: with nothing matched the Flow contributes
        // no height, so the message gets its own allowance instead.
        height: (root.matchCount === 0 && root.query !== ""
                 ? 44
                 : Math.min(columns.height, columns.implicitHeight)) + 76
        radius: Theme.cornerRadius

        // ALPHA IN THE COLOUR, NOT `opacity`. An Item's opacity applies to its
        // whole subtree, so setting it here made every key and label translucent
        // as well - the terminal behind the panel was legible through the text.
        // Putting the alpha in the fill colour leaves the content opaque.
        color: Qt.alpha(Theme.panelTop, Theme.panelAlpha)
        border.width: 1
        border.color: Theme.rim

        scale: root.revealed ? 1 : 0.97
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuint } }

        // Swallows clicks so they do not reach the dismissing MouseArea.
        MouseArea { anchors.fill: parent }

        // ESCAPE LIVES ON THE CARD, NOT THE WINDOW. PanelWindow has no `focus`
        // property - assigning one is what made this fail to load the first time -
        // so the card takes focus and the window is told to give it, which is the
        // same arrangement PowerMenu uses. Escape matters more here than on
        // Hyprland: niri does not implement the focus-grab protocol that dismisses
        // these panels on an outside click.
        focus: true
        Keys.onEscapePressed: root.close()

        Text {
            id: heading
            anchors { top: parent.top; left: parent.left; margins: 24 }
            text: "Keys"
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSizeTitle
            font.weight: Theme.weightSemi
        }

        // --- the filter -----------------------------------------------------
        //
        // NO BOX AROUND IT. Every other field in this shell - the launcher's,
        // the network password - sits in a framed row because it is the thing
        // you came to that panel to use. Here the list is, and a bordered input
        // beside the title would read as another panel stacked on this one.
        // A glyph, a line of text and a rule under it is enough to say "type
        // here" next to a heading.
        //
        // IT HAS FOCUS FROM THE MOMENT THE CARD OPENS, so the keystroke after
        // the one that opened this goes into the filter rather than nowhere.
        // Escape is handled here as well as on the card, because focus lives
        // here now and the card would never see it.
        Row {
            id: filterRow
            anchors { top: parent.top; topMargin: 24
                      left: heading.right; leftMargin: 20 }
            spacing: 8
            width: 190

            Text {
                id: filterGlyph
                anchors.verticalCenter: filter.verticalCenter
                text: "\u{F0349}"               // nf-md-magnify
                font.family: Theme.glyphFont
                font.pixelSize: 14
                color: root.query === "" ? Theme.dim : Theme.accent
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
            }

            TextInput {
                id: filter
                width: filterRow.width - filterGlyph.width - filterRow.spacing
                text: root.query
                onTextChanged: root.query = text
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                selectByMouse: true
                selectionColor: Theme.accent
                clip: true

                Keys.onEscapePressed: {
                    // Escape clears a filter first and closes second, so a
                    // mistyped search does not cost you the panel.
                    if (root.query !== "") root.query = ""
                    else root.close()
                }

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: filter.text === ""
                    text: "filter"
                    color: Theme.dim
                    font: filter.font
                }
            }
        }

        // The rule under the filter, so it reads as a field rather than a
        // stray word beside the title.
        Rectangle {
            anchors { left: filterRow.left; right: filterRow.right
                      top: filterRow.bottom; topMargin: 4 }
            height: 1
            color: root.query === "" ? Theme.outline : Theme.accent
            opacity: root.query === "" ? 0.6 : 1
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }

        // Nothing matched: said where the list would have been, rather than
        // leaving an empty card that looks broken.
        Text {
            visible: root.query !== "" && root.matchCount === 0
            anchors { left: parent.left; leftMargin: 24
                      top: heading.bottom; topMargin: 24 }
            text: "no key matches \"" + root.query + "\""
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
        }

        // WHICH COMPOSITOR THESE KEYS CAME FROM, with its mark beside the name.
        //
        // The same assets/niri.svg the bar's CompositorMark draws, and the same
        // rule: only niri has a vendored mark, so on Hyprland the row is the
        // word alone rather than the wrong logo.
        //
        // BASELINE-ALIGNED TO THE TEXT, NOT CENTRED ON THE ROW. A mark centred
        // against a 12px label sits visibly high - the word's weight is at its
        // x-height and the mark's is at its middle - and at this size a pixel
        // of that reads as a mistake rather than as a style.
        Row {
            anchors { top: parent.top; right: parent.right; margins: 24 }
            spacing: 7

            Image {
                id: compositorMark
                visible: Compositor.backend === "niri"
                source: visible ? Qt.resolvedUrl("assets/niri.svg") : ""
                // 2x then scaled, as in CompositorMark.qml: an SVG rasterised
                // at its display size is mush on a 204ppi panel.
                sourceSize { width: 32; height: 32 }
                width: 16
                height: 16
                smooth: true
                anchors.verticalCenter: backendName.verticalCenter
                anchors.verticalCenterOffset: -1
            }

            Text {
                id: backendName
                text: Compositor.backend
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        // COLUMNS RATHER THAN ONE LIST, because sixty entries in one column is a
        // scrollbar, not a cheatsheet.
        //
        // TopToBottom, with a height and no width: the Flow fills a column down to
        // that height, then starts another beside it. Left to right it would wrap
        // into ROWS of groups instead, and one tall group - Workspaces is twenty
        // entries - would set the height of its whole row.
        Flow {
            id: columns
            flow: Flow.TopToBottom
            x: 24
            y: heading.y + heading.height + 16
            // TUNED TO THE CONTENT, not to the screen. With the numbered runs
            // collapsed the list is about forty rows, which splits into two
            // columns of roughly this height. Taller and the third column holds
            // three entries and a lot of nothing; shorter and it spills into four.
            // Clamped by the screen so the laptop panel cannot be overflowed.
            height: Math.min(root.height - BarStyle.barBottom - Theme.barPadding * 4 - 76,
                             660)
            spacing: 26

            Repeater {
                model: root.visibleGroups

                ColumnLayout {
                    spacing: 3

                    Text {
                        text: modelData.name
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSizeSmall + 1
                        font.weight: Theme.weightSemi
                        font.capitalization: Font.AllUppercase
                        Layout.bottomMargin: 4
                    }

                    Repeater {
                        model: modelData.binds

                        RowLayout {
                            spacing: 10

                            // The key, in the glyph-capable font at a fixed width
                            // so the labels line up down the column.
                            Text {
                                text: modelData.key.replace(/\bMod\b/, "Super")
                                color: Theme.fg
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize
                                font.weight: Theme.weightMedium
                                // 132 LINES THE LABELS UP WITHOUT SETTING THE
                                // WIDTH. It is a minimum, not a cap: the few
                                // long key names - XF86AudioRaiseVolume is
                                // twenty characters - push past it and widen
                                // their own column, which is correct. What it
                                // must not do is reserve that much for every
                                // row, which at 158 it did.
                                Layout.minimumWidth: 132
                            }

                            // THE LABEL IS CAPPED AND WRAPS, SO PROSE CANNOT
                            // SET THE CARD'S WIDTH.
                            //
                            // These strings are not written for this panel. The
                            // compositor ones are hotkey-overlay titles and the
                            // shell ones are read straight out of
                            // bashrc.d/tmux.sh's header - "attach to it - or
                            // switch, if you are already inside tmux" is a
                            // sentence in a file that explains itself, and it is
                            // fifty-six characters. Uncapped, the single longest
                            // line in sixty-eight set the width of its column,
                            // and the card came out 1378px wide on a 1410px
                            // screen: a cheatsheet the size of the desktop.
                            //
                            // WRAPPED RATHER THAN ELIDED. Eliding would hide the
                            // end of exactly the entries that needed explaining,
                            // and the only thing wrong with them is that they
                            // are long, not that they are unimportant.
                            Text {
                                text: modelData.label
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                                // 240: THE WIDEST THAT STILL COSTS NO HEIGHT.
                                //
                                // Measured, all of them. 190 gives a 1096-wide
                                // card - the same width as the settings panel,
                                // which is tidy - but several labels wrap onto a
                                // second line and the rows go ragged, and the
                                // extra lines push the card to 728 tall. 240
                                // gives 1222x696: wider, but almost nothing
                                // wraps, so it is also SHORTER. 290 was the
                                // uncapped behaviour at 1354, which is the
                                // full-width card this started as.
                                //
                                // The cap stays rather than being removed, and
                                // that is the point: without it one
                                // fifty-six-character sentence in tmux.sh sets
                                // the width of a column, so the panel grows
                                // whenever someone edits a comment in a shell
                                // file. 240 is a bound, not a layout.
                                Layout.maximumWidth: 240
                            }
                        }
                    }
                }
            }
        }
    }

}
