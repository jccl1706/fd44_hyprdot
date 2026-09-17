// =========================================================================
// PowerButton - switch the machine off
// =========================================================================
//
// Two clicks and the machine powers down. It duplicates the Shut down entry
// in PowerMenu.qml on purpose: that menu is opened by Super+M or the
// physical power key, and in the living room there is neither a keyboard nor
// a power button within reach of the sofa - only the controller's trackpad,
// which needs something to click on.
//
// A DIRECT ACTION RATHER THAN A SECOND WAY INTO THE MENU. Opening the menu
// from here would be one more click on a trackpad for the one entry that is
// ever wanted from across a room; lock, suspend and restart are all things
// done at the desk, where the keybind already reaches them.
//
// TWO CLICKS - see ArmedButton.qml. The bar is the one part of the screen
// that is always there, so a single-click power button on it would be the
// easiest thing in the desktop to press by mistake.
//
// `systemctl poweroff` rather than logind's own handling: the same command
// the menu uses, so both routes shut down identically.

import QtQuick

ArmedButton {
    // nf-md-power - the standard power symbol, and the same glyph the menu's
    // Shut down entry carries, so the two are recognisably one action.
    //
    // 17px. Measured from the font: 11.4 x 12.1 px here, just inside the
    // moon's 12.2 x 13.2 at 15. It needs the extra two px because it is a
    // thin-line glyph like the moon rather than a solid one like the coffee
    // cup; at 15 it draws 10.0 x 10.6 and reads as the smallest icon in the
    // bar.
    glyph: "\u{F0425}"
    glyphSize: 17

    command: ["systemctl", "poweroff"]
}
