import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import ".."
import "../Icons.js" as Icons

// Equalizer bars in the album's colour, from eqLevels (mirrored so the
// middle bars move most, like the phone's).
Row {
  id: eq
  property var root
  property real span: root.u(14)
  // two device pixels wide, three apart: fine and sharp at any scale
  property real barW: root.px(2)
  spacing: root.px(3)
  height: span
  Repeater {
    model: 5
    Rectangle {
      required property int index
      readonly property real level: root.eqLevels[[3, 1, 0, 2, 4][index]] || 0
      anchors.verticalCenter: parent.verticalCenter
      width: eq.barW
      // whole device pixels, even, so the centred bar keeps sharp ends
      height: Math.max(eq.barW, Math.round(level * eq.span * root.dpr / 2) * 2 / root.dpr)
      radius: width / 2
      color: root.artColor
      opacity: root.playing ? 1 : 0.55
      Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
      Behavior on color { ColorAnimation { duration: 600 } }
    }
  }
}
