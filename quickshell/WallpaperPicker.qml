// =========================================================================
// WallpaperPicker - a coverflow strip of wallpapers
// =========================================================================
//
// Hidden until IPC opens it (Super+comma, see binds.lua). Every wallpaper in
// the repo's wallpapers/ directory is laid edge to edge across a band in the
// middle of the screen, squeezed to narrow slivers - except the selected one,
// which expands to full size in the centre with its name underneath.
//
// WHY A STRIP AND NOT A GRID:
// A grid shows eleven thumbnails at once and asks you to judge them at
// postage-stamp size. A strip shows ONE at a size you can actually see, and
// uses the slivers purely as a position indicator - how far through the set
// you are, and roughly what is coming - which is all the others need to say.
// It also scales: a grid of eighty wallpapers is a mess, a strip of eighty is
// the same strip.
//
// It does NOT talk to hyprpaper itself. bin/wallpaper.sh does that, because
// applying a wallpaper and REMEMBERING it are two different jobs: hyprpaper
// forgets everything when it restarts. Keeping that in one script means the
// picker, the keybind and autostart all go through the same code path.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    property bool revealed: false
    property int selected: 0

    // --- geometry --------------------------------------------------------

    readonly property int bandHeight:  300   // the sliver strip
    readonly property int selWidth:    520   // the expanded, centred one
    readonly property int selHeight:   340   // taller, so it breaks the band
    readonly property int sliverWidth:  54

    // How far each tile leans, in degrees. Expressed as an ANGLE rather than
    // a pixel offset on purpose: the slivers and the expanded tile are
    // different heights, and only a shared angle keeps their slanted edges
    // parallel. Parallel edges are what lets the tiles interlock with no gap
    // between them - a parallelogram tiles against its neighbour exactly.
    readonly property real leanAngle: 7

    // THE ONE DECODE SIZE. Every Image that loads a wallpaper must use this.
    //
    // Qt's pixmap cache keys on the URL *and the sourceSize*. Two Images of
    // the same file at different sourceSizes are two separate cache entries
    // and two separate decodes - which is how an attempt to speed this up by
    // adding a cheap 160px "base" image underneath made it slower: the base
    // matched nothing that had been pre-decoded, so every tile decoded its
    // full 4K-to-8K frame again on open.
    //
    // selWidth is logical; this panel renders at 1.567, so 1.6 covers the
    // expanded tile at native resolution with nothing to spare.
    readonly property int decodeWidth: Math.round(selWidth * 1.6)

    // --- where the repo is -----------------------------------------------
    //
    // Cannot be done with Qt.resolvedUrl("../wallpapers"): Quickshell
    // deliberately BLACKHOLES any path that escapes the config directory and
    // returns "qrc:/qs-blackhole" rather than an error, so the folder model
    // reports zero files and it looks like an empty directory.
    //
    // Quickshell.shellDir is no good alone either - it is the config path,
    // ~/.config/quickshell, with the symlink NOT resolved, so appending
    // "/../wallpapers" lands in ~/.config. readlink -f resolves it to the
    // real directory inside the repo; its parent is the repo root. On a
    // copied rather than symlinked config this still works, because
    // readlink -f on a plain directory returns the directory.
    property string repoRoot: ""

    Process {
        running: true
        command: ["sh", "-c", "dirname \"$(readlink -f '" + Quickshell.shellDir + "')\""]
        stdout: StdioCollector {
            onStreamFinished: root.repoRoot = text.trim()
        }
    }

    readonly property string setterScript: repoRoot ? repoRoot + "/bin/wallpaper.sh" : ""

    // THE PICKER READS PREVIEWS, NOT WALLPAPERS.
    //
    // The originals are 2560px wide and the set is ~38 megapixels - enough
    // that decoding them was a visible pause on the keypress however the work
    // was scheduled. bin/wallpaper.sh generates 960px previews into the cache
    // directory; the whole set is then ~6 MP and 368 KB.
    //
    // The path comes FROM the script rather than being rebuilt here, so there
    // is one definition of where previews live instead of two that can drift.
    property string thumbDir: ""

    Process {
        id: thumbDirReader
        running: root.setterScript !== ""
        command: root.setterScript ? [root.setterScript, "thumbdir"] : []
        stdout: StdioCollector {
            onStreamFinished: root.thumbDir = text.trim()
        }
    }

    // Falls back to the originals when no previews have been generated yet -
    // a fresh install before autostart has run once. Slower, but showing the
    // wallpapers beats showing an empty picker.
    readonly property url wallpaperDir:
        thumbDir ? "file://" + thumbDir
        : repoRoot ? "file://" + repoRoot + "/wallpapers"
        : ""

    // --- window ----------------------------------------------------------

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-wallpapers"
    WlrLayershell.keyboardFocus: revealed ? WlrKeyboardFocus.Exclusive
                                          : WlrKeyboardFocus.None

    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: false

    // --- model -----------------------------------------------------------

    FolderListModel {
        id: files
        folder: root.wallpaperDir
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
        showDirs: false
        sortField: FolderListModel.Name
    }

    // --- public API ------------------------------------------------------

    function open(): void {
        root.visible = true
        root.revealed = true
        strip.forceActiveFocus()
        // Start on whatever is actually on screen rather than always at the
        // first file. Useful in its own right - you open the picker to change
        // the wallpaper, so the one you have is the reference point - and it
        // also means the strip normally opens with slivers on BOTH sides
        // instead of a bare half-screen, which is what index 0 looks like.
        if (root.setterScript) currentReader.running = true
    }

    Process {
        id: currentReader
        command: root.setterScript ? [root.setterScript, "current"] : []
        stdout: StdioCollector {
            onStreamFinished: {
                const cur = text.trim()
                if (!cur) return
                for (let i = 0; i < files.count; i++) {
                    if (String(files.get(i, "filePath")) === cur) {
                        // Jump, do not sweep. Without this the strip would
                        // animate all the way from wherever it was left - on
                        // the first open of a session, from index 0 - which
                        // reads as the picker scrolling to find itself.
                        strip.snap = true
                        root.selected = i
                        strip.snap = false
                        return
                    }
                }
            }
        }
    }

    function close(): void { root.revealed = false }

    function toggle(): void {
        if (root.revealed) root.close()
        else root.open()
    }

    // Emitted with the ORIGINAL wallpaper's path. shell.qml hands it to
    // WallpaperFade, which crossfades and then applies it - the picker does
    // not run the script itself any more, because the fade has to be able to
    // sequence the swap behind its own curtain.
    // The script path travels with the request: the picker is what resolved
    // the repo root, and the fade surface has no way of its own to find it.
    signal applyRequested(string path, string script)

    function apply(path): void {
        if (!path) return
        if (!root.repoRoot) {
            console.warn("wallpaper: repo root not resolved yet")
            return
        }
        root.close()

        // The model lists PREVIEWS, which live in the cache and are always
        // .webp. The original keeps the same basename in wallpapers/, so it
        // can be named directly - and the fade needs the full-size file, not
        // the 960px preview it would otherwise be handed.
        const name = String(path).split("/").pop()
        root.applyRequested(root.repoRoot + "/wallpapers/" + name, root.setterScript)
    }

    function applySelected(): void {
        root.apply(files.get(root.selected, "fileUrl"))
    }

    // Clamped rather than wrapping: running off the end of a carousel and
    // reappearing at the other end loses your place in a way a grid does not.
    function move(delta: int): void {
        const n = files.count
        if (n === 0) return
        root.selected = Math.max(0, Math.min(n - 1, root.selected + delta))
    }

    // --- cache warming ---------------------------------------------------
    //
    // WHY THE PREVIEW FELT SLOW, AND WHY THIS FIXES IT.
    //
    // The tiles live in a ListView, which creates delegates lazily - so not
    // one image began decoding until the picker was opened. Every press paid
    // the whole cost up front: these wallpapers total 159 MEGAPIXELS (one is
    // 7680x4320, against a 2256x1504 panel), and sourceSize does not help,
    // because libwebp decodes the full frame before it downscales.
    //
    // These Images are created when the shell starts and are never shown.
    // Setting `source` is what triggers a decode - visibility has nothing to
    // do with it - so the work happens in the background shortly after login
    // and lands in Qt's pixmap cache. By the time the key is pressed the
    // ListView's own Images resolve to cache hits.
    //
    // Now that the model points at 960px previews this is nearly free, but it
    // is kept: it guarantees the first press of the session is a cache hit
    // rather than merely a fast decode.
    Repeater {
        model: files
        delegate: Image {
            required property url fileUrl
            source: fileUrl
            sourceSize.width: root.decodeWidth
            asynchronous: true
            visible: false
            width: 0
            height: 0
        }
    }

    // --- scrim -----------------------------------------------------------
    //
    // Lighter than a modal dialog's would be. The point of this picker is
    // judging images against the desktop they are going to sit on, so the
    // desktop stays visible; the scrim only stops a busy wallpaper competing
    // with the strip.

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: root.revealed ? 0.45 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.animReveal; easing.type: Easing.InOutCubic }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    // --- the strip -------------------------------------------------------

    Item {
        id: bandWrap
        anchors { left: parent.left; right: parent.right
                  verticalCenter: parent.verticalCenter }
        height: root.selHeight

        opacity: root.revealed ? 1 : 0
        scale: root.revealed ? 1 : 0.96

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animReveal
                easing.type: Easing.InOutCubic
                onRunningChanged: {
                    if (!running && !root.revealed) root.visible = false
                }
            }
        }
        Behavior on scale {
            NumberAnimation { duration: Theme.animReveal; easing.type: Easing.InOutCubic }
        }

        // ONE ANIMATED VALUE DRIVES EVERYTHING.
        //
        // This was a ListView with StrictlyEnforceRange and animated delegate
        // widths, and the two fought: the view computed where to scroll from
        // the delegates' positions, while those positions were themselves
        // mid-animation. Measured, the scroll snapped 153px and recovered
        // instead of moving, and collapsing the highlight range to a point
        // only changed the shape of the snap.
        //
        // There is no scrolling here at all now. `pos` is a real number that
        // animates from the old index to the new one, and every tile's width,
        // height, position and emphasis is a pure function of its distance
        // from it. Nothing can race anything else, because there is only one
        // thing moving.
        Item {
            id: strip
            anchors.fill: parent
            focus: true

            // Set true around an assignment to selected that should take
            // effect immediately rather than animate - see currentReader.
            property bool snap: false

            property real pos: root.selected
            Behavior on pos {
                enabled: !strip.snap
                NumberAnimation { duration: Theme.animReveal
                                  easing.type: Easing.InOutCubic }
            }

            readonly property real expand: root.selWidth - root.sliverWidth

            // How expanded tile i is, 0..1. Continuous, so the border, the
            // veil and the height all cross-fade between neighbours instead
            // of popping the moment the selection index changes.
            function grow(i) { return Math.max(0, 1 - Math.abs(i - strip.pos)) }

            function widthAt(i) { return root.sliverWidth + strip.expand * strip.grow(i) }

            function leftAt(i) {
                // Slivers are uniform, so only the expanding neighbours add
                // anything. O(n) per tile is nothing at this size and keeps
                // the arithmetic obvious.
                let x = i * root.sliverWidth
                for (let j = 0; j < i; j++) x += strip.expand * strip.grow(j)
                return x
            }

            // Slide the whole strip so the focused point sits dead centre,
            // interpolating between the two tiles `pos` currently lies
            // between - which is what keeps the motion continuous rather
            // than stepping from one tile's centre to the next.
            readonly property real offset: {
                const k = Math.floor(strip.pos)
                const f = strip.pos - k
                const c0 = strip.leftAt(k)   + strip.widthAt(k)   / 2
                const c1 = strip.leftAt(k+1) + strip.widthAt(k+1) / 2
                return strip.width / 2 - (c0 * (1 - f) + c1 * f)
            }

            Keys.onEscapePressed: root.close()
            Keys.onLeftPressed:   root.move(-1)
            Keys.onRightPressed:  root.move(1)
            Keys.onReturnPressed: root.applySelected()
            Keys.onEnterPressed:  root.applySelected()

            Repeater {
                model: files

                delegate: Item {
                    id: cell
                    required property int index
                    required property url fileUrl
                    required property string fileName

                    readonly property real t: strip.grow(cell.index)

                    x: strip.leftAt(cell.index) + strip.offset
                    y: 0
                    width: strip.widthAt(cell.index)
                    height: root.selHeight

                    // Off-screen tiles cost nothing to skip, and with eighty
                    // wallpapers most of them are off-screen.
                    visible: x + width > -40 && x < strip.width + 40

                    Item {
                        id: tile
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: root.bandHeight + (root.selHeight - root.bandHeight) * cell.t

                        // The lean. A horizontal shear: x displaced in
                        // proportion to y, so the vertical edges tip over
                        // while top and bottom stay level - a rectangle
                        // becomes a parallelogram, not a rotated rectangle.
                        //
                        // Sheared about the MIDDLE (the +k*h/2 term). Without
                        // it the tile would also slide sideways as it leans.
                        transform: Matrix4x4 {
                            readonly property real k: Math.tan(root.leanAngle * Math.PI / 180)
                            matrix: Qt.matrix4x4(1, -k, 0, k * tile.height / 2,
                                                 0,  1, 0, 0,
                                                 0,  0, 1, 0,
                                                 0,  0, 0, 1)
                        }

                        Image {
                            anchors.fill: parent
                            // Must match the warm-up's sourceSize exactly:
                            // Qt's pixmap cache keys on it, so any other
                            // value is a second cache entry and a re-decode.
                            sourceSize.width: root.decodeWidth
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            source: cell.fileUrl
                        }

                        // Unselected tiles are pushed back, proportionally,
                        // so the centre one reads as lit rather than merely
                        // larger.
                        Rectangle {
                            anchors.fill: parent
                            color: "#000000"
                            opacity: 0.45 * (1 - cell.t)
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.width: 2
                            border.color: Qt.rgba(1, 1, 1, cell.t)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        // First click centres a tile, a second applies it -
                        // choosing from a 54px sliver would mean picking a
                        // wallpaper you cannot see.
                        onClicked: {
                            if (cell.index === root.selected) root.applySelected()
                            else root.selected = cell.index
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: files.count === 0
                text: "No images in wallpapers/"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                color: "#ffffff"
            }
        }
    }

    // --- name ------------------------------------------------------------

    Text {
        anchors { horizontalCenter: parent.horizontalCenter
                  top: bandWrap.bottom; topMargin: 18 }
        text: files.count > 0
              ? String(files.get(root.selected, "fileName") || "").replace(/\.[^.]+$/, "")
              : "No images in wallpapers/"
        font.family: Theme.font
        font.weight: Theme.weightMedium
        font.pixelSize: Theme.fontSizeTitle
        color: "#ffffff"
        opacity: root.revealed ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.animReveal; easing.type: Easing.InOutCubic }
        }

        // A soft shadow: this sits directly on the wallpaper rather than on a
        // panel, so it has no guaranteed contrast behind it.
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 0.6
            shadowOpacity: 0.8
            shadowColor: "#000000"
        }
    }
}
