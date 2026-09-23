// =========================================================================
// TrayMenu - a tray item's own menu, drawn in this shell's own style
// =========================================================================
//
// WHY THIS EXISTS AT ALL, when Quickshell appears to offer two ways to put a
// tray menu on screen and neither works in 0.3.1:
//
//   SystemTrayItem.display(window, x, y)  returns without complaint and draws
//                                         nothing. Measured: the layer-surface
//                                         count is identical either side of
//                                         the call.
//   QsMenuAnchor.open()                   leaves `visible` false, with the
//                                         menu handle valid and populated.
//
// What does work is QsMenuOpener, which reads the entries perfectly - 16 of
// them from Steam, labels and all. So the data was never the problem; there
// was nothing to draw it in, and 0.3.1 has no PopupWindow type either. Hence
// a DropPanel, like every other panel in this shell.
//
// It is arguably the better outcome. A GTK menu dropped into this bar would
// have looked like a visitor; this one is the same card, the same radius and
// the same colours as the audio and network panels.
//
// THE MENU IS STILL THE APPLICATION'S. Nothing here decides what is in it:
// the entries, their order, their enabled state and what a click does all
// come from the program over DBus. This draws them and forwards the click.
import Quickshell
import QtQuick

DropPanel {
    id: root
    layerNamespace: "quickshell-traymenu"
    panelWidth: 260

    // The SystemTrayItem whose menu is on show. Set by shell.qml just before
    // opening, because one panel serves every tray icon rather than there
    // being one panel per application.
    property var item: null

    readonly property string appName: root.item ? (root.item.title || root.item.id) : ""

    QsMenuOpener {
        id: opener
        menu: root.item ? root.item.menu : null
    }

    Column {
        width: parent.width
        spacing: 0

        // The application's name, so a menu of bare verbs - "Library",
        // "Settings", "Exit" - says whose they are. Tray menus routinely omit
        // this and are ambiguous when two are open in a session.
        Item {
            width: parent.width
            height: 44
            Text {
                anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                text: root.appName
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSizeTitle
                font.weight: Theme.weightSemi
                elide: Text.ElideRight
                width: parent.width - 32
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.outline }

        Repeater {
            model: opener.children

            delegate: Item {
                id: row
                required property var modelData

                width: root.panelWidth
                // A separator is a hairline with air around it, not a row.
                height: row.modelData.isSeparator ? 9 : 34

                Rectangle {
                    visible: row.modelData.isSeparator
                    anchors.centerIn: parent
                    width: parent.width - 24
                    height: 1
                    color: Theme.outline
                }

                Rectangle {
                    visible: !row.modelData.isSeparator
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    radius: height / 2
                    color: Theme.surfaceHigh
                    opacity: hover.hovered && row.modelData.enabled ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                }

                // The entry's own icon where it has one. Many do not, and a
                // blank gutter for those keeps the labels on one line rather
                // than ragged.
                Image {
                    visible: !row.modelData.isSeparator && row.modelData.icon !== ""
                    anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                    width: 16
                    height: 16
                    source: row.modelData.icon
                    sourceSize.width: 32
                    sourceSize.height: 32
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    opacity: row.modelData.enabled ? 1 : 0.4
                }

                Text {
                    visible: !row.modelData.isSeparator
                    anchors {
                        left: parent.left
                        leftMargin: row.modelData.icon !== "" ? 40 : 16
                        right: parent.right
                        rightMargin: 34
                        verticalCenter: parent.verticalCenter
                    }
                    text: row.modelData.text
                    color: row.modelData.enabled ? Theme.fg : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    elide: Text.ElideRight
                }

                // A submenu is marked and not entered. Opening one in place
                // would need a second panel and a way back out of it; saying
                // so plainly beats a chevron that does nothing when clicked.
                Text {
                    visible: !row.modelData.isSeparator && row.modelData.hasChildren
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    text: "\u{F0142}"          // chevron-right
                    font.family: Theme.glyphFont
                    font.pixelSize: 15
                    color: Theme.dim
                }

                // Checkable entries - "Show notifications" and the like.
                // checkState is Qt.Unchecked/Checked/PartiallyChecked.
                Text {
                    visible: !row.modelData.isSeparator
                             && !row.modelData.hasChildren
                             && row.modelData.checkState === Qt.Checked
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    text: "\u{F012C}"          // check
                    font.family: Theme.glyphFont
                    font.pixelSize: 15
                    color: Theme.accent
                }

                HoverHandler { id: hover; enabled: !row.modelData.isSeparator }

                MouseArea {
                    anchors.fill: parent
                    enabled: !row.modelData.isSeparator && row.modelData.enabled
                    // A submenu has nothing to trigger, so let the click fall
                    // through rather than closing the panel for no reason.
                    onClicked: {
                        if (row.modelData.hasChildren) return
                        row.modelData.triggered()
                        root.close()
                    }
                }
            }
        }

        // An application is entitled to publish a menu with nothing in it, and
        // an empty card with no explanation looks like a bug in this shell.
        Item {
            width: parent.width
            height: opener.children && opener.children.values.length === 0 ? 46 : 0
            visible: height > 0
            Text {
                anchors.centerIn: parent
                text: "No menu entries"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        Item { width: parent.width; height: 6 }
    }
}
