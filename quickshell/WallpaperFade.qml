// =========================================================================
// WallpaperFade - crossfades one wallpaper into the next
// =========================================================================
//
// hyprpaper swaps wallpapers instantly and has no transition of any kind.
// Neither does swaybg, and swww - which does - is not packaged for Fedora.
// So the fade is done here instead, with hyprpaper still owning the actual
// persistent wallpaper.
//
// HOW IT HIDES THE SWAP:
//
//   1. this surface appears with the NEW image at opacity 0
//   2. it fades to 1     -> the crossfade you see, over the old wallpaper
//   3. hyprpaper is told to switch, while this surface is FULLY OPAQUE,
//      so its instant swap happens behind a curtain and is never seen
//   4. it fades back to 0 -> revealing hyprpaper showing the same image,
//      so nothing appears to change
//   5. unmapped
//
// Step 3 is the whole point. Fading out over a wallpaper that had already
// changed would show the switch at the start instead of the end; doing it
// at full opacity means there is no frame in which the two disagree.
//
// LAYER: Bottom, not Overlay or Background.
//   - above Background, where hyprpaper draws, or it would be behind the
//     thing it is trying to cover
//   - below windows, because a wallpaper change should only be visible
//     where the desktop is actually visible
//
// The input region is emptied: this covers the whole screen for about a
// second and must never swallow a click on the desktop.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    // Path to bin/wallpaper.sh, handed down by shell.qml.
    property string setterScript: ""

    property bool covering: false
    property string pendingPath: ""

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "quickshell-wallpaper-fade"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: false
    mask: Region {}

    // How long each half of the crossfade takes. The whole gesture is twice
    // this plus however long hyprpaper needs in the middle.
    readonly property int fadeDuration: 420

    // --- public API ------------------------------------------------------

    function fadeTo(path): void {
        if (!path || !root.setterScript) return
        root.pendingPath = path
        image.source = "file://" + path
        root.visible = true
        // If the image cannot be shown there is nothing to fade behind, so
        // skip straight to applying it rather than covering the screen with
        // a blank rectangle.
        if (image.status === Image.Error) {
            root.applyNow()
            return
        }
        root.covering = true
    }

    function applyNow(): void {
        setter.command = [root.setterScript, "set", root.pendingPath]
        setter.running = true
    }

    Process {
        id: setter
        onExited: (code, status) => {
            if (code !== 0) console.warn("wallpaper.sh failed with", code)
            // Uncover regardless: leaving the curtain up on a failure would
            // freeze the desktop's wallpaper at an image that is not set.
            root.covering = false
        }
    }

    Image {
        id: image
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        // Full size: this is standing in for the real wallpaper, so it has to
        // be as sharp as the thing it hands over to. Not the picker's 960px
        // preview.
        sourceSize.width: root.screen ? root.screen.width * root.screen.devicePixelRatio : 2560
        asynchronous: true

        opacity: root.covering ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: root.fadeDuration
                easing.type: Easing.InOutCubic

                onRunningChanged: {
                    if (running) return
                    if (root.covering) {
                        // Fully opaque now - safe to swap underneath.
                        root.applyNow()
                    } else {
                        // Fully transparent again; hyprpaper is showing the
                        // same image, so there is nothing left to draw.
                        root.visible = false
                        image.source = ""
                    }
                }
            }
        }
    }
}
