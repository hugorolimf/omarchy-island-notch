import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import ".."
import "../Icons.js" as Icons

// One of your messages in the conversation card: on the right in a soft
// bubble, the time and how it was asked above it when given.
Item {
  id: askBubble
  property var root
  property string text: ""
  property string meta: ""
  implicitHeight: (askBubbleMeta.visible ? askBubbleMeta.implicitHeight + root.u(4) : 0) + askBubbleBox.height
  Sub { root: askBubble.root
    id: askBubbleMeta
    visible: askBubble.meta !== ""
    anchors.right: parent.right
    anchors.rightMargin: root.u(6)
    font.pointSize: root.fontPt(8.5)
    text: askBubble.meta
  }
  Rectangle {
    id: askBubbleBox
    anchors.right: parent.right
    y: askBubbleMeta.visible ? askBubbleMeta.implicitHeight + root.u(4) : 0
    width: Math.min(askBubbleText.implicitWidth + root.u(24), askBubble.width * 0.82)
    height: askBubbleText.implicitHeight + root.u(13)
    radius: root.u(14)
    color: Qt.rgba(1, 1, 1, 0.09)
    Text {
      id: askBubbleText
      anchors.fill: parent
      anchors.leftMargin: root.u(12)
      anchors.rightMargin: root.u(12)
      anchors.topMargin: root.u(6)
      text: askBubble.text
      color: root.strong
      font.family: root.sansFont
      font.pointSize: root.fontPt(12)
      wrapMode: Text.Wrap
      lineHeight: 1.1
      textFormat: Text.PlainText
    }
  }
}
