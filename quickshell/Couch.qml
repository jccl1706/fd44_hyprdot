// =========================================================================
// Couch - is this machine one that can become a games console?
// =========================================================================
//
// A singleton for one boolean, because the answer has to be known before
// CouchButton exists: Bar.qml leaves the plugin out of the layout entirely
// on a machine without it, so there is no button to ask.
//
// THIS CONFIG IS SHARED BETWEEN MACHINES. ~/.config/quickshell is a symlink
// into the same checkout on the desktop and on both laptops, and only the
// desktop has a television, a controller and the NixOS module that provides
// fd44-session and fd44-couch. A couch-mode button on the Framework would be
// a button that does nothing, which is worse than no button.
//
// PROBED, NOT HARDCODED TO A HOSTNAME. What makes couch mode possible is the
// command being installed, and that is exactly what this asks - so a second
// machine that gains the module gets the button with no change here, and the
// desktop loses it again if the module is ever taken out.
//
// STARTS FALSE. The probe is asynchronous and takes a few milliseconds, so
// the icon fades in just after the bar appears rather than appearing and
// then vanishing on the machines that do not have it.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: couch

    property bool available: false

    Process {
        id: probe
        running: true
        // `command -v` rather than a path: fd44-session lives in
        // /run/current-system/sw/bin on NixOS and could reasonably live in
        // ~/.local/bin elsewhere. What matters is that it can be run.
        command: ["sh", "-c", "command -v fd44-session >/dev/null 2>&1"]
        onExited: (code, status) => couch.available = (code === 0)
    }
}
