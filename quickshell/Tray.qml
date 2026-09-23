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
import Quickshell.Io
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

    // Diagnostic handle, so the menu can be opened without a mouse:
    //
    //     qs ipc call tray open      -> first item's menu
    //     qs ipc call tray count     -> how many items are registered
    //
    // Kept because a tray is otherwise only testable by hand, and "nothing
    // happens when I click" is indistinguishable from "the icon is not there"
    // without it.
    // Diagnostic handle, because a tray is otherwise only testable by hand
    // and "nothing happens when I click" is indistinguishable from "the icon
    // is not there":
    //
    //     qs ipc --pid $(pgrep -n quickshell) call tray count
    //     qs ipc --pid $(pgrep -n quickshell) call tray describe
    //
    IpcHandler {
        target: "tray"

        function count(): string {
            return String(SystemTray.items.values.length)
        }

        // entries= is the number that decides what a left click does, so it
        // is the one worth printing: >0 shows the menu, 0 activates.
        function describe(): string {
            const out = []
            for (let i = 0; i < row.children.length; i++) {
                const d = row.children[i]
                if (!d || d.menuEntries === undefined) continue
                out.push((d.modelData.title || d.modelData.id)
                         + "  entries=" + d.menuEntries
                         + "  hasMenu=" + d.modelData.hasMenu
                         + "  -> " + (d.menuEntries > 0 ? "menu" : "activate"))
            }
            return out.length > 0 ? out.join("\n") : "no items"
        }
    }

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
                    id: icon
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

                // A LETTER WHEN THERE IS NO ICON, because an item is entitled
                // to publish neither an icon name nor a pixmap and a 22px hole
                // in the bar looks like a bug. Battle.net under Proton is the
                // case that found this: IconName is the empty string.
                Text {
                    anchors.centerIn: parent
                    visible: icon.status !== Image.Ready
                    text: (entry.modelData.title || entry.modelData.id || "?")
                              .trim().charAt(0).toUpperCase()
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Theme.weightSemi
                    color: hover.hovered ? Theme.fg : Theme.pluginIcon
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

                // hasMenu IS NOT TRUSTWORTHY, so the menu is read and counted
                // instead. Measured on this machine, the two tray items are
                // exact opposites:
                //
                //   Steam        16 entries, no Activate method at all
                //   Battle.net   Menu = "/NO_DBUSMENU", Activate works
                //
                // and Quickshell reports hasMenu=true for BOTH. Believing it
                // opened an empty panel over Battle.net; believing Activate
                // did nothing at all over Steam. The entry count is the only
                // thing that distinguishes them.
                QsMenuOpener {
                    id: opener
                    menu: entry.modelData.menu
                }

                readonly property int menuEntries:
                    opener.children ? opener.children.values.length : 0

                HoverHandler { id: hover }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                    // THE MENU WINS A LEFT CLICK WHENEVER THERE IS ONE, and
                    // that is not the obvious reading of the spec - it is what
                    // the applications actually do.
                    //
                    // Activate is OPTIONAL in StatusNotifierItem, and the
                    // libappindicator/ayatana family simply does not implement
                    // it: those items are menus with an icon on them. Measured
                    // on Steam, which is the tray item this was built against:
                    //
                    //     busctl --user call ... org.kde.StatusNotifierItem \
                    //            Activate ii 0 0
                    //     Call failed: No such method "Activate"
                    //
                    // Its introspection lists Scroll and SecondaryActivate and
                    // no Activate at all. Nor does it set ItemIsMenu, so
                    // onlyMenu is false and honouring that alone left the icon
                    // doing nothing whatsoever when clicked.
                    //
                    // The cost is that left and right do the same thing on an
                    // item that has both a menu and a working Activate -
                    // KeePassXC being the case in point. That is a small loss:
                    // such a menu almost always carries the same "show the
                    // window" entry that Activate would have triggered. The
                    // alternative is an icon that ignores clicks, which is
                    // worse and is what this replaced. There is no way to ask
                    // an item whether Activate exists without calling it, and
                    // a call that fails silently cannot be fallen back from.
                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) {
                            if (entry.menuEntries > 0) entry.openMenu()
                            else                       entry.activateOrRaise()
                        } else if (mouse.button === Qt.RightButton) {
                            // No menu to show means right-click has nothing to
                            // do, rather than opening an empty card.
                            if (entry.menuEntries > 0) entry.openMenu()
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

                // THE MENU IS A PANEL, not something drawn here. Quickshell
                // 0.3.1 offers two routes that look right and are not:
                // SystemTrayItem.display() returns without complaint and draws
                // nothing, and QsMenuAnchor.open() leaves `visible` false even
                // with a populated handle. Both were measured on this machine.
                // TrayMenu.qml reads the entries with QsMenuOpener - which does
                // work - and draws them as one of this shell's own panels.
                // ACTIVATE FIRST, THEN A FALLBACK, because an item may
                // advertise Activate and ignore it. Battle.net under Proton
                // does exactly that: the method is there, the call returns
                // success, and the window does not move - measured with the
                // window present and another program focused, which stayed
                // focused.
                //
                // bin/tray-click.sh handles what QML cannot: it calls
                // ContextMenu over DBus, which is what Battle.net answers and
                // what SystemTrayItem does not expose - activate,
                // secondaryActivate and scroll are all there is, and display()
                // does nothing for either item on this machine.
                //
                // It used to try focusing a window whose title matched first.
                // That is removed: Battle.net's MENU window carries the same
                // title as its main window, so one menu left on screen
                // satisfied the match forever and every later click focused
                // that instead of doing anything.
                Process {
                    id: clickFallback
                    stderr: StdioCollector { id: fbErr }
                    // Quiet when it works, loud when it does not: the script
                    // fails silently otherwise and a dead icon gives nothing
                    // to go on.
                    onExited: (code, status) => {
                        if (code !== 0)
                            console.warn("tray-click:", entry.modelData.title,
                                         "exit=" + code, fbErr.text.trim())
                    }
                }

                function activateOrRaise(): void {
                    entry.modelData.activate()

                    const t = entry.modelData.title || ""
                    if (t === "") return

                    // WINDOW coordinates, which is what the application
                    // expects and not what Hyprland uses. A Wine program
                    // believes it is on a screen starting at 0,0; this monitor
                    // starts at x = -2560 (monitors.lua, auto-left). The bar
                    // window spans the monitor, so a position within it is
                    // exactly Wine's idea of the screen. Measured: passing the
                    // Hyprland x put the menu in the opposite corner.
                    const p = entry.mapToItem(null, 0, entry.height)
                    const sx = Math.round(p.x)
                    const sy = Math.round(p.y)

                    clickFallback.command = ["sh", "-c",
                        "\"$(dirname \"$(readlink -f '" + Quickshell.shellDir
                        + "')\")/bin/tray-click.sh\" \"$1\" \"$2\" \"$3\"",
                        "sh", t, String(sx), String(sy)]
                    clickFallback.running = true
                }

                function openMenu(): void {
                    if (entry.menuEntries === 0 || !root.barWindow) return
                    const x = entry.mapToItem(null, entry.width / 2, 0).x
                    root.barWindow.trayMenuRequested(x, entry.modelData)
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
