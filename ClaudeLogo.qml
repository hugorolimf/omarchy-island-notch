import QtQuick
import QtQuick.Shapes
import "Icons.js" as Icons

// Claude's mark as Anthropic draws it: the filled spark only, no outline,
// so the rays stay thin and taper to their tips (FillIcon adds a stroke that
// rounds corners, which thickens this shape). On a 24-unit grid, redrawn at
// the real size.
Item {
  id: root

  property real size: 16
  property color color: "#D97757"
  readonly property real f: size / 24

  implicitWidth: size
  implicitHeight: size

  Shape {
    width: root.size
    height: root.size
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeWidth: -1
      strokeColor: "transparent"
      fillColor: root.color
      fillRule: ShapePath.WindingFill
      PathSvg { path: Icons.scalePath(Icons.claude, root.f) }
    }
  }
}
