import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import ".."
import "../Icons.js" as Icons

Text {
  id: label
  property var root
  color: root.strong
  font.family: root.monoFont
  font.pointSize: root.fontPt(10.5)
  font.weight: Font.Medium
  textFormat: Text.PlainText
}
