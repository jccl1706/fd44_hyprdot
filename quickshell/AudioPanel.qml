// =========================================================================
// AudioPanel - volume and device selection, sliding down out of the bar
// =========================================================================
//
// Opened by the speaker glyph in the bar's right pill (AudioButton.qml). The
// desktop's keyboard has no media keys, so this is the way to change volume
// and to switch between outputs and inputs without opening pavucontrol.
//
// The third of the sliding panels, after Launcher.qml (up out of the bottom
// frame) and PowerMenu.qml (out of the right frame). This one comes DOWN out
// of the bar in the top-right corner, directly under the glyph that opened
// it. Same surface arrangement as those two - full-screen for click-outside,
// unmapped when closed, exclusion ignored, keyboard focus only while open -
// and the reasoning is written out in Launcher.qml rather than repeated here.
//
// WHAT COUNTS AS A DEVICE: every PipeWire node with audio controls that is not
// a stream. That excludes application streams and, on the EVO4, the UCM
// "split" loopback nodes (`*.split`) and the raw `hw_EVO4_0` pro-audio pair,
// none of which carry audio controls. What is left is exactly the list
// `wpctl status` prints under Sinks and Sources.
//
// OUTPUTS ARE LISTED, INPUTS ARE A DROPDOWN. Outputs get switched - speakers,
// headphones, the monitor - so they stay one click away. Inputs are set once
// and left, and the EVO4 alone exposes five of them, three of which are
// loopbacks; listed in full they were most of the panel.
//
// SELECTING A DEVICE sets PipeWire's CONFIGURED default, the same thing
// `wpctl set-default` does - WirePlumber stores it, so the choice survives a
// reboot, and every app following the default moves with it.

