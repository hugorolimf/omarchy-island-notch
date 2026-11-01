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

// The day's thread in the assistant card; it keeps to its end as messages
// come in, and its edges fade into the notch when there is more.
Item {
  id: askThreadView
  property var root
  property var askCard
  property var askBox
  readonly property Flickable scroll: askScroll
  readonly property NumberAnimation scrollAnim: askScrollAnim
  readonly property real contentHeight: askThreadCol.implicitHeight
  width: parent.width
  height: askScroll.height
  visible: askThreadCol.implicitHeight > 0
  Flickable {
    id: askScroll
    width: parent.width
    // the box grows over the thread, so the card stays inside the layer
    height: Math.min(contentHeight, root.u(300) - Math.max(0, askBox.height - root.u(34)))
    contentWidth: width
    contentHeight: askThreadCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    function toEnd() { askScrollAnim.stop(); contentY = Math.max(0, contentHeight - height) }
    onContentHeightChanged: Qt.callLater(toEnd)
    onHeightChanged: Qt.callLater(toEnd)
    NumberAnimation on contentY {
      id: askScrollAnim
      running: false
      duration: 260
      easing.type: Easing.Bezier
      easing.bezierCurve: root.ease
    }
    Column {
      id: askThreadCol
      width: askScroll.width
      spacing: root.u(10)
      Repeater {
        model: askCard.thread
        Item {
          required property var modelData
          required property int index
          readonly property bool mine: modelData.quem === "voce"
          width: askThreadCol.width
          height: mine ? mineBubble.implicitHeight : reply.implicitHeight
          AskBubble { root: askThreadView.root
            id: mineBubble
            visible: parent.mine
            width: parent.width
            text: String(parent.modelData.texto || "")
            // the time once per minute, with how it was asked
            meta: !parent.mine ? "" : (parent.index >= 2 && askCard.thread[parent.index - 2].hora === parent.modelData.hora) ? ""
              : String(parent.modelData.hora || "") + "  ·  " + askCard.viaLabel(parent.modelData)
          }
          Text {
            id: reply
            visible: !parent.mine
            width: parent.width - root.u(8)
            text: String(parent.modelData.texto || "")
            color: parent.modelData.ok === false ? root.amber : root.strong
            font.family: root.sansFont
            font.pointSize: root.fontPt(12)
            wrapMode: Text.Wrap
            lineHeight: 1.1
            textFormat: Text.PlainText
          }
        }
      }
      // what is on its way: the question, then the assistant at work
      AskBubble { root: askThreadView.root
        visible: askCard.pending !== ""
        width: parent.width
        text: askCard.pending
      }
      Row {
        visible: askCard.st === "thinking"
        spacing: root.u(8)
        AskMark { root: askThreadView.root; anchors.verticalCenter: parent.verticalCenter; busy: true }
        // what it is doing right now (assistente's «passo»), else Pensando…
        Label { root: askThreadView.root
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, parent.parent.width - root.u(40))
          elide: Text.ElideRight
          color: root.muted
          text: askCard.pending === "" ? root.tr("Transcrevendo…")
            : root.ask && root.ask.passo ? String(root.ask.passo) : root.tr("Pensando…")
        }
      }
      Label { root: askThreadView.root
        visible: askCard.st === "missed"
        color: root.amber
        text: root.tr("Não entendi")
      }
    }
  }
  // more above or below: that edge fades into the notch
  Rectangle {
    width: parent.width
    height: root.u(18)
    visible: askScroll.contentY > 1
    gradient: Gradient {
      GradientStop { position: 0; color: root.plate }
      GradientStop { position: 1; color: Qt.rgba(root.plate.r, root.plate.g, root.plate.b, 0) }
    }
  }
  Rectangle {
    width: parent.width
    height: root.u(18)
    anchors.bottom: parent.bottom
    visible: askScroll.contentY < askScroll.contentHeight - askScroll.height - 1
    gradient: Gradient {
      GradientStop { position: 0; color: Qt.rgba(root.plate.r, root.plate.g, root.plate.b, 0) }
      GradientStop { position: 1; color: root.plate }
    }
  }
  Rectangle {
    visible: askScroll.contentHeight > askScroll.height + 1
    anchors.right: parent.right
    anchors.rightMargin: -root.u(10)
    y: askScroll.visibleArea.yPosition * askScroll.height
    width: root.u(2)
    height: Math.max(root.u(16), askScroll.visibleArea.heightRatio * askScroll.height)
    radius: width / 2
    color: Qt.rgba(1, 1, 1, 0.18)
  }
}
