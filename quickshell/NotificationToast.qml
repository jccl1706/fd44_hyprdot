// =========================================================================
// NotificationToast - one notification card
// =========================================================================
//
// Drawn like the bar's panels rather than like a system dialog: the same
// surface colour, corner radius and hairline outline, so a notification
// reads as part of this desktop instead of as something that arrived from
// outside it.
//
// THE COUNTDOWN PAUSES ON HOVER, which is why it is a 100ms ticker counting
// `remaining` down rather than a single Timer of `duration`. A Timer
// restarted after a hover begins its interval again, so passing the pointer
// over a toast would silently grant it a fresh full lifetime.

import Quickshell
import Quickshell.Widgets
import QtQuick

Rectangle {
    id: toast

    required property string key
    required property string summary
    required property string body
    required property string appName
    required property string appIcon

    // WHAT THE ICON ACTUALLY IS, once, rather than a chain of conditionals
    // evaluated in two places that then disagree with each other.
    //
    // A notification's image-path hint may be a file or a themed NAME - the
    // spec allows both - and quickshell hands either to us already wrapped as
    // image://icon/…, its own provider. The provider resolves a name through
    // Qt, which in this session can only see the hicolor theme (see
    // bin/icon-bridge.sh), so a name it cannot find renders as the
    // missing-icon chequerboard rather than as nothing. Asking
    // hasThemeIcon() first is what turns that into an honest "no icon", and
    // the dot below then has something to take over from.
    //
    // A path arrives wrapped too, as image://icon//usr/share/…, which the
    // provider happens to handle - but only by accident of the leading
    // slash. Unwrapping it into a plain file: URL says what is meant.
    readonly property string iconSource: {
        if (toast.image !== "") return toast.resolveIcon(toast.image)
        if (toast.appIcon !== "") return Quickshell.iconPath(toast.appIcon, true)
        return ""
    }

    function resolveIcon(url: string): string {
        const prefix = "image://icon/"
        if (!url.startsWith(prefix)) return url
        const name = decodeURIComponent(url.substring(prefix.length).split("?")[0])
        if (name.startsWith("/")) return "file://" + name
        return Quickshell.hasThemeIcon(name) ? url : ""
    }
    required property string image
    required property int    urgency
    required property int    duration          // 0 means it stays until touched

    signal activated()
    signal dismissed()

    property int remaining: duration

    // Critical keeps a coloured edge: it is the one urgency the user has to
    // be able to pick out of a stack without reading it.
    readonly property bool critical: urgency === 2

    implicitWidth: 360
    implicitHeight: Math.max(64, layout.implicitHeight + 24)

    radius: Theme.cornerRadius
    color: Qt.alpha(Theme.surface, Theme.panelAlpha)
    border.width: 1
    border.color: toast.critical ? Theme.danger : Theme.outline

    Timer {
        interval: 100
        repeat: true
        running: toast.duration > 0 && !hover.hovered && toast.remaining > 0
        onTriggered: {
            toast.remaining -= 100
            if (toast.remaining <= 0) toast.dismissed()
        }
    }

    HoverHandler { id: hover }

    Row {
        id: layout
        anchors {
            left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
            leftMargin: 12; rightMargin: 12
        }
        spacing: 10

        // The sender's image if it sent one, its themed icon otherwise, and
        // a dot when it sent neither - so the text always starts at the same
        // x and a stack of cards has one left edge.
        Item {
            width: 28
            height: 28
            anchors.verticalCenter: parent.verticalCenter

            IconImage {
                anchors.fill: parent
                source: toast.iconSource
                visible: source !== ""
            }

            Rectangle {
                anchors.centerIn: parent
                width: 8; height: 8; radius: 4
                color: toast.critical ? Theme.danger : Theme.accent
                // Keyed on the RESOLVED source, not on whether a notification
                // named an icon. Those differ whenever the name does not
                // resolve, and when they did the toast drew neither - no dot,
                // because an icon had been named, and no icon, because it
                // could not be found. A chequerboard sat there instead.
                visible: toast.iconSource === ""
            }
        }

        Column {
            width: layout.width - 28 - layout.spacing - closeButton.width - layout.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: toast.summary
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSizeTitle
                font.weight: Theme.weightSemi
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                text: toast.body
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                // Markup, because bodyMarkupSupported is advertised to
                // senders - promising it and then printing the tags would be
                // worse than not promising it.
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 3
                visible: text !== ""
            }
        }

        // Revealed on hover only: a close affordance on every card at rest
        // turns a quiet stack into a row of buttons.
        Item {
            id: closeButton
            width: 20; height: 20
            anchors.verticalCenter: parent.verticalCenter
            opacity: hover.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: closeHover.hovered ? Theme.surfaceHigh : "transparent"
            }

            Text {
                anchors.centerIn: parent
                text: "\u{F0156}"                     // mdi-close
                font.family: Theme.glyphFont
                font.pixelSize: 13
                color: closeHover.hovered ? Theme.fg : Theme.dim
            }

            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: toast.dismissed() }
        }
    }

    // The card itself is the click target for the default action. Declared
    // after the close button so the button wins where they overlap.
    TapHandler {
        onTapped: toast.activated()
    }
}
