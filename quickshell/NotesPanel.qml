// =========================================================================
// NotesPanel - somewhere to put a thought
// =========================================================================
//
// A plain text area that keeps what you type. Not a notes app: no titles,
// no list, no sync - one page that is always the same page, which is what a
// scratchpad is for. Anything that outgrows it belongs in a file.
//
// TextEdit RATHER THAN QtQuick.Controls' TextArea, because nothing else in
// this shell imports Controls and a single Controls widget would arrive
// with its own style engine to fight - the Launcher's search field is a
// plain TextInput for the same reason.
//
// THE TEXT IS COPIED IN AND OUT, not bound. A two-way binding between the
// editor and the singleton breaks the moment a keystroke assigns to
// TextEdit.text directly, and what it breaks is the direction that was
// keeping the file up to date. Loaded on opening, written back on change
// and again on closing.

import Quickshell
import QtQuick

DropPanel {
    id: root

    layerNamespace: "quickshell-notes"
    panelWidth: 420

    onOpening: {
        editor.text = Notes.text
        // After the text, or the cursor lands at 0 and the first keystroke
        // types into the beginning of whatever was already there.
        editor.cursorPosition = editor.length
    }

    onClosing: Notes.flush()

    // The card takes focus when it opens; hand it to the editor so typing
    // goes into the page rather than nowhere.
    onRevealedChanged: if (root.revealed) editor.forceActiveFocus()

    Column {
        width: parent.width
        spacing: 0

        Item {
            width: parent.width
            height: 44

            Text {
                anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                text: "Scratchpad"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSizeTitle
                font.weight: Theme.weightSemi
            }

            // Says the file is behind the text rather than that a save
            // happened - a flashing "saved" would be a thing to watch
            // instead of a thing to trust.
            Text {
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                text: Notes.dirty ? "unsaved" : ""
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSizeSmall
                opacity: text !== "" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.outline }

        Item {
            width: parent.width
            height: 300

            Flickable {
                id: flick
                anchors {
                    fill: parent
                    leftMargin: 16; rightMargin: 16
                    topMargin: 12;  bottomMargin: 12
                }
                contentWidth: width
                contentHeight: editor.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                // Follows the cursor, so typing past the bottom scrolls
                // rather than writing off the edge of the card.
                function ensureVisible(r) {
                    if (contentY >= r.y) contentY = r.y
                    else if (contentY + height <= r.y + r.height)
                        contentY = r.y + r.height - height
                }

                TextEdit {
                    id: editor
                    width: flick.width
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText

                    color: Theme.fg
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.accentFg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    // A scratchpad is read at a glance and a tight leading
                    // makes a page of notes a wall.
                    renderType: Text.NativeRendering

                    onTextChanged: Notes.setText(text)
                    onCursorRectangleChanged: flick.ensureVisible(cursorRectangle)

                    // Escape belongs to the panel, which closes on it. Every
                    // other key is the note's.
                    Keys.onEscapePressed: event => event.accepted = false
                }

                Text {
                    anchors { left: parent.left; top: parent.top }
                    text: "Type anything. It keeps itself."
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    visible: editor.text === ""
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.outline }

        Item {
            width: parent.width
            height: 38

            Text {
                anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                text: {
                    const n = editor.text.trim()
                    if (n === "") return ""
                    const words = n.split(/\s+/).length
                    const lines = editor.lineCount
                    return words + (words === 1 ? " word" : " words")
                         + "  -  " + lines + (lines === 1 ? " line" : " lines")
                }
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSizeSmall
            }

            Text {
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                visible: editor.text !== ""
                text: "Clear"
                color: clearHover.hovered ? Theme.danger : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSizeSmall
                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                HoverHandler { id: clearHover }
                TapHandler {
                    onTapped: {
                        editor.text = ""
                        Notes.setText("")
                        Notes.flush()
                    }
                }
            }
        }
    }
}
