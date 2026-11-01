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
  id: sub
  property var root
  color: root.muted
  font.family: root.monoFont
  font.pointSize: root.fontPt(10)
  textFormat: Text.PlainText
}
