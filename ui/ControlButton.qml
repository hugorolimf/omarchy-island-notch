import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import ".."
import "../Icons.js" as Icons

// Solid round-hit media button (play/pause, skip), like the phone's.
Item {
  id: control
  property var root
  property string path: ""
  property real iconSize: root.u(22)
  property bool enabledAction: true
  signal activated()
  width: iconSize + root.u(18)
  height: width
  opacity: enabledAction ? 1 : 0.3
  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: Qt.rgba(1, 1, 1, controlArea.containsMouse && control.enabledAction ? (controlArea.pressed ? 0.16 : 0.08) : 0)
    Behavior on color { ColorAnimation { duration: root.fadeMs } }
  }
  FillIcon {
    anchors.centerIn: parent
    size: control.iconSize
    color: root.strong
    path: control.path
    scale: controlArea.pressed ? 0.86 : 1
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
  }
  MouseArea {
    id: controlArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: control.enabledAction ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (control.enabledAction) control.activated()
  }
}