import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    property bool revealed: false

    // The input dropdown. Always starts closed.
    property bool inputsOpen: false

    // --- window ----------------------------------------------------------

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-audio"
    WlrLayershell.keyboardFocus: revealed ? WlrKeyboardFocus.Exclusive
                                          : WlrKeyboardFocus.None

    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: false

    // --- devices ---------------------------------------------------------

    readonly property var devices: Pipewire.nodes.values.filter(n => n.audio && !n.isStream)
    readonly property var sinks:   devices.filter(n => n.isSink)
    readonly property var sources: devices.filter(n => !n.isSink)

    // Volume and mute are only live on BOUND nodes. The two defaults are the
    // only ones whose levels are shown; the lists need nothing but names.
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    // --- public API ------------------------------------------------------

    function open(): void {
        root.inputsOpen = false
        root.visible = true
        // Before `revealed`, always - see the duration note in PowerMenu.qml.
        root.slideDuration = root.openDuration
        root.revealed = true
        card.forceActiveFocus()
    }

    function close(): void {
        root.slideDuration = root.closeDuration
        root.revealed = false
    }

    function toggle(): void {
        if (root.revealed) root.close()
        else root.open()
    }

    // Capped at 100%. Past that PipeWire amplifies in software and clips, and
    // the volume keys cap there too (`wpctl set-volume -l 1`).
    function setVolume(node, v: real): void {
        if (!node || !node.audio) return
        node.audio.volume = Math.max(0, Math.min(1, v))
    }

    function toggleMute(node): void {
        if (!node || !node.audio) return
        node.audio.muted = !node.audio.muted
    }

    function setDefault(node): void {
        if (!node) return
        if (node.isSink) Pipewire.preferredDefaultAudioSink = node
        else             Pipewire.preferredDefaultAudioSource = node
    }

    // --- labels ----------------------------------------------------------
    //
    // The description is the useful name for most devices ("EVO4 Headphone /
    // Line Out"), but for HDMI it names the GPU's audio controller, and the
    // nickname is the monitor on the other end ("LG ULTRAGEAR"). So: the
    // nickname leads when it says something the description does not, and the
    // description drops to the subtitle.

    function nickLeads(n): bool {
        const nick = n.nickname || ""
        const desc = n.description || n.name
        return nick.length > 0 && !desc.startsWith(nick)
    }

    function title(n): string {
        if (!n) return ""
        return root.nickLeads(n) ? n.nickname : (n.description || n.name)
    }

    function subtitle(n): string {
        if (!n) return ""
        return root.nickLeads(n) ? (n.description || "") : ""
    }

    function deviceGlyph(n): string {
        if (!n || !n.isSink) return "\u{F036C}"                  // nf-md-microphone
        const s = (n.name + " " + n.description).toLowerCase()
        if (s.includes("hdmi") || s.includes("displayport"))
            return "\u{F0379}"                                   // nf-md-monitor
        if (s.includes("headphone") || s.includes("headset"))
            return "\u{F02CB}"                                   // nf-md-headphones
        return "\u{F04C3}"                                       // nf-md-speaker
    }

    // --- scrim -----------------------------------------------------------
    //
    // Inset past the bar and the frame and rounded to the well, exactly as in
    // PowerMenu.qml - a square scrim dims the frame's concave corner pieces.

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
        opacity: root.revealed ? 0.35 : 0
        Behavior on opacity {
            NumberAnimation { duration: root.slideDuration; easing.type: Easing.InOutCubic }
        }
    }

    // Covers the bar too, so clicking the glyph again closes the panel rather
    // than reaching the bar underneath and reopening it.
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    readonly property int openDuration: 260
    readonly property int closeDuration: 140
    property int slideDuration: openDuration

    // --- card ------------------------------------------------------------

    // The card slides down from BEHIND the bar, and this surface is an overlay
    // above it - unclipped, the card would be drawn across the bar's right
    // pill on its way down. Clipping to the region below the bar makes it
    // emerge from the bar's bottom edge instead.
    Item {
        id: well
        anchors { fill: parent; topMargin: Theme.barHeight }
        clip: true

        Item {
            id: card

            readonly property int pad: 14

            // The extra frameThickness runs under the right frame strip, as
            // in PowerMenu.qml, so the card and the frame are one shape.
            width: 340 + Theme.frameThickness

            // Tracks the content every frame, so the dropdown opening grows
            // the card on the dropdown's own curve rather than a second one.
            height: content.implicitHeight + pad * 2

            anchors.right: parent.right
            anchors.top: parent.top

            // Closed offset includes the fillet that hangs below the card.
            // Bound to `height`, which only changes while closed when a device
            // comes or goes; that merely re-runs an invisible slide.
            anchors.topMargin: root.revealed ? 0 : -(height + Theme.cornerRadius)

            Behavior on anchors.topMargin {
                NumberAnimation {
                    duration: root.slideDuration
                    easing.type: Easing.InOutCubic
                    onRunningChanged: {
                        if (!running && !root.revealed) root.visible = false
                    }
                }
            }

            focus: true
            // Esc backs out one level: the dropdown first, then the panel.
            Keys.onEscapePressed: {
                if (root.inputsOpen) root.inputsOpen = false
                else root.close()
            }
            Keys.onRightPressed:  root.setVolume(Pipewire.defaultAudioSink,
                                                 (Pipewire.defaultAudioSink?.audio?.volume ?? 0) + 0.05)
            Keys.onLeftPressed:   root.setVolume(Pipewire.defaultAudioSink,
                                                 (Pipewire.defaultAudioSink?.audio?.volume ?? 0) - 0.05)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_M) {
                    root.toggleMute(Pipewire.defaultAudioSink)
                    event.accepted = true
                }
            }

            // Background and fillets flattened into one translucent layer -
            // see PowerMenu.qml for why layer.enabled is required.
            Item {
                id: panel
                anchors.fill: parent
                anchors.leftMargin:   -Theme.cornerRadius
                anchors.bottomMargin: -Theme.cornerRadius
                opacity: Theme.panelAlpha
                layer.enabled: true

                Rectangle {
                    id: panelBody
                    anchors.fill: parent
                    anchors.leftMargin:   Theme.cornerRadius
                    anchors.bottomMargin: Theme.cornerRadius

                    // The launcher's gradient turned upside down: this card
                    // grows out of the BAR, so its TOP stop is exactly
                    // Theme.bg and the junction has no seam.
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.bg }
                        GradientStop { position: 1.0; color: Theme.panelTop }
                    }

                    // Only the corner that is out in the open is rounded. The
                    // top edge is the bar and the right edge is the frame.
                    bottomLeftRadius: Theme.cornerRadius
                }

                // Where the card's left edge meets the bar.
                InnerCorner {
                    corner: "topright"
                    anchors { top: parent.top
                              right: panelBody.left; rightMargin: -1 }
                }

                // Where the card's bottom edge meets the right frame.
                InnerCorner {
                    corner: "topright"
                    anchors { top: panelBody.bottom; topMargin: -1
                              right: parent.right; rightMargin: Theme.frameThickness }
                }
            }

            // Swallows clicks so they do not reach the dismissing MouseArea.
            MouseArea { anchors.fill: parent }

            Column {
                id: content
                anchors {
                    top: parent.top;     topMargin: card.pad
                    left: parent.left;   leftMargin: card.pad
                    right: parent.right; rightMargin: card.pad + Theme.frameThickness
                }

                Repeater {
                    model: [
                        { label: "Output", output: true },
                        { label: "Input",  output: false }
                    ]

                    // SPACING 0, gaps built into the children instead. A
                    // positioner drops the spacing around a child the moment
                    // its height reaches 0, unanimated - so the collapsing
                    // dropdown would finish its curve and then snap shut by a
                    // few more pixels. Same trap as the OSD in Osd.qml.
                    delegate: Column {
                        id: section

                        required property var modelData
                        required property int index

                        readonly property bool output: modelData.output
                        readonly property var node: output ? Pipewire.defaultAudioSink
                                                           : Pipewire.defaultAudioSource
                        readonly property var list: output ? root.sinks : root.sources
                        readonly property real volume: node?.audio?.volume ?? 0
                        readonly property bool muted:  node?.audio?.muted ?? false

                        // Inputs hide their devices behind a dropdown.
                        readonly property bool collapsible: !output
                        readonly property bool listShown: !collapsible || root.inputsOpen

                        width: parent.width

                        // Divider between the two sections.
                        Item {
                            visible: section.index > 0
                            width: parent.width
                            height: 17
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 1
                                color: Theme.dim
                                opacity: 0.25
                            }
                        }

                        Text {
                            leftPadding: 4
                            height: 20
                            verticalAlignment: Text.AlignVCenter
                            text: section.modelData.label
                            font.family: Theme.font
                            font.weight: Theme.weightSemi
                            font.pixelSize: Theme.fontSizeSmall
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 0.8
                            color: Theme.dim
                        }

                        // --- level --------------------------------------------

                        Item {
                            width: parent.width
                            height: 44

                            // Mute toggle. The glyph shows the state it is IN,
                            // like the bar's own indicators.
                            Rectangle {
                                id: muteBtn
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                width: 32
                                height: 32
                                radius: width / 2
                                // A red wash behind the red glyph while
                                // muted, so the button reads as switched OFF
                                // rather than merely recoloured.
                                color: section.muted
                                       ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b,
                                                 muteArea.containsMouse ? 0.26 : 0.16)
                                       : muteArea.containsMouse
                                         ? Theme.surfaceHigh
                                         : Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g,
                                                   Theme.surfaceHigh.b, 0.6)
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                                Text {
                                    anchors.centerIn: parent
                                    text: section.output
                                          ? (section.muted          ? "\u{F075F}"
                                             : section.volume < 0.34 ? "\u{F057F}"
                                             : section.volume < 0.67 ? "\u{F0580}"
                                                                     : "\u{F057E}")
                                          : (section.muted ? "\u{F036D}" : "\u{F036C}")
                                    font.family: Theme.glyphFont
                                    font.pixelSize: 16
                                    // Red while muted, matching the bar's
                                    // AudioButton.
                                    color: section.muted ? Theme.danger : Theme.fg
                                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                }

                                MouseArea {
                                    id: muteArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleMute(section.node)
                                }
                            }

                            Item {
                                id: slider
                                anchors {
                                    left: muteBtn.right; leftMargin: 12
                                    right: pct.left;     rightMargin: 10
                                    verticalCenter: parent.verticalCenter
                                }
                                height: 24

                                // THE KNOB IS NOT DRAWN FROM PIPEWIRE WHILE
                                // YOU DRAG IT.
                                //
                                // It used to be: every mouse move set the
                                // volume, and the knob moved when PipeWire
                                // reported the new value back. That round
                                // trip is asynchronous and the reports arrive
                                // late and in bursts, so the knob lurched
                                // along behind the pointer instead of sitting
                                // under it.
                                //
                                // Now the pointer owns the drawn value while
                                // pressed - and for a moment after release,
                                // until PipeWire has caught up - and the
                                // volume is sent on a steady tick behind it.
                                readonly property bool held: dragArea.pressed || settle.running
                                property real dragValue: 0
                                property real lastSent: -1

                                // Everything else - wheel, arrow keys, wpctl,
                                // another app - glides instead of jumping.
                                property real smoothed: Math.max(0, Math.min(1, section.volume))
                                Behavior on smoothed {
                                    NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic }
                                }

                                readonly property real shown: held ? dragValue : smoothed

                                function send(): void {
                                    if (Math.abs(slider.dragValue - slider.lastSent) < 0.001) return
                                    slider.lastSent = slider.dragValue
                                    root.setVolume(section.node, slider.dragValue)
                                }

                                // ~30 updates a second: smooth to the ear,
                                // and not one PipeWire param change per
                                // pointer event.
                                Timer {
                                    id: sender
                                    interval: 33
                                    repeat: true
                                    running: dragArea.pressed
                                    onTriggered: slider.send()
                                }

                                Timer {
                                    id: settle
                                    interval: 300
                                }

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 4
                                    radius: 2
                                    color: Qt.rgba(Theme.dim.r, Theme.dim.g, Theme.dim.b, 0.4)

                                    // Ends at the knob's centre, not at
                                    // value * width, or the two part company
                                    // by up to half a knob at either end.
                                    Rectangle {
                                        height: parent.height
                                        radius: parent.radius
                                        width: knob.x + knob.width / 2
                                        color: section.muted ? Theme.dim : Theme.accent
                                    }
                                }

                                Rectangle {
                                    id: knob
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 14
                                    height: 14
                                    radius: width / 2
                                    x: slider.shown * (slider.width - width)
                                    color: section.muted ? Theme.dim : Theme.accent
                                    scale: dragArea.pressed || dragArea.containsMouse ? 1.2 : 1
                                    Behavior on scale { NumberAnimation { duration: Theme.animFast } }
                                }

                                MouseArea {
                                    id: dragArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    preventStealing: true
                                    cursorShape: Qt.PointingHandCursor

                                    function track(x: real): void {
                                        slider.dragValue = Math.max(0, Math.min(1,
                                            (x - knob.width / 2) / (width - knob.width)))
                                    }

                                    onPressed: mouse => {
                                        settle.stop()
                                        track(mouse.x)
                                        slider.send()
                                    }
                                    onPositionChanged: mouse => { if (pressed) track(mouse.x) }
                                    onReleased: {
                                        slider.send()
                                        settle.restart()
                                    }
                                    onWheel: wheel => root.setVolume(section.node,
                                        section.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
                                }
                            }

                            Text {
                                id: pct
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                width: 40
                                horizontalAlignment: Text.AlignRight
                                text: section.muted ? "muted"
                                    : Math.round((slider.held ? slider.dragValue : section.volume) * 100) + "%"
                                font.family: Theme.font
                                font.weight: Theme.weightMedium
                                font.pixelSize: Theme.fontSize
                                font.features: { "tnum": 1 }
                                color: section.muted ? Theme.dim : Theme.fg
                            }
                        }

                        // --- dropdown (inputs) ---------------------------------
                        //
                        // The current device, standing in for the list until
                        // it is asked for.

                        Rectangle {
                            id: picker
                            visible: section.collapsible
                            width: parent.width
                            height: 40
                            radius: 8
                            color: pickerArea.containsMouse || root.inputsOpen
                                   ? Theme.surfaceHigh
                                   : Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g,
                                             Theme.surfaceHigh.b, 0.6)
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }

                            Text {
                                id: pickerGlyph
                                anchors { left: parent.left; leftMargin: 12
                                          verticalCenter: parent.verticalCenter }
                                width: 20
                                horizontalAlignment: Text.AlignHCenter
                                text: root.deviceGlyph(section.node)
                                font.family: Theme.glyphFont
                                font.pixelSize: 16
                                color: Theme.accent
                            }

                            Text {
                                anchors {
                                    left: pickerGlyph.right; leftMargin: 10
                                    right: chevron.left;     rightMargin: 8
                                    verticalCenter: parent.verticalCenter
                                }
                                text: section.node ? root.title(section.node) : "No input device"
                                font.family: Theme.font
                                font.weight: Theme.weightMedium
                                font.pixelSize: Theme.fontSize
                                color: section.node ? Theme.fg : Theme.dim
                                elide: Text.ElideRight
                            }

                            Text {
                                id: chevron
                                anchors { right: parent.right; rightMargin: 12
                                          verticalCenter: parent.verticalCenter }
                                text: "\u{F0140}"                    // nf-md-chevron_down
                                font.family: Theme.glyphFont
                                font.pixelSize: 16
                                color: Theme.dim
                                rotation: root.inputsOpen ? 180 : 0
                                Behavior on rotation {
                                    NumberAnimation { duration: Theme.animReveal; easing.type: Easing.InOutCubic }
                                }
                            }

                            MouseArea {
                                id: pickerArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.inputsOpen = !root.inputsOpen
                            }
                        }

                        // --- devices ------------------------------------------
                        //
                        // Always laid out; a dropdown reveals it by animating
                        // the clip height, so the card grows on the same
                        // curve as the list rather than jumping.

                        Item {
                            id: listBox
                            width: parent.width
                            clip: true

                            // The gap under the dropdown button lives inside
                            // this height, so it closes with the list.
                            readonly property int lead: section.collapsible ? 4 : 0

                            height: section.listShown ? devicesCol.implicitHeight + lead : 0
                            Behavior on height {
                                enabled: section.collapsible
                                NumberAnimation { duration: Theme.animReveal; easing.type: Easing.InOutCubic }
                            }

                            opacity: section.listShown ? 1 : 0
                            Behavior on opacity {
                                enabled: section.collapsible
                                NumberAnimation { duration: Theme.animReveal; easing.type: Easing.InOutCubic }
                            }

                            Column {
                                id: devicesCol
                                y: listBox.lead
                                width: parent.width
                                spacing: 2

                                Repeater {
                                    model: section.list

                                    delegate: Rectangle {
                                        id: row

                                        required property var modelData

                                        // By id: two JS wrappers of one node
                                        // are not guaranteed to compare
                                        // identical.
                                        readonly property bool current:
                                            section.node !== null && modelData.id === section.node.id

                                        width: devicesCol.width
                                        height: root.subtitle(modelData) ? 44 : 36
                                        radius: 8

                                        // The launcher's selection wash and
                                        // marker, so "current device" and
                                        // "selected app" read as one idea.
                                        color: row.current
                                               ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                                               : rowArea.containsMouse
                                                 ? Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g,
                                                           Theme.surfaceHigh.b, 0.6)
                                                 : "transparent"
                                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                                        Rectangle {
                                            anchors { left: parent.left; leftMargin: 2
                                                      verticalCenter: parent.verticalCenter }
                                            width: 3
                                            height: row.current ? 18 : 0
                                            radius: 1.5
                                            color: Theme.accent
                                            Behavior on height {
                                                NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
                                            }
                                        }

                                        Text {
                                            id: rowGlyph
                                            anchors { left: parent.left; leftMargin: 12
                                                      verticalCenter: parent.verticalCenter }
                                            width: 20
                                            horizontalAlignment: Text.AlignHCenter
                                            text: root.deviceGlyph(row.modelData)
                                            font.family: Theme.glyphFont
                                            font.pixelSize: 16
                                            color: row.current ? Theme.accent : Theme.dim
                                        }

                                        Column {
                                            anchors {
                                                left: rowGlyph.right; leftMargin: 10
                                                right: parent.right;  rightMargin: 10
                                                verticalCenter: parent.verticalCenter
                                            }
                                            spacing: 1

                                            Text {
                                                width: parent.width
                                                text: root.title(row.modelData)
                                                font.family: Theme.font
                                                font.weight: row.current ? Theme.weightSemi : Theme.weightMedium
                                                font.pixelSize: Theme.fontSize
                                                color: Theme.fg
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                visible: text !== ""
                                                width: parent.width
                                                text: root.subtitle(row.modelData)
                                                font.family: Theme.font
                                                font.weight: Theme.weightNormal
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.letterSpacing: Theme.trackingLoose
                                                color: Theme.dim
                                                elide: Text.ElideRight
                                            }
                                        }

                                        MouseArea {
                                            id: rowArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.setDefault(row.modelData)
                                                // A choice made closes the
                                                // dropdown it was made in.
                                                if (section.collapsible) root.inputsOpen = false
                                            }
                                        }
                                    }
                                }

                                Text {
                                    visible: section.list.length === 0
                                    leftPadding: 4
                                    height: 32
                                    verticalAlignment: Text.AlignVCenter
                                    text: section.output ? "No output devices" : "No input devices"
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize
                                    color: Theme.dim
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
