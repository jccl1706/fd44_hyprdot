// =========================================================================
// Logo - the running system's mark at the far left of the bar
// =========================================================================
//
// IT READS /etc/os-release RATHER THAN BEING TOLD. This was a hardcoded Fedora
// glyph, which was true of every machine it ran on until it was not: on
// nixos-gaming00 the bar announced Fedora while running NixOS. One checkout
// drives both, so anything naming a single distribution is wrong on the other -
// the same shape as the MangoHud font path and eDP-1 in the workspace rules.
//
// GLYPH vs IMAGE:
// Uses Nerd Font glyphs from Symbols Nerd Font, installed per-user at
// ~/.local/share/fonts/SymbolsNerdFont-Regular.ttf (official
// NerdFontsSymbolsOnly release, 2.3 MiB, glyphs only - it adds no text
// characters so it cannot disturb existing font matching).
//
// Verify a glyph resolves:   fc-match ':charset=f313'
// It should name SymbolsNerdFont. If it says Noto Sans the font is missing and
// this renders as an empty box.
//
// THE CODEPOINTS WERE RENDERED, NOT READ OFF A TABLE. fc-match only proves a
// font CLAIMS a codepoint, not that the glyph is the shape you expect, and
// these tables have been wrong here before. All of the below were drawn at
// 56px and looked at.

import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: root


    // Flip to true once a Nerd Font is installed.
    property bool useGlyph: true
    property string glyphFont: Theme.glyphFont

    // The ID field of /etc/os-release, lowercased - "fedora", "nixos", "arch".
    // Empty until the file has been read, which is why the glyph below falls
    // back to Tux rather than to nothing: a bar that is briefly generic looks
    // fine, a bar that is briefly empty looks broken.
    property string osId: ""

    // ID -> glyph. Every one of these was rendered and looked at; see the
    // header. Tux is the fallback for anything unlisted, which is the honest
    // answer for a distribution this has never run on.
    readonly property var osGlyphs: ({
        "fedora":    "\uf30a",
        "nixos":     "\uf313",
        "arch":      "\uf303",
        "debian":    "\uf306",
        "ubuntu":    "\uf31b",
        "gentoo":    "\uf30d",
        "opensuse":  "\uf314",
        "opensuse-tumbleweed": "\uf314",
        "linuxmint": "\uf30e",
        "manjaro":   "\uf312"
    })

    property string glyph: root.osGlyphs[root.osId] || "\uf17c"   // Tux

    // The SVG fallback is FEDORA-ONLY, because that file is Fedora's own and no
    // other system puts one there - NixOS has no /usr/share at all. Elsewhere
    // this is empty and the "neither worked" dot below takes over, which beats
    // a broken image path.
    property string imageSource: root.osId === "fedora"
        ? "file:///usr/share/pixmaps/fedora-logo-sprite.svg"
        : ""

    // Read once at startup: /etc/os-release does not change while a session
    // runs, so there is nothing to watch for.
    FileView {
        id: osRelease
        path: "/etc/os-release"
        printErrors: false
        onLoaded: {
            // ID may be bare or quoted: ID=fedora, ID="opensuse-tumbleweed".
            const m = /^ID=\"?([^\"\n]+)\"?/m.exec(osRelease.text())
            if (m) root.osId = m[1].trim().toLowerCase()
        }
    }

    // Drawn size of the mark. Kept separate from implicitWidth/Height so the
    // clickable area stays comfortable even when the glyph itself is small -
    // shrinking the hit target along with the icon makes it fiddly to click.
    property real glyphSize: Theme.glyphSize

    // Emitted on click, so the bar decides what a click means rather than
    // this component hardcoding it.
    signal activated()

    implicitWidth: 22
    implicitHeight: 22

    Image {
        id: img
        anchors.centerIn: parent
        visible: !root.useGlyph && status === Image.Ready
        source: root.useGlyph ? "" : root.imageSource

        // Render the SVG at the size actually needed rather than scaling a
        // bitmap up - sourceSize is what makes an SVG crisp.
        sourceSize.width: root.glyphSize
        sourceSize.height: root.glyphSize
        width: root.glyphSize
        height: root.glyphSize

        opacity: mouse.containsMouse ? 1.0 : 0.85
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    Text {
        anchors.centerIn: parent
        visible: root.useGlyph
        text: root.glyph
        font.family: root.glyphFont
        font.pixelSize: root.glyphSize
        color: mouse.containsMouse ? Theme.accent : Theme.fg
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    // If neither path produced anything visible, show something rather than
    // a silent gap - an invisible logo looks like a broken bar.
    Text {
        anchors.centerIn: parent
        visible: !root.useGlyph && img.status !== Image.Ready
        text: "●"                        // filled circle
        font.pixelSize: root.glyphSize * 0.6
        color: Theme.fg
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
