// =========================================================================
// Tray - StatusNotifierItem icons, for applications that expect a tray
// =========================================================================
//
// One plugin holding N icons, which is what makes it different from every
// other thing in the bar. AudioButton and the rest are a fixed 22x22 and the
// zone lays them out; this one's width follows however many applications have
// registered, and is zero when none have. BarZone animates its own width, so
// an application appearing or leaving slides the neighbours rather than
// jumping them.
//
// WHAT PUBLISHES HERE. StatusNotifierItem over DBus - the freedesktop
// successor to the old XEmbed tray. Steam, Discord, Nextcloud, KeePassXC,
// OBS and anything Electron use it. Nothing appears until such a program is
// running, so an empty bar is the normal state, not a fault.
//
// IT NEEDS A SESSION BUS. Without DBUS_SESSION_BUS_ADDRESS the service has
// nothing to watch and the tray stays empty forever. On Fedora systemd's user
// bus provides it; on FreeBSD the session has to be started with
// `dbus-run-session Hyprland` - see hypr/autostart.lua.
import Quickshell
import Quickshell.Services.SystemTray
import QtQuick

Item {
    id: root

    // The bar's PanelWindow, handed down from Bar.qml. Needed because
    // SystemTrayItem.display() anchors the application's own menu to a window
    // and a position inside it, and Quickshell 0.3.1 has no attached property
    // to find the window from here.
    property var barWindow: null

    implicitWidth: row.implicitWidth
    implicitHeight: 22

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter

        // Tighter than the zone's own 10px. These are application icons rather
        // than bar controls, and they read as one group when close together.
        spacing: 6

        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animNormal }
        }
        move: Transition {
            NumberAnimation { properties: "x"; duration: Theme.animNormal; easing.type: Easing.OutCubic }
        }

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: entry
                required property var modelData

                implicitWidth: 22
                implicitHeight: 22

                // NeedsAttention is the one status worth showing differently -
                // it is what a chat client sets for an unread message. Passive
                // items are NOT hidden: a tray that silently drops icons is
                // worse than one with a quiet icon in it, and the application
                // put it there on purpose.
                readonly property bool attention:
                    entry.modelData.status === Status.NeedsAttention

                Rectangle {
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    radius: width / 2
                    color: Theme.surfaceHigh
                    opacity: hover.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                }

                // The icon is whatever the application published - a themed
                // name or a pixmap Quickshell has already resolved to a URL.
                // Nothing here can restyle it, so the bar's own colours do not
                // apply and must not be faked: a tray of recoloured icons is
                // unrecognisable.
                Image {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    source: entry.modelData.icon
                    sourceSize.width: 32      // ask for 2x so a fractional
                    sourceSize.height: 32     // scale has pixels to work with
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    opacity: entry.attention ? 1 : (hover.hovered ? 1 : 0.85)
                    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                }

                // A dot rather than a colour change, for the same reason the
                // icon is left alone: the application owns how it looks.
                Rectangle {
                    visible: entry.attention
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 1
                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.danger
                }

                HoverHandler { id: hover }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                    onClicked: mouse => {
                        // onlyMenu means the application says a left click has
                        // no meaning and only the menu does - honouring it is
                        // the difference between a working icon and one that
                        // appears dead.
                        if (mouse.button === Qt.LeftButton) {
                            if (entry.modelData.onlyMenu) entry.openMenu()
                            else                          entry.modelData.activate()
                        } else if (mouse.button === Qt.RightButton) {
                            entry.openMenu()
                        } else if (mouse.button === Qt.MiddleButton) {
                            entry.modelData.secondaryActivate()
                        }
                    }

                    // Volume-style scrolling, which is what a mixer applet in
                    // the tray expects. Sends both axes as the item asked.
                    onWheel: wheel => {
                        if (wheel.angleDelta.y !== 0)
                            entry.modelData.scroll(wheel.angleDelta.y, false)
                        if (wheel.angleDelta.x !== 0)
                            entry.modelData.scroll(wheel.angleDelta.x, true)
                    }
                }

                // The menu is the APPLICATION'S, drawn by Quickshell from the
                // DBusMenu it exports - not something this file lays out. It is
                // anchored under the icon: mapToItem(null, ...) gives window
                // coordinates, which is the same trick Bar.qml uses to place
                // its drop-down panels.
                function openMenu(): void {
                    if (!entry.modelData.hasMenu || !root.barWindow) return
                    const p = entry.mapToItem(null, 0, entry.height)
                    entry.modelData.display(root.barWindow, p.x, p.y)
                }

                // NO HOVER TOOLTIP, and that is the repository's stance
                // rather than an omission - SettingsRow.qml puts it plainly:
                // "THE HELP TEXT IS ALWAYS VISIBLE, not a tooltip". Nothing
                // here imports QtQuick.Controls either, and pulling it in for
                // one label would be the tail wagging the dog.
                //
                // The identification is the icon, and right-clicking opens the
                // application's own menu, which names itself at the top.
                // tooltipTitle and tooltipDescription are there on the item if
                // this is ever reconsidered.
            }
        }
    }
}
