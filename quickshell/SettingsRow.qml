// =========================================================================
// SettingsRow - one schema row, rendered as whatever control it asks for
// =========================================================================
//
// The control factory. SettingsPanel hands it a descriptor from
// Settings.schema and this picks the widget: a slider for a number, a switch
// for a boolean, a segmented picker for a short list, a button for an action.
//
// THE HELP TEXT IS ALWAYS VISIBLE, not a tooltip. A setting whose effect you
// have to hover to discover is a setting nobody touches, and these are exactly
// the sort of thing - a notification timeout, a ranking half-life - where the
// label alone does not tell you what changing it will do.

import Quickshell
import QtQuick
import QtQuick.Controls

Item {
    id: item

    // NOT `row` - that was the root's id, and a property cannot share it.
    required property var row
    property string fromSection: ""

    readonly property bool isAction: item.row.type === "action"
    readonly property var  value: item.row.key ? Settings[item.row.key] : undefined

    implicitHeight: body.implicitHeight + 18
    height: implicitHeight

    Column {
        id: body
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 3

        // When searching, say which section a hit came from - otherwise a
        // result list of bare labels gives no sense of where you are.
        Text {
            visible: item.fromSection !== ""
            text: item.fromSection
            color: Theme.dim
            font.pixelSize: 10
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.6
        }

        Item {
            width: parent.width
            implicitHeight: Math.max(label.implicitHeight, control.implicitHeight)

            Column {
                id: label
                anchors { left: parent.left; right: control.left; rightMargin: 16
                          verticalCenter: parent.verticalCenter }
                spacing: 2
                Text {
                    text: item.row.label || ""
                    color: Theme.fg
                    font.pixelSize: 13
                    width: parent.width
                    elide: Text.ElideRight
                }
                Text {
                    visible: !!item.row.help
                    text: item.row.help || ""
                    color: Theme.dim
                    font.pixelSize: 11
                    width: parent.width
                    wrapMode: Text.WordWrap
                }
            }

            Loader {
                id: control
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                sourceComponent: {
                    switch (item.row.type) {
                        case "action":  return actionButton
                        case "toggle":  return toggleSwitch
                        case "select":  return segmented
                        default:        return numberSlider     // "ms", "days"
                    }
                }
            }
        }
    }

    // --- controls ---------------------------------------------------------

    Component {
        id: actionButton
        Rectangle {
            implicitWidth: txt.implicitWidth + 26
            implicitHeight: 28
            radius: 8
            color: ma.containsMouse ? Theme.surfaceHigh : Theme.bg
            border.width: 1
            border.color: Theme.outline
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            Text {
                id: txt
                anchors.centerIn: parent
                // The label IS the verb for an action, so the button says
                // something shorter rather than repeating it.
                text: "Run"
                color: Theme.fg
                font.pixelSize: 12
            }
            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (item.row.run) item.row.run()
            }
        }
    }

    Component {
        id: toggleSwitch
        Rectangle {
            implicitWidth: 44; implicitHeight: 24
            radius: height / 2
            color: item.value ? Theme.accent : Theme.surfaceHigh
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            Rectangle {
                width: 18; height: 18; radius: 9
                color: Theme.bg
                y: 3
                x: item.value ? parent.width - width - 3 : 3
                Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Settings.setValue(item.row.key, !item.value)
            }
        }
    }

    Component {
        id: segmented
        Row {
            spacing: 4
            Repeater {
                model: item.row.options || []
                Rectangle {
                    required property var modelData
                    readonly property bool on: item.value === modelData.value
                    implicitWidth: t.implicitWidth + 22
                    implicitHeight: 26
                    radius: 7
                    color: on ? Theme.accent : (h.containsMouse ? Theme.surfaceHigh : Theme.bg)
                    border.width: 1
                    border.color: on ? Theme.accent : Theme.outline
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text {
                        id: t
                        anchors.centerIn: parent
                        text: modelData.label
                        color: parent.on ? Theme.bg : Theme.fg
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: h
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Settings.setValue(item.row.key, modelData.value)
                    }
                }
            }
        }
    }

    Component {
        id: numberSlider
        Row {
            spacing: 10
            Slider {
                id: sl
                width: 170
                anchors.verticalCenter: parent.verticalCenter
                from: item.row.min
                to: item.row.max
                stepSize: item.row.step || 1
                snapMode: Slider.SnapAlways
                value: item.value === undefined ? from : item.value
                // COMMIT ON RELEASE, not on every pixel. Dragging a slider
                // bound straight to the store would write the settings file
                // dozens of times per drag and, for the notification timeouts,
                // re-time every toast on screen while you dragged.
                onPressedChanged: if (!pressed) Settings.setValue(item.row.key, value)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 46
                horizontalAlignment: Text.AlignRight
                color: Theme.fg
                font.pixelSize: 12
                // Milliseconds are stored but seconds are what a person thinks
                // in; days likewise read better than a bare number.
                text: item.row.type === "ms"
                        ? (sl.value / 1000).toFixed(sl.value % 1000 ? 1 : 0) + "s"
                        : sl.value.toFixed(0) + "d"
            }
        }
    }
}
