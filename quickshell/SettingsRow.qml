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
    id: settingRow

    // THE ID IS NOT `item`, AND NOT `row`, AND BOTH MATTER.
    //
    // `row` is out because a property cannot share its own id. `item` is out
    // because a Loader HAS an `item` property, and inside a Component the
    // Loader instantiates, a bare `item` resolves to that rather than to this
    // root - so every control below read `undefined.row` and rendered nothing
    // while the label beside it, outside the Loader, worked fine.
    required property var row
    property string fromSection: ""

    // A WIDE control goes UNDER the label at full width instead of beside it.
    // The wallpaper grid is the only one so far: a row of thumbnails has
    // nothing to gain from being squeezed into the right-hand column next to
    // its own help text.
    readonly property bool wide: settingRow.row.type === "wallpapers"

    // A MENU is a select with too many options to sit in a row. Twelve
    // resolutions across the pane would be unreadable and would not fit, so
    // the button names the current one and the list opens underneath - the
    // same full-width slot the wallpaper grid uses, and the same chips as the
    // segmented control, wrapped.
    readonly property bool isMenu: settingRow.row.type === "menu"
    property bool expanded: false

    readonly property bool isAction: settingRow.row.type === "action"
    // A row either names a key in the Settings store or brings its own
    // accessors - see the schema. Reading through row.get() still tracks the
    // singleton property it touches, so a control bound to this updates when
    // the real owner changes underneath it.
    readonly property var  value: settingRow.row.get ? settingRow.row.get()
                                : settingRow.row.key ? Settings[settingRow.row.key]
                                : undefined

    function commit(v): void {
        if (settingRow.row.set) settingRow.row.set(v)
        else Settings.setValue(settingRow.row.key, v)
    }

    // WHERE THIS ROW SITS IN ITS GROUP. Rows share one rounded container the
    // way a GNOME settings page groups them, which is the difference between
    // a section reading as one thing and reading as a pile of controls that
    // happen to be near each other. Only the ends are rounded, so the group
    // looks like a single card rather than a stack of separate ones.
    property bool first: true
    property bool last: true
    readonly property int boxRadius: 10

    implicitHeight: body.implicitHeight + 22
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        color: Theme.surfaceTop
        topLeftRadius:     settingRow.first ? settingRow.boxRadius : 0
        topRightRadius:    settingRow.first ? settingRow.boxRadius : 0
        bottomLeftRadius:  settingRow.last  ? settingRow.boxRadius : 0
        bottomRightRadius: settingRow.last  ? settingRow.boxRadius : 0

        // A hairline between rows, INSET FROM THE LEFT rather than running
        // edge to edge: it separates the rows without cutting the card in
        // two, which is the detail that makes a boxed list look deliberate.
        Rectangle {
            visible: !settingRow.first
            anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: 14 }
            height: 1
            color: Theme.outline
            opacity: 0.45
        }
    }

    Column {
        id: body
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                  leftMargin: 14; rightMargin: 14 }
        spacing: 3

        // When searching, say which section a hit came from - otherwise a
        // result list of bare labels gives no sense of where you are.
        Text {
            visible: settingRow.fromSection !== ""
            text: settingRow.fromSection
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
                    text: settingRow.row.label || ""
                    color: Theme.fg
                    font.pixelSize: 13
                    width: parent.width
                    elide: Text.ElideRight
                }
                Text {
                    visible: !!settingRow.row.help
                    text: settingRow.row.help || ""
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
                    if (settingRow.wide) return null
                    switch (settingRow.row.type) {
                        case "action":  return actionButton
                        case "toggle":  return toggleSwitch
                        case "select":  return segmented
                        case "menu":    return menuButton
                        default:        return numberSlider     // "ms", "days"
                    }
                }
            }
        }

        Loader {
            width: body.width
            active: settingRow.wide || (settingRow.isMenu && settingRow.expanded)
            visible: active
            sourceComponent: settingRow.wide ? wallpaperGrid : menuList
        }
    }

    // --- controls ---------------------------------------------------------

    // FOUR ACROSS, and scrolling for the rest. WallpaperPicker deliberately
    // does NOT do this - its comment argues a grid "shows eleven thumbnails at
    // once and asks you to judge them at postage-stamp size" - and that is
    // still the right call for a full-screen picker, where one wallpaper shown
    // large is worth more than sixteen shown small. This is the other job:
    // seeing at a glance WHICH ONE IS SET, and changing it without leaving
    // settings. At four across in this pane a tile is ~190px, which is a good
    // deal larger than a postage stamp, and the strip is still one key away.
    Component {
        id: wallpaperGrid
        Item {
            implicitHeight: grid.cellHeight * 4 + 8

            GridView {
                id: grid
                anchors.fill: parent
                anchors.topMargin: 8
                clip: true
                cellWidth: Math.floor(width / 4)
                // 16:9, plus the gap that makes the tiles read as separate.
                cellHeight: Math.round(cellWidth * 9 / 16) + 8
                model: WallpaperLibrary.files
                boundsBehavior: Flickable.StopAtBounds

                // Previews may still have been generating when the shell
                // started, in which case the model is pointed at the
                // full-size originals. Asking again when the page is opened
                // costs one process and fixes the rest of the session.
                Component.onCompleted: WallpaperLibrary.rescan()

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Item {
                    id: tile
                    required property url fileUrl
                    required property string fileName
                    width: grid.cellWidth
                    height: grid.cellHeight

                    readonly property bool current: WallpaperLibrary.isCurrent(tile.fileUrl)

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 6
                        color: Theme.surfaceHigh
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: tile.fileUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            // The tile is ~190px wide; decoding a 960px
                            // preview to fill it wastes most of the pixels.
                            sourceSize.width: 400
                        }

                        // The one in use, and the one under the pointer. The
                        // ring is drawn OVER the image rather than around the
                        // tile so it cannot change the layout as it appears.
                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            color: "transparent"
                            border.width: tile.current ? 3 : (tileMa.containsMouse ? 2 : 0)
                            border.color: tile.current ? Theme.accent : Theme.fg
                            opacity: tile.current ? 1 : 0.7
                            Behavior on border.width { NumberAnimation { duration: Theme.animFast } }
                        }

                        MouseArea {
                            id: tileMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: WallpaperLibrary.choose(tile.fileUrl)
                        }
                    }
                }
            }
        }
    }

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
                onClicked: if (settingRow.row.run) settingRow.row.run()
            }
        }
    }

    Component {
        id: toggleSwitch
        Rectangle {
            implicitWidth: 44; implicitHeight: 24
            radius: height / 2
            color: settingRow.value ? Theme.accent : Theme.surfaceHigh
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            Rectangle {
                width: 18; height: 18; radius: 9
                color: Theme.bg
                y: 3
                x: settingRow.value ? parent.width - width - 3 : 3
                Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: settingRow.commit(!settingRow.value)
            }
        }
    }

    Component {
        id: segmented
        Row {
            spacing: 4
            Repeater {
                model: settingRow.row.options || []
                Rectangle {
                    required property var modelData
                    readonly property bool on: settingRow.value === modelData.value
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
                        onClicked: settingRow.commit(modelData.value)
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
                from: settingRow.row.min
                to: settingRow.row.max
                stepSize: settingRow.row.step || 1
                snapMode: Slider.SnapAlways
                value: settingRow.value === undefined ? from : settingRow.value
                // COMMIT ON RELEASE, not on every pixel. Dragging a slider
                // bound straight to the store would write the settings file
                // dozens of times per drag and, for the notification timeouts,
                // re-time every toast on screen while you dragged.
                onPressedChanged: if (!pressed) settingRow.commit(value)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 46
                horizontalAlignment: Text.AlignRight
                color: Theme.fg
                font.pixelSize: 12
                // Milliseconds are stored but seconds are what a person thinks
                // in; days likewise read better than a bare number.
                text: settingRow.row.type === "ms"
                        ? (sl.value / 1000).toFixed(sl.value % 1000 ? 1 : 0) + "s"
                        : sl.value.toFixed(0) + "d"
            }
        }
    }

    // The closed menu: what is set now, and a hint that there is more.
    Component {
        id: menuButton
        Rectangle {
            readonly property var chosen: (settingRow.row.options || [])
                .find(o => o.value === settingRow.value)
            implicitWidth: label.implicitWidth + 34
            implicitHeight: 26
            radius: 7
            color: hover.containsMouse || settingRow.expanded ? Theme.surfaceHigh : Theme.bg
            border.width: 1
            border.color: settingRow.expanded ? Theme.accent : Theme.outline
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            Text {
                id: label
                anchors { left: parent.left; leftMargin: 11; verticalCenter: parent.verticalCenter }
                // An option that is not in the list is still worth naming -
                // a mode set by hand in monitors.lua, say.
                text: parent.chosen ? parent.chosen.label : (settingRow.value || "-")
                color: Theme.fg
                font.pixelSize: 12
            }
            Text {
                anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter }
                text: settingRow.expanded ? "\u25B4" : "\u25BE"
                color: Theme.dim
                font.pixelSize: 10
            }
            MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: settingRow.expanded = !settingRow.expanded
            }
        }
    }

    // The open menu. A Flow rather than a Column: twelve resolutions are
    // short strings, and wrapping them across the pane shows the whole set at
    // once instead of making a list to scroll.
    Component {
        id: menuList
        Flow {
            spacing: 4
            bottomPadding: 4
            Repeater {
                model: settingRow.row.options || []
                Rectangle {
                    required property var modelData
                    readonly property bool on: settingRow.value === modelData.value
                    implicitWidth: item.implicitWidth + 22
                    implicitHeight: 26
                    radius: 7
                    color: on ? Theme.accent : (mouse.containsMouse ? Theme.surfaceHigh : Theme.bg)
                    border.width: 1
                    border.color: on ? Theme.accent : Theme.outline
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text {
                        id: item
                        anchors.centerIn: parent
                        text: modelData.label
                        color: parent.on ? Theme.bg : Theme.fg
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // Closing on choice is what makes this a menu rather
                        // than a segmented control that happens to wrap.
                        onClicked: {
                            settingRow.commit(modelData.value)
                            settingRow.expanded = false
                        }
                    }
                }
            }
        }
    }
}
