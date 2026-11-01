import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import ".."
import "../Icons.js" as Icons

// Claude's own mark: breathes while it works, still while it waits for
// you, and gives way to a check when the turn is done.
Item {
  id: claudeMark
  property var root
  implicitWidth: root.u(14)
  implicitHeight: root.u(14)
  ClaudeLogo {
    id: claudeLogoMark
    anchors.centerIn: parent
    visible: root.claudeState !== "done"
    size: root.u(14)
    readonly property bool working: root.claudeState === "working" && (root.view === "claude" || root.view === "claudeX")
    SequentialAnimation on opacity {
      running: claudeLogoMark.working
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
    }
  }
  StrokeIcon {
    anchors.centerIn: parent
    visible: root.claudeState === "done"
    size: root.u(14)
    strokeWidth: 1.5
    color: root.green
    path: "M5.5 12.5l4 4 9-9.5"
  }
}
