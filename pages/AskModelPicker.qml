import QtQuick
import ".."
import "../ui"

// Claude Code's models (the same list as its /model), dropped under the model
// chip over the thread: each name, Claude Code's own words for it, and a check
// on the one answering. ↑↓ walk it, Enter picks, Esc, Tab or ← go back to the
// box; a click picks. The list is asked again each time it opens.
Rectangle {
  id: picker
  property var root
  property var askCard
  property int hot: -1
  readonly property var models: root.askModels
  readonly property bool open: askCard.picking
  readonly property real pad: root.u(8)
  function indexOf(value) {
    for (var i = 0; i < models.length; i++) if (models[i].valor === value) return i
    return -1
  }
  function reset() {
    hot = Math.max(0, indexOf(root.askModel))
    Qt.callLater(showHot)
  }
  function move(step) {
    if (models.length === 0) return
    hot = Math.max(0, Math.min(models.length - 1, hot < 0 ? 0 : hot + step))
    showHot()
  }
  function pickHot() { if (hot >= 0 && hot < models.length) askCard.pickModel(models[hot].valor) }
  // keeps the row walked to inside the list
  function showHot() {
    var row = rows.itemAt(hot)
    if (!row) return
    if (row.y < list.contentY) list.contentY = row.y
    else if (row.y + row.height > list.contentY + list.height) list.contentY = row.y + row.height - list.height
  }
  onOpenChanged: if (open) reset()
  onModelsChanged: if (open) { hot = Math.min(Math.max(hot, indexOf(root.askModel)), models.length - 1); Qt.callLater(showHot) }

  opacity: open ? 1 : 0
  visible: opacity > 0
  Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: root.ease } }
  transform: Translate {
    y: picker.open ? 0 : -root.u(6)
    Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.Bezier; easing.bezierCurve: root.ease } }
  }
  height: Math.min(caption.height + root.u(6) + Math.max(listCol.implicitHeight, root.u(34)) + pad * 2, root.u(268))
  radius: root.u(14)
  color: Qt.tint(root.plate, Qt.rgba(1, 1, 1, 0.07))
  border.width: 0.6
  border.color: Qt.rgba(root.hi.r, root.hi.g, root.hi.b, 0.2)
  clip: true

  // the thread under it takes no clicks or scrolling meanwhile
  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onWheel: function(wheel) { wheel.accepted = true }
  }

  Text {
    id: caption
    x: picker.pad + root.u(10)
    y: picker.pad + root.u(4)
    text: root.tr("MODELOS DO CLAUDE CODE")
    color: root.muted
    font.family: root.monoFont
    font.pointSize: root.fontPt(9)
    font.weight: Font.Medium
    font.letterSpacing: 0.5
    textFormat: Text.PlainText
  }

  Flickable {
    id: list
    x: picker.pad
    y: caption.y + caption.height + root.u(6)
    width: picker.width - picker.pad * 2
    height: picker.height - y - picker.pad
    contentWidth: width
    contentHeight: listCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    Column {
      id: listCol
      width: list.width
      spacing: root.u(2)
      Repeater {
        id: rows
        model: picker.models
        Rectangle {
          id: row
          required property var modelData
          required property int index
          readonly property bool chosen: modelData.valor === root.askModel
          readonly property string note: root.modelNote(modelData)
          width: listCol.width
          height: rowCol.implicitHeight + root.u(12)
          radius: root.u(10)
          color: index === picker.hot ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
          Behavior on color { ColorAnimation { duration: 140 } }
          Column {
            id: rowCol
            x: root.u(10)
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - root.u(44)
            spacing: root.u(1)
            Text {
              width: parent.width
              text: root.modelName(row.modelData)
              color: row.chosen || row.index === picker.hot ? root.strong : Qt.rgba(root.strong.r, root.strong.g, root.strong.b, 0.78)
              font.family: root.sansFont
              font.pointSize: root.fontPt(12)
              font.weight: row.chosen ? Font.DemiBold : Font.Normal
              elide: Text.ElideRight
              textFormat: Text.PlainText
            }
            Text {
              visible: row.note !== ""
              width: parent.width
              text: row.note
              color: root.muted
              font.family: root.sansFont
              font.pointSize: root.fontPt(10)
              elide: Text.ElideRight
              textFormat: Text.PlainText
            }
          }
          StrokeIcon {
            visible: row.chosen
            anchors.right: parent.right
            anchors.rightMargin: root.u(12)
            anchors.verticalCenter: parent.verticalCenter
            size: root.u(14)
            strokeWidth: 1.8
            color: root.hi
            path: "M5 12.5l4.5 4.5L19 7"
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: picker.hot = row.index
            onClicked: askCard.pickModel(row.modelData.valor)
          }
        }
      }
    }
  }
  // where the list is, when it doesn't fit
  Rectangle {
    visible: list.contentHeight > list.height + 1
    x: picker.width - root.u(5)
    y: list.y + list.visibleArea.yPosition * list.height
    width: root.u(2)
    height: Math.max(root.u(16), list.visibleArea.heightRatio * list.height)
    radius: width / 2
    color: Qt.rgba(1, 1, 1, 0.18)
  }
}
