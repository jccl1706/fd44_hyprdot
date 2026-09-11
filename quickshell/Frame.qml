// =========================================================================
// Frame - one edge of the border that encloses the screen
// =========================================================================
//
// Three instances (left, right, bottom) plus the Bar at the top form a
// continuous border around the desktop. Each reserves its own thickness via
// exclusiveZone, so windows tile inside the frame rather than under it.
//
// JOINING THE BAR:
// The Bar is the frame's top edge and is drawn with square corners, and the
// side pieces run from directly beneath it. Nothing is rounded where the
// pieces meet, so there is no notch at the junction - the four surfaces read
// as one border.
//
// The rounding is on the OUTER bottom corners instead, where the frame meets
// the bottom of the screen. Those belong to the SIDE pieces: each runs the
// full height below the bar and so reaches the bottom of the screen itself.
// The bottom piece cannot own them - layer-shell shrinks it to fit between
// the sides' exclusive zones, so it never reaches the corners at all.
//
// CLICK-THROUGH:
// The frame is decoration, so its input region is emptied with `mask`.
// Without that, an 8px strip down every edge of the screen silently swallows
// clicks - maddening to diagnose, because everything LOOKS right and only the
// outermost pixels misbehave.

import Quickshell
import QtQuick

PanelWindow {
    id: root

    // Variants sets this - one frame per monitor, same as the Bar.
    required property var modelData
    screen: modelData

    // "left" | "right" | "bottom"
    required property string edge

    readonly property bool isLeft:   edge === "left"
    readonly property bool isRight:  edge === "right"
    readonly property bool isBottom: edge === "bottom"

    color: "transparent"

    // The side pieces do NOT anchor to the top: the Bar occupies that, and its
    // exclusiveZone pushes these down so the frame starts directly below it.
    // The bottom piece anchors left AND right so it spans the full width and
    // can own both outer corners.
    anchors {
        left:   isLeft  || isBottom
        right:  isRight || isBottom
        bottom: true
        top:    isLeft  || isRight
    }

    // The SIDE pieces are wider than the space they reserve. The extra width
    // overhangs into the content area so there is room to draw the concave
    // inner corner where the bar meets this piece - an 8px-wide surface has
    // nowhere to put a 12px corner. exclusiveZone stays at the real thickness,
    // so the overhang reserves nothing and windows still tile at x=8; the
    // surface is click-through and transparent apart from the corner itself.
    implicitWidth:  isBottom ? Theme.frameThickness
                             : Theme.frameThickness + Theme.cornerRadius
    implicitHeight: Theme.frameThickness

    exclusiveZone: Theme.frameThickness

    // Empty input region - pointer events pass straight through.
    mask: Region {}

    // The frame strip itself - only as wide as the reserved thickness, pinned
    // to the screen edge. The rest of the surface stays transparent.
    Rectangle {
        width:  root.isBottom ? parent.width : Theme.frameThickness
        height: root.isBottom ? Theme.frameThickness : parent.height
        anchors {
            left:   root.isLeft  || root.isBottom ? parent.left  : undefined
            right:  root.isRight ? parent.right : undefined
            bottom: parent.bottom
            top:    root.isBottom ? undefined : parent.top
        }
        color: Theme.bg

        // Each side piece rounds the screen corner it reaches. The desktop
        // shows through the curve.
        bottomLeftRadius:  root.isLeft  ? Theme.frameCornerRadius : 0
        bottomRightRadius: root.isRight ? Theme.frameCornerRadius : 0
    }

    // Seam filler - overlaps the bottom strip by one pixel.
    //
    // The side and bottom pieces are separate layer-shell surfaces that meet
    // at logical x=8. Under fractional scaling that boundary lands mid-pixel
    // (8 * 1.5667 = 12.53 on this panel), so Qt antialiases each surface's own
    // edge and NEITHER fully owns the shared physical pixel. The result is a
    // dim 1px vertical line down the corner - subtle, but visible against a
    // light frame, and it only spares the right side here by rounding luck.
    //
    // Widening by a pixel makes the side piece cover the boundary outright, so
    // nothing depends on the two surfaces blending to opaque. It is confined
    // to the bottom strip's own band, where the frame is solid anyway, so the
    // extra pixel never widens the visible border.
    Rectangle {
        visible: !root.isBottom
        width:  Theme.frameThickness + 1
        height: Theme.frameThickness
        anchors {
            bottom: parent.bottom
            left:   root.isLeft  ? parent.left  : undefined
            right:  root.isRight ? parent.right : undefined
        }
        color: Theme.bg

        // Must repeat the strip's rounding, or this squares the corner back off.
        bottomLeftRadius:  root.isLeft  ? Theme.frameCornerRadius : 0
        bottomRightRadius: root.isRight ? Theme.frameCornerRadius : 0
    }

    // Concave corners of the content well, so it reads as a rounded opening
    // rather than a square hole. Both live on the SIDE pieces: each runs the
    // full height between the bar and the bottom edge, so it touches both of
    // the corners on its side. The bottom piece is shrunk to fit between them
    // and never reaches a corner at all.
    //
    // Offset by the frame thickness on every edge: the corner belongs just
    // INSIDE the strip, at the lip of the well, not painted on top of it.

    // Top - where the bar's bottom edge meets this side piece.
    InnerCorner {
        visible: !root.isBottom
        corner: root.isLeft ? "topleft" : "topright"
        anchors {
            top:         parent.top
            left:        root.isLeft  ? parent.left  : undefined
            leftMargin:  root.isLeft  ? Theme.frameThickness : 0
            right:       root.isRight ? parent.right : undefined
            rightMargin: root.isRight ? Theme.frameThickness : 0
        }
    }

    // Bottom - where the bottom strip meets this side piece. bottomMargin
    // clears the bottom strip's own thickness, so the curve sits at the lip
    // of the well rather than overlapping the strip.
    InnerCorner {
        visible: !root.isBottom
        corner: root.isLeft ? "bottomleft" : "bottomright"
        anchors {
            bottom:       parent.bottom
            bottomMargin: Theme.frameThickness
            left:         root.isLeft  ? parent.left  : undefined
            leftMargin:   root.isLeft  ? Theme.frameThickness : 0
            right:        root.isRight ? parent.right : undefined
            rightMargin:  root.isRight ? Theme.frameThickness : 0
        }
    }
}
