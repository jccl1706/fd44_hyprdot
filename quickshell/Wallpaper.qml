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

    readonly property int fadeDuration: 700

    // Decoded at the monitor's real pixel size, both dimensions: with both
    // set and PreserveAspectCrop, Qt scales the image to COVER the screen at
    // decode time, so nothing is stored bigger than the panel (one wallpaper
    // is 7680x4320) and nothing is upscaled at draw time either.
    readonly property int pixelWidth:  screen ? Math.round(screen.width  * screen.devicePixelRatio) : 2560
    readonly property int pixelHeight: screen ? Math.round(screen.height * screen.devicePixelRatio) : 1440

    property Image base: imageA
    property Image over: imageB

    readonly property string target: WallpaperState.path
    onTargetChanged: root.show(root.target)
    Component.onCompleted: root.show(root.target)

    function show(p: string): void {
        if (!p) return
        const url = "file://" + p
        if (String(root.base.source) === url && String(root.over.source) === "") return
        fade.stop()
        root.over.opacity = 0
        root.over.source = url
        // A cache hit can be Ready before any status change is signalled.
        if (root.over.status === Image.Ready) root.startFade()
    }

    function startFade(): void {
        fade.target = root.over
        fade.start()
    }

    NumberAnimation {
        id: fade
        property: "opacity"
        from: 0
        to: 1
        duration: root.fadeDuration
        easing.type: Easing.InOutCubic
        onFinished: {
            // A fade stopped halfway by a newer choice is not a finished one.
            if (root.over.opacity < 1) return
            root.base.source = ""
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
