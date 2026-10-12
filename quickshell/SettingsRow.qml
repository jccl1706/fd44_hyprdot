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
                              || settingRow.row.type === "themes"
                              || settingRow.row.type === "networks"

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

    // 18, not 22. With the help text now a size smaller and dimmer, the old
    // padding left each row looking like a paragraph with a control beside it.
    // A GROUP HEADING NEEDS AIR ABOVE IT OR IT DOES NOT GROUP.
    //
    // The zone labels on the Bar page - CENTRE LEFT, CENTRE RIGHT, RIGHT - sat
    // with the same gap above them as between two rows inside a group, so the
    // three groups were legible but did not separate: you could read where one
    // began only by reading the label, which is the thing a heading is supposed
    // to save you from doing.
    //
    // ABOVE, NOT AROUND. The extra height is pushed entirely over the heading
    // by offsetting the body's centre, so the heading stays tight to the rows
    // it introduces rather than floating midway between two groups and
    // belonging to neither.
    readonly property int groupGap: settingRow.fromSection !== "" ? 12 : 0

    implicitHeight: body.implicitHeight + 18 + groupGap
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
                  leftMargin: 14; rightMargin: 14
                  verticalCenterOffset: settingRow.groupGap / 2 }
        spacing: 3

        // When searching, say which section a hit came from - otherwise a
        // result list of bare labels gives no sense of where you are.
        Text {
            font.family: Theme.font
            visible: settingRow.fromSection !== ""
            text: settingRow.fromSection
            color: Theme.dim
            font.pixelSize: Theme.fontSizeSmall
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
                    font.family: Theme.font
                    text: settingRow.row.label || ""
                    // AN OFF TOGGLE DIMS ITS OWN LABEL, so a page of fifteen can
                    // be read by scanning the left edge instead of the switches
                    // on the right. The switch is the control; this is the state,
                    // and the state is what you are looking for when you open
                    // this page wondering what you turned off last week.
                    //
                    // Only toggles. A number or a picker has no off, and dimming
                    // their labels would say something untrue about them.
                    color: (settingRow.row.type === "toggle" && settingRow.value === false)
                           ? Theme.dim : Theme.fg
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    font.pixelSize: Theme.fontSizeTitle
                    width: parent.width
                    elide: Text.ElideRight
                }
                // HELP IS SUBORDINATE TO THE LABEL AND HAS TO LOOK IT. It was
                // 12px against a 14px label in the same Theme.dim the label's own
                // secondary text uses, wrapping to two and three lines - so a row
                // read as a paragraph with a control parked beside it. A size
                // down and capped at two lines puts the control back in charge of
                // the row; the full text is still there on hover.
                Text {
                    id: helpText
                    font.family: Theme.font
                    visible: !!settingRow.row.help
                    text: settingRow.row.help || ""
                    color: Theme.dim
                    opacity: 0.85
                    font.pixelSize: Theme.fontSizeSmall
                    width: parent.width
                    wrapMode: Text.WordWrap
                    // TWO LINES, AFTER ONE TURNED OUT TO BE A LIE ABOUT THE DATA.
                    // One line is plenty in Appearance, where the help says what
                    // a control does. The Bar section's help says what you LOSE
                    // by hiding a plugin - "Hidden, there is no other way to
                    // switch it on" - and that is the half that got cut, in
                    // almost every row, mid-sentence. A help text truncated
                    // before its warning is worse than none, because the row
                    // still looks explained.
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    ToolTip.visible: helpHover.hovered && helpText.truncated
                    ToolTip.text: settingRow.row.help || ""
                    ToolTip.delay: 400
                    HoverHandler { id: helpHover }
                }
            }

            Loader {
                id: control
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                sourceComponent: {
                    // A wide row has its control underneath, but it may still
                    // want a button beside the label - the wallpaper strip
                    // does, to open the full-screen picker.
                    if (settingRow.wide) return settingRow.row.run ? actionButton : null
                    switch (settingRow.row.type) {
                        case "action":  return actionButton
                        case "toggle":  return toggleSwitch
                        case "select":  return segmented
                        case "menu":    return menuButton
                        default:        return numberSlider     // "ms", "min", "pct", days
                    }
                }
            }
        }

        Loader {
            width: body.width
            active: settingRow.wide || (settingRow.isMenu && settingRow.expanded)
            visible: active
            sourceComponent: settingRow.row.type === "wallpapers" ? wallpaperStrip
                           : settingRow.row.type === "themes"     ? themeStrip
                           : settingRow.row.type === "networks"   ? networkList
                           : menuList
        }
    }

    // --- controls ---------------------------------------------------------

    // A FEW, NOT ALL OF THEM. This was a scrolling grid of every wallpaper -
    // sixteen visible out of sixty-three - which made the Appearance page a
    // wall of thumbnails with no end in sight, on a page that is otherwise two
    // rows. WallpaperPicker's own comment had the argument already: a grid
    // "shows eleven thumbnails at once and asks you to judge them at
    // postage-stamp size".
    //
    // So this shows the one in use and its neighbours, and the button beside
    // the label opens the full-screen picker for everything else. Stepping to
    // a near one stays a single click, browsing happens where the pictures are
    // shown large, and the page has a definite end.
    Component {
        id: wallpaperStrip
        Item {
            // Four. Six fitted, but each tile is then narrow enough that a
            // wallpaper is a smear of colour rather than a picture, which is
            // the failing this row was replacing rather than one to repeat at
            // a smaller scale.
            // SIX, BETWEEN THE TWO EXTREMES EITHER SIDE OF IT. Four tiles stretched
            // across the full width came out ~175x145 each, so that one row was
            // taller than the rest of the section together while showing four of
            // sixty-three. Eight fixed the proportions and went too far the other
            // way: at that size the darker wallpapers stopped being tellable
            // apart, which is the one thing a thumbnail has to do.
            readonly property int howMany: 6
            readonly property var shown: WallpaperLibrary.nearby(howMany)
            readonly property int gap: 6
            readonly property real tileWidth:
                shown.length ? (width - gap * (shown.length - 1)) / shown.length : 0

            implicitHeight: Math.round(tileWidth * 9 / 16) + 4

            Row {
                spacing: parent.gap
                Repeater {
                    model: parent.parent.shown
                    Rectangle {
                        required property var modelData
                        readonly property bool current: WallpaperLibrary.isCurrent(modelData.url)

                        width: Math.floor(parent.parent.tileWidth)
                        height: Math.round(width * 9 / 16)
                        radius: 6
                        color: Theme.surfaceHigh
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: modelData.url
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            // A tile here is ~130px; decoding a 960px preview
                            // to fill it would waste most of the pixels.
                            sourceSize.width: 320
                        }

                        // The one in use, and the one under the pointer.
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "transparent"
                            border.width: parent.current ? 3 : (hover.containsMouse ? 2 : 0)
                            border.color: parent.current ? Theme.accent : Theme.fg
                            Behavior on border.width { NumberAnimation { duration: Theme.animFast } }
                        }

                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: WallpaperLibrary.choose(parent.modelData.url)
                        }
                    }
                }
            }

            // Previews may still have been generating when the shell started,
            // in which case the model points at the full-size originals.
            // Asking again when the page is opened costs one process and fixes
            // the rest of the session.
            Component.onCompleted: WallpaperLibrary.rescan()
        }
    }

    // THE SAME SHAPE AS wallpaperStrip ABOVE, deliberately: a row of tiles, the
    // current one ringed in the accent colour, the one under the pointer ringed
    // in the foreground. A theme has no picture, so each tile DRAWS the palette
    // instead - the bar's own arrangement in miniature, which is a truer preview
    // than four colour bands would be because it shows the colours doing the
    // job they will actually do.
    //
    // ALL OF THEM, NOT A WINDOW OF FOUR. WallpaperLibrary.nearby() exists
    // because there can be hundreds of wallpapers; there are four palettes, and
    // a picker that scrolled would be stranger than one that does not.
    Component {
        id: themeStrip
        Item {
            readonly property var shown: ThemeLibrary.themes
            readonly property int gap: 8
            implicitHeight: 38

            // COLOUR CHIPS, NOT MINIATURE DESKTOPS. Each theme used to be a 16:9
            // card drawing a little mock bar - a pill, an accent dot, a line - and
            // stretched across the full width those came out about 200px wide and
            // 130px tall, five of them, so choosing a theme took more of the panel
            // than everything else in the section.
            //
            // The mock bar was also answering a question nobody asks. You do not
            // pick a theme by how its bar is shaped; you pick it by its colours.
            // So each chip is the theme's own background with its surface, accent
            // and foreground beside the name - the three values that actually
            // differ - and the whole row fits on one line at a third the height.
            Row {
                spacing: parent.gap
                Repeater {
                    model: parent.parent.shown
                    Rectangle {
                        required property var modelData
                        readonly property bool current: ThemeLibrary.isCurrent(modelData.name)
                        height: 38
                        width: chipContent.implicitWidth + 26
                        radius: 9
                        color: modelData.bg || Theme.bg
                        border.width: current ? 2 : 1
                        border.color: current ? Theme.accent : (modelData.outline || Theme.outline)
                        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                        Row {
                            id: chipContent
                            anchors.centerIn: parent
                            spacing: 8

                            // The three values a palette is actually judged on,
                            // drawn in the theme's own colours rather than this
                            // one's - the point is to preview it, not to match.
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Repeater {
                                    model: [ modelData.surface || Theme.surface,
                                             modelData.accent  || Theme.accent,
                                             modelData.fg      || Theme.fg ]
                                    Rectangle {
                                        required property var modelData
                                        // 13, not 9. At 9px the three swatches
                                        // read as punctuation before the name
                                        // rather than as the thing being chosen -
                                        // and the colours are the whole point of
                                        // the chip.
                                        width: 13; height: 13; radius: 6.5
                                        color: modelData
                                        // A hairline, so a swatch the same colour
                                        // as the chip's background still has an
                                        // edge: cream's surface against cream's
                                        // bg would otherwise be an invisible dot.
                                        border.width: 1
                                        border.color: Qt.rgba(0, 0, 0, 0.18)
                                    }
                                }
                            }

                            Text {
                                font.family: Theme.font
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name
                                // The theme's own foreground, so the chip reads as
                                // a sample of the theme rather than as a label on
                                // top of one.
                                color: modelData.fg || Theme.fg
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: parent.parent.parent.current ? Theme.weightSemi
                                                                          : Theme.weightMedium
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ThemeLibrary.choose(parent.modelData.name)
                        }
                    }
                }
            }

            // Themes are files on disk and one can appear between restarts;
            // opening this page is the moment to notice.
            Component.onCompleted: ThemeLibrary.rescan()
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
                font.family: Theme.font
                id: txt
                anchors.centerIn: parent
                // The label IS the verb for an action, so the button says
                // something shorter rather than repeating it - unless the row
                // gives it words of its own, which a row whose label is a
                // noun needs.
                text: settingRow.row.runLabel || "Run"
                color: Theme.fg
                font.pixelSize: Theme.fontSize
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
                        font.family: Theme.font
                        id: t
                        anchors.centerIn: parent
                        text: modelData.label
                        color: parent.on ? Theme.bg : Theme.fg
                        font.pixelSize: Theme.fontSize
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

                // STYLED, BECAUSE AN UNSTYLED Slider IS NOT NEUTRAL - IT IS BLUE.
                // QtQuick Controls' default style paints its groove and handle in
                // its own stock blue, so this one control sat there in a colour no
                // palette on this machine contains, through every theme. Every
                // other widget in the panel was already drawn by hand, which is
                // why it was the only thing that never changed.
                // AND THE SLIDER NEEDS A HEIGHT OF ITS OWN once these replace
                // the defaults. A Slider takes its implicit size from its
                // background and handle; two Rectangles with no implicit size
                // gave it zero, and the control vanished - the row kept its
                // label, its help and its value and simply had no slider in it.
                height: 20

                background: Rectangle {
                    x: sl.leftPadding
                    y: sl.topPadding + sl.availableHeight / 2 - height / 2
                    implicitWidth: 170
                    implicitHeight: 4
                    width: sl.availableWidth
                    height: 4
                    radius: 2
                    color: Theme.surfaceHigh
                    // The filled part, which is the value - so it takes the
                    // accent, the colour this bar uses for "the live one".
                    Rectangle {
                        width: sl.visualPosition * parent.width
                        height: parent.height
                        radius: parent.radius
                        color: Theme.accent
                    }
                }

                handle: Rectangle {
                    x: sl.leftPadding + sl.visualPosition * (sl.availableWidth - width)
                    y: sl.topPadding + sl.availableHeight / 2 - height / 2
                    implicitWidth: 16
                    implicitHeight: 16
                    width: 16
                    height: 16
                    radius: 8
                    color: sl.pressed ? Theme.surfaceHigh : Theme.surface
                    border.width: 2
                    border.color: Theme.accent
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                }
                // COMMIT ON RELEASE, not on every pixel. Dragging a slider
                // bound straight to the store would write the settings file
                // dozens of times per drag and, for the notification timeouts,
                // re-time every toast on screen while you dragged.
                onPressedChanged: if (!pressed) settingRow.commit(value)
            }
            Text {
                font.family: Theme.font
                anchors.verticalCenter: parent.verticalCenter
                width: 46
                horizontalAlignment: Text.AlignRight
                color: Theme.fg
                font.pixelSize: Theme.fontSize
                // Milliseconds are stored but seconds are what a person thinks
                // in; days likewise read better than a bare number.
                // The fallthrough was "d" for days, which made every future
                // slider a number of days until someone noticed. A percentage
                // reads as one now; anything still unlabelled is days.
                text: settingRow.row.type === "ms"
                        ? (sl.value / 1000).toFixed(sl.value % 1000 ? 1 : 0) + "s"
                      : settingRow.row.type === "min"
                        ? sl.value.toFixed(0) + " min"
                      : settingRow.row.type === "pct"
                        ? sl.value.toFixed(0) + "%"
                      : settingRow.row.type === "k"
                        ? sl.value.toFixed(0) + "K"
                        : sl.value.toFixed(0) + "d"
            }
        }
    }

    // The same switch-and-list the bar's network button drops down, shown in
    // place rather than sending you to another surface. Its own switch is off
    // here: the page has one as a row above this.
    Component {
        id: networkList
        NetworkList {
            active: true
            showSwitch: false
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
                font.family: Theme.font
                id: label
                anchors { left: parent.left; leftMargin: 11; verticalCenter: parent.verticalCenter }
                // An option that is not in the list is still worth naming -
                // a mode set by hand in monitors.lua, say.
                text: parent.chosen ? parent.chosen.label : (settingRow.value || "-")
                color: Theme.fg
                font.pixelSize: Theme.fontSize
            }
            Text {
                font.family: Theme.font
                anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter }
                text: settingRow.expanded ? "\u25B4" : "\u25BE"
                color: Theme.dim
                font.pixelSize: Theme.fontSizeSmall
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
                        font.family: Theme.font
                        id: item
                        anchors.centerIn: parent
                        text: modelData.label
                        color: parent.on ? Theme.bg : Theme.fg
                        font.pixelSize: Theme.fontSize
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
