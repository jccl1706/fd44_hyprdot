// =========================================================================
// Theme - shared constants for the whole bar
// =========================================================================
//
// A singleton: exactly one instance exists and every component reads from it
// directly, rather than each declaring its own copy and Bar.qml threading the
// values down by hand. Before this, the same six values lived in four files
// and every new module meant five more lines of plumbing.
//
// Use it from anywhere with no import of its own - `Theme.fg`, `Theme.font`.
//
// DELIBERATELY CONSTANTS ONLY.
// Colours, fonts and metrics belong here. Mutable state does NOT - a global
// that anything can write to is where this pattern starts causing problems
// rather than solving them. If a module needs state, it owns it.
//
// The tradeoff accepted here: this is global, so two bars cannot have
// different palettes without threading values again. Fine for one personal
// bar; it would be the wrong call for a reusable widget library.

pragma Singleton

import Quickshell
import QtQuick

Singleton {
    // --- palette ---------------------------------------------------------
    readonly property color bg:      "#11111b"
    readonly property color fg:      "#cdd6f4"
    readonly property color dim:     "#6c7086"
    readonly property color accent:  "#89b4fa"

    // Text drawn on top of the accent colour (the focused workspace chip)
    // needs to be dark, not fg, or it disappears.
    //
    // NOT named "onAccent": QML parses any identifier starting with "on" plus
    // a capital letter as a SIGNAL HANDLER, so `readonly property color
    // onAccent` fails with "Cannot assign a value to a signal".
    readonly property color accentFg: "#11111b"

    // --- type ------------------------------------------------------------
    // NOTE: "Inter Variable", not "Inter". rsms-inter-vf-fonts registers it
    // under that name; asking for "Inter" silently falls back to Noto Sans
    // and merely looks slightly wrong. Check: fc-match "Inter Variable"
    readonly property string font:      "Inter Variable"

    // Glyphs for the logo and OSD icons. Not packaged by Fedora - see the
    // font notes in the README. Check: fc-match ':charset=f30a'
    readonly property string glyphFont: "Symbols Nerd Font"

    readonly property bool bold: true

    readonly property int fontSize:      11   // default bar text
    readonly property int fontSizeSmall: 10   // workspace numbers
    readonly property int fontSizeClock: 16

    // --- metrics ---------------------------------------------------------
    readonly property int barHeight:   34
    readonly property int barPadding:  12   // gap from the screen edge
    readonly property int itemSpacing: 12   // between groups in a region
    readonly property int glyphSize:   18

    // Rounded only on the BOTTOM corners - the top edge sits flush against
    // the screen edge, so rounding it would just show a gap.
    readonly property int cornerRadius: 12

    // --- motion ----------------------------------------------------------
    // Kept short throughout: a bar should feel instant. Anything above about
    // 200ms starts to read as lag rather than animation.
    readonly property int animFast:   120
    readonly property int animNormal: 140
    readonly property int animSlow:   160
}
