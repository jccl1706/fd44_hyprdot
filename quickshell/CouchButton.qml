// =========================================================================
// CouchButton - hand the television over to Steam
// =========================================================================
//
// Ends the desktop session and brings the machine back as Steam Big Picture
// under gamescope. The same thing `fd44-session couch --now` does from a
// terminal, which is what it runs - and the reason it exists as a button is
// that in the living room there is no terminal and no keyboard, only the
// controller's trackpad.
//
// HOW THE SWITCH ACTUALLY HAPPENS, which is worth knowing because nothing
// here launches gamescope: fd44-session writes `couch` to the session-mode
// flag in ~/.local/state/fd44-hyprdot and then exits Hyprland. tty1 logs
// straight back in, the login hook in the NixOS module reads the flag, and
// starts fd44-couch instead of Hyprland. The way back is Steam's Return to
// Desktop shortcut, which clears the flag and ends the couch session the
// same way.
//
// IN A TRANSIENT SCOPE, not a plain exec, and for the reason PowerMenu's
// Lock action spells out: a process quickshell spawns shares its cgroup and
// dies with it. This one deliberately kills Hyprland, and quickshell with
// it, so it would be racing its own death - the flag is written first and
// would survive, but the exit dispatch might not, leaving the desktop up
// with the flag set. A scope under the user manager outlives the compositor
// and finishes the job.
//
// TWO CLICKS - see ArmedButton.qml. This throws away everything open on the
// desktop, so it is not something to do by brushing the bar.
//
// ONLY ON A MACHINE THAT HAS fd44-session - see Couch.qml.

import QtQuick

ArmedButton {
    // nf-md-google_controller. A controller silhouette rather than a
    // television or a sofa: it says "games" at a glance, where a TV glyph
    // beside a power symbol would read as something to do with the display.
    //
    // 15px. Measured from the font: 12.5 x 8.4 px here, against the moon's
    // 12.2 x 13.2 at the same size. The widths match, which is what carries
    // a row of glyphs; the height does not, and cannot - a controller is a
    // wide shape, and sizing it up until it were as tall as the moon would
    // make it visibly the largest thing in the bar.
    glyph: "\u{F02B4}"
    glyphSize: 15

    command: ["systemd-run", "--user", "--scope", "--quiet", "--collect",
              "--unit=fd44-session-switch",
              "fd44-session", "couch", "--now"]
}
