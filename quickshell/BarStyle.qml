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

    // BIGGER PILLS WHEN THEY ARE THE WHOLE BAR. Framed, a pill is a group
    // marked out on a strip and Theme.barHeight's 38 sets the scale, so 26 is
    // a pill with 6px of bar showing above and below it. Floating, the strip
    // is invisible and the pill IS the bar - at 26 it reads as a thin sliver
    // with a lot of wallpaper round it rather than as the shell's main
    // control. The extra 10 of height and 8 of padding is what puts it back
    // in proportion to the gap it now sits in - 36 and 18 against the framed
    // 26 and 10. It was tried at 32 and 14 first and still read as thin.
    readonly property int pillHeight:  Theme.pillHeight  + (floating ? 10 : 0)
    readonly property int pillPadding: Theme.pillPadding + (floating ? 8  : 0)

    // WHERE THE CHROME BELOW THE BAR STARTS. This is the bar window's full
    // height, which is also its exclusive zone, so a panel's top edge lands
    // exactly where a tiled window's top edge does rather than a few pixels
    // off it.
    //
    // Floating it is the PILL plus its margins, not Theme.barHeight plus
    // them. barHeight is the height of an opaque strip, and the 6px of slack
    // it carries above and below the pill is part of that strip's look; with
    // no strip drawn that slack is just wallpaper nothing may tile into, and
    // the gap above the pill would come out larger than the gap beside it.
    readonly property int barBottom: floating ? pillHeight + margin * 2
                                              : Theme.barHeight

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
    // THE SCRIM IS A FRAME-MODE THING. An open panel dims the desktop behind
    // it, which suits a bar welded to a border round the screen: the chrome
    // is one enclosing shape and a panel coming out of it is modal over
    // everything inside.
    //
    // Floating it does not suit at all. It was tried both ways. Stopping the
    // dimming at the bar left the top 48px of WALLPAPER at full brightness
    // with everything under it at 60%, and that hard horizontal edge across
    // the whole screen read as a black rectangle drawn over the desktop.
    // Dimming the whole screen instead removed the edge but was not wanted
    // either: a floating panel is an object lying on the wallpaper next to
    // the pills, not a mode the desktop has entered, and darkening everything
    // to announce it overstates what just happened.
    //
    // Only the PAINT goes. The full-screen MouseArea under it is what closes
    // a panel on a click outside, and that stays in both modes.
    readonly property bool scrim: joined
}
