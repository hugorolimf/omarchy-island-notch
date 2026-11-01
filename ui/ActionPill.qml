import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import ".."
import "../Icons.js" as Icons

// Pill button of a pinned notification (same look as COPIAR).
Rectangle {
  id: pill
  property var root
  property string label: ""
  property bool accent: false
  property bool selected: false  // keyboard selection
  signal activated()
  width: pillText.implicitWidth + root.u(18)
  height: root.u(22)
  radius: height / 2
  color: pillArea.containsMouse || selected ? Qt.rgba(1, 1, 1, 0.09) : (accent ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
  border.width: selected ? 1.2 : 0.6
  border.color: Qt.rgba(root.hi.r, root.hi.g, root.hi.b, selected ? 0.9 : accent ? 0.5 : 0.25)
  Behavior on color { ColorAnimation { duration: root.fadeMs } }
  Text {
    id: pillText
    anchors.centerIn: parent
    text: pill.label
    color: pill.accent ? root.strong : root.hi
    font.family: root.monoFont
    font.pointSize: root.fontPt(9.5)
    font.weight: Font.Medium
    font.letterSpacing: 0.5
    textFormat: Text.PlainText
  }
  MouseArea {
    id: pillArea
    anchors.fill: parent
    anchors.margins: -root.u(3)
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: pill.activated()
  }
}
