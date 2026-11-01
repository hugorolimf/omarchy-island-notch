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

// PENSAMENTO: the level as five bars, like a signal meter, that spring up and
// settle down as it changes; the pill squeezes and springs back on each step.
Rectangle {
  id: askThink
  property var root
  property var askCard
  function pop() { askThinkPop.restart() }
  readonly property int level: root.askEfforts.indexOf(root.askEffort)
  readonly property bool selected: askCard.sel === "pensar"
  anchors.verticalCenter: parent.verticalCenter
  width: askThinkRow.implicitWidth + root.u(18)
  height: root.u(22)
  radius: height / 2
  color: askThinkArea.containsMouse || selected ? Qt.rgba(1, 1, 1, 0.09) : "transparent"
  border.width: selected ? 1.2 : 0.6
  border.color: Qt.rgba(root.hi.r, root.hi.g, root.hi.b, selected ? 0.9 : 0.25)
  Behavior on color { ColorAnimation { duration: root.fadeMs } }
  Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
  Row {
    id: askThinkRow
    anchors.centerIn: parent
    spacing: root.u(6)
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.tr("PENSAMENTO")
      color: root.hi
      font.family: root.monoFont
      font.pointSize: root.fontPt(9.5)
      font.weight: Font.Medium
      font.letterSpacing: 0.5
      textFormat: Text.PlainText
    }
    Row {
      anchors.verticalCenter: parent.verticalCenter
      height: root.u(10)
      spacing: root.u(1.5)
      Repeater {
        model: 5
        Rectangle {
          required property int index
          readonly property bool on: index <= askThink.level
          anchors.bottom: parent.bottom
          width: root.u(2)
          radius: width / 2
          height: on ? root.u(4 + index * 1.5) : root.u(2)
          color: on ? root.strong : Qt.rgba(1, 1, 1, 0.2)
          Behavior on height { NumberAnimation { duration: 300 + index * 40; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
          Behavior on color { ColorAnimation { duration: 200 } }
        }
      }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.tr(root.askEffortLabel[root.askEffort])
      color: root.strong
      font.family: root.monoFont
      font.pointSize: root.fontPt(9.5)
      font.weight: Font.Medium
      font.letterSpacing: 0.5
      textFormat: Text.PlainText
    }
  }
  MouseArea {
    id: askThinkArea
    anchors.fill: parent
    anchors.margins: -root.u(3)
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) { root.cycleAskEffort(-1); askThinkPop.restart() }
      else askCard.act("pensar")
    }
  }
  SequentialAnimation {
    id: askThinkPop
    NumberAnimation { target: askThink; property: "scale"; to: 0.84; duration: 90; easing.type: Easing.OutQuad }
    NumberAnimation { target: askThink; property: "scale"; to: 1; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
  }
}
