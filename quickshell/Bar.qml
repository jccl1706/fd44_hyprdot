// =========================================================================
// Bar - a full-width panel across the top of one monitor
// =========================================================================
//
// Three pills: logo, workspaces and the OSD on the left; the clock in the
// centre; and whatever plugins BarLayout.qml places around them.
//
// MOVABLE PLUGINS. The audio, network and theme glyphs are not fixed in this
// file. BarLayout says which zone each sits in - after the workspaces, either
// side of the clock, or the right pill - and BarZone draws them. Press and
// hold one (about a third of a second) to pick it up, drag it along the bar,
// and let go where the gap opens. Let go well away from the bar to put it
// back. A quick click still does what the plugin does.

import Quickshell
import QtQuick

PanelWindow {
    id: root

    // Exposed so the IpcHandler in shell.qml can trigger it.
    property alias osd: osd

    // A plugin glyph was clicked. `x` is the glyph's centre in this window,
    // which spans the monitor, so it is the screen x the panel should open
    // under. shell.qml owns the panels and opens the one on this monitor; the
    // bar does not reach for windows itself.
    signal audioRequested(real x)
    signal networkRequested(real x)
    signal notificationsRequested(real x)

    // Variants sets this, one instance per monitor. The name must be exactly
    // `modelData` - that is what Variants assigns into the delegate.
    required property var modelData

    // PanelWindow's own `screen` property decides which output the layer
    // surface is placed on.
    screen: modelData

    // PanelWindow is a layer-shell surface. Anchoring to three edges is what
    // makes it span the full width: left+right pins both sides, so the width
    // follows the monitor instead of being a fixed number.
    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: Theme.barHeight

    // Layer-shell surfaces can reserve space, so tiled windows are placed
    // below the bar instead of underneath it. Hyprland honours this via
    // `exclusiveZone`; leaving it at the default means the bar would overlap
    // windows. Setting it to the bar's own height reserves exactly that.
    exclusiveZone: implicitHeight

    color: "transparent"

    // --- plugins ---------------------------------------------------------
    //
    // One component per BarLayout id. A new plugin needs a component here,
    // a branch in activate(), and an entry in BarLayout.defaults.

    Component { id: audioPlugin;   AudioButton {} }
    Component { id: networkPlugin; NetworkButton {} }
    Component { id: themePlugin;   ThemeToggle {} }
    Component { id: caffeinePlugin; CaffeineButton {} }
    Component { id: couchPlugin;   CouchButton {} }
    Component { id: powerPlugin;   PowerButton {} }
    Component { id: notifyPlugin;  NotifyButton {} }

    // Where a dragged icon will land: a faint ring the size of a glyph.
    Component {
        id: placeholderPlugin
        Item {
            implicitWidth: 22
            implicitHeight: 22
            Rectangle {
                anchors.centerIn: parent
                width: 22
                height: 22
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: Theme.dim
                opacity: 0.7
            }
        }
    }

    function componentFor(id: string): var {
        switch (id) {
        case "audio":       return audioPlugin
        case "network":     return networkPlugin
        case "theme":       return themePlugin
        case "caffeine":    return caffeinePlugin
        case "couch":       return couchPlugin
        case "power":       return powerPlugin
        case "notify":      return notifyPlugin
        case "placeholder": return placeholderPlugin
        }
        return null
    }

    // A click on a plugin. `slot` is the Loader drawing it.
    function activate(id: string, slot): void {
        const x = slot.mapToItem(null, slot.width / 2, 0).x
        if (id === "audio")                    root.audioRequested(x)
        else if (id === "network")             root.networkRequested(x)
        else if (id === "notify")              root.notificationsRequested(x)
        else if (id === "theme" && slot.item)  slot.item.activate()
        else if (id === "caffeine")            Caffeine.toggle()
        // Both of these arm on the first click and fire on the second, so
        // the branch is the same one twice - the state lives in the button.
        else if (id === "couch" && slot.item)  slot.item.activate()
        else if (id === "power" && slot.item)  slot.item.activate()
    }

    // The same as clicking plugin `id` wherever it currently sits - for IPC
    // and keybinds, so a panel opened without the mouse still drops down
    // under its glyph.
    function activateId(id: string): void {
        for (const z of BarLayout.zones) {
            const slot = root.zoneItem(z).itemFor(id)
            if (slot) {
                root.activate(id, slot)
                return
            }
        }
    }

    // --- dragging --------------------------------------------------------

    // The plugin being dragged, or "".
    property string dragId: ""

    // Where it would land - { zone, index } - or null while it is too far
    // from the bar to land anywhere.
    property var dropTarget: null

    // Pointer x, for the icon that follows it.
    property real dragX: 0

    // What the zones draw: the saved layout, or during a drag the saved
    // layout with the dragged icon lifted out and a placeholder where it
    // would land.
    readonly property var viewLayout: {
        const base = BarLayout.current
        const out = {}
        for (const z of BarLayout.zones)
            out[z] = base[z].filter(i => i !== root.dragId && root.shows(i))
        if (root.dragId !== "" && root.dropTarget)
            out[root.dropTarget.zone].splice(root.dropTarget.index, 0, "placeholder")
        return out
    }

    // Whether this machine can offer plugin `id` at all. Only the couch
    // button has an answer other than yes - see Couch.qml for why it is asked
    // rather than assumed.
    //
    // FILTERED HERE, NOT IN BarLayout. The layout is what the plugins are
    // arranged as, and it is saved; dropping an id from it on a machine that
    // cannot draw it would forget where it had been put on the machine that
    // can - the two share one checkout, but not one bar-layout.json, so this
    // is only about not losing an arrangement on a reinstall. Hidden ids stay
    // in the saved order and simply are not drawn.
    //
    // targetFor() deliberately still counts against the FULL layout, so a
    // drop index means the same thing on both machines: itemFor() returns
    // null for a hidden id and the loop steps over it without advancing.
    function shows(id: string): bool {
        if (id === "couch") return Couch.available
        return true
    }

    function zoneItem(name: string): var {
        switch (name) {
        case "left":        return leftZone
        case "centerLeft":  return centerLeftZone
        case "centerRight": return centerRightZone
        case "right":       return rightZone
        }
        return null
    }

    // The plugin under (x, y), as { id, slot }, or null. The hit area is the
    // glyph's width and the bar's full height - a bar is a thin target.
    function slotAt(x: real, y: real): var {
        if (y < 0 || y > root.height) return null
        for (const z of BarLayout.zones) {
            const zone = root.zoneItem(z)
            for (const id of root.viewLayout[z]) {
                if (id === "placeholder") continue
                const slot = zone.itemFor(id)
                if (!slot) continue
                const p = slot.mapToItem(dragArea, 0, 0)
                if (x >= p.x && x <= p.x + slot.width) return { id: id, slot: slot }
            }
        }
        return null
    }

    // The nearest zone, and the position in it: after every icon whose centre
    // is left of the pointer.
    //
    // Measured against the icons as they are drawn - with the placeholder in
    // them - and still stable: the placeholder always opens on the pointer's
    // side of an icon, which moves that icon AWAY from the pointer, never
    // across it.
    function targetFor(px: real, py: real): var {
        if (py < -Theme.barHeight || py > root.height + Theme.barHeight) return null

        let best = null
        for (const z of BarLayout.zones) {
            const box = root.zoneItem(z)
            const p = box.mapToItem(dragArea, 0, 0)
            const d = px < p.x ? p.x - px
                    : px > p.x + box.width ? px - (p.x + box.width)
                    : 0
            if (best === null || d < best.d) best = { zone: z, d: d, box: box }
        }

        const others = BarLayout.current[best.zone].filter(i => i !== root.dragId)
        let index = 0
        for (let i = 0; i < others.length; i++) {
            const slot = best.box.itemFor(others[i])
            if (slot && slot.mapToItem(dragArea, slot.width / 2, 0).x < px) index = i + 1
        }
        return { zone: best.zone, index: index }
    }

    // --- surface ---------------------------------------------------------

    Rectangle {
        anchors.fill: parent
        color: Theme.bg

        // Square on every corner. The bar is the TOP EDGE of the frame that
        // Frame.qml draws down the sides and across the bottom, so rounding
        // where they meet would leave a visible notch at the junction instead
        // of one continuous border. The rounding lives on the frame's outer
        // bottom corners instead.

        // Three regions: left, centre, right. Laid out independently so a
        // wide centre widget cannot push the side ones around, which is what
        // happens if the whole bar is one RowLayout.
        // Each region sits on its own rounded container rather than directly
        // on the bar. That is the single change that makes this read as a
        // designed bar instead of icons floating on a strip: it groups what
        // belongs together, and gives the eye edges to rest against.
        Item {
            id: leftRegion
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: Theme.barPadding }
            width: leftPill.width

            Rectangle {
                id: leftPill
                anchors.verticalCenter: parent.verticalCenter
                height: Theme.pillHeight
                // Tracks its contents, so the OSD sliding out and a plugin
                // dropped in both widen the pill with them. Each of the three
                // parts animates its own width, and the pill adds them up.
                width: leftRow.implicitWidth + leftZone.width + osd.implicitWidth
                       + Theme.pillPadding * 2
                radius: height / 2

                // Lit from above - see the depth note in Theme.qml.
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.surfaceTop }
                    GradientStop { position: 1.0; color: Theme.surface }
                }
                border.width: 1
                border.color: Theme.rim

                // NO Behavior ON THIS WIDTH, deliberately.
                //
                // The parts are ALREADY animating - the OSD its implicitWidth,
                // the zone its width. An animation here would be a second one
                // chasing a target that moves every frame, restarting a fresh
                // curve each time, so the pill lags its own contents and then
                // snaps to catch up at the end.

                Row {
                    id: leftRow
                    anchors { left: parent.left
                              leftMargin: Theme.pillPadding
                              verticalCenter: parent.verticalCenter }
                    spacing: Theme.itemSpacing

                    Logo {
                        anchors.verticalCenter: parent.verticalCenter
                        // Nothing wired to the click yet - this is where a
                        // launcher or a menu would go once one exists.
                        onActivated: console.log("logo clicked")
                    }

                    Workspaces {
                        // This bar's monitor, so the row can show the
                        // workspaces pinned to it rather than the same five
                        // numbers on every screen.
                        screenName: root.modelData.name
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Plugins placed after the workspaces. Outside the Row, with
                // its own leading gap, for the same reason as the OSD.
                BarZone {
                    id: leftZone
                    name: "left"
                    ids: root.viewLayout.left
                    componentFor: root.componentFor
                    gapSide: "lead"
                    anchors { left: leftRow.right; verticalCenter: parent.verticalCenter }
                }

                // Hidden until a volume/brightness key is pressed. Sits right
                // after the workspaces and their plugins, and collapses to
                // nothing when idle. It carries its own leading gap.
                Osd {
                    id: osd
                    anchors { left: leftZone.right
                              verticalCenter: parent.verticalCenter }
                }
            }
        }

        Item {
            id: centerRegion
            anchors.centerIn: parent
            width: centerPill.width
            height: parent.height

            Rectangle {
                id: centerPill
                anchors.centerIn: parent
                height: Theme.pillHeight
                width: centerRow.implicitWidth + Theme.pillPadding * 2
                radius: height / 2

                // Lit from above - see the depth note in Theme.qml.
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.surfaceTop }
                    GradientStop { position: 1.0; color: Theme.surface }
                }
                border.width: 1
                border.color: Theme.rim

                // Spacing 0: the zones either side of the clock carry their
                // own gap to it.
                Row {
                    id: centerRow
                    anchors.centerIn: parent
                    spacing: 0

                    BarZone {
                        id: centerLeftZone
                        name: "centerLeft"
                        ids: root.viewLayout.centerLeft
                        componentFor: root.componentFor
                        gapSide: "trail"
                        gap: 10
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Clock {
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    BarZone {
                        id: centerRightZone
                        name: "centerRight"
                        ids: root.viewLayout.centerRight
                        componentFor: root.componentFor
                        gapSide: "lead"
                        gap: 10
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        Item {
            id: rightRegion
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: Theme.barPadding }
            width: rightPill.width

            Rectangle {
                id: rightPill
                anchors.verticalCenter: parent.verticalCenter
                // With every plugin moved elsewhere there is nothing to put a
                // pill around.
                visible: rightZone.width > 0.5
                height: Theme.pillHeight
                width: rightZone.width + Theme.pillPadding * 2
                radius: height / 2

                // Lit from above - see the depth note in Theme.qml.
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.surfaceTop }
                    GradientStop { position: 1.0; color: Theme.surface }
                }
                border.width: 1
                border.color: Theme.rim

                BarZone {
                    id: rightZone
                    name: "right"
                    ids: root.viewLayout.right
                    componentFor: root.componentFor
                    anchors.centerIn: parent
                }
            }
        }

        // --- clicks and drags on plugins ------------------------------------
        //
        // ONE handler over the whole bar, not one per icon. A drag lifts the
        // icon out of its zone, which destroys the item drawing it - a handler
        // inside that item would be destroyed mid-drag along with it. Up here
        // it outlives every change to the zones.
        //
        // Presses that miss every plugin are REFUSED, so they fall through to
        // the workspaces and the logo underneath as if this were not here.
        // Hover is not taken either, so the glyphs' own hover effects and
        // cursors still work.
        MouseArea {
            id: dragArea
            anchors.fill: parent
            z: 10
            pressAndHoldInterval: 300

            property string pressedId: ""
            property var pressedSlot: null
            property bool dragging: false

            function sameTarget(a, b): bool {
                if (a === null || b === null) return a === b
                return a.zone === b.zone && a.index === b.index
            }

            onPressed: mouse => {
                dragging = false
                const hit = root.slotAt(mouse.x, mouse.y)
                if (!hit) {
                    mouse.accepted = false
                    return
                }
                pressedId = hit.id
                pressedSlot = hit.slot
            }

            onPressAndHold: mouse => {
                if (pressedId === "") return
                dragging = true
                root.dragX = mouse.x
                root.dragId = pressedId
                root.dropTarget = root.targetFor(mouse.x, mouse.y)
            }

            onPositionChanged: mouse => {
                if (!dragging) return
                root.dragX = mouse.x
                const t = root.targetFor(mouse.x, mouse.y)
                if (!sameTarget(t, root.dropTarget)) root.dropTarget = t
            }

            onReleased: mouse => {
                if (!dragging) return
                if (root.dropTarget)
                    BarLayout.move(root.dragId, root.dropTarget.zone, root.dropTarget.index)
                root.dropTarget = null
                root.dragId = ""
                // `dragging` stays true until the next press, so the click
                // that follows this release is not taken as a tap.
            }

            onClicked: mouse => {
                if (!dragging && pressedSlot) root.activate(pressedId, pressedSlot)
            }

            onCanceled: {
                dragging = false
                root.dropTarget = null
                root.dragId = ""
            }
        }

        // The icon under the pointer while dragging. Dimmed while it is too
        // far from the bar to land.
        Loader {
            z: 11
            active: root.dragId !== ""
            sourceComponent: root.dragId !== "" ? root.componentFor(root.dragId) : null
            x: root.dragX - width / 2
            anchors.verticalCenter: parent.verticalCenter
            scale: 1.15
            opacity: root.dropTarget ? 0.95 : 0.4
            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        }
    }
}
