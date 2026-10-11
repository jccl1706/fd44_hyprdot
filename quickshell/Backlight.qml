// =========================================================================
// Backlight - the one place QML learns the brightness curve
// =========================================================================
//
// bin/backlight.sh SETS brightness through `brightnessctl -e<curve>`, so a
// percentage is what you want to see and the panel gets that raised to the
// power of the curve. Anything that wants to DISPLAY a level has to invert
// that, and before this there were two copies of the exponent - one in
// Osd.qml, one in Settings.qml - with a third in the script.
//
// THREE COPIES OF A NUMBER THAT MUST AGREE IS HOW THE LAST SIX BUGS HAPPENED.
// The OSD reported a raw percentage while everything set a perceived one, and
// the two disagreed for long enough that the stored settings, the keys and the
// slider all told different stories about the same screen. The exponent lives
// in the script now and is asked for here.
//
// THE DEFAULT IS THE SCRIPT'S OWN VALUE, so the moment before the answer
// arrives converts identically rather than wrongly. If the script cannot be
// run at all, this stays correct until someone edits one and not the other -
// which is the failure this file exists to make unlikely, not impossible.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: backlight

    property real curve: 2.2

    readonly property string script:
        Quickshell.env("HOME") + "/Work/fd44_hyprdot/bin/backlight.sh"

    // Raw sysfs value -> the 0-1 level the controls speak in.
    function perceived(cur: real, max: real): real {
        if (!(max > 0) || !(cur >= 0)) return 0
        return Math.pow(cur / max, 1 / backlight.curve)
    }

    function perceivedPct(cur: real, max: real): int {
        return Math.round(backlight.perceived(cur, max) * 100)
    }

    Process {
        running: true
        command: [backlight.script, "curve"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseFloat(text.trim())
                // A curve outside this range is a misread, not a setting: keep
                // the default rather than rendering every level nonsense.
                if (v >= 1 && v <= 8) backlight.curve = v
            }
        }
    }
}
