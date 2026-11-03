import QtQuick
import ".."
import "../ui"

// The assistant card's text box; holding F10 turns it into the mic. While it
// answers, as in Claude Code: Enter (or the arrow) puts the message in the
// queue, and the stop button (or Esc) interrupts the answer.
Rectangle {
  id: askBox
  property var root
  property var askCard
  property var askScroll
  property var askScrollAnim
  readonly property Item input: askInput
  readonly property bool hearing: askCard.st === "listening"
  readonly property bool answering: askCard.st === "thinking"
  readonly property bool canSend: askInput.text.trim() !== "" && !hearing
  readonly property real button: root.u(22)
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
    anchors.right: askActions.left
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
    // the model list, when open, takes the keys first
    Keys.onReturnPressed: function(event) {
      if (askCard.picking) askCard.picker.pickHot()
      else if (event.modifiers & Qt.ShiftModifier) event.accepted = false
      else if (text === "" && askCard.sel !== "") askCard.act(askCard.sel)
      else askCard.send()
    }
    Keys.onEnterPressed: askCard.picking ? askCard.picker.pickHot() : askCard.send()
    Keys.onEscapePressed: {
      if (askCard.picking) askCard.closePicker()
      else if (askBox.answering) askCard.stop()
      else root.closeCard()
    }
    Keys.onTabPressed: askCard.picking ? askCard.closePicker() : root.closeCard()
    Keys.onBacktabPressed: askCard.picking ? askCard.closePicker() : root.closeCard()
    Keys.onPressed: function(event) {
      if (askCard.picking) {
        if (event.key === Qt.Key_Up) askCard.picker.move(-1)
        else if (event.key === Qt.Key_Down) askCard.picker.move(1)
        else if (event.key === Qt.Key_PageUp) askCard.picker.move(-5)
        else if (event.key === Qt.Key_PageDown) askCard.picker.move(5)
        else if (event.key === Qt.Key_Left) askCard.closePicker()
        else return
        event.accepted = true
        return
      }
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
      text: askBox.answering ? root.tr("Escreva a próxima; ela espera na fila…")
        : askCard.thread.length > 0 ? root.tr("Responda ao assistente…") : root.tr("Pergunte ao assistente…")
      color: root.muted
      font: parent.font
    }
  }
  // Bottom right: the round arrow once there's text (while it answers, it
  // queues), and the stop button for as long as it answers, at the edge.
  Item {
    id: askActions
    anchors.right: parent.right
    anchors.rightMargin: root.u(6)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: root.u(6)
    height: askBox.button
    width: askBox.answering && askBox.canSend ? askBox.button * 2 + root.u(6) : askBox.button
    Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.Bezier; easing.bezierCurve: root.ease } }
    Rectangle {
      id: askSendButton
      x: askBox.answering ? 0 : parent.width - width
      width: askBox.button
      height: width
      radius: width / 2
      opacity: askBox.canSend ? 1 : 0
      scale: askBox.canSend ? 1 : 0.6
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
        enabled: askBox.canSend
        cursorShape: Qt.PointingHandCursor
        onClicked: askCard.send()
      }
    }
    // stop: a square in a quiet ring, like the media controls
    Rectangle {
      id: askStopButton
      x: parent.width - width
      width: askBox.button
      height: width
      radius: width / 2
      readonly property bool shown: askBox.answering
      opacity: !shown ? 0 : root.askStopping ? 0.45 : 1
      scale: shown ? 1 : 0.6
      color: askStopArea.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.1)
      border.width: 0.6
      border.color: Qt.rgba(root.hi.r, root.hi.g, root.hi.b, askStopArea.containsMouse ? 0.6 : 0.3)
      Behavior on opacity { NumberAnimation { duration: root.fadeMs } }
      Behavior on scale { NumberAnimation { duration: root.fadeMs; easing.type: Easing.OutBack } }
      Behavior on color { ColorAnimation { duration: root.fadeMs } }
      Rectangle {
        anchors.centerIn: parent
        width: root.u(8)
        height: width
        radius: root.u(1.5)
        color: root.strong
      }
      MouseArea {
        id: askStopArea
        anchors.fill: parent
        anchors.margins: -root.u(3)
        enabled: askStopButton.shown && !root.askStopping
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: askCard.stop()
      }
    }
  }
}
