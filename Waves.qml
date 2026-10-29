import QtQuick

// Thin bars for live audio. "bounce": each bar swings between low and high,
// staggered (the dictation wave of the anatomy prototype). "travel": the
// bars shrink to dots and a slow wave runs through them (transcribing).
// Nothing animates while `running` is false.
Row {
  id: root

  property int count: 9
  property real barWidth: 1.6
  property real maxHeight: 12
  property real minHeight: 2
  property color color: "#d4d4d4"
  property bool running: false
  property string mode: "bounce"
  property int period: 1000
  readonly property var ease: [0.32, 0.72, 0, 1, 1, 1]

  spacing: 1.5
  height: maxHeight

  // travel mode: one phase drives every bar
  property real phase: 0
  NumberAnimation on phase {
    running: root.running && root.mode === "travel"
    from: 0
    to: Math.PI * 2
    duration: 1600
    loops: Animation.Infinite
  }

  Repeater {
    model: root.count

    Rectangle {
      id: bar
      required property int index
      property real level: 0

      readonly property real travelLevel: 0.5 + 0.5 * Math.sin(root.phase - index * 0.7)

      anchors.verticalCenter: parent.verticalCenter
      width: root.barWidth
      height: root.mode === "travel"
        ? root.barWidth + (root.maxHeight * 0.45 - root.barWidth) * travelLevel
        : root.minHeight + (root.maxHeight - root.minHeight) * level
      radius: width / 2
      color: root.color
      opacity: root.mode === "travel" ? 0.45 + 0.55 * travelLevel : 1


      SequentialAnimation {
        id: swing
        loops: Animation.Infinite
        NumberAnimation { target: bar; property: "level"; to: 1; duration: root.period; easing.type: Easing.Bezier; easing.bezierCurve: root.ease }
        NumberAnimation { target: bar; property: "level"; to: 0; duration: root.period; easing.type: Easing.Bezier; easing.bezierCurve: root.ease }
      }

      // CSS-like animation-delay: (i % 5) * 110 ms
      Timer {
        interval: (bar.index % 5) * 110 + 1
        running: root.running && root.mode === "bounce"
        onTriggered: swing.start()
      }

      Connections {
        target: root
        function onRunningChanged() { if (!root.running) { swing.stop(); bar.level = 0 } }
        function onModeChanged() { if (root.mode !== "bounce") swing.stop() }
      }
    }
  }
}
