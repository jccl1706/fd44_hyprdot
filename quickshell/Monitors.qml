// What screens are attached, and what scale each one should run at.
//
// The idea is borrowed from omarchy-monitor-settings, which offers named
// scaling presets rather than a number box, on the grounds that nobody knows
// what 1.5666667 means but everybody knows whether the text is too small.
// Omarchy's own "Setup -> Monitors" just opens monitors.lua in an editor.
//
// WHAT IS DIFFERENT HERE: the presets are computed from the panel in front of
// you, not looked up from a table of common resolutions. Hyprland reports
// physicalWidth and physicalHeight in millimetres, so the real pixel density
// is known, and hypr/monitors.lua already says what to aim at - "about 125-130
// effective px per inch, so text is the same physical size on every machine".
// That file measured two panels by hand to hit it. This does the same
// arithmetic for any panel, including ones nobody has measured yet.
//
// NOT EVERY SCALE IS AVAILABLE, and this is the part that makes a number box
// a bad control. Hyprland silently moves a scale it cannot use - monitors.lua
// records 1.25 on the Framework landing at 1.175 - and this panel has only ten
// usable scales in the whole range from 1 to 3. validScales() below has the
// rule and the evidence for it. Every scale offered here is snapped first, so
// each option states the logical resolution it will actually produce rather
// than the one it was asked for.
//
// NOTHING IS DONE ABOUT GDK_SCALE, deliberately. Omarchy pairs a compositor
// scale with a GTK one, which is right for its integer-scaling advice and
// wrong here: GDK_SCALE is an integer multiplier applied on top of the
// compositor's, so setting it alongside a fractional scale double-scales GTK
// apps. Wayland hands the fractional scale to the toolkit, which is enough.
// XCURSOR_SIZE stays where it is in hypr/autostart.lua for the same reason -
// Hyprland scales the cursor theme itself.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: monitors

    // One entry per attached output, as hyprctl reports it plus what we work
    // out from it. Empty until the first read finishes.
    property var list: []

    // The effective density "Standard" aims at, in px per inch.
    //
    // hypr/monitors.lua's target, in its words: "about 125-130 effective px
    // per inch, so text is the same physical size on every machine". The two
    // panels it measured by hand land on 130 and 126, so this reproduces the
    // hand-tuned value rather than competing with it.
    readonly property int standardPpi: 128

    // Densities outside this range are not believed, and no ppi figure is
    // shown for them. hypr/monitors.lua records why: the LG television's EDID
    // claims a physical size of 1600x900 mm, "a lie no 4K television is",
    // which works out at about 60 ppi. Printing "30 ppi" under a scale-2
    // option would be stating a measurement that is not one.
    readonly property int minBelievablePpi: 80
    readonly property int maxBelievablePpi: 400

    // What to call each screen, where "BOE 0x0BCA" is not an answer.
    //
    // That string is the panel's EDID identity - maker and model code - and it
    // is the right thing for hypr/monitors.lua to match on, because it follows
    // the panel rather than the connector. It is the wrong thing to read in a
    // settings window. These are the same screens that file names in its own
    // comments; this puts those names on screen instead of leaving them in
    // the source.
    //
    // KEYED ON THE DESCRIPTION, NOT THE HOSTNAME, for the reason monitors.lua
    // gives for doing the same: neither machine needs to know the other
    // exists, and a panel moved between them keeps its name.
    //
    // Anything not listed keeps whatever Hyprland calls it, which for an
    // ordinary monitor is usually already a maker and a model somebody can
    // read. An unlisted internal panel becomes "Built-in display" - true on
    // any laptop, and better than a hex code.
    readonly property var friendlyNames: ({
        "BOE 0x0BCA":                       "Framework display",
        "AU Optronics 0x213D":              "ThinkPad display",
        "LG Electronics LG ULTRAGEAR":      "UltraGear monitor",
        "LG Electronics LG TV SSCR2":       "Living-room TV",
        "The Linux Foundation fd44 stream": "Streaming dummy"
    })

    // MATCHED AS A PREFIX, like hypr/monitors.lua's desc: rules - that file
    // says so in as many words: "the match is a prefix, so a serial number
    // after the model does not break it". The desktop's monitor is the case
    // that needs it: hyprctl calls it "LG Electronics LG ULTRAGEAR
    // 106NTNH2R807", and the tail is that particular unit's serial. Keying on
    // the whole string would name one monitor and no other of the same model.
    function prettyName(description: string, internal: bool): string {
        if (monitors.friendlyNames[description]) return monitors.friendlyNames[description]
        for (const key in monitors.friendlyNames)
            if (description.indexOf(key) === 0) return monitors.friendlyNames[key]
        return internal ? "Built-in display" : description
    }

    // --- reading ----------------------------------------------------------

    function refresh(): void {
        reader.running = false
        reader.running = true
    }

    Process {
        id: reader
        running: true
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: monitors.list = monitors.interpret(text)
        }
    }

    function interpret(json: string): var {
        let raw
        try {
            raw = JSON.parse(json)
        } catch (e) {
            console.warn("monitors: hyprctl gave something that is not JSON:", e)
            return []
        }
        if (!Array.isArray(raw)) return []
        return raw.filter(m => !m.disabled).map(m => monitors.describe(m))
    }

    // hyprctl's entry, plus density and the scales this panel can actually do.
    function describe(m: var): var {
        const mmDiagonal = Math.sqrt(m.physicalWidth * m.physicalWidth
                                   + m.physicalHeight * m.physicalHeight)
        const inches = mmDiagonal / 25.4
        const ppi = inches > 0
            ? Math.sqrt(m.width * m.width + m.height * m.height) / inches
            : 0
        const description = m.description || m.name
        const internal = /^eDP/i.test(m.name)
        return {
            name: m.name,
            description: description,
            // What the row is labelled. `description` stays as it is, because
            // it is what the generated rule has to match on.
            title: monitors.prettyName(description, internal),
            width: m.width,
            height: m.height,
            scale: m.scale,
            ppi: ppi,
            inches: inches,
            // eDP is an internal panel by definition - the same test
            // hypr/monitors.lua uses to decide placement.
            internal: internal,
            options: ppi > 0 ? monitors.presetsFor(m, ppi, m.scale) : [],

            // Modes, split into the two things anyone actually chooses.
            // Kept so a later setResolution() can find the rates on offer
            // without another call to hyprctl.
            availableModes: m.availableModes || [],
            resolutionOptions: monitors.resolutionsOf(m),
            refreshOptions: monitors.refreshesOf(m, m.width + "x" + m.height),
            currentResolution: m.width + "x" + m.height,
            currentRefresh: monitors.nearestRefresh(m)
        }
    }

    // --- modes ------------------------------------------------------------
    //
    // hyprctl gives one flat list - "2256x1504@60.00Hz", "2256x1504@48.00Hz",
    // "1920x1200@60.00Hz" and nine more - which is not how anyone picks a
    // mode. Nobody wants a list of thirteen; they want a resolution, and then
    // a refresh rate if that resolution offers more than one. This panel has
    // twelve resolutions and exactly one of them has a second rate, which is
    // why they are two rows and not one.

    function splitMode(mode: string): var {
        const at = mode.indexOf("@")
        if (at < 0) return { res: mode, hz: "" }
        // "60.00Hz" -> "60.00"; the Hz is for the label, not the value.
        return { res: mode.substring(0, at), hz: mode.substring(at + 1).replace(/Hz$/i, "") }
    }

    // Biggest first. Sorting by pixel count rather than by string keeps
    // 1920x1200 above 1920x1080, which sorting by width alone would not.
    function resolutionsOf(m: var): var {
        const seen = {}
        const out = []
        for (const mode of (m.availableModes || [])) {
            const res = monitors.splitMode(mode).res
            if (seen[res]) continue
            seen[res] = true
            const parts = res.split("x")
            out.push({ value: res, label: res, pixels: parseInt(parts[0]) * parseInt(parts[1]) })
        }
        out.sort((a, b) => b.pixels - a.pixels)
        // The native mode is the first one hyprctl lists, and it is the one
        // worth marking: on a flat panel anything else is interpolated and
        // soft, which the resolution on its own does not tell you.
        if (out.length && m.availableModes && m.availableModes.length) {
            const native = monitors.splitMode(m.availableModes[0]).res
            for (const o of out) if (o.value === native) o.label = o.value + " (native)"
        }
        return out
    }

    function refreshesOf(m: var, resolution: string): var {
        const seen = {}
        const out = []
        for (const mode of (m.availableModes || [])) {
            const parsed = monitors.splitMode(mode)
            if (parsed.res !== resolution || seen[parsed.hz]) continue
            seen[parsed.hz] = true
            out.push({
                value: parsed.hz,
                label: monitors.tidyHz(parsed.hz) + " Hz",
                rate: parseFloat(parsed.hz)
            })
        }
        out.sort((a, b) => b.rate - a.rate)
        return out
    }

    // "60.00" -> "60", "143.97" -> "144", "99.95" -> "100".
    //
    // A tenth of a hertz, not a twentieth. The desktop's UltraGear advertises
    // 143.97, 120.00, 99.95 and 59.95, and a monitor calling 60 Hz "59.95" is
    // the normal state of affairs rather than a distinction anyone wants in a
    // settings window. 0.05 rounded these correctly only because 99.95 and
    // 59.95 are a hair under 0.05 away in binary floating point, which is not
    // a thing to depend on.
    function tidyHz(hz: string): string {
        const n = parseFloat(hz)
        return Math.abs(n - Math.round(n)) < 0.1 ? String(Math.round(n)) : n.toFixed(2)
    }

    // WHAT IT IS RUNNING AT, MATCHED BACK TO A MODE STRING. hyprctl reports
    // refreshRate as 59.999 while the mode it came from is called "60.00", so
    // comparing them as text finds nothing. Half a hertz is a wide enough
    // window to pair them and far too narrow to confuse 60 with 48.
    function nearestRefresh(m: var): string {
        const resolution = m.width + "x" + m.height
        let best = ""
        for (const option of monitors.refreshesOf(m, resolution))
            if (best === "" || Math.abs(option.rate - m.refreshRate)
                             < Math.abs(parseFloat(best) - m.refreshRate))
                best = option.value
        return best
    }

    // --- the presets ------------------------------------------------------

    function gcd(a: int, b: int): int {
        while (b) { const t = b; b = a % b; a = t }
        return a
    }

    // WHICH SCALES A PANEL CAN ACTUALLY HOLD, in 120ths.
    //
    // hypr/monitors.lua records the symptom - "a value that cannot be snapped
    // cleanly ends up somewhere else - 1.25 on the Framework lands on 1.175" -
    // without the rule behind it. This is the rule, and it was worked out by
    // asking Hyprland for scales and reading back what it kept.
    //
    // Wayland carries a fractional scale as an integer number of 120ths, so a
    // scale is really k/120. The logical size has to come out whole, which
    // means 120*w/k and 120*h/k must both be integers - so k has to DIVIDE
    // 120*gcd(w, h). Hyprland then takes the valid k nearest the one asked
    // for. On this panel 120*gcd(2256,1504) = 90240, whose divisors in range
    // give only ten usable scales:
    //
    //   1.0  1.0667  1.175  1.3333  1.5667  1.6  1.9583  2.0  2.35  2.6667
    //
    // 1.25 asks for k=150; the nearest divisors are 141 and 160, and 141 wins
    // by one - which is 1.175, exactly what that file saw. Predicted and then
    // confirmed against a live Hyprland for 1.25, 1.4, 1.748837, 1.9, 2.3 and
    // 2.6; every one landed where this says.
    //
    // THE NAIVE VERSION IS WRONG AND LOOKS RIGHT. Requiring only w/scale and
    // h/scale to be whole admits scales Hyprland will not keep: 1.748837
    // divides 2256 into exactly 1290, and asking for it gives 1.6.
    function validScales(w: int, h: int): var {
        const n = 120 * monitors.gcd(w, h)
        const out = []
        for (let k = 120; k <= 360; k++)       // scale 1 through 3
            if (n % k === 0) out.push(k)
        return out
    }

    // The scales people mean. Each is snapped before it is offered, so what
    // the row shows is what the panel will be on.
    readonly property var roundScales: [1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 3]

    // A step has to be worth taking. On this panel 1.5667 and 1.6 are both
    // available and three percent apart - offering the second as "Larger"
    // next to the first is offering nothing.
    readonly property real minStep: 1.08

    function presetsFor(m: var, ppi: real, current: real): var {
        const ks = monitors.validScales(m.width, m.height)
        if (!ks.length) return []
        const believable = ppi >= monitors.minBelievablePpi && ppi <= monitors.maxBelievablePpi

        function snap(wanted) {
            const want = Math.round(wanted * 120)
            let best = ks[0]
            for (const k of ks) if (Math.abs(k - want) < Math.abs(best - want)) best = k
            return best / 120
        }

        const now = snap(current)
        const seen = {}
        const out = []
        function offer(scale, label) {
            if (scale < 1 || scale > 3) return
            const value = monitors.spell(scale)
            if (seen[value]) return
            seen[value] = true
            out.push({
                value: value,
                label: label,
                detail: Math.round(m.width / scale) + "x" + Math.round(m.height / scale)
                        + (believable ? "  ·  " + Math.round(ppi / scale) + " ppi" : "")
            })
        }

        // What it is on now takes its own value first, so it is labelled "As
        // set" rather than by a preset that happens to land on the same
        // number - which is how monitors.lua's hand-measured scale stays
        // visible and selectable on its own machine.
        offer(now, "As set")

        // The density target, where the panel's own figures can be believed,
        // and only when it beats what the panel is already on. On the
        // Framework the nearest round scale is 1.5 - which snaps to 1.5667,
        // the measured value - so this usually says nothing there, which is
        // correct: that file already did this arithmetic by hand.
        if (believable) {
            let best = null
            for (const candidate of monitors.roundScales) {
                const scale = snap(candidate)
                if (scale < 1 || scale > 3) continue
                if (best === null
                    || Math.abs(ppi / scale - monitors.standardPpi)
                     < Math.abs(ppi / best - monitors.standardPpi))
                    best = scale
            }
            // ...and only when it is a real step away. On the Framework the
            // nearest round scale is 1.6 against the 1.5667 in monitors.lua:
            // three percent apart, for one effective ppi. Offering that as a
            // named recommendation would be offering noise.
            if (best !== null
                && Math.abs(ppi / best - monitors.standardPpi)
                 < Math.abs(ppi / now - monitors.standardPpi)
                && (best >= now * monitors.minStep || best <= now / monitors.minStep))
                offer(best, "Standard")
        }

        // One usable step either side.
        let below = null, above = null
        for (const candidate of monitors.roundScales) {
            const scale = snap(candidate)
            if (scale <= now / monitors.minStep && (below === null || scale > below)) below = scale
            if (scale >= now * monitors.minStep && (above === null || scale < above)) above = scale
        }
        // Smaller scale, smaller everything - the label says what happens to
        // the desktop, not which way the number moves.
        if (below !== null) offer(below, "Smaller")
        if (above !== null) offer(above, "Larger")

        // ONE OPTION IS NOT A CHOICE, so the row is not drawn at all.
        return out.length >= 2 ? out.sort((a, b) => parseFloat(a.value) - parseFloat(b.value)) : []
    }

    // A scale as Hyprland wants it written. Six decimals is what `hyprctl
    // monitors` prints back for 752/480, and trailing zeros are noise in a
    // generated file that someone may well read.
    function spell(scale: real): string {
        return scale.toFixed(6).replace(/0+$/, "").replace(/\.$/, "")
    }

    // What the selected option produces - logical resolution, and effective
    // density where the panel's own figures can be believed.
    //
    // THE SEGMENTED CONTROL DRAWS ONLY `label`, so this is how the numbers
    // reach the screen at all: the row's help line carries them for whichever
    // option is selected. Putting them in the labels instead would make three
    // or four segments of "Larger 1290x860" and overflow the pane.
    function currentDetail(monitor: var): string {
        const now = monitors.spell(monitor.scale)
        for (const o of monitor.options)
            if (o.value === now) return o.detail
        return ""
    }

    // Which preset is in use, or "" when the panel is on something else -
    // a value from monitors.lua that no target happens to land on.
    function currentOption(monitor: var): string {
        const now = monitors.spell(monitor.scale)
        return monitor.options.some(o => o.value === now) ? now : ""
    }

    // --- applying ---------------------------------------------------------

    // The rule for one output, as a line of Lua.
    //
    // NOT `hyprctl keyword monitor ...`, which is the obvious call and does
    // not work here: this configuration is hyprland.lua, so Hyprland is on its
    // non-legacy parser and answers "keyword can't work with non-legacy
    // parsers. Use eval." `hyprctl eval` takes Lua, and hl.monitor is the same
    // function hypr/monitors.lua calls - so what is applied at runtime and
    // what is written to the file are the same statement.
    //
    // POSITION MIRRORS hypr/monitors.lua rather than being invented here: that
    // file gives internal panels `auto` and everything else `auto-left`, on the
    // argument that an external display is the one being looked at and belongs
    // to the left of the laptop. Writing a fixed x,y instead would be more
    // precise and would stop the rule following the screen when it is plugged
    // in somewhere else.
    function rule(monitor: var, scale: string, mode: string): string {
        return 'hl.monitor({ output = "desc:' + monitor.description + '",'
             + ' mode = "' + mode + '",'
             + ' position = "' + (monitor.internal ? "auto" : "auto-left") + '",'
             + ' scale = "' + scale + '" })'
    }

    // A rule names every field, so changing one means restating the others.
    // These read from the override where there is one and from the live
    // monitor otherwise, which is what keeps picking a resolution from
    // silently resetting a scale chosen a minute earlier.
    function currentScaleOf(monitor: var): string {
        const kept = monitors.overrides[monitor.description]
        return (kept && kept.scale) || monitors.spell(monitor.scale)
    }

    // "preferred" until a mode is actually chosen. Writing the live mode
    // instead would pin the panel to whatever it happened to come up at,
    // which for an external display is a promise this page cannot keep when
    // it is plugged into something else.
    function currentModeOf(monitor: var): string {
        const kept = monitors.overrides[monitor.description]
        return (kept && kept.mode) || "preferred"
    }

    function apply(monitor: var, scale: string, mode: string): void {
        applier.command = ["hyprctl", "eval", monitors.rule(monitor, scale, mode)]
        applier.running = true
        monitors.remember(monitor, scale, mode)
    }

    function setScale(monitor: var, scale: string): void {
        monitors.apply(monitor, scale, monitors.currentModeOf(monitor))
    }

    // Picking a resolution takes the fastest rate that resolution offers.
    // The alternative - keeping the rate and hoping the new resolution has it
    // - produces a mode that does not exist, and Hyprland answers that by
    // falling back to something neither asked for.
    function setResolution(monitor: var, resolution: string): void {
        const rates = monitors.refreshesOf({ availableModes: monitor.availableModes },
                                           resolution)
        const hz = rates.length ? rates[0].value : ""
        monitors.apply(monitor, monitors.currentScaleOf(monitor),
                       hz ? resolution + "@" + hz : resolution)
    }

    function setRefresh(monitor: var, hz: string): void {
        monitors.apply(monitor, monitors.currentScaleOf(monitor),
                       monitor.currentResolution + "@" + hz)
    }

    Process {
        id: applier
        running: false
        onExited: (code) => {
            if (code !== 0) console.warn("monitors: hyprctl keyword failed:", code)
            monitors.refresh()
        }
    }

    // --- remembering ------------------------------------------------------

    // Scales chosen here, by output description.
    property var overrides: ({})

    function remember(monitor: var, scale: string, mode: string): void {
        const next = Object.assign({}, monitors.overrides)
        next[monitor.description] = { scale: scale, mode: mode, internal: monitor.internal }
        monitors.overrides = next
        monitors.save()
    }

    // WRITTEN TO A FILE OF ITS OWN, NEVER INTO monitors.lua. That file is two
    // hundred lines of measured reasoning in git - which panel reports its
    // maker wrongly, why the television is scale 2, what the display dummy is
    // for - and round-tripping it through a generator would leave none of it.
    // Hyprland applies monitor rules in order and the last match wins, which
    // monitors.lua already depends on for its own catch-all, so a rule
    // required at the end of that file simply beats the one above it.
    //
    // Per machine and not in git: the whole point is that the Framework and
    // the desktop want different numbers.
    FileView {
        id: file
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
              + "/hypr/monitors_local.lua"
        // Not existing is the ordinary state - nothing has been chosen yet -
        // and FileView logs a WARN for it on every start otherwise.
        printErrors: false
        onLoaded: monitors.overrides = monitors.readBack(text())
        onLoadFailed: monitors.overrides = ({})     // nothing chosen yet
        onSaveFailed: err => console.warn("monitors: could not save:", FileViewError.toString(err))
    }

    // The generated file is also the record of what was chosen, so it is read
    // back rather than kept in a second place that could disagree with it.
    function readBack(text: string): var {
        const found = {}
        const line = /output\s*=\s*"desc:([^"]+)".*?mode\s*=\s*"([^"]+)".*?position\s*=\s*"([^"]+)".*?scale\s*=\s*"([^"]+)"/g
        let m
        while ((m = line.exec(text)) !== null)
            found[m[1]] = { mode: m[2], scale: m[4], internal: m[3] === "auto" }
        return found
    }

    function save(): void {
        const names = Object.keys(monitors.overrides).sort()
        let out = "-- Generated by the Display page in quickshell's settings.\n"
                + "-- Edits here are overwritten. To keep a scale, move the line\n"
                + "-- into monitors.lua, where it will be read by a person.\n"
                + "--\n"
                + "-- Required last by monitors.lua, so these win: Hyprland applies\n"
                + "-- monitor rules in order and the last one matching an output takes\n"
                + "-- effect.\n\n"
        for (const name of names) {
            const o = monitors.overrides[name]
            out += "hl.monitor({\n"
                 + '    output   = "desc:' + name + '",\n'
                 + '    mode     = "' + (o.mode || "preferred") + '",\n'
                 + '    position = "' + (o.internal ? "auto" : "auto-left") + '",\n'
                 + '    scale    = "' + o.scale + '",\n'
                 + "})\n\n"
        }
        file.setText(out)
    }
}
