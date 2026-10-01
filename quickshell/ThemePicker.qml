// =========================================================================
// ThemePicker - the wallpaper picker's shape, for palettes
// =========================================================================
//
// Hidden until IPC opens it (Super+period, see binds.lua), and built as the
// same object as WallpaperPicker: a band across the middle of the screen with
// every theme laid edge to edge, leaning at the same angle, all of them squeezed
// to slivers except the selected one, which expands in the centre with its name
// underneath. Same keys, same clamping, same way out.
//
// WHAT IT DRAWS INSTEAD OF A PHOTOGRAPH. A palette has no picture, so each tile
// is a MOCK OF THIS DESKTOP in that palette: the wallpaper's colour behind, the
// bar across the top with its three pills and an accent on one of them, and a
// window below it. That is a truer preview than a row of colour chips, because
// the question anyone opens this to answer is "what will my screen look like",
// and the chips answer a different one.
//
// NO IMAGE DECODING, which is most of what WallpaperPicker's complexity is for -
// the sliver cache, the one-decode-size rule, the warming on open. Rectangles
// cost nothing, so none of that exists here and the file is a third the size.
//
// IT DOES NOT APPLY THE THEME ITSELF. ThemeLibrary.choose() runs bin/theme.sh,
// which has to reach kitty, btop, GTK and hyprlock as well as the bar - the same
// reason the settings row goes through it.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    property bool revealed: false
    property int selected: 0

    // --- geometry, borrowed so the two pickers read as one idea -----------

    readonly property int bandHeight:  300
    readonly property int selWidth:    520
    readonly property int selHeight:   340
    readonly property int sliverWidth:  54

    // The same lean as the wallpaper strip. An ANGLE rather than an offset,
    // because the slivers and the expanded tile are different heights and only
    // a shared angle keeps their slanted edges parallel - which is what lets
    // them interlock with no gap.
    readonly property real leanAngle: 7

    readonly property var themes: ThemeLibrary.themes

    // Above everything, with its own namespace so a compositor rule can name it,
    // and taking the keyboard only while it is up - otherwise an invisible
    // window would swallow every keystroke in the session.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-themes"
    WlrLayershell.keyboardFocus: revealed ? WlrKeyboardFocus.Exclusive
                                          : WlrKeyboardFocus.None

    // Anchored to all four edges and, like the wallpaper picker, deliberately
    // WITHOUT ExclusionMode.Ignore: the bar's and the frame's exclusive zones
    // shrink the surface to the content well, and a layer is blurred only as
    // far as its own surface reaches. That is what lets the frame keep its hard
    // edge while everything behind this is blurred. See the picker-blur rule in
    // hypr/rules.lua, which matches this namespace too.
    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"
    visible: false

    // --- public API -------------------------------------------------------

    function open(): void {
        root.visible = true
        root.revealed = true
        // A palette added since the shell started should be here.
        ThemeLibrary.rescan()
        strip.forceActiveFocus()
        root.selectCurrent()
    }

    // Open on the theme in use, not on the first one: you come here to change
    // the theme, so the one you have is the reference point.
    function selectCurrent(): void {
        for (let i = 0; i < root.themes.length; i++) {
            if (root.themes[i].name === ThemeLibrary.current) {
                strip.snap = true
                root.selected = i
                strip.snap = false
                return
            }
        }
    }

    function close(): void { root.revealed = false }

    function toggle(): void {
        if (root.revealed) root.close()
        else root.open()
    }

    function applySelected(): void {
        const t = root.themes[root.selected]
        if (!t) return
        root.close()
        ThemeLibrary.choose(t.name)
    }

    // Clamped rather than wrapping, like the wallpaper strip: running off the
    // end and reappearing at the other loses your place.
    function move(delta: int): void {
        const n = root.themes.length
        if (n === 0) return
        root.selected = Math.max(0, Math.min(n - 1, root.selected + delta))
    }

    // --- the scrim --------------------------------------------------------

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        // Light, because the compositor is blurring behind this as well, and
        // blur plus a heavy scrim together just make the desktop mud. The same
        // value the wallpaper picker settled on.
        opacity: root.revealed ? 0.30 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    // --- the band ---------------------------------------------------------

    Item {
        id: bandWrap
        anchors { left: parent.left; right: parent.right
                  verticalCenter: parent.verticalCenter }
        height: root.selHeight
        opacity: root.revealed ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }

        Item {
            id: strip
            anchors.fill: parent
            focus: true

            // Jump rather than sweep when the selection is set programmatically.
            property bool snap: false
            property real pos: root.selected
            Behavior on pos {
                enabled: !strip.snap
                NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic }
            }

            readonly property real expand: root.selWidth - root.sliverWidth

            // 1 at the selection, falling to 0 one step away: the tile grows as
            // it becomes the selection rather than snapping to full size.
            function grow(i) { return Math.max(0, 1 - Math.abs(i - strip.pos)) }
            function widthAt(i) { return root.sliverWidth + strip.expand * strip.grow(i) }

            // Everything to the left of the selection, laid end to end, then
            // centred on the selected tile.
            function leftAt(i) {
                let x = 0
                for (let k = 0; k < i; k++) x += strip.widthAt(k)
                return x
            }
            readonly property real totalBefore: strip.leftAt(Math.round(strip.pos))
            readonly property real centreOffset:
                width / 2 - strip.totalBefore - strip.widthAt(Math.round(strip.pos)) / 2

            Keys.onEscapePressed: root.close()
            Keys.onLeftPressed:   root.move(-1)
            Keys.onRightPressed:  root.move(1)
            Keys.onReturnPressed: root.applySelected()
            Keys.onEnterPressed:  root.applySelected()

            Repeater {
                model: root.themes

                Item {
                    id: cell
                    required property int index
                    required property var modelData

                    readonly property real g: strip.grow(index)
                    readonly property bool isSel: index === Math.round(strip.pos)

                    width: strip.widthAt(index)
                    // Band height normally; the selected one grows past it,
                    // which is what breaks the strip's line and makes the
                    // expanded tile read as lifted rather than merely wider.
                    height: root.bandHeight + (root.selHeight - root.bandHeight) * g
                    x: strip.centreOffset + strip.leftAt(index)
                    anchors.verticalCenter: parent.verticalCenter

                    // The lean, as a shear - the same parallelogram the
                    // wallpaper tiles use.
                    Item {
                        anchors.fill: parent
                        transform: Matrix4x4 {
                            matrix: Qt.matrix4x4(1, Math.tan(root.leanAngle * Math.PI / 180), 0, 0,
                                                 0, 1, 0, 0,
                                                 0, 0, 1, 0,
                                                 0, 0, 0, 1)
                        }

                        // --- the mock desktop, in this palette ---------------
                        Rectangle {
                            anchors.fill: parent
                            color: cell.modelData.bg || Theme.bg
                            clip: true

                            // The bar: a strip with the three pills on it.
                            Rectangle {
                                id: mockBar
                                width: parent.width
                                height: Math.max(8, parent.height * 0.1)
                                color: cell.modelData.surface || Theme.surface

                                Row {
                                    anchors.centerIn: parent
                                    spacing: Math.max(3, parent.height * 0.3)
                                    visible: cell.g > 0.35      // only legible on the big one

                                    Repeater {
                                        model: 3
                                        Rectangle {
                                            required property int index
                                            width: index === 1 ? mockBar.height * 2.6 : mockBar.height * 1.8
                                            height: mockBar.height * 0.62
                                            radius: height / 2
                                            color: cell.modelData.surfaceTop || Theme.surfaceTop
                                            border.width: 1
                                            border.color: cell.modelData.outline || Theme.outline

                                            Rectangle {
                                                visible: index === 2
                                                anchors.centerIn: parent
                                                width: parent.height * 0.5
                                                height: width
                                                radius: width / 2
                                                color: cell.modelData.accent || Theme.accent
                                            }
                                        }
                                    }
                                }
                            }

                            // A window below it, with a line of text in the
                            // theme's foreground - the pair that has to stay
                            // legible, and the one thing a colour chip hides.
                            Rectangle {
                                id: mockWindow
                                visible: cell.g > 0.35
                                anchors { horizontalCenter: parent.horizontalCenter }
                                y: parent.height * 0.3
                                width: parent.width * 0.62
                                height: parent.height * 0.42
                                radius: 8
                                color: cell.modelData.surface || Theme.surface
                                border.width: 1
                                border.color: cell.modelData.outline || Theme.outline

                                // Everything inside is a FRACTION OF THE WINDOW,
                                // not a pixel count: the tile is still growing
                                // when this becomes visible, and fixed widths
                                // meant the lines nearly touched both edges at
                                // the moment it appeared and looked lost in it a
                                // few frames later.
                                Column {
                                    anchors { left: parent.left; top: parent.top
                                              margins: mockWindow.width * 0.075 }
                                    spacing: mockWindow.height * 0.09
                                    Repeater {
                                        model: 3
                                        Rectangle {
                                            required property int index
                                            width: mockWindow.width * (index === 2 ? 0.19 : 0.34)
                                            height: Math.max(2, mockWindow.height * 0.037)
                                            radius: height / 2
                                            color: index === 0 ? (cell.modelData.accent || Theme.accent)
                                                               : (cell.modelData.fg || Theme.fg)
                                            opacity: index === 0 ? 1 : 0.65
                                        }
                                    }
                                }
                            }
                        }

                        // Unselected tiles are pushed back, proportionally, so the
                        // centre one reads as lit rather than merely larger. Inside
                        // the shear, so the veil is the same parallelogram as the
                        // tile and no un-dimmed corner shows past it.
                        Rectangle {
                            anchors.fill: parent
                            color: "#000000"
                            opacity: 0.45 * (1 - cell.g)
                        }

                        // Selected ring, in the palette's OWN accent so the ring is
                        // part of the preview rather than the current theme
                        // commenting on it.
                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.width: cell.isSel ? 3 : 0
                            border.color: cell.modelData.accent || Theme.accent
                            Behavior on border.width { NumberAnimation { duration: Theme.animFast } }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (cell.isSel) root.applySelected()
                            else root.selected = cell.index
                        }
                    }
                }
            }
        }
    }

    // --- the name, under the band ----------------------------------------

    Column {
        anchors { horizontalCenter: parent.horizontalCenter
                  top: bandWrap.bottom; topMargin: 18 }
        spacing: 6
        opacity: root.revealed ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.themes[root.selected] ? root.themes[root.selected].name : ""
            font.family: Theme.font
            // The wallpaper picker's caption exactly: light, at display size,
            // loosely tracked. Two windows that are the same shape should not
            // label themselves in two different voices, and the name was being
            // set in list-row type - 13px semibold under a 340px tile.
            font.weight: Theme.weightLight
            font.pixelSize: Theme.fontSizeDisplay
            font.letterSpacing: 1.6
            // Inter's optical-size axis is not applied by Qt on its own, so
            // without this the name is drawn with letterforms meant for 14px
            // body text.
            font.variableAxes: ({ "opsz": Theme.fontSizeDisplay })
            // Theme.fg, not the wallpaper caption's hard white: that one sits
            // directly on a photograph and needs a shadow to survive it, while
            // this sits on a scrim of known colour and simply follows it. On
            // the cream theme white here would be invisible.
            color: Theme.fg
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: ThemeLibrary.isCurrent(root.themes[root.selected]
                      ? root.themes[root.selected].name : "")
                  ? "in use" : "enter to apply"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSizeSmall
            font.letterSpacing: Theme.trackingLoose
        }
    }

    onRevealedChanged: if (!revealed) hideTimer.restart()
    Timer {
        id: hideTimer
        interval: Theme.animNormal + 40
        onTriggered: if (!root.revealed) root.visible = false
    }
}
