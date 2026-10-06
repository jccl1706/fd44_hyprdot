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

    function open(): void {
        reader.running = true          // re-read every time: binds change
        root.revealed = true
        card.forceActiveFocus()
    }

    function close(): void {
        root.revealed = false
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
        width: Math.min(parent.width - Theme.barPadding * 4, columns.implicitWidth + 48)
        // HUGS THE CONTENT, NOT THE ALLOWANCE. columns.height is the height the
        // Flow is ALLOWED to use before wrapping into another column; the tallest
        // column it actually produced is implicitHeight. Using the former left a
        // strip of empty card below the last group.
        height: Math.min(columns.height, columns.implicitHeight) + 76
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
            font.weight: Font.DemiBold
        }

        Text {
            anchors { top: parent.top; right: parent.right; margins: 24 }
            text: Compositor.backend
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSizeSmall
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
                model: root.groups

                ColumnLayout {
                    spacing: 3

                    Text {
                        text: modelData.name
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSizeSmall + 1
                        font.weight: Font.DemiBold
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
                                font.weight: Font.Medium
                                Layout.minimumWidth: 158
                            }

                            Text {
                                text: modelData.label
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        }
    }

}
