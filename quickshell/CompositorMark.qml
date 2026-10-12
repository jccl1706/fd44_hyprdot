// =========================================================================
// CompositorMark - which compositor this session is, at the end of the bar
// =========================================================================
//
// The distro's mark sits at the far left in Logo.qml; this is its counterpart:
// what is DRAWING the bar rather than what is underneath it. Together they say
// "Fedora, running niri" without a word of text.
//
// IT ASKS Compositor RATHER THAN ASSUMING, for the reason written at the top of
// Logo.qml and learned the same way: one checkout drives both machines, and
// anything naming a single compositor is wrong on the other. Compositor.backend
// already answers this - it is what every other plugin uses to decide how to
// talk to the session - so there is no new detection here.
//
// THE ASSET IS VENDORED, NOT READ FROM THE SYSTEM. niri ships its logo in
// /usr/share/doc/niri/wiki/logo/, and a doc path is the wrong thing to depend
// on: `tsflags=nodocs` in dnf.conf removes it entirely, which is a normal
// setting on a minimal install, and NixOS puts it somewhere else again. The
// same reasoning as Logo.qml's note that the Fedora SVG fallback is Fedora-only
// because no other system has that file. 21KB of Inkscape metadata was stripped
// on the way in; what is committed is 1.5KB and two paths.
//
// IN ITS OWN COLOUR, WHICH IS A DELIBERATE EXCEPTION. The rule stated in
// BatteryButton.qml - colour means something is wrong - is about STATE: a glyph
// that tints to say the battery is low or an update is waiting. This is not a
// state, it is a mark, and a logo rendered in grey is a logo with its identity
// taken off. The Fedora mark at the other end has the same licence.
//
// #d55c44 is niri's own warm orange, which the palette has no equivalent of.
// Two coloured marks at the two ends of the bar, and nothing coloured between
// them unless something has gone wrong, keeps the rule intact where it matters.

import Quickshell
import QtQuick

Item {
    id: root
    implicitWidth: 20
    implicitHeight: 20

    // Only niri has a vendored mark so far. On Hyprland this draws nothing
    // rather than drawing niri's logo, which would be worse than an empty slot.
    readonly property string markSource:
        Compositor.backend === "niri"
            ? Qt.resolvedUrl("assets/niri.svg")
            : ""

    visible: root.markSource !== ""

    Image {
        id: mark
        anchors.centerIn: parent
        // SOURCE SIZE AT 2x AND THEN SCALED DOWN, because an SVG rasterised at
        // its display size is mush on a 204ppi panel. Qt renders the SVG once
        // at sourceSize and scales the bitmap afterwards.
        sourceSize { width: 40; height: 40 }
        // BIGGER THAN THE GLYPHS BESIDE IT, on purpose. niri's mark is a thin
        // crescent where the neighbouring glyphs are solid strokes, so at a
        // matched 16px it read as the faintest thing in the pill. 20 gives it
        // the same presence rather than the same measurement.
        width: 20
        height: 20
        source: root.markSource
        smooth: true
    }

    // A small lift on hover, since the colour is already its own and there is
    // nothing to tint towards.
    opacity: hover.hovered ? 1 : 0.88
    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

    HoverHandler { id: hover }
}
