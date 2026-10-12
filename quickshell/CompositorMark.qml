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
// TINTED, NOT DRAWN IN ITS OWN COLOUR. niri's mark is #d55c44, a warm orange
// that is not in this palette and would be the loudest thing on a bar whose
// rule - stated in BatteryButton.qml - is that colour means something is wrong.
// It renders in the same dim as every other idle glyph and brightens on hover,
// exactly like the rest.

import Quickshell
import QtQuick
import QtQuick.Effects

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
        // 16px and drawn at 16px is mush on a 204ppi panel. Qt renders the SVG
        // once at sourceSize and scales the bitmap afterwards.
        sourceSize { width: 32; height: 32 }
        width: 16
        height: 16
        source: root.markSource
        smooth: true
        // Hidden: what is seen is the tinted copy below.
        visible: false
    }

    MultiEffect {
        anchors.fill: mark
        source: mark
        colorization: 1.0
        colorizationColor: hover.hovered ? Theme.fg : Theme.dim
        Behavior on colorizationColor { ColorAnimation { duration: Theme.animFast } }
    }

    HoverHandler { id: hover }
}
