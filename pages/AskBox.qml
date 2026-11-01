import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import ".."
import "../ui"
import "../Icons.js" as Icons

// The assistant card's text box; holding F10 turns it into the mic.
Rectangle {
  id: askBox
  property var root
  property var askCard
  property var askScroll
  property var askScrollAnim
  readonly property Item input: askInput
  readonly property bool hearing: askCard.st === "listening"
  width: parent.width
  height: Math.min(root.u(120), Math.max(root.u(34), askInput.contentHeight + root.u(14)))
  radius: Math.min(height / 2, root.u(17))
  color: Qt.rgba(1, 1, 1, 0.06)
  border.width: 0.6
  border.color: askInput.activeFocus || hearing ? Qt.rgba(root.hi.r, root.hi.g, root.hi.b, 0.45) : Qt.rgba(1, 1, 1, 0.1)
  Behavior on border.color { ColorAnimation { duration: root.fadeMs } }
  clip: true
  // holding F10: the box becomes the mic
  Row {
    anchors.centerIn: parent
    spacing: root.u(8)
    opacity: askBox.hearing ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: root.fadeMs } }
    LiveBars { root: askBox.root; anchors.verticalCenter: parent.verticalCenter; span: root.u(16) }
    Label { root: askBox.root; anchors.verticalCenter: parent.verticalCenter; text: root.tr("Ouvindo…") }
  }
  TextEdit {
    id: askInput
    anchors.left: parent.left
    anchors.right: askSendButton.left
    anchors.leftMargin: root.u(14)
    anchors.rightMargin: root.u(8)
    anchors.verticalCenter: parent.verticalCenter
    opacity: askBox.hearing ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: root.fadeMs } }
    color: root.strong
    selectionColor: Qt.rgba(root.blue.r, root.blue.g, root.blue.b, 0.35)
    font.family: root.sansFont
    font.pointSize: root.fontPt(12)
    wrapMode: TextEdit.Wrap
    textFormat: TextEdit.PlainText
    onTextChanged: if (text !== "") askCard.sel = ""
    Keys.onReturnPressed: function(event) {
      if (event.modifiers & Qt.ShiftModifier) event.accepted = false
      else if (text === "" && askCard.sel !== "") askCard.act(askCard.sel)
      else askCard.send()
    }
    Keys.onEnterPressed: askCard.send()
    Keys.onEscapePressed: root.closeCard()
    Keys.onTabPressed: root.closeCard()
    Keys.onBacktabPressed: root.closeCard()
    Keys.onPressed: function(event) {
      var line = cursorRectangle
      var page = askScroll.height * 0.8
      var step = root.u(64)
      var at = askScrollAnim.running ? askScrollAnim.to : askScroll.contentY
      if (event.key === Qt.Key_PageUp) askCard.scrollTo(at - page)
      else if (event.key === Qt.Key_PageDown) askCard.scrollTo(at + page)
      // ↑↓ move the cursor inside a long message, then scroll
      else if (event.key === Qt.Key_Up && line.y < line.height / 2) askCard.scrollTo(at - step)
      else if (event.key === Qt.Key_Down && line.y + line.height * 1.5 > contentHeight) askCard.scrollTo(at + step)
      else if (text === "" && event.key === Qt.Key_Right) askCard.walk(1)
      else if (text === "" && event.key === Qt.Key_Left) askCard.walk(-1)
      else return
      event.accepted = true
    }
    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      visible: parent.text === ""
      text: askCard.thread.length > 0 ? root.tr("Responda ao assistente…") : root.tr("Pergunte ao assistente…")
      color: root.muted
      font: parent.font
    }
  }
  // send: the same round arrow as the reply box, once there's text
  // and the assistant isn't busy with the last one
  Rectangle {
    id: askSendButton
    anchors.right: parent.right
    anchors.rightMargin: root.u(6)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: root.u(6)
    width: root.u(22)
    height: width
    radius: width / 2
    readonly property bool ready: askInput.text.trim() !== "" && !root.askBusy
    opacity: ready ? 1 : 0
    scale: ready ? 1 : 0.6
    color: root.strong
    Behavior on opacity { NumberAnimation { duration: root.fadeMs } }
    Behavior on scale { NumberAnimation { duration: root.fadeMs; easing.type: Easing.OutBack } }
    StrokeIcon {
      anchors.centerIn: parent
      size: root.u(13)
      strokeWidth: 1.8
      color: root.plate
      path: "M12 18V6M7 11l5-5 5 5"
    }
    MouseArea {
      anchors.fill: parent
      enabled: askSendButton.ready
      cursorShape: Qt.PointingHandCursor
      onClicked: askCard.send()
    }
  }
}
