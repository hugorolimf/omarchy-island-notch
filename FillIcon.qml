import QtQuick
import QtQuick.Shapes
import "Icons.js" as Icons

// Solid icon (media controls, like the phone's): an SVG path on a 24-unit
// grid, filled, with a thin stroke of the same colour to round its corners.
// Rewritten at the real size, so it stays sharp.
Item {
  id: root

  property string path: ""
  property real size: 20
  property color color: "#e6e6e6"
  readonly property real f: size / 24

  implicitWidth: size
  implicitHeight: size

  Shape {
    width: root.size
    height: root.size
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: root.color
      strokeWidth: Math.max(1, root.size / 14)
      fillColor: root.color
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: Icons.scalePath(root.path, root.f) }
    }
  }
}
