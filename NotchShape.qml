import QtQuick
import QtQuick.Shapes

// The island's outline: flat top flush with the screen edge, rounded bottom
// corners, and concave "ears" at the top corners that blend it into the bar.
// The body is `bodyWidth` wide; the ears hang `ear` px outside it on both
// sides, so the item is bodyWidth + 2·ear wide.
Item {
  id: root

  property real bodyWidth: 0
  property real bodyHeight: 26
  property real radius: 10
  property real ear: 7
  property color color: "#000000"
  property color rimColor: Qt.rgba(1, 1, 1, 0.08)
  property real rimWidth: 0.6

  // Keep the curves valid while the body is tiny (growing from nothing).
  readonly property real e: Math.max(0, Math.min(ear, bodyWidth / 4, bodyHeight / 3))
  readonly property real r: Math.max(0, Math.min(radius, bodyWidth / 2, bodyHeight - e))
  readonly property real w: Math.max(0, bodyWidth)
  readonly property real h: Math.max(0, bodyHeight)

  width: w + 2 * e
  height: h
  visible: w > 0.5

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: root.color
      strokeColor: "transparent"
      strokeWidth: 0
      startX: 0; startY: 0
      PathLine { x: root.w + 2 * root.e; y: 0 }
      PathArc { x: root.w + root.e; y: root.e; radiusX: root.e; radiusY: root.e; direction: PathArc.Counterclockwise }
      PathLine { x: root.w + root.e; y: root.h - root.r }
      PathArc { x: root.w + root.e - root.r; y: root.h; radiusX: root.r; radiusY: root.r }
      PathLine { x: root.e + root.r; y: root.h }
      PathArc { x: root.e; y: root.h - root.r; radiusX: root.r; radiusY: root.r }
      PathLine { x: root.e; y: root.e }
      PathArc { x: 0; y: 0; radiusX: root.e; radiusY: root.e; direction: PathArc.Counterclockwise }
    }

    // Rim on the sides and bottom only: the top melts into the bar.
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.rimColor
      strokeWidth: root.rimWidth
      capStyle: ShapePath.FlatCap
      startX: root.w + 2 * root.e; startY: 0
      PathArc { x: root.w + root.e; y: root.e; radiusX: root.e; radiusY: root.e; direction: PathArc.Counterclockwise }
      PathLine { x: root.w + root.e; y: root.h - root.r }
      PathArc { x: root.w + root.e - root.r; y: root.h; radiusX: root.r; radiusY: root.r }
      PathLine { x: root.e + root.r; y: root.h }
      PathArc { x: root.e; y: root.h - root.r; radiusX: root.r; radiusY: root.r }
      PathLine { x: root.e; y: root.e }
      PathArc { x: 0; y: 0; radiusX: root.e; radiusY: root.e; direction: PathArc.Counterclockwise }
    }
  }
}
