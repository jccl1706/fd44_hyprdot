pragma Singleton

// =========================================================================
// BarStyle - what "frame" and "pill" mean in pixels
// =========================================================================
//
// Settings.barStyle is a word; this is the same answer as geometry, in one
// place so the bar, the launcher, the power menu, the drop-down panels and
// the notification toasts cannot disagree about it. Before this the numbers
// were spelt out at each site - `Theme.barHeight` for where the chrome
// begins, `Theme.frameThickness` for how far a card runs past its visible
// edge - and every one of those was an assumption that the frame exists.
//
// WHY NOT IN Theme.qml, which is where every other constant lives: Theme
// would then have to read Settings, and Settings already reads Theme (the
// theme row in its schema asks Theme for the current name). Two singletons
// each holding a property binding into the other is a cycle that QML
// resolves by luck of initialisation order. A third singleton that reads
// both and is read by neither has no such problem.
//
// THE FRAME IS THE DEFAULT and these numbers are written so that frame mode
// is exactly what the code did before this file existed: margin 0, inset 0,
// frameRun back to Theme.frameThickness, joined true.

import Quickshell
import QtQuick

Singleton {
    id: style

    // The bar floats clear of the screen edges, and Frame.qml is not drawn.
    readonly property bool floating: Settings.barStyle === "pill"

    // The gap the bar keeps from the top and sides when floating.
    readonly property int margin: floating ? Theme.barFloatMargin : 0

    // WHERE THE CHROME BELOW THE BAR STARTS. This is the bar window's full
    // height, which is also its exclusive zone, so a panel's top edge lands
    // exactly where a tiled window's top edge does rather than a few pixels
    // off it. In frame mode the two halves of that sum collapse to the bar
    // height, which is what every call site used to say directly.
    readonly property int barBottom: Theme.barHeight + margin * 2

    // How far a card is held off the left, right and bottom edges of the
    // screen. Zero in frame mode is not an oversight: there the card runs all
    // the way to the edge and the last frameRun pixels of it sit UNDER the
    // frame strip in the same colour, so card and frame read as one shape.
    readonly property int edgeInset: margin

    // The width of that overlap. A floating card has nothing to meet, so it
    // is drawn at its visible size and no wider.
    readonly property int frameRun: floating ? 0 : Theme.frameThickness

    // Whether a card is welded to something - the bar above it, the frame
    // beside it - and therefore wants concave fillets at the junction and a
    // square edge where it meets. Floating, every corner is out in the open.
    readonly property bool joined: !floating

    // How far in from a screen edge the usable area starts: past the frame
    // strip when there is one, past the bar's own gap when it floats. This is
    // for things that sit NEXT TO the chrome rather than joining it - the
    // notification toasts - as opposed to cards that run underneath it, which
    // want edgeInset and frameRun instead.
    readonly property int contentInset: floating ? edgeInset : Theme.frameThickness

    // The scrim covers everything below the bar. In frame mode it stops short
    // of the frame and is rounded to match, because a square scrim painted
    // over the frame's concave corner pieces dims them and they stop looking
    // like part of the border. Floating there is no border to protect, and an
    // inset scrim would leave an undimmed band down each side instead.
    readonly property int scrimInset: floating ? 0 : Theme.frameThickness
    readonly property int scrimRadius: floating ? 0 : Theme.cornerRadius
}
