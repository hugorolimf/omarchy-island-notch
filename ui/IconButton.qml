import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import ".."
import "../Icons.js" as Icons

Item {
  id: iconButton
  property var root
  property string path: ""
  property real iconSize: root.u(14)
  property bool enabledAction: true
  signal activated()
  width: root.u(26)
  height: root.u(26)
  opacity: enabledAction ? 1 : 0.35
  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: Qt.rgba(1, 1, 1, area.containsMouse && iconButton.enabledAction ? (area.pressed ? 0.14 : 0.07) : 0)
    Behavior on color { ColorAnimation { duration: root.fadeMs } }
  }
  StrokeIcon {
    anchors.centerIn: parent
    size: iconButton.iconSize
    strokeWidth: 1.25
    color: root.hi
    path: iconButton.path
    opacity: area.pressed ? 0.7 : 1
  }
  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: iconButton.enabledAction ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (iconButton.enabledAction) iconButton.activated()
  }
}
