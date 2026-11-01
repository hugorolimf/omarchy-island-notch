import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import ".."
import "../Icons.js" as Icons

// One page per view. Never hidden with `visible` (positioners inside
// would report zero size); a faded page just stops taking input. Content
// fades in once the morph is under way and out at once.
Item {
  id: page
  property var root
  property string key: ""
  readonly property bool active: root.view === key
  property int inPause: active ? 150 : 0
  readonly property int fadeOut: root.view === "idle" ? 150 : 300
  anchors.horizontalCenter: parent.horizontalCenter
  anchors.top: parent.top
  opacity: active ? 1 : 0
  enabled: active
  Behavior on opacity {
    SequentialAnimation {
      PauseAnimation { duration: inPause }
      NumberAnimation { duration: active ? 300 : fadeOut; easing.type: Easing.Bezier; easing.bezierCurve: root.ease }
    }
  }
  // content drops in from just above as the notch opens up under it
  property real drop: active ? 0 : -root.u(6)
  Behavior on drop {
    SequentialAnimation {
      PauseAnimation { duration: inPause }
      NumberAnimation { duration: 380; easing.type: Easing.Bezier; easing.bezierCurve: root.ease }
    }
  }
  transform: Translate { y: drop }
}
