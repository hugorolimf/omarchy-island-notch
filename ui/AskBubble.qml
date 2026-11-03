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
// bubble, the time and how it was asked above it when given. Queued (not
// sent yet, it waits for the answer under way) it is only an outline, and a
// click takes it back to the box.
Item {
  id: askBubble
  property var root
  property string text: ""
  property string meta: ""
  property bool queued: false
  signal clicked()
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
    color: askBubble.queued ? "transparent" : Qt.rgba(1, 1, 1, 0.09)
    border.width: askBubble.queued ? 0.6 : 0
    border.color: Qt.rgba(root.hi.r, root.hi.g, root.hi.b, askBubbleArea.containsMouse ? 0.55 : 0.25)
    Behavior on border.color { ColorAnimation { duration: root.fadeMs } }
    Text {
      id: askBubbleText
      anchors.fill: parent
      anchors.leftMargin: root.u(12)
      anchors.rightMargin: root.u(12)
      anchors.topMargin: root.u(6)
      text: askBubble.text
      color: askBubble.queued && !askBubbleArea.containsMouse ? Qt.rgba(root.strong.r, root.strong.g, root.strong.b, 0.55) : root.strong
      font.family: root.sansFont
      font.pointSize: root.fontPt(12)
      wrapMode: Text.Wrap
      lineHeight: 1.1
      textFormat: Text.PlainText
    }
    MouseArea {
      id: askBubbleArea
      anchors.fill: parent
      enabled: askBubble.queued
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: askBubble.clicked()
    }
  }
}
