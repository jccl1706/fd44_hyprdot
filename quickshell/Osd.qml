// =========================================================================
// Osd - inline volume / brightness indicator
// =========================================================================
//
// Hidden by default. Hyprland's volume and brightness keybinds poke it over
// Quickshell's IPC (see the IpcHandler in shell.qml), it slides out to the
// right of the workspaces, and hides itself again after a moment.
//
// WHY IPC RATHER THAN WATCHING THE VALUES:
// Watching would also catch changes made by other means, which sounds nicer -
// but there is no reliable way to watch backlight. /sys/class/backlight does
// not emit usable inotify events, so a FileView would never fire. Since the
// requirement is specifically "show when I press the key", having the key
// itself announce the change is both simpler and exactly right.
//
// The VALUE is still read from the real source at display time - PipeWire for
// volume, sysfs for brightness - so the number shown is the truth, not
// something this component tried to track itself.

import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

Item {
    id: root

    property color fgColor:     "#cdd6f4"
    property color dimColor:    "#6c7086"
    property color accentColor: "#89b4fa"
    property string fontFamily: "Inter Variable"
    property bool fontBold: true

    // How long the OSD stays up after the last keypress.
    property int hideDelay: 1500

    // "volume" | "brightness" | "" (hidden)
    property string mode: ""

    readonly property bool shown: mode !== ""

    // Collapses to nothing when hidden so it takes no space in the bar's row.
    implicitWidth: shown ? content.implicitWidth : 0
    implicitHeight: 18
    clip: true

    Behavior on implicitWidth {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 140 } }

    // --- sources ---------------------------------------------------------

    // Bind to the default audio sink. Quickshell tracks it, so switching
    // outputs (headphones in) follows automatically.
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    readonly property real volume: Pipewire.defaultAudioSink?.audio?.volume ?? 0
    readonly property bool muted:  Pipewire.defaultAudioSink?.audio?.muted ?? false

    // Backlight. Read on demand rather than watched - see the header note.
    FileView {
        id: brightnessFile
        path: "/sys/class/backlight/amdgpu_bl1/brightness"
    }
    FileView {
        id: maxBrightnessFile
        path: "/sys/class/backlight/amdgpu_bl1/max_brightness"
    }

    readonly property real brightness: {
        const cur = parseFloat(brightnessFile.text())
        const max = parseFloat(maxBrightnessFile.text())
        if (isNaN(cur) || isNaN(max) || max <= 0) return 0
        return cur / max
    }

    // What the bar should currently display.
    readonly property real value: mode === "brightness" ? brightness
                                : muted                 ? 0
                                                        : volume

    readonly property string glyph: {
        if (mode === "brightness") return "\u{F00DE}"        // nf-md-brightness_7
        if (muted)                 return "\u{F075F}"        // nf-md-volume_off
        if (volume < 0.34)         return "\u{F057F}"        // nf-md-volume_low
        if (volume < 0.67)         return "\u{F0580}"        // nf-md-volume_medium
        return "\u{F057E}"                                   // nf-md-volume_high
    }

    // --- public API ------------------------------------------------------

    function show(which) {
        // Re-read the backlight every time; FileView caches otherwise and the
        // OSD would show a stale value on the second press.
        if (which === "brightness") {
            brightnessFile.reload()
            maxBrightnessFile.reload()
        }
        root.mode = which
        hideTimer.restart()
    }

    Timer {
        id: hideTimer
        interval: root.hideDelay
        onTriggered: root.mode = ""
    }

    // --- visuals ---------------------------------------------------------

    Row {
        id: content
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.glyph
            font.family: "Symbols Nerd Font"
            font.pixelSize: 14
            color: root.muted && root.mode === "volume" ? root.dimColor : root.fgColor
        }

        // Track with a filled portion. Fixed width so the bar does not jitter
        // as the value changes.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 70
            height: 4
            radius: 2
            color: Qt.rgba(root.dimColor.r, root.dimColor.g, root.dimColor.b, 0.4)

            Rectangle {
                height: parent.height
                radius: parent.radius
                width: parent.width * Math.max(0, Math.min(1, root.value))
                color: root.muted && root.mode === "volume" ? root.dimColor : root.accentColor
                Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.muted && root.mode === "volume"
                  ? "muted"
                  : Math.round(root.value * 100) + "%"
            font.family: root.fontFamily
            font.bold: root.fontBold
            font.pixelSize: 11
            font.features: { "tnum": 1 }
            color: root.fgColor
            // Reserve the width of the widest label so the track does not
            // shift when 9% becomes 10%.
            width: 34
            horizontalAlignment: Text.AlignRight
        }
    }
}
