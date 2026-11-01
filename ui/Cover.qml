import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import ".."
import "../Icons.js" as Icons

Rectangle {
  id: cover
  property var root
  property real size: root.u(14)
  property real rounding: root.u(4)
  width: size
  height: size
  radius: rounding
  color: root.faint
  clip: true
  StrokeIcon {
    anchors.centerIn: parent
    visible: coverImg.status !== Image.Ready
    size: parent.size * 0.7
    strokeWidth: 1
    color: root.hi
    path: "M9 17.5V6l10-2v11.5M9 17.5a2.5 2.5 0 1 1-5 0a2.5 2.5 0 1 1 5 0zM19 15.5a2.5 2.5 0 1 1-5 0a2.5 2.5 0 1 1 5 0z"
  }
  Image {
    id: coverImg
    anchors.fill: parent
    source: root.artUrl
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    sourceSize.width: 128
    sourceSize.height: 128
    opacity: status === Image.Ready ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: root.fadeMs } }
  }
}
