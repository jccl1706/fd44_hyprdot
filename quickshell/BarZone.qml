// =========================================================================
// BarZone - one of the bar's spots for movable plugins
// =========================================================================
//
// Draws the plugins BarLayout.qml puts in this zone, in order, plus the
// "placeholder" gap Bar.qml inserts while an icon is being dragged over it.
//
// A LISTMODEL, EDITED IN PLACE, not the id array handed straight to the
// Repeater. A plain array is a new model on every change, so every icon in
// the zone would be destroyed and rebuilt each time the drag gap moved one
// slot - and nothing could animate, because nothing survives to move.
// sync() turns each new array into moves, inserts and removes, so the Row's
// own transitions slide the icons aside for the gap.
//
// THE GAP TO THE FIXED MODULES BELONGS TO THE ZONE, like the OSD's leading
// gap in Osd.qml: a positioner drops the spacing around an empty child
// instantly, so a Row-provided gap would snap shut after the zone's width had
// finished animating to zero.

import QtQuick

Item {
    id: zone

    // BarLayout zone name.
    required property string name

    // The ids to draw, placeholder included.
    required property var ids

    // id -> Component. A function, supplied by Bar.qml.
    required property var componentFor

    // Which side faces the fixed modules and carries the gap: "lead" (the
    // zone's left edge), "trail" (its right edge), or "" for none.
    property string gapSide: ""
    property int gap: Theme.itemSpacing

    readonly property int count: keys.count

    // row.implicitWidth, NOT count, decides whether there is a zone at all:
    // a plugin can be present and draw nothing - the tray with no items, the
    // update box with nothing to install - and a zone holding only those
    // would otherwise still reserve its gap to the fixed modules.
    width: count > 0 && row.implicitWidth > 0
           ? row.implicitWidth + (gapSide !== "" ? gap : 0) : 0
    height: 22
    clip: true

    Behavior on width {
        NumberAnimation { duration: Theme.animReveal; easing.type: Easing.InOutCubic }
    }

    ListModel { id: keys }

    onIdsChanged: zone.sync()
    Component.onCompleted: zone.sync()

    function sync(): void {
        const target = zone.ids || []
        for (let i = 0; i < target.length; i++) {
            if (i < keys.count && keys.get(i).key === target[i]) continue
            let found = -1
            for (let j = i + 1; j < keys.count; j++) {
                if (keys.get(j).key === target[i]) { found = j; break }
            }
            if (found >= 0) keys.move(found, i, 1)
            else keys.insert(i, { key: target[i] })
        }
        while (keys.count > target.length) keys.remove(keys.count - 1)
    }

    // The slot (a Loader) currently drawing `id`, or null.
    function itemFor(id: string): var {
        for (let i = 0; i < repeater.count; i++) {
            const slot = repeater.itemAt(i)
            if (slot && slot.key === id) return slot
        }
        return null
    }

    Row {
        id: row
        x: zone.gapSide === "lead" ? zone.gap : 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        move: Transition {
            NumberAnimation { properties: "x"; duration: Theme.animNormal; easing.type: Easing.OutCubic }
        }
        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animNormal }
        }

        Repeater {
            id: repeater
            model: keys

            delegate: Loader {
                required property string key
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: zone.componentFor(key)

                // A Row still spaces around a child of zero width, so a
                // plugin that draws nothing would leave a 10px hole between
                // its neighbours. An INVISIBLE child is skipped by the
                // positioner entirely, so a plugin that wants no space is
                // hidden here.
                //
                // BY ITS WIDTH, NOT BY ITS `visible`. Reading item.visible
                // looks like the obvious test and deadlocks: QQuickItem's
                // visible getter returns EFFECTIVE visibility, so an item
                // inside a hidden Loader reports false whatever it asked for,
                // the Loader stays hidden on that answer, and the plugin can
                // never come back. The update box was invisible with seven
                // packages waiting for exactly this reason.
                visible: item ? item.implicitWidth > 0 : true
            }
        }
    }
}
