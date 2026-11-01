import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import ".."
import "../Icons.js" as Icons

// Claude's state: a pulse while it works, amber while it waits for you, a
// check when the turn is done.
// The assistant's mark: Claude's, drawn as the bar draws it; breathes while it thinks.
Item {
  id: askMark
  property var root
  property bool busy: false
  implicitWidth: root.u(16)
  implicitHeight: root.u(16)
  ClaudeLogo {
    anchors.centerIn: parent
    size: parent.width
  }
  SequentialAnimation on opacity {
    running: askMark.busy
    loops: Animation.Infinite
    alwaysRunToEnd: true
    NumberAnimation { to: 0.35; duration: 650; easing.type: Easing.InOutSine }
    NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutSine }
  }
}
