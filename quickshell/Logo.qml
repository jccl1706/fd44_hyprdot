// =========================================================================
// Logo - Fedora mark at the far left of the bar
// =========================================================================
//
// GLYPH vs IMAGE:
// Uses the Nerd Font glyph nf-linux-fedora (U+F30A) from Symbols Nerd Font,
// installed per-user at ~/.local/share/fonts/SymbolsNerdFont-Regular.ttf
// (official NerdFontsSymbolsOnly release, 2.3 MiB, glyphs only - it adds no
// text characters so it cannot disturb existing font matching).
//
// Verify the glyph resolves:   fc-match ':charset=f30a'
// It should name SymbolsNerdFont. If it says Noto Sans, the font is missing
// and this will render as an empty box - set useGlyph to false to fall back
// to the SVG path below, which uses Fedora's own
// /usr/share/pixmaps/fedora-logo-sprite.svg via qt6-qtsvg and needs no font.

import Quickshell
import QtQuick

Item {
    id: root


    // Flip to true once a Nerd Font is installed.
    property bool useGlyph: true
    property string glyphFont: Theme.glyphFont
    property string glyph: ""          // nf-linux-fedora

    property string imageSource: "file:///usr/share/pixmaps/fedora-logo-sprite.svg"

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
