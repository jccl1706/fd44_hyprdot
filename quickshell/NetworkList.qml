// The Wi-Fi switch and the list of networks, on its own so that two surfaces
// can show it.
//
// IT LIVED IN NetworkPanel, and moving it out is what let the settings window
// hold the same thing. The alternative was a second, smaller network list in
// settings, which would have meant two implementations of scanning, sorting,
// password entry and failure reporting - drifting apart the first time either
// was touched. One component, two hosts.
//
// `active` drives scanning: a list nobody is looking at should not keep the
// radio busy. `needsFocus` is for the host that cares - the dropdown takes
// the keyboard back when a row collapses; the settings panel has nothing to
// take it back from.

pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick

Item {
    id: list

    property bool active: false
    signal needsFocus()

    // The dropdown needs its own Wi-Fi switch, because it is the whole of the
    // network UI there. The settings page already has one as a proper row
    // with its help text, and two switches for one radio, inches apart, is
    // worse than either.
    property bool showSwitch: true

    implicitHeight: wifi.implicitHeight

    // Back to a clean slate: no row opened, no stale failure from last time.
    function reset(): void {
        list.expanded = ""
        list.failures = ({})
        list.refreshNetworks(true)
    }

    // Name of the network opened in place, or "".
    property string expanded: ""

    // Network name -> why its last connection attempt failed.
    property var failures: ({})

    // The wireless device itself. It came with this block from NetworkPanel,
    // where it was derived from a `devices` list that stayed behind - so it is
    // asked for directly here instead.
    readonly property var wifiDevice:
        Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null

    readonly property bool wantScan: list.active && Networking.wifiEnabled && list.wifiDevice !== null
    onWantScanChanged: {
        if (list.wifiDevice) list.wifiDevice.scannerEnabled = list.wantScan
    }

    // --- networks --------------------------------------------------------

    // Connected first, then saved, then by signal in quarter steps - coarse on
    // purpose, so two networks a few percent apart do not swap on every scan.
    // Hidden networks (no name) cannot be joined from a list, so they are
    // left out.
    readonly property var liveNetworks: {
        if (!list.wifiDevice) return []
        return list.wifiDevice.networks.values
            .filter(n => n.name && n.name.length > 0)
            .sort((a, b) => (b.connected - a.connected)
                         || (b.known - a.known)
                         || (Math.round(b.signalStrength * 4) - Math.round(a.signalStrength * 4))
                         || a.name.localeCompare(b.name))
    }

    // What the list actually shows - see THE LIST HOLDS STILL above. Replaced
    // only when the order or the set of networks really changed, so a
    // strength update alone does not rebuild every row either.
    property var shownNetworks: []
    property string shownKey: ""

    function refreshNetworks(force: bool): void {
        if (list.expanded !== "" && !force) return
        const live = list.liveNetworks
        const key = live.map(n => n.name + (n.connected ? "*" : "")).join("\n")
        const sameObjects = list.shownNetworks.length === live.length
                            && list.shownNetworks.every(n => live.includes(n))
        if (!force && key === list.shownKey && sameObjects) return
        list.shownKey = key
        list.shownNetworks = live
    }

    onLiveNetworksChanged: list.refreshNetworks(false)
    onExpandedChanged: {
        if (list.expanded === "") list.refreshNetworks(false)
    }

    // Failures are caught here rather than in the rows: a row can be rebuilt
    // while its connection attempt is still running, and would miss the
    // signal. This follows the device's own network list, which is stable.
    Instantiator {
        model: list.wifiDevice ? list.wifiDevice.networks : []
        delegate: Connections {
            required property var modelData
            target: modelData
            ignoreUnknownSignals: true
            function onConnectionFailed(reason) {
                list.noteFailure(modelData.name, reason, list.takesPassword(modelData.security))
            }
        }
    }

    function noteFailure(name: string, reason: int, withPassword: bool): void {
        const f = Object.assign({}, list.failures)
        f[name] = (reason === ConnectionFailReason.NoSecrets && withPassword)
                  ? "Wrong password"
                  : ConnectionFailReason.toString(reason)
        list.failures = f
        // Open it again, so the fix - usually retyping the password - is
        // right there.
        list.expanded = name
    }

    function clearFailure(name: string): void {
        if (!(name in list.failures)) return
        const f = Object.assign({}, list.failures)
        delete f[name]
        list.failures = f
    }

    // --- security --------------------------------------------------------

    function isOpen(sec: int): bool {
        return sec === WifiSecurityType.Open || sec === WifiSecurityType.Owe
    }

    // The only kinds connectWithPsk accepts - see its documentation.
    function takesPassword(sec: int): bool {
        return sec === WifiSecurityType.WpaPsk
            || sec === WifiSecurityType.Wpa2Psk
            || sec === WifiSecurityType.Sae
    }

    function strengthGlyph(s: real, locked: bool): string {
        const i = s < 0.25 ? 0 : s < 0.5 ? 1 : s < 0.75 ? 2 : 3
        return locked
            ? ["\u{F0921}", "\u{F0924}", "\u{F0927}", "\u{F092A}"][i]   // nf-md-wifi_strength_N_lock
            : ["\u{F091F}", "\u{F0922}", "\u{F0925}", "\u{F0928}"][i]   // nf-md-wifi_strength_N
    }


        Column {
            id: wifi
            visible: list.wifiDevice !== null
            width: parent.width

            Item {
                visible: list.showSwitch
                height: visible ? 28 : 0
                width: parent.width

                Text {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    leftPadding: 4
                    text: "Wi-Fi"
                    font.family: Theme.font
                    font.weight: Theme.weightSemi
                    font.pixelSize: Theme.fontSizeSmall
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.8
                    color: Theme.dim
                }

                // On/off switch. Unusable while a hardware switch (or rfkill)
                // holds the radio off - software cannot override that.
                Rectangle {
                    id: wifiSwitch

                    readonly property bool on: Networking.wifiEnabled
                    readonly property bool usable: Networking.wifiHardwareEnabled

                    anchors { right: parent.right; rightMargin: 4
                              verticalCenter: parent.verticalCenter }
                    width: 34
                    height: 18
                    radius: height / 2
                    opacity: usable ? 1 : 0.4
                    color: on ? Theme.accent
                              : Qt.rgba(Theme.dim.r, Theme.dim.g, Theme.dim.b, 0.4)
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Rectangle {
                        y: 2
                        x: wifiSwitch.on ? parent.width - width - 2 : 2
                        width: 14
                        height: 14
                        radius: width / 2
                        color: wifiSwitch.on ? Theme.accentFg : Theme.fg
                        Behavior on x {
                            NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        // A switch this small is a hard target; the click
                        // area is a little bigger than what is drawn.
                        anchors.margins: -6
                        cursorShape: wifiSwitch.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (wifiSwitch.usable) Networking.wifiEnabled = !Networking.wifiEnabled
                        }
                    }
                }
            }

            Text {
                visible: !Networking.wifiEnabled || list.shownNetworks.length === 0
                leftPadding: 4
                height: 36
                verticalAlignment: Text.AlignVCenter
                text: !Networking.wifiHardwareEnabled ? "Wi-Fi is blocked by a hardware switch"
                    : !Networking.wifiEnabled         ? "Wi-Fi is off"
                                                      : "Searching for networks…"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                color: Theme.dim
            }

            ListView {
                id: networkList

                visible: Networking.wifiEnabled && count > 0
                width: parent.width

                // Grows with its rows up to about seven, then scrolls. Tracks
                // contentHeight live, so a row opening grows the card with it.
                height: visible ? Math.min(contentHeight, 320) : 0

                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                model: list.shownNetworks

                delegate: Item {
                    id: row

                    required property var modelData

                    readonly property var net: modelData
                    readonly property string name: net?.name ?? ""
                    readonly property bool expanded: name !== "" && list.expanded === name
                    readonly property bool connected: net?.connected ?? false
                    readonly property bool known: net?.known ?? false
                    readonly property int security: net?.security ?? WifiSecurityType.Unknown
                    readonly property int state: net?.state ?? ConnectionState.Unknown
                    // Own keys only: a network named "toString" would otherwise pick
                    // up the object's built-in function as its failure text.
                    readonly property string failure:
                        Object.prototype.hasOwnProperty.call(list.failures, name) ? list.failures[name] : ""

                    readonly property bool open: list.isOpen(security)

                    // A saved network whose password was just rejected needs
                    // a new one, not another try with the old.
                    readonly property bool needsPassword:
                        list.takesPassword(security) && !connected
                        && (!known || failure === "Wrong password")

                    // Anything else that is not open needs more than this
                    // panel can ask for.
                    readonly property bool needsSetup:
                        !open && !known && !list.takesPassword(security)

                    readonly property bool canConnect: !needsPassword || pwInput.text.length >= 8

                    readonly property var actionList: {
                        const a = []
                        if (known) a.push({ id: "forget", label: "Forget" })
                        if (connected) a.push({ id: "disconnect", label: "Disconnect" })
                        else if (!needsSetup) a.push({ id: "connect", label: "Connect", primary: true })
                        return a
                    }

                    width: networkList.width
                    height: head.height + actions.height
                    clip: true

                    function act(id: string): void {
                        if (!row.net) return
                        if (id === "connect") {
                            if (!row.canConnect) return
                            list.clearFailure(row.name)
                            if (row.needsPassword) {
                                // A rejected password left a saved profile
                                // behind; connecting with a new one replaces
                                // its secret.
                                row.net.connectWithPsk(pwInput.text)
                            } else {
                                row.net.connect()
                            }
                        } else if (id === "disconnect") {
                            row.net.disconnect()
                        } else if (id === "forget") {
                            list.clearFailure(row.name)
                            row.net.forget()
                        }
                        list.expanded = ""
                        list.needsFocus()
                    }

                    onExpandedChanged: {
                        if (row.expanded && row.needsPassword) {
                            Qt.callLater(() => pwInput.forceActiveFocus())
                        } else if (!row.expanded) {
                            pwInput.text = ""
                            pwInput.reveal = false
                        }
                    }

                    // --- the row itself ---------------------------------------

                    Rectangle {
                        id: head
                        width: parent.width
                        height: 44
                        radius: 8

                        color: row.connected
                               ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                               : row.expanded || headArea.containsMouse
                                 ? Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g,
                                           Theme.surfaceHigh.b, 0.6)
                                 : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        Rectangle {
                            anchors { left: parent.left; leftMargin: 2
                                      verticalCenter: parent.verticalCenter }
                            width: 3
                            height: row.connected ? 18 : 0
                            radius: 1.5
                            color: Theme.accent
                            Behavior on height {
                                NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
                            }
                        }

                        Text {
                            id: netGlyph
                            anchors { left: parent.left; leftMargin: 12
                                      verticalCenter: parent.verticalCenter }
                            width: 20
                            horizontalAlignment: Text.AlignHCenter
                            text: list.strengthGlyph(row.net?.signalStrength ?? 0, !row.open)
                            font.family: Theme.glyphFont
                            font.pixelSize: 16
                            color: row.connected ? Theme.accent : Theme.dim
                        }

                        Column {
                            anchors {
                                left: netGlyph.right; leftMargin: 10
                                right: parent.right;  rightMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 1

                            Text {
                                width: parent.width
                                // Plain text: an SSID is chosen by whoever broadcasts it, and
                                // Text's default AutoText would render one that looks like HTML.
                                textFormat: Text.PlainText
                                text: row.name
                                font.family: Theme.font
                                font.weight: row.connected ? Theme.weightSemi : Theme.weightMedium
                                font.pixelSize: Theme.fontSize
                                color: Theme.fg
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: row.failure                                  ? row.failure
                                    : row.connected                                ? "Connected"
                                    : row.state === ConnectionState.Connecting     ? "Connecting…"
                                    : row.state === ConnectionState.Disconnecting  ? "Disconnecting…"
                                    : row.known                                    ? "Saved"
                                    : row.open                                     ? "Open"
                                    : WifiSecurityType.toString(row.security)
                                font.family: Theme.font
                                font.weight: Theme.weightNormal
                                font.pixelSize: Theme.fontSizeSmall
                                font.letterSpacing: Theme.trackingLoose
                                color: row.failure ? Theme.danger : Theme.dim
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: headArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: list.expanded = row.expanded ? "" : row.name
                        }
                    }

                    // --- opened in place --------------------------------------

                    Item {
                        id: actions
                        anchors.top: head.bottom
                        width: parent.width
                        height: row.expanded ? actionsCol.implicitHeight + 10 : 0
                        opacity: row.expanded ? 1 : 0
                        Behavior on height {
                            NumberAnimation { duration: Theme.animReveal; easing.type: Easing.InOutCubic }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: Theme.animReveal; easing.type: Easing.InOutCubic }
                        }

                        Column {
                            id: actionsCol
                            y: 6
                            x: 8
                            width: parent.width - 16
                            spacing: 8

                            Rectangle {
                                visible: row.needsPassword
                                width: parent.width
                                height: 36
                                radius: 8
                                color: Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g,
                                               Theme.surfaceHigh.b, 0.6)
                                border.width: 1
                                border.color: pwInput.activeFocus ? Theme.accent : "transparent"

                                TextInput {
                                    id: pwInput

                                    property bool reveal: false

                                    anchors {
                                        left: parent.left;   leftMargin: 12
                                        right: eye.left;     rightMargin: 8
                                        verticalCenter: parent.verticalCenter
                                    }
                                    echoMode: reveal ? TextInput.Normal : TextInput.Password
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize
                                    color: Theme.fg
                                    selectionColor: Theme.accent
                                    selectedTextColor: Theme.accentFg
                                    clip: true

                                    Keys.onReturnPressed: row.act("connect")
                                    Keys.onEnterPressed:  row.act("connect")

                                    Text {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        visible: pwInput.text === ""
                                        text: "Password"
                                        font: pwInput.font
                                        color: Theme.dim
                                    }
                                }

                                Text {
                                    id: eye
                                    anchors { right: parent.right; rightMargin: 10
                                              verticalCenter: parent.verticalCenter }
                                    text: pwInput.reveal ? "\u{F0209}" : "\u{F0208}"   // nf-md-eye_off / eye
                                    font.family: Theme.glyphFont
                                    font.pixelSize: 16
                                    color: eyeArea.containsMouse ? Theme.fg : Theme.dim

                                    MouseArea {
                                        id: eyeArea
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: pwInput.reveal = !pwInput.reveal
                                    }
                                }
                            }

                            Text {
                                visible: row.needsSetup
                                width: parent.width
                                wrapMode: Text.WordWrap
                                text: WifiSecurityType.toString(row.security)
                                      + " needs more than a password - set it up with nmcli."
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.dim
                            }

                            Item {
                                visible: row.actionList.length > 0
                                width: parent.width
                                height: 30

                                Row {
                                    anchors.right: parent.right
                                    spacing: 6

                                    Repeater {
                                        model: row.actionList

                                        delegate: Rectangle {
                                            id: btn

                                            required property var modelData

                                            readonly property bool primary: modelData.primary === true
                                            readonly property bool usable: modelData.id !== "connect" || row.canConnect

                                            width: btnLabel.implicitWidth + 24
                                            height: 30
                                            radius: height / 2
                                            opacity: usable ? 1 : 0.45
                                            color: btn.primary
                                                   ? Theme.accent
                                                   : btnArea.containsMouse
                                                     ? Theme.surfaceHigh
                                                     : Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g,
                                                               Theme.surfaceHigh.b, 0.6)
                                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

                                            Text {
                                                id: btnLabel
                                                anchors.centerIn: parent
                                                text: btn.modelData.label
                                                font.family: Theme.font
                                                font.weight: Theme.weightSemi
                                                font.pixelSize: Theme.fontSize
                                                // Forget throws away a saved
                                                // password, so it is the red one.
                                                color: btn.primary                       ? Theme.accentFg
                                                     : btn.modelData.id === "forget"     ? Theme.danger
                                                                                         : Theme.fg
                                            }

                                            MouseArea {
                                                id: btnArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: btn.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: {
                                                    if (btn.usable) row.act(btn.modelData.id)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
}
