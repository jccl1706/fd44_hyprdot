// =========================================================================
// Wallpaper - the desktop background, drawn by quickshell itself
// =========================================================================
//
// One per monitor, on the Background layer. There is no wallpaper daemon:
// hyprpaper came from a COPR that shipped a build aborting on start, swaybg
// cannot change an image without a new process, and neither has transitions.
// An Image in a layer-shell surface does all of it, and a change is simply a
// crossfade.
//
// WHICH IMAGE comes from WallpaperState, which watches the state file that
// bin/wallpaper.sh writes.
//
// HOW THE FADE WORKS. Two Images, `base` (showing) and `over` (on top). A new
// wallpaper loads into `over` at opacity 0; once it has decoded, `over` fades
// to 1 over `base`; then `base` is emptied and the two swap roles. So at most
// two full-size images are ever held, and only during the fade. Waiting for
// the decode matters: fading in an image that is still loading would fade in
// nothing and then pop.
//
// IT ALSO SETTLES: the incoming wallpaper starts four percent oversized and
// eases down to its true size while it fades, which reads as the picture
// coming to rest rather than simply appearing. Four percent is deliberately
// almost too small to name - at eight the movement is a visible slide and
// draws the eye to a change nobody asked to be shown, which is the wrong
// manners for something that happens by itself every hour.
//
// SCALING UP AND NOT DOWN, so the image covers the screen for every frame of
// the animation. Starting under 1.0 would show the desktop behind the
// wallpaper at the edges, and PreserveAspectCrop only guarantees cover at the
// size it decoded for. OutCubic rather than InOutCubic because the motion
// should arrive quickly and ease to a stop, not creep away from where it
// started.
//
// WHILE QUICKSHELL RESTARTS this surface is gone for about a second, and
// Hyprland paints misc.background_color, which bin/theme.sh keeps at the
// theme's background - see hypr/look.lua.
//
// Input is disabled: the desktop is not clickable, and this must never be
// what swallows a click.

import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell-wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    // What shows before the first image decodes, or if it cannot be read.
    color: Theme.bg
    mask: Region {}

    readonly property int fadeDuration: 1200

    // Where the incoming wallpaper starts. See the note above on why it is
    // small, and why it is above 1.0 rather than below.
    readonly property real zoomFrom: 1.04

    // Decoded at the monitor's real pixel size, both dimensions: with both
    // set and PreserveAspectCrop, Qt scales the image to COVER the screen at
    // decode time, so nothing is stored bigger than the panel (one wallpaper
    // is 7680x4320) and nothing is upscaled at draw time either.
    readonly property int pixelWidth:  screen ? Math.round(screen.width  * screen.devicePixelRatio) : 2560
    readonly property int pixelHeight: screen ? Math.round(screen.height * screen.devicePixelRatio) : 1440

    property Image base: imageA
    property Image over: imageB

    // The animations bind to this rather than taking a target when they start:
    // a ParallelAnimation does not hand its target down to its children, so
    // each one needs to know for itself which image is coming in.
    property Image incoming: null

    readonly property string target: WallpaperState.path
    onTargetChanged: root.show(root.target)
    Component.onCompleted: root.show(root.target)

    function show(p: string): void {
        if (!p) return
        const url = "file://" + p
        if (String(root.base.source) === url && String(root.over.source) === "") return
        fade.stop()
        root.over.opacity = 0
        root.over.scale = root.zoomFrom
        root.over.source = url
        // A cache hit can be Ready before any status change is signalled.
        if (root.over.status === Image.Ready) root.startFade()
    }

    function startFade(): void {
        root.incoming = root.over
        fade.start()
    }

    ParallelAnimation {
        id: fade

        NumberAnimation {
            target: root.incoming
            property: "opacity"
            from: 0
            to: 1
            duration: root.fadeDuration
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: root.incoming
            property: "scale"
            from: root.zoomFrom
            to: 1
            duration: root.fadeDuration
            easing.type: Easing.OutCubic
        }

        onFinished: {
            // A fade stopped halfway by a newer choice is not a finished one.
            if (root.over.opacity < 1) return
            root.base.source = ""
            // The outgoing image keeps whatever scale it ended on, and it is
            // about to become the one a future wallpaper loads into. Left at
            // 1.04 it would start its next fade already settled and never
            // move, so the reset belongs here rather than in show().
            root.base.scale = 1
            const previous = root.base
            root.base = root.over
            root.over = previous
        }
    }

    component Layer: Image {
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: root.pixelWidth
        sourceSize.height: root.pixelHeight
        asynchronous: true
        z: this === root.over ? 1 : 0

        onStatusChanged: {
            if (this !== root.over) return
            if (status === Image.Ready && opacity === 0) {
                root.startFade()
            } else if (status === Image.Error) {
                // Keep showing what was there rather than fading to nothing.
                console.warn("wallpaper: cannot load", source)
                source = ""
            }
        }
    }

    Layer { id: imageA }
    Layer { id: imageB; opacity: 0 }
}
