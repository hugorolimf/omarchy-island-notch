import QtQuick
import QtQuick.Shapes
import "Icons.js" as Icons

// Line icon in the anatomy style: an SVG path on a 24-unit grid, stroked
// thin with round caps. The path is rewritten at the icon's real size (no
// transform), so it is drawn natively sharp. `strokeWidth` is in pixels.
Item {
  id: root

  property string path: ""
  property string faintPath: ""
  property real size: 14
  property real strokeWidth: 1.25
  property color color: "#d4d4d4"
  readonly property real f: size / 24

  implicitWidth: size
  implicitHeight: size

  Shape {
    width: root.size
    height: root.size
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: root.color
      strokeWidth: root.strokeWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: Icons.scalePath(root.path, root.f) }
    }

    ShapePath {
      strokeColor: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.4)
      strokeWidth: root.strokeWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: Icons.scalePath(root.faintPath, root.f) }
    }
  }
}
