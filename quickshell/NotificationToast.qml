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
import QtQuick
import QtQuick.Effects

Rectangle {
    id: toast

    required property string key
    required property string summary
    required property string body
    required property string appName
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
                    + (toast.showsShot ? shot.height + 10 : 0)

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

    // THE PREVIEW IS DRAWN BY MultiEffect AND THE Image ITSELF IS HIDDEN:
    // the effect reads it as a texture and paints the rounded version, so
    // showing both would draw the picture twice, square copy underneath.
    //
    // Qt5Compat's OpacityMask is not installed on this machine; QtQuick.Effects
    // is the Qt6 module that replaced it. `clip` is no substitute - it is
    // always a rectangle, so a parent with a radius still shows square corners
    // through it.
    Image {
        id: shot
        visible: false
        anchors {
            left: parent.left; right: parent.right
            bottom: parent.bottom
            leftMargin: 12; rightMargin: 12; bottomMargin: 12
        }
        height: toast.showsShot ? 120 : 0
        // THE PATH IS DUG OUT OF QUICKSHELL'S URL, which is an ICON provider
        // URL - image://icon//home/jc/Pictures/... - and that provider renders
        // themed icons, not photographs: handed the URL unchanged it loaded
        // without error and painted flat grey, which looks like a layout bug
        // and is not one.
        //
        // Prefixing it instead gave file://image//icon//home/... and the log
        // said so outright:  Cannot open: file://image//icon//home/jc/Pi...
        //
        // So take the path back out and load the file directly.
        source: toast.showsShot ? toast.shotPath : ""
        // CROPPED, NOT LETTERBOXED. A 2256x1504 shot fitted whole into a strip
        // this wide would be 40px tall between two bars; cropping keeps it
        // legible as a picture of something.
        fillMode: Image.PreserveAspectCrop
        // Decoded at roughly the size it is drawn. The file is 2MB, the strip
        // is 120px tall, and a stack of toasts would otherwise hold several
        // full-resolution screenshots in memory at once.
        sourceSize.height: 240
        asynchronous: true
        smooth: true
        cache: false
        // layer.enabled WITH visible:false. An invisible item is not rendered
        // and so has no texture for MultiEffect to read - the card grew by the
        // preview's height and painted nothing. The layer gives it one without
        // putting the square original on screen.
    }

    Item {
        id: shotMask
        visible: false
        layer.enabled: true
        anchors.fill: shot
        Rectangle { anchors.fill: parent; radius: 8 }
    }

    MultiEffect {
        anchors.fill: shot
        visible: toast.showsShot
        source: shot
        maskEnabled: true
        maskSource: shotMask
    }

    // THE ONE EXCEPTION TO THE DOT, AND IT IS NOT A RETREAT FROM IT. The rule
    // above - a dot whatever the sender sent - is about senders decorating
    // their own messages: a Chromium favicon beside a grey device glyph beside
    // nothing, artwork competing with the words for the first glance.
    //
    // A screenshot is the opposite case. The image IS the message: "Screenshot
    // saved" cannot tell you whether slurp caught the rectangle you meant,
    // and a thumbnail answers that before you have finished reading. So this
    // is drawn wide and below the text rather than squeezed into the icon
    // column, where it would be 28px of unreadable grey and would put the
    // artwork back where the comment above says it does not belong.
    //
    // Only for this shell's own screenshots - appName is set by
    // bin/screenshot.sh - so no sender can opt itself into a picture here.
    readonly property string shotPath: {
        const s = String(toast.image)
        const marker = "image://icon/"
        return s.startsWith(marker) ? "file://" + s.slice(marker.length) : s
    }

    readonly property bool showsShot: toast.appName === "Screenshot"
                                      && toast.image !== ""

    Row {
        id: layout
        // WITH A PREVIEW THE TEXT GOES TO THE TOP, not the middle: a centred
        // Row in a card made taller by the image below it would float the
        // words into the gap and leave the heading nowhere near the top edge.
        anchors {
            left: parent.left; right: parent.right
            leftMargin: 12; rightMargin: 12
            top: toast.showsShot ? parent.top : undefined
            topMargin: toast.showsShot ? 12 : 0
            verticalCenter: toast.showsShot ? undefined : parent.verticalCenter
        }
        spacing: 10

        // A DOT, WHATEVER THE SENDER SENT. The toast used to draw the
        // notification's own image or its themed icon and fall back to this,
        // which meant a stack of them was a row of unrelated pictures at
        // wildly different weights - a Chromium favicon beside a flat grey
        // device glyph beside nothing at all - and the eye spent its first
        // moment on the artwork rather than on the words.
        //
        // The dot is what the history rows in NotificationPanel.qml have
        // always used, so the two now agree.
        //
        // IT STILL CARRIES ONE PIECE OF INFORMATION: red for a critical
        // notification, the accent otherwise. That is the one thing worth
        // knowing before reading, and it is the reason this is a coloured
        // dot rather than no column at all.
        Item {
            width: 28
            height: 28
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.centerIn: parent
                width: 8; height: 8; radius: 4
                color: toast.critical ? Theme.danger : Theme.accent
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
