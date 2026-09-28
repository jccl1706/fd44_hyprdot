// =========================================================================
// UpdatesButton - the box that appears when packages are waiting
// =========================================================================
//
// Not there at all until there is something to install, which is the whole
// design: an icon that is always present and merely changes colour has to be
// read every time you look at the bar, and this one only ever means one
// thing. Its arrival IS the notification.
//
// A CLOSED BOX AND A NUMBER, picked by rendering the candidates rather than
// from an icon table - the same way NotifyButton's bell was chosen. A box on
// its own says "packages" but not "waiting"; the count beside it is what
// makes it a number of things to do. On NixOS that number is days behind
// rather than packages, which is why the tooltip spells out what it counted.
//
// ACCENT, NOT DANGER. Updates being available is normal and not a fault -
// the machine is fine, there is simply something to do when convenient. The
// red is kept for things that are actually wrong.
//
// ONE CLICK OPENS A TERMINAL and that is all it does: nothing is installed by
// the bar itself. The transaction is worth seeing, it wants a password, and a
// bar icon that silently starts a system update on a stray click would be the
// wrong thing in every direction. Bar.qml routes the click here.

import QtQuick

Item {
    id: root

    // ITS OWN FLAG, not `visible`, because everything else here keys off it
    // and reading back `visible` would give effective visibility - false
    // whenever an ancestor is hidden, which is how this plugin locked itself
    // out of existence once already. See BarZone.qml.
    readonly property bool shown: Updates.pending

    // Nothing drawn and no space taken; BarZone skips a zero-width plugin in
    // its Row, so the neighbours close up instead of leaving a hole.
    visible: root.shown
    implicitWidth: root.shown ? content.implicitWidth : 0
    implicitHeight: 22

    readonly property string boxGlyph: "\u{F03D7}"   // nf-md-package_variant_closed

    // NO TOOLTIP, deliberately: nothing in this bar has one - "THE HELP TEXT
    // IS ALWAYS VISIBLE, not a tooltip", as Settings.qml puts it - and a
    // hover-only label is the one place this desktop does not put words. What
    // the count is made of is a question with an answer already:
    //
    //     qs ipc call updates status
    //     -> dnf 7 (chromium, vim-enhanced, quickshell and 4 more)
    //
    Rectangle {
        anchors.centerIn: content
        width: content.implicitWidth + 8
        height: 22
        radius: height / 2
        color: Theme.surfaceHigh
        opacity: hover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 4

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.boxGlyph
            font.family: Theme.glyphFont
            // 15: the box is a solid outline shape that fills its em box more
            // like the coffee cup than like the thin-line moon, and at 17 it
            // stood taller than the bell beside it.
            font.pixelSize: 15
            color: hover.hovered ? Theme.fg : Theme.accent
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            // A cap, because the width of this plugin moves the clock beside
            // it: a fresh install with 400 updates would shove the centre of
            // the bar sideways to say something "99+" says just as well.
            text: Updates.count > 99 ? "99+" : String(Updates.count)
            font.family: Theme.font
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.weightMedium
            font.features: { "tnum": 1 }
            color: hover.hovered ? Theme.fg : Theme.accent
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
    }

    // It arrives on its own, without anyone touching the bar, so it fades in
    // rather than appearing between two frames. The width is animated by the
    // zone around it; this is only the ink.
    opacity: root.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
}
