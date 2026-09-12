// =========================================================================
// Launcher - application launcher, slides up out of the bottom frame
// =========================================================================
//
// Hidden until Hyprland pokes it over IPC (Super+Space, see binds.lua). The
// card rises from the middle of the bottom frame, takes keyboard focus,
// filters desktop entries as you type, and launches on Return.
//
// WHY A FULL-SCREEN SURFACE FOR A SMALL CARD:
// The window covers the whole output even though the card is 560x420 in the
// middle of it. That buys click-outside-to-dismiss from a single surface - a
// card-sized window has no "outside" to click. The cost is that an invisible
// full-screen layer would swallow every click on the desktop, so the window
// is genuinely unmapped (visible = false) whenever it is closed rather than
// merely transparent. That is also why closing is a two-step affair: the
// slide has to finish before the surface can go away.
//
// KEYBOARD FOCUS:
// Layer-shell surfaces get no keyboard input by default - a bar should never
// steal your typing. Exclusive focus is taken only while open and dropped the
// moment it closes, so the frame and bar never interfere with the focused
// window.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: root

    // Variants sets this - one launcher per monitor, same as the Bar.
    required property var modelData
    screen: modelData

    // --- state -----------------------------------------------------------

    // The card is on screen (or animating towards it).
    property bool revealed: false

    // Index into `results` that Return will launch.
    property int selected: 0

    // Hyprland's own layer animation is disabled for this namespace (see the
    // layer rule in hypr/rules.lua) - with it on, the compositor was fading
    // the whole surface in while Qt slid the card, and the two fighting is
    // what made the motion look like it was stuttering.
    readonly property int openDuration: 260

    // CLOSING IS DELIBERATELY FASTER THAN OPENING.
    //
    // Partly taste - an opening panel is worth watching, a closing one is just
    // in the way. Mostly, though, it is about the blur: Hyprland holds the
    // blur region for as long as the surface is mapped and does not track the
    // panel as it slides away inside it, so the blurred patch outlives the
    // card by however long the close takes. Measured at 260ms the blur lingered
    // ~190ms after the card had visibly gone, which reads as the launcher
    // leaving a smear behind. The surface cannot be unmapped any earlier than
    // this - the card is only fully off screen when the slide ends - so the
    // only lever is to make the slide shorter.
    readonly property int closeDuration: 140

    // Whichever of the two applies to the transition now in flight.
    //
    // SET IMPERATIVELY, and always BEFORE `revealed` flips. Binding it to
    // `revealed ? openDuration : closeDuration` looks equivalent and is not:
    // flipping revealed invalidates this binding and the bottomMargin binding
    // together, QML re-evaluates them lazily, and the Behavior can start its
    // animation - reading duration once, at start - before this one has been
    // recomputed. The close then silently runs at the OPEN duration. It cost a
    // round of confused measurements: the file said 140, the close still took
    // 260.
    property int activeDuration: openDuration

    // --- window ----------------------------------------------------------

    // Overlay, so it covers the bar and frame rather than sliding under them.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-launcher"

    // Only while open - see the header note.
    WlrLayershell.keyboardFocus: revealed ? WlrKeyboardFocus.Exclusive
                                          : WlrKeyboardFocus.None

    anchors { left: true; right: true; top: true; bottom: true }

    // Reserves nothing, AND is not pushed around by anything else's
    // reservation. Without Ignore the bar and frame zones shrink the surface
    // to the content well (4,34 1432x922), so the scrim stops short of the bar
    // and the card stops 4px above the frame instead of meeting it.
    //
    // Do NOT also set exclusiveZone here: assigning it puts the window back
    // into Normal exclusion mode and undoes this.
    exclusionMode: ExclusionMode.Ignore

    color: "transparent"

    // Starts unmapped. open() maps it, and the slide-out animation unmaps it
    // again once the card is fully off screen.
    visible: false

    // --- public API ------------------------------------------------------

    function open(): void {
        search.text = ""
        root.selected = 0
        root.visible = true
        root.activeDuration = root.openDuration
        root.revealed = true
        search.forceActiveFocus()
    }

    function close(): void {
        root.activeDuration = root.closeDuration
        root.revealed = false
        // visible goes false when the slide finishes - see card.onYChanged.
    }

    function toggle(): void {
        if (root.revealed) root.close()
        else root.open()
    }

    function launch(entry): void {
        if (!entry) return
        root.close()

        // Launch through uwsm so the app becomes its own systemd scope under
        // app.slice, NOT a child of quickshell. Anything spawned as a child
        // shares quickshell's cgroup and dies with it, so restarting the bar
        // would take every app you had opened down with it.
        launcher.entry = entry
        launcher.command = ["uwsm", "app", "--", entry.id + ".desktop"]
        launcher.running = true
    }

    Process {
        id: launcher

        // Held so the fallback below knows what failed to start.
        property var entry: null

        onExited: (code, status) => {
            // uwsm can refuse an entry it cannot resolve. Rather than leave
            // the user staring at nothing, fall back to Quickshell's own
            // launcher, which loses the systemd scope but does start the app.
            if (code !== 0 && launcher.entry) {
                console.warn("launcher: uwsm failed for", launcher.entry.id,
                             "- falling back to direct execute")
                launcher.entry.execute()
            }
            launcher.entry = null
        }
    }

    // --- results ---------------------------------------------------------

    // NOTE: the desktop entry scan is ASYNCHRONOUS. This list is empty for the
    // first few hundred ms of a quickshell run, so it must stay a live binding
    // - snapshot it once at startup and the launcher is permanently empty.
    readonly property var entries: DesktopEntries.applications.values

    readonly property var results: {
        const all = root.entries.filter(e => !e.noDisplay)
        const q = search.text.trim().toLowerCase()

        if (q === "")
            return all.slice().sort((a, b) => a.name.localeCompare(b.name))

        // Rank rather than merely filter, so typing "fi" puts Files above
        // something that only mentions "profile" in its description.
        const scored = []
        for (const e of all) {
            const name    = (e.name || "").toLowerCase()
            const generic = (e.genericName || "").toLowerCase()
            const comment = (e.comment || "").toLowerCase()
            const keys    = (e.keywords || []).join(" ").toLowerCase()

            let rank = -1
            if      (name.startsWith(q)) rank = 0
            else if (name.includes(q))   rank = 1
            else if (generic.includes(q)) rank = 2
            else if (keys.includes(q))    rank = 3
            else if (comment.includes(q)) rank = 4

            if (rank >= 0) scored.push({ entry: e, rank: rank, name: name })
        }

        scored.sort((a, b) => a.rank - b.rank || a.name.localeCompare(b.name))
        return scored.map(x => x.entry)
    }

    // Every change to the query restarts the selection at the top, otherwise
    // the highlight can sit past the end of a shorter result list.
    onResultsChanged: root.selected = 0

    // --- scrim -----------------------------------------------------------

    // Dims the CONTENT WELL only - inset past the bar and the frame, so the
    // chrome keeps its real colour. This is what lets the card read as part of
    // the frame: dim the frame too and the card's Theme.bg no longer matches
    // the strip it is supposed to be growing out of, and the junction shows up
    // as a seam.
    Rectangle {
        anchors {
            fill: parent
            topMargin:    Theme.barHeight
            leftMargin:   Theme.frameThickness
            rightMargin:  Theme.frameThickness
            bottomMargin: Theme.frameThickness
        }
        // The well is not a rectangle: Frame.qml rounds all four of its inner
        // corners with a concave piece of Theme.cornerRadius that reaches
        // cornerRadius INTO the well, past this inset. A square scrim paints
        // over those four pieces and dims them while the frame strips they
        // belong to stay bright, so the corners read as damaged whenever the
        // launcher is open.
        //
        // Rounding by the same radius makes this exactly the well's opening:
        // a corner piece's arc runs from (frame + radius) to (frame), which is
        // precisely the arc of a rounded rect inset to the frame.
        radius: Theme.cornerRadius

        color: "#000000"
        opacity: root.revealed ? 0.35 : 0
        Behavior on opacity {
            NumberAnimation { duration: root.activeDuration
                              easing.type: Easing.OutQuint }
        }
    }

    // Click anywhere to dismiss. Separate from the scrim because it must cover
    // the whole surface including the chrome, while the scrim must not.
    // The card sits above this and swallows its own clicks.
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    // --- card ------------------------------------------------------------

    Item {
        id: card

        width: 560

        // Tallest the card is allowed to get. Beyond this the list scrolls
        // instead of the panel growing further.
        readonly property int maxHeight: 420

        // Everything that is not the results list: the search row and its
        // margins, the divider, and the list's own insets.
        readonly property int chromeHeight:
            Theme.barPadding + searchRow.height + Theme.barPadding
            + divider.height + 6 + 6 + Theme.frameThickness

        // FITS ITS CONTENTS rather than standing at a fixed 420. With a
        // handful of apps installed the old fixed height left half the panel
        // empty, which reads as unfinished rather than spacious - and the
        // emptiness grew as you typed and the list shrank.
        height: Math.min(maxHeight, chromeHeight + list.contentHeight)

        Behavior on height {
            NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
        }

        anchors.horizontalCenter: parent.horizontalCenter

        // Runs all the way to the bottom of the SCREEN, not to the top of the
        // frame - the last frameThickness pixels of the card sit exactly where
        // the frame strip is, in the same colour, so the two are one shape
        // with no seam to notice.
        anchors.bottom: parent.bottom

        // ANIMATED VIA THE MARGIN, NOT y.
        // Binding y to `parent.height - height` looks equivalent but is not:
        // a freshly mapped layer surface reports its size only after the
        // compositor configures it, so on open the card would be positioned
        // against a stale height, then jump when the real one arrived. That
        // jump was most of the clunkiness. The margin is relative to an anchor
        // that tracks the parent by itself and never needs the height at all.
        // -maxHeight, NOT -height: the closed offset has to be a CONSTANT.
        // Bound to `height` it would be re-evaluated every time the results
        // list changed size, which restarts this Behavior - and its
        // onRunningChanged is what unmaps the surface. Filtering while closed
        // could then unmap a panel that was opening. maxHeight always clears
        // the screen, since height can never exceed it.
        anchors.bottomMargin: root.revealed ? 0 : -maxHeight

        Behavior on anchors.bottomMargin {
            NumberAnimation {
                duration: root.activeDuration

                // Front-loaded, like the "snappy" bezier the Hyprland config
                // uses: most of the travel happens immediately and then it
                // settles, which reads as responsive rather than as a slide
                // you are waiting on.
                easing.type: Easing.OutQuint

                // The surface can only be unmapped once the card is fully off
                // screen, or closing snaps instead of sliding.
                onRunningChanged: {
                    if (!running && !root.revealed) root.visible = false
                }
            }
        }

        // --- background -------------------------------------------------
        //
        // The panel and the two fillets that join it to the frame are drawn
        // OPAQUE into an offscreen layer, and the whole layer is then made
        // translucent in one composite.
        //
        // layer.enabled is not an optimisation here, it is the entire point.
        // Plain `opacity` on a parent multiplies into each child separately,
        // so the 1px overlap where a fillet meets the panel would blend twice
        // - 1-(1-a)^2, about 0.98 against 0.85 - and show up as a bright line
        // exactly where the seam used to be a dark one. Flattening first makes
        // the overlap opaque, as it is at full alpha, and the single composite
        // that follows is uniform.
        //
        // Wider than the card by cornerRadius on each side: a layer is clipped
        // to its item's bounds, and the fillets live outside the panel.
        Item {
            id: panel

            anchors.fill: parent
            anchors.leftMargin:  -Theme.cornerRadius
            anchors.rightMargin: -Theme.cornerRadius

            opacity: Theme.panelAlpha
            layer.enabled: true

            Rectangle {
                id: panelBody
                anchors.fill: parent
                anchors.leftMargin:  Theme.cornerRadius
                anchors.rightMargin: Theme.cornerRadius

                // Same lift as the bar pills, with one hard constraint: the
                // bottom stop is exactly Theme.bg, because this card merges
                // into the bottom frame and any other value would put the
                // seam straight back. No border either - a rim would draw a
                // line across that junction.
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.panelTop }
                    GradientStop { position: 1.0; color: Theme.bg }
                }

                // Rounded on top only - the mirror of the bar, which is
                // rounded on the bottom only. The bottom edge is flat because
                // it is the frame.
                topLeftRadius:  Theme.cornerRadius
                topRightRadius: Theme.cornerRadius
            }

            // Concave fillets where the panel's sides meet the top of the
            // bottom frame, so it grows out of the strip instead of being a
            // slab dropped on top of it. The same trick the bar uses where it
            // meets the side pieces, just rotated.
            //
            // The -1 margins overlap each fillet a pixel into the panel. Butt
            // them up exactly and the shared pixel lands on a fractional
            // device pixel under this display's scaling, where each shape
            // antialiases its own side and the two sum to about 78% coverage
            // instead of opaque. Same defect, and same fix, as the frame's own
            // corner seam in Frame.qml.
            InnerCorner {
                corner: "bottomright"      // fills toward the panel, cuts the well
                anchors {
                    right: panelBody.left
                    rightMargin: -1
                    bottom: parent.bottom
                    bottomMargin: Theme.frameThickness
                }
            }

            InnerCorner {
                corner: "bottomleft"
                anchors {
                    left: panelBody.right
                    leftMargin: -1
                    bottom: parent.bottom
                    bottomMargin: Theme.frameThickness
                }
            }
        }

        // Swallows clicks so they do not reach the dismissing MouseArea below.
        MouseArea { anchors.fill: parent }

        // --- search field -------------------------------------------------

        Item {
            id: searchRow
            anchors { top: parent.top; left: parent.left; right: parent.right
                      margins: Theme.barPadding }
            height: 40

            Text {
                id: searchGlyph
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "\u{F0349}"                    // nf-md-magnify
                font.family: Theme.glyphFont
                font.pixelSize: Theme.glyphSize
                color: Theme.dim
            }

            TextInput {
                id: search
                anchors {
                    left: searchGlyph.right; leftMargin: Theme.itemSpacing
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                font.family: Theme.font
                // Medium, not bold. At 16px a bold input reads as a heading
                // rather than a field you are meant to type into.
                font.weight: Theme.weightMedium
                font.pixelSize: Theme.fontSizeClock
                font.letterSpacing: Theme.trackingTight
                font.variableAxes: ({ "opsz": Theme.fontSizeClock })
                color: Theme.fg
                selectionColor: Theme.accent
                selectedTextColor: Theme.accentFg
                clip: true

                // All navigation lives here because this is what holds focus.
                // Putting it on the ListView instead would need focus to move
                // between the two, and then typing would stop working.
                Keys.onEscapePressed: root.close()
                Keys.onDownPressed:   root.move(1)
                Keys.onUpPressed:     root.move(-1)
                Keys.onReturnPressed: root.launch(root.results[root.selected])
                Keys.onEnterPressed:  root.launch(root.results[root.selected])
                Keys.onTabPressed:    root.move(1)
                Keys.onBacktabPressed: root.move(-1)

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: search.text === ""
                    text: "Search applications"
                    font: search.font
                    color: Theme.dim
                }
            }
        }

        Rectangle {
            id: divider
            anchors { top: searchRow.bottom; topMargin: Theme.barPadding
                      left: parent.left; right: parent.right }
            height: 1
            color: Theme.dim
            opacity: 0.25
        }

        // --- results list -------------------------------------------------

        ListView {
            id: list
            anchors {
                top: divider.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: 6
                // The card's last few pixels ARE the frame strip - keep rows
                // out of them, or a row can appear to bleed into the border.
                bottomMargin: 6 + Theme.frameThickness
            }

            clip: true
            model: root.results
            currentIndex: root.selected

            // Keeps the highlighted row on screen when navigating by keyboard.
            highlightFollowsCurrentItem: true
            highlightMoveDuration: Theme.animFast

            delegate: Rectangle {
                id: row

                // ListView hands array items over as modelData, same as
                // Variants does. `index` must be declared to be used.
                required property var modelData
                required property int index

                width: list.width
                height: 44
                radius: 8

                readonly property bool active: row.index === root.selected

                // A WASH, NOT A SLAB. Filling the whole row with solid accent
                // made the selection the loudest thing on screen - louder than
                // the panel containing it - and forced the text to invert,
                // which broke the type hierarchy on exactly the one row you
                // were looking at. A tint plus the marker below says the same
                // thing without shouting, and lets the text keep its colours.
                color: row.active
                       ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                       : "transparent"

                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                // The actual selection marker.
                Rectangle {
                    anchors { left: parent.left; leftMargin: 2
                              verticalCenter: parent.verticalCenter }
                    width: 3
                    height: row.active ? 20 : 0
                    radius: 1.5
                    color: Theme.accent
                    Behavior on height {
                        NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
                    }
                }

                Image {
                    id: icon
                    anchors { left: parent.left; leftMargin: 10
                              verticalCenter: parent.verticalCenter }
                    width: 28; height: 28
                    sourceSize: Qt.size(28, 28)
                    // iconPath's second argument returns "" instead of a
                    // broken-image placeholder when the theme has no icon.
                    source: row.modelData.icon
                            ? Quickshell.iconPath(row.modelData.icon, true)
                            : ""
                    visible: source !== ""
                }

                // Shown only when the theme has no icon for this entry, so a
                // missing icon leaves a glyph rather than a ragged gap.
                Text {
                    anchors.centerIn: icon
                    visible: !icon.visible
                    text: "\u{F0349}"
                    font.family: Theme.glyphFont
                    font.pixelSize: Theme.glyphSize
                    color: Theme.dim
                }

                Column {
                    anchors {
                        left: icon.right; leftMargin: Theme.itemSpacing
                        right: parent.right; rightMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 1

                    Text {
                        width: parent.width
                        text: row.modelData.name
                        font.family: Theme.font
                        font.weight: Theme.weightSemi
                        font.pixelSize: Theme.fontSizeTitle
                        color: Theme.fg
                        elide: Text.ElideRight
                    }

                    // ONLY THE SELECTED ROW SHOWS ITS DESCRIPTION. Every row
                    // carrying two lines is a wall of text once there are more
                    // than a handful of results, and the description is only
                    // ever useful for the one you are about to launch.
                    //
                    // Faded rather than hidden, and the space is reserved
                    // whether or not it shows: collapsing it would move the
                    // title, so every arrow-key press would jiggle two rows.
                    // This way nothing moves - the subtitle simply appears.
                    Text {
                        width: parent.width
                        text: row.modelData.comment || row.modelData.genericName || ""
                        font.family: Theme.font
                        font.weight: Theme.weightNormal
                        font.pixelSize: Theme.fontSizeSmall
                        font.letterSpacing: Theme.trackingLoose
                        color: Theme.dim
                        opacity: row.active ? 1 : 0
                        elide: Text.ElideRight
                        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    // Hover drives the same selection the keyboard uses, so
                    // there is only ever one highlighted row.
                    onEntered: root.selected = row.index
                    onClicked: root.launch(row.modelData)
                }
            }

            // --- empty state ----------------------------------------------

            Text {
                anchors.centerIn: parent
                visible: list.count === 0
                text: root.entries.length === 0 ? "Loading applications…"
                                                : "No matches"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                color: Theme.dim
            }
        }
    }

    // Moves the selection by `delta`, clamped to the ends rather than
    // wrapping - wrapping from the last result back to the first is
    // disorienting when you are holding Down to scan the list.
    function move(delta: int): void {
        const n = root.results.length
        if (n === 0) return
        root.selected = Math.max(0, Math.min(n - 1, root.selected + delta))
        list.positionViewAtIndex(root.selected, ListView.Contain)
    }
}
