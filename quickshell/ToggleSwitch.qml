// =========================================================================
// ToggleSwitch - the small on/off switch the network rows use
// =========================================================================
//
// Pulled out of NetworkList.qml when the Ethernet rows needed the same
// thing. It was forty lines of geometry and two animations; a second copy
// would have drifted from the first the moment either was touched.
//
//     ToggleSwitch {
//         checked: Networking.wifiEnabled
//         interactive: Networking.wifiHardwareEnabled
//         onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
//     }
//
// IT REPORTS, IT DOES NOT DECIDE. `checked` is a binding to the real state,
// and the click only emits `toggled()` - it never flips `checked` itself.
// So a switch whose action fails, or takes a moment, stays where the truth
// is rather than snapping to where the finger was. NetworkManager takes a
// visible fraction of a second to drop a wired link, and a switch that
// moved first and waited would look like it had worked before it had.
//
// `interactive`, not `enabled`: Item.enabled already means something here -
// it stops the MouseArea receiving anything at all - and the two would have
// had to be kept in step for no gain.

import QtQuick

Rectangle {
    id: root

    property bool checked: false

    // False greys it and ignores clicks: a hardware rfkill switch, a device
    // NetworkManager does not manage. Something software cannot override.
    property bool interactive: true

    signal toggled()

    width: 34
    height: 18
    radius: height / 2

    opacity: root.interactive ? 1 : 0.4
    color: root.checked ? Theme.accent
                        : Qt.rgba(Theme.dim.r, Theme.dim.g, Theme.dim.b, 0.4)
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Rectangle {
        y: 2
        x: root.checked ? parent.width - width - 2 : 2
        width: 14
        height: 14
        radius: width / 2
        color: root.checked ? Theme.accentFg : Theme.fg
        Behavior on x {
            NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        anchors.fill: parent
        // A switch this small is a hard target; the click area is a little
        // bigger than what is drawn.
        anchors.margins: -6
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.interactive) root.toggled()
    }
}
