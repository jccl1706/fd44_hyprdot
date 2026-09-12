// =========================================================================
// PowerMenu - session actions, sliding out of the right frame
// =========================================================================
//
// The mirror of Launcher.qml: where that rises out of the bottom frame, this
// slides out of the right one. Same surface arrangement, same reasoning -
// full-screen for click-outside, genuinely unmapped when closed, exclusion
// ignored, keyboard focus only while open - all of which is written out there
// rather than repeated here.
//
// It replaces the old Super+M binding, which ran `hyprctl dispatch exit`
// immediately. An unconfirmed keystroke that kills the session is a bad
// default; a menu is the confirmation.
//
// NO HIBERNATE, deliberately. /sys/power/state advertises "disk", but the
// only swap on this machine is zram - you cannot hibernate into compressed
// RAM. The entry would be there purely to fail.

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

    // Index of a destructive action that has been clicked once and is waiting
    // for a second click, or -1.
    //
    // ARM-THEN-FIRE, rather than a separate confirmation dialog. A dialog
    // would need words, and this menu deliberately has none; the button
    // swapping to a tick says "again to confirm" without any. It also keeps
    // the confirmation on the same control, so the second click is in the
    // same place as the first - a yes/no dialog trains you to click
    // somewhere else quickly, which is how people confirm things they did
    // not mean to.
    property int armed: -1

    // Disarms on its own. An armed shutdown button left sitting there is a
    // trap for the next person to press Enter.
    Timer {
        id: disarm
        interval: 4000
        onTriggered: root.armed = -1
    }

    // --- window ----------------------------------------------------------

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-power"
    WlrLayershell.keyboardFocus: revealed ? WlrKeyboardFocus.Exclusive
                                          : WlrKeyboardFocus.None

    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: false

    // --- actions ---------------------------------------------------------
    //
    // `danger` marks the three that end the session. They get the error
    // colour AND the second press - see `armed` above. Lock and Suspend are
    // both trivially undone, so they fire on the first press.

    readonly property var actions: [
        {
            name: "Lock",
            detail: "Lock the screen",
            glyph: "\u{F033E}",
            danger: false,
            // A TRANSIENT SCOPE, not a plain exec. Started as a child of
            // quickshell, hyprlock shares its cgroup and dies with it - so
            // reloading the bar would unlock the machine. Learned the hard
            // way when restarting hypridle killed the running lock screen.
            cmd: ["systemd-run", "--user", "--scope", "--quiet", "--collect",
                  "--unit=hyprlock", "hyprlock"]
        },
        {
            name: "Suspend",
            detail: "Sleep to RAM",
            glyph: "\u{F0904}",
            danger: false,
            cmd: ["systemctl", "suspend"]
        },
        {
            name: "Log out",
            detail: "End this session",
            glyph: "\u{F0343}",
            danger: true,
            // uwsm owns the session, so it is what should tear it down -
            // killing Hyprland directly leaves graphical-session.target and
            // everything bound to it running.
            cmd: ["uwsm", "stop"]
        },
        {
            name: "Restart",
            detail: "Reboot now",
            glyph: "\u{F0709}",
            danger: true,
            cmd: ["systemctl", "reboot"]
        },
        {
            name: "Shut down",
            detail: "Power off now",
            glyph: "\u{F0425}",
            danger: true,
            cmd: ["systemctl", "poweroff"]
        }
    ]

    // --- public API ------------------------------------------------------

    function open(): void {
        root.selected = 0
        root.armed = -1
        root.visible = true
        // Before `revealed`, always: the Behavior reads `duration` once when
        // it starts, and binding it to `revealed` loses that race.
        root.slideDuration = root.openDuration
        root.revealed = true
        card.forceActiveFocus()
    }

    function close(): void {
        root.armed = -1
        disarm.stop()
        root.slideDuration = root.closeDuration
        root.revealed = false
    }

    function toggle(): void {
        if (root.revealed) root.close()
        else root.open()
    }

    function run(i): void {
        if (i < 0 || i >= root.actions.length) return

        // Destructive actions need two presses. The first only arms.
        if (root.actions[i].danger && root.armed !== i) {
            root.armed = i
            disarm.restart()
            return
        }

        root.armed = -1
        disarm.stop()
        root.close()
        runner.command = root.actions[i].cmd
        runner.running = true
    }

    Process {
        id: runner
        onExited: (code, status) => {
            if (code !== 0)
                console.warn("power menu: command exited", code)
        }
    }

    function move(delta: int): void {
        const n = root.actions.length
        const next = Math.max(0, Math.min(n - 1, root.selected + delta))
        // Moving off an armed button cancels it: arming is about the button
        // you are pointing at, and carrying it along would mean a stray Enter
        // elsewhere fires something you armed moments ago.
        if (next !== root.selected) {
            root.armed = -1
            disarm.stop()
        }
        root.selected = next
    }

    // --- scrim -----------------------------------------------------------
    //
    // Inset past the bar and the frame, and rounded to the well's radius, so
    // the chrome keeps its real colour. A square scrim paints over the four
    // concave corner pieces Frame.qml draws INTO the well and dims them while
    // the strips they belong to stay bright.

    Rectangle {
        anchors {
            fill: parent
            topMargin:    Theme.barHeight
            leftMargin:   Theme.frameThickness
            rightMargin:  Theme.frameThickness
            bottomMargin: Theme.frameThickness
        }
        radius: Theme.cornerRadius
        color: "#000000"
        opacity: root.revealed ? 0.4 : 0
        Behavior on opacity {
            NumberAnimation { duration: root.slideDuration; easing.type: Easing.InOutCubic }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    // Closing is faster than opening: an opening panel is worth watching, a
    // closing one is in the way. Set imperatively rather than bound to
    // `revealed`, because a binding loses the race with the Behavior - it
    // reads `duration` once, at start, and can do so before a dependent
    // binding has been recomputed.
    readonly property int openDuration: 260
    readonly property int closeDuration: 140
    property int slideDuration: openDuration

    // --- card ------------------------------------------------------------

    Item {
        id: card

        // ICON-ONLY CIRCLES, no labels. The glyph is the whole label, which
        // is why they are all from one Nerd Font set and visually distinct
        // from each other rather than five variations on a power symbol.
        readonly property int btn: 48
        readonly property int gap: 14
        readonly property int pad: 16

        // The extra frameThickness runs UNDER the frame strip - the card ends
        // at the screen edge, not at the inside of the frame, so the two read
        // as one shape. The buttons are centred in the visible part, not in
        // the whole card, or they would sit a couple of pixels right of
        // centre.
        width: btn + pad * 2 + Theme.frameThickness
        height: root.actions.length * btn
                + (root.actions.length - 1) * gap
                + pad * 2

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        // Animated via the margin, never by binding x to parent.width: a
        // freshly mapped layer surface learns its size only after the
        // compositor configures it, so the card would be placed against a
        // stale width and then jump.
        anchors.rightMargin: root.revealed ? 0 : -width

        Behavior on anchors.rightMargin {
            NumberAnimation {
                duration: root.slideDuration
                easing.type: Easing.InOutCubic
                onRunningChanged: {
                    if (!running && !root.revealed) root.visible = false
                }
            }
        }

        focus: true
        Keys.onEscapePressed: root.close()
        Keys.onUpPressed:     root.move(-1)
        Keys.onDownPressed:   root.move(1)
        Keys.onReturnPressed: root.run(root.selected)
        Keys.onEnterPressed:  root.run(root.selected)

        // Background and the fillets that join it to the frame, flattened
        // into one layer and made translucent as a whole.
        //
        // layer.enabled is not an optimisation: plain `opacity` on a parent
        // multiplies into each child separately, so the 1px overlap where a
        // fillet meets the panel would blend twice and show as a bright line
        // exactly where the seam would otherwise be dark.
        Item {
            id: panel
            anchors.fill: parent
            anchors.topMargin: -Theme.cornerRadius
            anchors.bottomMargin: -Theme.cornerRadius
            opacity: Theme.panelAlpha
            layer.enabled: true

            Rectangle {
                id: panelBody
                anchors.fill: parent
                anchors.topMargin: Theme.cornerRadius
                anchors.bottomMargin: Theme.cornerRadius

                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.panelTop }
                    GradientStop { position: 1.0; color: Theme.bg }
                }

                // Rounded on the LEFT only - the mirror of the launcher,
                // which is rounded on top only. The flat edge is the one
                // touching the frame.
                topLeftRadius:    Theme.cornerRadius
                bottomLeftRadius: Theme.cornerRadius
            }

            // Concave fillets where the card's top and bottom edges meet the
            // right frame. The -1 margins overlap each a pixel into the
            // panel: butted up exactly, the shared edge lands on a fractional
            // device pixel under this display's scaling and the two
            // antialiased sides sum to ~78% coverage instead of opaque.
            InnerCorner {
                corner: "bottomright"
                anchors { bottom: panelBody.top; bottomMargin: -1
                          right: parent.right; rightMargin: Theme.frameThickness }
            }

            InnerCorner {
                corner: "topright"
                anchors { top: panelBody.bottom; topMargin: -1
                          right: parent.right; rightMargin: Theme.frameThickness }
            }
        }

        MouseArea { anchors.fill: parent }

        Column {
            spacing: card.gap
            anchors {
                verticalCenter: parent.verticalCenter
                // Centred in the VISIBLE width - the card runs under the
                // frame by frameThickness.
                horizontalCenter: parent.horizontalCenter
                horizontalCenterOffset: -Theme.frameThickness / 2
            }

            Repeater {
                model: root.actions

                delegate: Rectangle {
                    id: btn
                    required property int index
                    required property var modelData

                    width: card.btn
                    height: card.btn
                    radius: width / 2

                    readonly property bool active: btn.index === root.selected
                    readonly property bool isArmed: btn.index === root.armed

                    // Filled when selected, as in the reference: the circle
                    // becomes the light surface and the glyph inverts to sit
                    // on it. Destructive actions fill RED instead of light,
                    // so the two that end the session are never a neutral
                    // colour under the pointer.
                    //
                    // Armed is the same red at full strength - the state is
                    // carried by the glyph swapping to a tick rather than by
                    // another colour, because a third shade of red would be
                    // read as decoration rather than as a change of state.
                    color: btn.isArmed ? Theme.danger
                         : btn.active  ? (btn.modelData.danger ? Theme.danger : Theme.fg)
                                       : Theme.surfaceHigh
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    // A ring that appears only while armed, so the button
                    // reads as raised out of the column and is hard to miss
                    // at a glance.
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 8
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: btn.isArmed ? 2 : 0
                        border.color: Qt.rgba(Theme.danger.r, Theme.danger.g,
                                              Theme.danger.b, 0.55)
                    }

                    Text {
                        anchors.centerIn: parent
                        // A tick means "press again". No words, which is the
                        // point of this menu.
                        text: btn.isArmed ? "\u{F012C}" : btn.modelData.glyph
                        font.family: Theme.glyphFont
                        font.pixelSize: btn.isArmed ? 24 : 22
                        color: btn.isArmed ? Theme.bg
                             : btn.active  ? Theme.bg
                                           : Theme.fg
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            // Hovering a different button cancels an arm, for
                            // the same reason moving the selection does.
                            if (root.armed !== btn.index) root.armed = -1
                            root.selected = btn.index
                        }
                        onClicked: root.run(btn.index)
                    }
                }
            }
        }
    }
}
