// =========================================================================
// ThemeToggle - the sun/moon button beside the clock
// =========================================================================
//
// Flips the desktop between the themes in themes/ by running bin/theme.sh.
// The same thing Super+T does; this is the discoverable version of it, and
// unlike the keybind it also SHOWS which theme is active without being
// pressed.
//
// IT SHOWS THE CURRENT STATE, NOT THE TARGET. A moon means "you are in the
// dark theme", not "click for dark". Both conventions exist and neither is
// self-evident, so the choice is: this is an indicator that happens to be
// clickable, and an indicator that displays a state it is not in would be a
// strange thing.
//
// THE WORK HAPPENS IN THE SCRIPT, NOT HERE. Three of the four things a theme
// switch touches - kitty, GTK, Hyprland - are nothing to do with quickshell,
// so the button cannot do the job itself even for its own colours. It shells
// out and then does nothing: the palette file changes, Theme.qml's FileView
// notices, and this button recolours along with everything else. It never
// sets its own colour directly.

import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: root

    implicitWidth: 20
    implicitHeight: 20

    // Nerd Font weather glyphs. Distinct in silhouette at 13px, which matters
    // more than detail at this size - a crescent and a disc with rays read
    // apart instantly, where two similar round glyphs would not.
    readonly property string moonGlyph: "\u{F0594}"
    readonly property string sunGlyph:  "\u{F0599}"

    Process {
        id: switcher
        // Resolved at press time rather than held in a property: this needs
        // the path once per click, and the async dance to pre-resolve it
        // would be more code than the thing it saves. ~/.config/quickshell is
        // a symlink into the checkout, so dirname of its target is the repo -
        // the same anchor the Hyprland config uses, and just as independent
        // of where the checkout actually lives.
        command: ["sh", "-c",
                  "\"$(dirname \"$(readlink -f '" + Quickshell.shellDir + "')\")/bin/theme.sh\" toggle"]
        onExited: (code, status) => {
            if (code !== 0) console.warn("theme toggle failed with", code)
        }
    }

    // Hover backdrop. Sits behind the glyph rather than around it so the
    // button does not change size on hover and shove the clock sideways.
    Rectangle {
        anchors.centerIn: parent
        width: 20
        height: 20
        radius: width / 2
        color: Theme.surfaceHigh
        opacity: hover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    Text {
        id: glyph
        anchors.centerIn: parent
        text: Theme.isDark ? root.moonGlyph : root.sunGlyph
        font.family: Theme.glyphFont
        // 15, matched against the coffee cup beside it (14 px, 12.3 x 11.0).
        // Measured in a probe: the sun draws 12.7 x 11.0 here, and the moon
        // 12.2 x 13.2 - as wide as the cup, a little taller, which a
        // thin-line crescent needs to look as large as a solid cup. At 13
        // both read as tiny next to it.
        font.pixelSize: 15
        color: hover.hovered ? Theme.fg : Theme.dim

        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        // The glyph swap is instant, but a quarter-turn carries the eye
        // across it so the change registers as one action rather than as the
        // icon having been replaced when you were not looking.
        rotation: Theme.isDark ? 0 : 90
        Behavior on rotation {
            NumberAnimation { duration: Theme.animReveal; easing.type: Easing.InOutCubic }
        }
    }

    HoverHandler {
        id: hover
        // No cursorShape: crossing the bar's icons flipped the pointer
        // shape, and the hand's hotspot sits at the fingertip where the
        // arrow's is near its corner - so the pointer appeared to jump a
        // few pixels at every icon edge. See Bar.qml.
    }

    // Called by Bar.qml, which handles clicks on every movable plugin - a
    // TapHandler here would fire as well, and cannot tell a click from the
    // press-and-hold that drags this toggle elsewhere in the bar.
    function activate(): void {
        switcher.running = true
    }
}
