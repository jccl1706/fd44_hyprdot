// =========================================================================
// ClipboardPanel - what you copied, and a way back to it
// =========================================================================
//
// Super+Shift+C. bin/clipboard.sh does the storing through cliphist; this only
// shows it and offers the three things you can do with an entry.
//
// IMAGES ARE WHY THIS EXISTS. A screenshot on the clipboard was unreachable by
// anything that wanted a file - the friction that started this. An image entry
// here says what it is and how big, and "save" writes it out and puts the PATH
// on the clipboard, which is the thing a terminal can actually use.
//
// NEWEST FIRST AND NO SEARCH. cliphist keeps 750 entries; a list that long
// wants filtering, but the thing being looked for is almost always in the last
// five - this is "what did I copy a minute ago", not an archive. If that turns
// out to be wrong, the search box belongs here and not in a second panel.
//
// THE LIST IS READ WHEN THE PANEL OPENS, not watched. The store changes only
// when you copy something, and while this is on screen you are not copying.

import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

DropPanel {
    id: root
    layerNamespace: "quickshell-clipboard"
    panelWidth: 420

    property var entries: []
    property string note: ""

    readonly property string script:
        Quickshell.env("HOME") + "/Work/fd44_hyprdot/bin/clipboard.sh"

    // Re-read every time it is shown, so it never offers an entry that has
    // since been superseded.
    onRevealedChanged: if (revealed) root.refresh()

    function refresh(): void {
        if (lister.running) return
        lister.running = true
    }

    function act(verb: string, id: string): void {
        actor.command = [root.script, verb, id]
        actor.running = true
    }

    Process {
        id: lister
        command: [root.script, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.entries = JSON.parse(text) || [] }
                catch (e) { root.entries = [] }
            }
        }
    }

    Process {
        id: actor
        stdout: StdioCollector {
            onStreamFinished: {
                // `save` prints the path it wrote. Putting that on the
                // clipboard is the whole point: the next thing you do with a
                // saved image is name it to something, and typing a timestamped
                // path by hand is how you get it wrong.
                const out = String(text).trim()
                if (out.startsWith("/")) {
                    saver.command = ["sh", "-c", 'printf %s "$1" | wl-copy', "sh", out]
                    saver.running = true
                    root.note = "saved · path copied"
                } else {
                    root.note = ""
                }
                root.refresh()
            }
        }
    }
    Process { id: saver }

    Column {
        width: parent.width
        spacing: 10

        Item {
            width: parent.width
            height: 22
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "Clipboard"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSizeTitle
                font.weight: Theme.weightSemi
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: root.note !== "" ? root.note
                    : root.entries.length === 0 ? "nothing copied yet"
                    : root.entries.length + " kept"
                color: root.note !== "" ? Theme.accent : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSizeSmall
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
            }
        }

        Rectangle {
            width: parent.width; height: 1
            color: Theme.outline; opacity: 0.6
        }

        Repeater {
            model: root.entries.slice(0, 12)

            Item {
                required property var modelData
                width: parent.width
                height: 44

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: 8
                    color: hover.hovered ? Theme.surfaceHigh : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                }
                HoverHandler { id: hover }

                // A whole-row tap copies it back, which is what you came for.
                TapHandler { onTapped: root.act("copy", parent.modelData.id) }

                RowLayout {
                    anchors { left: parent.left; right: parent.right
                              verticalCenter: parent.verticalCenter }
                    spacing: 10

                    // An image says so with a glyph rather than a thumbnail: a
                    // thumbnail means decoding every entry on open, and the
                    // dimensions beside it are what tells them apart anyway.
                    Text {
                        text: parent.parent.modelData.kind === "image"
                              ? "\u{F02E9}" : "\u{F0219}"
                        font.family: Theme.glyphFont
                        font.pixelSize: 16
                        color: parent.parent.modelData.kind === "image"
                               ? Theme.accent : Theme.dim
                        Layout.preferredWidth: 20
                    }

                    Text {
                        text: parent.parent.modelData.preview
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        Layout.fillWidth: true
                    }

                    // Shown on hover only. Three controls on every row of twelve
                    // is a wall of glyphs; the row itself is the common action
                    // and these are the other two.
                    Row {
                        spacing: 4
                        opacity: hover.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

                        Repeater {
                            model: [
                                { g: "\u{F0193}", verb: "save",   tip: "save to a file" },
                                { g: "\u{F01B4}", verb: "delete", tip: "forget this" }
                            ]
                            Rectangle {
                                required property var modelData
                                width: 24; height: 24; radius: 6
                                color: btnHover.hovered ? Theme.surface : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.modelData.g
                                    font.family: Theme.glyphFont
                                    font.pixelSize: 13
                                    color: btnHover.hovered ? Theme.fg : Theme.dim
                                }
                                HoverHandler { id: btnHover }
                                TapHandler {
                                    onTapped: {
                                        root.act(parent.modelData.verb,
                                                 parent.parent.parent.parent.modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            visible: root.entries.length === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "copy something and it will appear here"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSizeSmall
        }
    }
}
