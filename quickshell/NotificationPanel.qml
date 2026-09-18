// =========================================================================
// NotificationPanel - silence, and what you missed
// =========================================================================
//
// Drops out of the bell in the bar, the same way the audio and network
// panels drop out of theirs. Two jobs:
//
//   * the do-not-disturb switch, which lives here rather than on the bar
//     glyph so that hitting it is deliberate and its effect is visible
//   * the history, newest first
//
// HISTORY IS WHAT SILENCE IS FOR. A notification silenced by DND is written
// straight into history rather than dropped, so "what did I miss" has an
// answer - the exception being the ones the sender marked transient, which
// are a volume OSD and belong to a moment that has passed.

import Quickshell
import QtQuick

DropPanel {
    id: root

    layerNamespace: "quickshell-notifications-panel"
    panelWidth: 360

    readonly property var entries: NotificationService.history

    Column {
        width: parent.width
        spacing: 0

        // --- do not disturb ------------------------------------------------

        Item {
            width: parent.width
            height: 48

            Text {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: NotificationService.doNotDisturb ? "Silenced" : "Notifications"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSizeTitle
                font.weight: Theme.weightSemi
            }

            // A track-and-knob switch rather than a checkbox, matching the
            // wifi toggle in NetworkPanel.
            Rectangle {
                id: dndSwitch
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                width: 40
                height: 22
                radius: height / 2
                color: NotificationService.doNotDisturb ? Theme.danger : Theme.surfaceHigh
                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                Rectangle {
                    width: 16
                    height: 16
                    radius: height / 2
                    color: NotificationService.doNotDisturb ? Theme.accentFg : Theme.dim
                    anchors.verticalCenter: parent.verticalCenter
                    x: NotificationService.doNotDisturb ? parent.width - width - 3 : 3
                    Behavior on x {
                        NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
                    }
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotificationService.toggleDnd()
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.outline
        }

        // --- history --------------------------------------------------------

        Item {
            width: parent.width
            height: 40
            visible: root.entries.length === 0

            Text {
                anchors.centerIn: parent
                text: "Nothing to catch up on"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }
        }

        Repeater {
            model: root.entries

            Item {
                id: row
                required property var modelData
                required property int index

                width: parent.width
                height: 54

                Rectangle {
                    anchors.fill: parent
                    color: Theme.fg
                    opacity: rowHover.hovered ? 0.06 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                }

                HoverHandler { id: rowHover }

                Rectangle {
                    id: dot
                    anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                    width: 6; height: 6; radius: 3
                    color: row.modelData.urgency === 2 ? Theme.danger : Theme.accent
                }

                Column {
                    anchors {
                        left: dot.right; leftMargin: 10
                        right: stamp.left; rightMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 1

                    Text {
                        width: parent.width
                        text: row.modelData.summary
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        font.weight: Theme.weightMedium
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        width: parent.width
                        text: row.modelData.body
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        visible: text !== ""
                    }
                }

                // Relative, because "4m" is what you want to know about a
                // notification and "14:32" is what you want about an event.
                Text {
                    id: stamp
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    text: root.ago(row.modelData.ts)
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.outline
            visible: root.entries.length > 0
        }

        Item {
            width: parent.width
            height: 40
            visible: root.entries.length > 0

            Text {
                id: clearLabel
                anchors.centerIn: parent
                text: "Clear history"
                color: clearHover.hovered ? Theme.fg : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
            }

            HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: NotificationService.clearHistory() }
        }
    }

    // Coarse on purpose: a notification from yesterday does not need a
    // minute on it, and anything under a minute is "now".
    function ago(ts): string {
        const secs = Math.max(0, Math.floor((Date.now() - ts) / 1000))
        if (secs < 60)    return "now"
        if (secs < 3600)  return Math.floor(secs / 60) + "m"
        if (secs < 86400) return Math.floor(secs / 3600) + "h"
        return Math.floor(secs / 86400) + "d"
    }
}
