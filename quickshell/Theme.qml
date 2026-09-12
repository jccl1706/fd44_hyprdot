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

    // --- tonal surfaces --------------------------------------------------
    // bg is the darkest tone, and until now it was the ONLY one - every
    // module sat directly on it, so the bar read as loose items scattered on
    // a flat strip. Material groups related controls onto raised surface
    // containers instead, and that needs tones between the background and the
    // foreground. These continue the same Catppuccin Mocha ramp bg came from:
    //   bg #11111b crust  ->  surface #1e1e2e base  ->  surfaceHigh #313244
    readonly property color surface:     "#1e1e2e"   // module containers
    readonly property color surfaceHigh: "#313244"   // hover / raised state
    readonly property color outline:     "#45475a"   // hairlines, separators

    // --- depth -----------------------------------------------------------
    // DARK THEMES GET THEIR DEPTH FROM LIGHT, NOT FROM SHADOW.
    //
    // A drop shadow needs the object to be darker than what is behind it. Here
    // the pills (#1e1e2e) sit on a bar that is darker still (#11111b), so a
    // black shadow under them lands on near-black and does nothing at all.
    // This is why Material 3 swaps shadows for elevation tint in dark themes,
    // and why dark macOS outlines its panels instead of shadowing them.
    //
    // So: a hairline rim as if catching light from above, and a gradient just
    // strong enough that a pill reads as curved rather than stamped out. Both
    // are deliberately near the threshold of visibility - the moment either is
    // obvious it stops looking like depth and starts looking like a gradient.
    readonly property color rim:        Qt.rgba(1, 1, 1, 0.055)
    readonly property color surfaceTop: Qt.lighter(surface, 1.28)

    // The launcher card's lift. Its bottom stop MUST be exactly bg: the card
    // merges into the bottom frame, and any other value reappears as the seam
    // that took three rounds to get rid of.
    readonly property color panelTop:   "#1e1e2e"

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

    // --- weight ----------------------------------------------------------
    // Inter Variable carries a continuous weight axis (100-900), and the
    // config used to ignore it: a single `bold` flag, set true, applied to the
    // clock, the bar, the workspace numbers, the launcher's search field, its
    // row titles and the OSD alike. Everything bold is the same as nothing
    // bold - there is no emphasis left to spend.
    //
    // Four steps, each with a job:
    readonly property int weightLight:  300   // display-size text only
    readonly property int weightNormal: 400   // subtitles, secondary text
    readonly property int weightMedium: 500   // default UI text
    readonly property int weightSemi:   600   // titles, the focused workspace
    readonly property int weightBold:   700   // the clock, and nothing else

    // Slight negative tracking at display sizes and slight positive at small
    // ones. Inter is drawn a little loose for UI use at 10-11px and a little
    // loose-looking when it gets big; these are the usual corrections.
    readonly property real trackingTight: -0.3   // >= 16px
    readonly property real trackingLoose:  0.15  // <= 10px

    readonly property int fontSize:      12   // default bar text
    readonly property int fontSizeSmall: 10   // workspace numbers, subtitles
    readonly property int fontSizeClock: 16

    // Display size: captions and titles that sit on their own rather than in
    // a panel. Large enough that a light weight still reads, which is the
    // whole reason to have a weight axis.
    readonly property int fontSizeDisplay: 26

    // List-row titles. Deliberately 3px clear of fontSizeSmall: at 11 against
    // 10 the only thing separating a title from its subtitle was weight and
    // colour, which is not enough to read as hierarchy at a glance.
    readonly property int fontSizeTitle:  13

    // --- metrics ---------------------------------------------------------
    // 38, not 34. The pills the modules now sit in need room to breathe -
    // a 26px container in a 34px bar leaves 4px top and bottom, which reads
    // as cramped rather than deliberate. Everything that positions itself
    // against the bar derives from this, so raising it moves the frame, the
    // launcher's scrim inset and the reserved zone together.
    readonly property int barHeight:   38

    // Module containers. Fully rounded: radius is half the height, so these
    // are pills rather than rounded rectangles.
    readonly property int pillHeight:  26
    readonly property int pillPadding: 10
    readonly property int barPadding:  12   // gap from the screen edge
    readonly property int itemSpacing: 12   // between groups in a region
    readonly property int glyphSize:   18

    // Rounded only on the BOTTOM corners - the top edge sits flush against
    // the screen edge, so rounding it would just show a gap.
    readonly property int cornerRadius: 12

    // Border enclosing the screen (Frame.qml). Windows tile inside it.
    // Keep hyprland's gaps_out small to match - the frame and the gap stack,
    // so a thick frame plus a wide gap is twice the dead space for no reason.
    // Currently paired with gaps_out = 4 in hypr/look.lua.
    readonly property int frameThickness: 4

    // Outer corner radius of the frame. ZERO, deliberately.
    //
    // The frame is the OUTERMOST thing on screen, so rounding its outer
    // corners does not reveal something tasteful underneath - it reveals the
    // wallpaper. At 4px thick Qt clamps the radius to half the thickness, so
    // this only ever drew a 2px nub: invisible as a design feature on a dark
    // wallpaper, and a bright speck in the corner of the screen on a pale one.
    // Measured at #839ea0 against a #11111b frame.
    //
    // If the frame ever gets thick enough for real rounding to read, the
    // corner would need something opaque behind it rather than just a radius.
    readonly property int frameCornerRadius: 0

    // Opacity of floating panels - currently just the launcher. The bar and
    // frame stay fully opaque: they sit against the screen edge with nothing
    // interesting behind them, and a translucent border reads as a rendering
    // fault rather than as a choice.
    //
    // Paired with a blur layer rule in hypr/rules.lua. Without the blur a
    // translucent panel over a terminal is genuinely hard to read - the text
    // behind it competes with the text on it.
    readonly property real panelAlpha: 0.85

    // --- motion ----------------------------------------------------------
    // Kept short throughout: a bar should feel instant. Anything above about
    // 200ms starts to read as lag rather than animation.
    readonly property int animFast:   120
    readonly property int animNormal: 140
    readonly property int animSlow:   160

    // The OSD reveal, shared by the indicator and everything that moves with
    // it. A single constant on purpose: these are one motion as far as the eye
    // is concerned, and when they ran on separate durations the pill finished
    // before its contents did.
    //
    // PAIRED WITH Easing.InOutCubic, NOT an ease-out. The rest of this config
    // is deliberately front-loaded - snappy - but that curve is wrong for a
    // container collapsing. Traced at OutQuint, the retract moved 45 of its
    // 132px in the FIRST 16ms frame and then spent the remaining 130ms
    // covering the last 9px. A third of the motion in one frame reads as a
    // pop, and the tail reads as a stall: exactly the "clunky" complaint.
    // InOutCubic eases in as well as out, so no single frame dominates.
    readonly property int animReveal: 220
}
