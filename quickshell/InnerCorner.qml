// =========================================================================
// InnerCorner - a concave corner piece
// =========================================================================
//
// Rounds the INSIDE of the frame, where the bar's bottom edge meets a side
// piece. That is a concave curve, and Rectangle's radius cannot draw one:
// radius removes material convexly (it rounds the shape's own corner), while
// this needs material ADDED into a square corner with a quarter-circle bite
// taken out of it.
//
// So it is drawn as a path: a square of Theme.bg with a quarter arc cut from
// the corner that faces the content area.
//
//   corner: "topleft"        the well's top-left inner corner
//     ##########
//     ##########      ## = painted (frame colour)
//     #######\--      the arc curves away toward the content
//     #####\
//     ####|
//
// Placed by Frame.qml, which widens its surface beyond its exclusiveZone so
// there is room to draw these without reserving extra space.

import QtQuick
import QtQuick.Shapes

Item {
    id: root

    // Which inner corner of the content well this fills.
    // "topleft" | "topright" | "bottomleft" | "bottomright"
    required property string corner

    property real radius: Theme.cornerRadius
    property color color: Theme.bg

    implicitWidth: radius
    implicitHeight: radius

    readonly property bool isTop:  corner === "topleft" || corner === "topright"
    readonly property bool isLeft: corner === "topleft" || corner === "bottomleft"

    Shape {
        anchors.fill: parent
        // Smooths the arc; without it the curve is visibly faceted at this
        // size on a HiDPI panel.
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.color
            strokeWidth: 0
            strokeColor: "transparent"

            // Start at the OUTER corner (the one against the frame), trace the
            // two straight edges, then arc back across the opening.
            startX: root.isLeft ? 0 : root.width
            startY: root.isTop  ? 0 : root.height

            PathLine {
                x: root.isLeft ? root.width : 0
                y: root.isTop  ? 0 : root.height
            }

            PathArc {
                x: root.isLeft ? 0 : root.width
                y: root.isTop  ? root.height : 0
                radiusX: root.radius
                radiusY: root.radius
                // Sweep direction flips with the corner, otherwise the arc
                // bulges outward and fills the wrong half.
                direction: (root.isTop === root.isLeft) ? PathArc.Counterclockwise
                                                        : PathArc.Clockwise
            }

            PathLine {
                x: root.isLeft ? 0 : root.width
                y: root.isTop  ? 0 : root.height
            }
        }
    }
}
