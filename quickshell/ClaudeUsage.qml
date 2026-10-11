// =========================================================================
// ClaudeUsage - what Claude Code has spent, read from its own transcripts
// =========================================================================
//
// bin/claude-usage.py does the reading and the arithmetic; this runs it on a
// timer and holds the answer. Everything that knows the shape of a transcript
// is in the script, so this file never changes when that format does.
//
// LOCAL LOGS, NOT THE API. Claude Code writes every exchange to
// ~/.claude/projects/<project>/<session>.jsonl and each assistant message
// carries the usage the server reported. Exact counts, no credentials, no rate
// limit, nothing leaves the machine - and it works with the network down.
//
// WHICH IS WHY THERE IS NO PERCENTAGE ANYWHERE IN THIS PLUGIN. The transcripts
// record what was spent and never what the allowance was. A percentage would
// have to be computed against a number this machine does not have, and a
// confident "73%" against a guess is worse than no number at all.
//
// BILLED EXCLUDES CACHE READS and the panel says so. On this machine the
// current block was 915k billed against 282M read from cache - three hundred
// times larger - so a single "tokens" figure would be a number about the
// context being resent, which is the one thing nobody did on purpose.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: usage

    // Nothing read yet, which is not the same as nothing used. The button
    // draws its own unknown state rather than a zero.
    property bool ready: false

    property int blockBilled: 0
    property int blockMessages: 0
    property int blockEndsIn: 0          // seconds until this window rolls over
    property int blockHours: 5
    property int blockCacheRead: 0

    property int todayBilled: 0
    property int todayMessages: 0
    property int weekBilled: 0

    property var models: []              // [{ name, billed }], biggest first
    property var recent: []              // the last 12 blocks, oldest first

    readonly property string script:
        Quickshell.env("HOME") + "/Work/fd44_hyprdot/bin/claude-usage.py"

    function refresh(): void {
        if (reader.running) return
        reader.running = true
    }

    // EVERY TWO MINUTES, NOT EVERY FEW SECONDS. A scan reads only what the
    // transcripts have grown by - 60ms on this machine against 12s for the
    // first pass over 567MB - but the number it produces moves slowly and a
    // bar plugin that wakes the disk constantly to tell you the same figure is
    // a cost with no reader.
    Timer {
        interval: 120000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: usage.refresh()
    }

    Process {
        id: reader
        command: [usage.script, "scan"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d
                try {
                    d = JSON.parse(text)
                } catch (e) {
                    // A broken answer leaves the last good one on screen rather
                    // than blanking the plugin: stale is more use than empty.
                    return
                }
                if (!d || !d.ok) return
                const b = d.block || {}
                usage.blockBilled    = b.billed || 0
                usage.blockMessages  = b.messages || 0
                usage.blockEndsIn    = b.endsIn || 0
                usage.blockHours     = b.hours || 5
                usage.blockCacheRead = b.cache_read_input_tokens || 0
                usage.todayBilled    = (d.today || {}).billed || 0
                usage.todayMessages  = (d.today || {}).messages || 0
                usage.weekBilled     = (d.week || {}).billed || 0
                usage.models         = d.models || []
                usage.recent         = d.recent || []
                usage.ready = true
            }
        }
    }

    // 1.2M / 912k / 847. Thousands are rounded because the last three digits of
    // a token count change while you are reading them and never meant anything.
    function human(n: int): string {
        if (n >= 1000000) return (n / 1000000).toFixed(1) + "M"
        if (n >= 1000)    return Math.round(n / 1000) + "k"
        return String(n)
    }

    function remaining(): string {
        const h = Math.floor(usage.blockEndsIn / 3600)
        const m = Math.floor((usage.blockEndsIn % 3600) / 60)
        return h > 0 ? h + "h " + m + "m" : m + "m"
    }
}
