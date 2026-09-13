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
        return root.nickLeads(n) ? n.nickname : (n.description || n.name)
    }

    function subtitle(n): string {
        return root.nickLeads(n) ? (n.description || "") : ""
    }

    function deviceGlyph(n): string {
        if (!n.isSink) return "\u{F036C}"                        // nf-md-microphone
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
            height: content.implicitHeight + pad * 2

            anchors.right: parent.right
            anchors.top: parent.top

            // Closed offset includes the fillet that hangs below the card.
            // Bound to `height`, which only changes when a device comes or
            // goes; while closed that merely re-runs an invisible slide.
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
            Keys.onEscapePressed: root.close()
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
                spacing: 0

                Repeater {
                    model: [
                        { label: "Output", output: true },
                        { label: "Input",  output: false }
                    ]

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

                        width: parent.width
                        spacing: 2

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
                                color: muteArea.containsMouse ? Theme.surfaceHigh
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
                                    color: section.muted ? Theme.dim : Theme.fg
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

                                readonly property real value: Math.max(0, Math.min(1, section.volume))
                                readonly property bool engaged: dragArea.pressed || dragArea.containsMouse

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
                                    x: slider.value * (slider.width - width)
                                    color: section.muted ? Theme.dim : Theme.accent
                                    scale: slider.engaged ? 1.2 : 1
                                    Behavior on scale { NumberAnimation { duration: Theme.animFast } }
                                }

                                // No Behavior on the value: a slider that eases
                                // towards the pointer feels like it is lagging
                                // behind the drag.
                                MouseArea {
                                    id: dragArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    preventStealing: true
                                    cursorShape: Qt.PointingHandCursor

                                    function seek(x: real): void {
                                        root.setVolume(section.node,
                                                       (x - knob.width / 2) / (width - knob.width))
                                    }

                                    onPressed: mouse => seek(mouse.x)
                                    onPositionChanged: mouse => { if (pressed) seek(mouse.x) }
                                    onWheel: wheel => root.setVolume(section.node,
                                        section.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
                                }
                            }

                            Text {
                                id: pct
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                width: 40
                                horizontalAlignment: Text.AlignRight
                                text: section.muted ? "muted" : Math.round(section.volume * 100) + "%"
                                font.family: Theme.font
                                font.weight: Theme.weightMedium
                                font.pixelSize: Theme.fontSize
                                font.features: { "tnum": 1 }
                                color: section.muted ? Theme.dim : Theme.fg
                            }
                        }

                        // --- devices ------------------------------------------

                        Repeater {
                            model: section.list

                            delegate: Rectangle {
                                id: row

                                required property var modelData

                                // By id: two JS wrappers of one node are not
                                // guaranteed to compare identical.
                                readonly property bool current:
                                    section.node !== null && modelData.id === section.node.id

                                width: section.width
                                height: root.subtitle(modelData) ? 44 : 36
                                radius: 8

                                // The launcher's selection wash and marker, so
                                // "current device" and "selected app" read as
                                // the same idea.
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
                                    onClicked: root.setDefault(row.modelData)
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
