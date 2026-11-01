import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import ".."
import "../Icons.js" as Icons

// Bars mirrored from the centre over the last mic levels. On the bigger
// screen there are more of them, not thicker ones.
Row {
  id: liveBars
  property var root
  property int count: root.big ? 13 : 9
  property real barWidth: 1.5
  property real span: root.u(12)
  readonly property int mid: Math.floor(count / 2)
  spacing: root.big ? 2 : 1.5
  height: 2 + span
  Repeater {
    model: liveBars.count
    Rectangle {
      required property int index
      // mirrored from the centre, 80 ms of history apart, so the bars differ
      readonly property real level: root.micHistory[Math.min(12, 2 * Math.abs(index - liveBars.mid))] || 0
      anchors.verticalCenter: parent.verticalCenter
      width: liveBars.barWidth
      height: 2 + level * liveBars.span
      radius: width / 2
      color: root.hi
      Behavior on height { NumberAnimation { duration: 70; easing.type: Easing.Bezier; easing.bezierCurve: root.ease } }
    }
  }
}
