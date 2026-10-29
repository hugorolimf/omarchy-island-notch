import QtQuick

// Live dot. With `running`, a halo grows out of it and fades (the prototype's
// box-shadow pulse); otherwise it is a plain dot.
Item {
  id: root

  property color color: "#ff6b6b"
  property real size: 6
  property bool running: false

  implicitWidth: size
  implicitHeight: size

  Rectangle {
    id: halo
    anchors.centerIn: parent
    width: root.size + spread * 2
    height: width
    radius: width / 2
    color: "transparent"
    border.width: spread
    border.color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.6 * (1 - spread / 6))
    property real spread: 0
    visible: spread > 0.05
  }

  Rectangle {
    anchors.centerIn: parent
    width: root.size
    height: root.size
    radius: width / 2
    color: root.color
  }

  SequentialAnimation {
    running: root.running
    loops: Animation.Infinite
    onStopped: halo.spread = 0
    NumberAnimation { target: halo; property: "spread"; from: 0; to: 6; duration: 1120; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1, 1, 1] }
    PauseAnimation { duration: 280 }
  }
}
