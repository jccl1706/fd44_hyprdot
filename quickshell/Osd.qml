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


    // How long the OSD stays up after the last keypress.
    property int hideDelay: Settings.osdHideMs   // default 1500, as it was

    // "volume" | "brightness" | "" (hidden). This decides VISIBILITY ONLY.
    property string mode: ""

    readonly property bool shown: mode !== ""

    // What to DRAW. Deliberately a separate property, and deliberately never
    // cleared.
    //
    // These two used to be one. `mode` going to "" on hide did not just start
    // the fade, it also changed the content underneath it: `glyph` and `value`
    // both fell through their brightness branches to the volume ones, and the
    // filled track - which has a Behavior of its own - then animated from the
    // brightness level to the volume level while the whole thing was fading
    // out. So dismissing a brightness OSD showed you a volume OSD for 200ms on
    // the way out. That was the skip.
    //
    // Keeping the last mode means the indicator fades out showing exactly what
    // it was showing when it was asked to go away.
    property string drawMode: "volume"

    // THE LEADING GAP BELONGS TO THIS ITEM, not to the Row's spacing.
    //
    // This used to sit inside the bar's Row and rely on Row.spacing for the
    // gap between it and the workspaces. A positioner stops allocating
    // spacing for a child once that child's width reaches 0 - and it does so
    // on the next layout pass, instantly and unanimated. So the width would
    // collapse smoothly over its full 220ms, finish, and then a frame later
    // the pill would snap a further 12px shut. Every curve in here animated
    // the part that was already smooth; the snap was the one piece of the
    // motion that was never animated at all.
    //
    // Owning the gap means it collapses on the same curve as everything else.
    readonly property int leadGap: Theme.itemSpacing

    // Collapses to nothing when hidden so it takes no space in the bar.
    implicitWidth: shown ? leadGap + content.implicitWidth : 0
    implicitHeight: 18
    clip: true

    // ONE CURVE FOR THE WHOLE REVEAL.
    //
    // This was three animations on three different durations: the width on
    // animSlow, the opacity on animNormal with NO easing specified - so
    // Easing.Linear, the least fluid curve there is - and the bar pill that
    // contains it on a third. Nothing landed at the same moment, which is what
    // read as stutter rather than as slowness.
    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.animReveal; easing.type: Easing.InOutCubic }
    }

    opacity: shown ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: Theme.animReveal; easing.type: Easing.InOutCubic }
    }

    // --- sources ---------------------------------------------------------

    // Bind to the default audio sink. Quickshell tracks it, so switching
    // outputs (headphones in) follows automatically.
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    readonly property real volume: Pipewire.defaultAudioSink?.audio?.volume ?? 0
    readonly property bool muted:  Pipewire.defaultAudioSink?.audio?.muted ?? false

    // Backlight. Read on demand rather than watched - see the header note.
    //
    // THE DEVICE IS RESOLVED, NOT NAMED. It used to be `amdgpu_bl1`, which is
    // this laptop's panel: an Intel machine calls it intel_backlight and a
    // DESKTOP HAS NONE. bin/backlight.sh finds it in /sys/class/backlight and
    // prints nothing when there is none, so on a machine without a backlight
    // `backlightPath` stays empty, both FileViews have no path to read, and
    // `brightness` falls back to 0 - which is only ever displayed if something
    // asks for the brightness OSD, and nothing does, because the keys that
    // trigger it also do nothing there.
    property string backlightPath: ""

    Process {
        running: true
        command: ["sh", "-c",
                  "\"$(dirname \"$(readlink -f '" + Quickshell.shellDir + "')\")/bin/backlight.sh\" path"]
        stdout: StdioCollector {
            onStreamFinished: root.backlightPath = text.trim()
        }
    }

    FileView {
        id: brightnessFile
        path: root.backlightPath ? root.backlightPath + "/brightness" : ""
    }
    FileView {
        id: maxBrightnessFile
        path: root.backlightPath ? root.backlightPath + "/max_brightness" : ""
    }

    readonly property real brightness: {
        const cur = parseFloat(brightnessFile.text())
        const max = parseFloat(maxBrightnessFile.text())
        if (isNaN(cur) || isNaN(max) || max <= 0) return 0
        return cur / max
    }

    // What the bar should currently display.
    readonly property real value: drawMode === "brightness" ? brightness
                                : muted                     ? 0
                                                            : volume

    readonly property string glyph: {
        if (drawMode === "brightness") return "\u{F00DE}"    // nf-md-brightness_7
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
        // drawMode first: it must already be correct before anything that
        // reacts to `mode` starts drawing.
        root.drawMode = which
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
        x: root.leadGap
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        // The content SLIDES, it is not merely unveiled. With clip:true and
        // only the width animating, the glyph was uncovered by a hard edge
        // sweeping across it while the glyph itself stayed put - the eye reads
        // that as a wipe, not as movement. Translating it in just behind the
        // opening edge is what makes the indicator look like it came out of
        // the workspaces beside it.
        transform: Translate {
            x: root.shown ? 0 : -12
            Behavior on x {
                NumberAnimation { duration: Theme.animReveal; easing.type: Easing.InOutCubic }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.glyph
            font.family: Theme.glyphFont
            font.pixelSize: 14
            color: root.muted && root.drawMode === "volume" ? Theme.dim : Theme.fg
        }

        // Track with a filled portion. Fixed width so the bar does not jitter
        // as the value changes.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 70
            height: 4
            radius: 2
            color: Qt.rgba(Theme.dim.r, Theme.dim.g, Theme.dim.b, 0.4)

            Rectangle {
                height: parent.height
                radius: parent.radius
                width: parent.width * Math.max(0, Math.min(1, root.value))
                color: root.muted && root.drawMode === "volume" ? Theme.dim : Theme.accent
                Behavior on width { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.muted && root.drawMode === "volume"
                  ? "muted"
                  : Math.round(root.value * 100) + "%"
            font.family: Theme.font
            font.weight: Theme.weightMedium
            font.pixelSize: Theme.fontSize
            font.features: { "tnum": 1 }
            color: Theme.fg
            // Reserve the width of the widest label so the track does not
            // shift when 9% becomes 10%.
            width: 34
            horizontalAlignment: Text.AlignRight
        }
    }
}
