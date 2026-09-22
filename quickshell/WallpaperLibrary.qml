// =========================================================================
// WallpaperLibrary - the set of wallpapers, and where their previews live
// =========================================================================
//
// One place that knows: where the repo is, where bin/wallpaper.sh is, where
// the generated previews are, and what the list of wallpapers actually is.
//
// A SINGLETON BECAUSE THERE ARE NOW TWO VIEWS OF THE SAME SET - the coverflow
// picker (WallpaperPicker.qml, Super+comma) and the grid on the settings
// panel's Appearance page. Both need the same three paths resolved by running
// the same two commands, and WallpaperPicker's own comment already warned
// about the failure this avoids: "the path comes FROM the script rather than
// being rebuilt here, so there is one definition of where previews live
// instead of two that can drift."
//
// It does not draw anything and it does not record anything. choose() hands
// the path to WallpaperState, which fades every monitor to it and has
// bin/wallpaper.sh write it down - so the picker, the grid, a terminal and
// autostart all end up in the same code path.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel

Singleton {
    id: library

    // ~/.config/quickshell is a symlink into the checkout, so the shell dir is
    // a real directory inside the repo and its parent is the repo root. On a
    // copied rather than symlinked config this still works, because readlink
    // -f on a plain directory returns the directory.
    property string repoRoot: ""

    Process {
        running: true
        command: ["sh", "-c", "dirname \"$(readlink -f '" + Quickshell.shellDir + "')\""]
        stdout: StdioCollector {
            onStreamFinished: library.repoRoot = text.trim()
        }
    }

    readonly property string setterScript: repoRoot ? repoRoot + "/bin/wallpaper.sh" : ""

    // THE VIEWS READ PREVIEWS, NOT WALLPAPERS.
    //
    // The originals are 2560px wide and the set is ~38 megapixels - enough
    // that decoding them was a visible pause on the keypress however the work
    // was scheduled. bin/wallpaper.sh generates 960px previews into the cache
    // directory; the whole set is then ~6 MP and 368 KB.
    property string thumbDir: ""

    Process {
        id: thumbDirReader
        running: library.setterScript !== ""
        command: library.setterScript ? [library.setterScript, "thumbdir"] : []
        stdout: StdioCollector {
            onStreamFinished: library.thumbDir = text.trim()
        }
    }

    // Ask again. On a first login the previews are still being generated when
    // the shell starts, so the answer at startup is "none yet" - without this
    // the views would use the full-size originals for the rest of the session.
    function rescan(): void {
        if (library.setterScript) thumbDirReader.running = true
    }

    // Falls back to the originals when no previews have been generated yet - a
    // fresh install before autostart has run once. Slower, but showing the
    // wallpapers beats showing an empty picker.
    readonly property url previewDir:
        thumbDir ? "file://" + thumbDir
        : repoRoot ? "file://" + repoRoot + "/wallpapers"
        : ""

    // The list itself, shared by both views. One model rather than one each:
    // they are looking at the same directory, in the same order, and a shared
    // model means the grid and the strip cannot disagree about what index 7 is.
    property alias files: folder

    FolderListModel {
        id: folder
        folder: library.previewDir
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
        showDirs: false
        sortField: FolderListModel.Name
    }

    // The full-size original for a preview. Previews live in the cache and are
    // always .webp; the original keeps the same basename in wallpapers/, so it
    // can be named directly - and a fade needs the full-size file, not the
    // 960px preview it would otherwise be handed.
    function originalFor(previewUrl): string {
        if (!previewUrl || !library.repoRoot) return ""
        const name = String(previewUrl).split("/").pop()
        return library.repoRoot + "/wallpapers/" + name
    }

    // Basename without extension, for comparing a preview against the wallpaper
    // actually in use - they are the same picture under two different
    // extensions in two different directories.
    function stemOf(p): string {
        if (!p) return ""
        const base = String(p).split("/").pop()
        const dot = base.lastIndexOf(".")
        return dot > 0 ? base.substring(0, dot) : base
    }

    // Whether `previewUrl` is the wallpaper currently on screen.
    function isCurrent(previewUrl): bool {
        const a = library.stemOf(previewUrl)
        return a !== "" && a === library.stemOf(WallpaperState.path)
    }

    // A filename dressed up as a caption: drop the extension, turn the
    // separators into spaces and title-case it, so "catppuccin-blue-eye" reads
    // as "Catppuccin Blue Eye". The files are named for sorting; this is the
    // only form a person is shown.
    //
    // HERE RATHER THAN IN THE PICKER, which is where it was written, because
    // the settings page now names the current wallpaper too and two copies of
    // this would drift.
    function caption(nameOrPath): string {
        const base = String(nameOrPath || "").split("/").pop()
        if (!base) return ""
        return base.replace(/\.[^.]+$/, "")
                   .replace(/[-_]+/g, " ")
                   .replace(/\b\w/g, c => c.toUpperCase())
    }

    readonly property string currentCaption: library.caption(WallpaperState.path)

    // Where the wallpaper in use sits in the list, or 0 if it is not in it.
    function indexOfCurrent(): int {
        for (let i = 0; i < library.files.count; i++)
            if (library.isCurrent(library.files.get(i, "fileUrl"))) return i
        return 0
    }

    // A window of `count` wallpapers centred on the one in use.
    //
    // THE SETTINGS PAGE SHOWS A FEW, NOT ALL OF THEM. There are 63; a grid of
    // them turned the Appearance page into a wall of thumbnails with no end in
    // sight, and the job there is seeing which one is set and stepping to a
    // neighbour. Browsing the whole set is what the full-screen picker is for,
    // where one wallpaper is shown at a time and large.
    //
    // The window slides rather than centring blindly, so the strip is full at
    // both ends of the list instead of showing three tiles and a gap.
    function nearby(count: int): var {
        const total = library.files.count
        if (total === 0) return []
        const span = Math.min(count, total)
        let start = library.indexOfCurrent() - Math.floor(span / 2)
        if (start < 0) start = 0
        if (start + span > total) start = total - span
        const out = []
        for (let i = start; i < start + span; i++)
            out.push({ url: library.files.get(i, "fileUrl"),
                       name: library.files.get(i, "fileName") })
        return out
    }

    // Show it now and remember it.
    function choose(previewUrl): void {
        const full = library.originalFor(previewUrl)
        if (!full) {
            console.warn("wallpaper: repo root not resolved yet")
            return
        }
        WallpaperState.apply(full, library.setterScript)
    }
}
