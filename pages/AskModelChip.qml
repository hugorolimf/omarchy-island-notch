import QtQuick
import ".."
import "../ui"

// The model that answers, as the card's title: a pill like PENSAMENTO's,
// with a chevron that turns when Claude Code's list is open under it. With
// no list (a script of your own without one) it is a plain title.
Rectangle {
  id: chip
  property var root
  property var askCard
  readonly property bool open: askCard.picking
  readonly property bool selected: askCard.sel === "modelo"
  readonly property bool hasList: root.askHasModels
  anchors.verticalCenter: parent.verticalCenter
  width: chipRow.implicitWidth + root.u(18)
  height: root.u(22)
  radius: height / 2
  color: chipArea.containsMouse || selected || open ? Qt.rgba(1, 1, 1, 0.09) : "transparent"
  border.width: !hasList ? 0 : selected ? 1.2 : 0.6
  border.color: Qt.rgba(root.hi.r, root.hi.g, root.hi.b, selected ? 0.9 : open ? 0.5 : 0.25)
  Behavior on color { ColorAnimation { duration: root.fadeMs } }
  Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
  Row {
    id: chipRow
    anchors.centerIn: parent
    spacing: root.u(5)
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: chip.hasList ? root.askModelName.toUpperCase() : root.tr("ASSISTENTE")
      color: root.strong
      font.family: root.monoFont
      font.pointSize: root.fontPt(9.5)
      font.weight: Font.Medium
      font.letterSpacing: 0.5
      textFormat: Text.PlainText
    }
    StrokeIcon {
      visible: chip.hasList
      anchors.verticalCenter: parent.verticalCenter
      size: root.u(11)
      strokeWidth: 1.6
      color: root.hi
      path: "M6 9l6 6 6-6"
      rotation: chip.open ? 180 : 0
      Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: root.ease } }
    }
  }
  MouseArea {
    id: chipArea
    anchors.fill: parent
    anchors.margins: -root.u(3)
    enabled: chip.hasList
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: askCard.act("modelo")
  }
}
