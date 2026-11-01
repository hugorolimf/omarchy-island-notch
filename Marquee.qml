import QtQuick

// Single-line label that scrolls when it does not fit: a pause, one smooth
// pass, and it loops seamlessly (the text is drawn twice). Edges fade into
// `fadeColor` so the cut is soft.
Item {
  id: root

  property string text: ""
  property color color: "white"
  property color fadeColor: "black"
  property string fontFamily: ""
  property real pixelSize: 12
  property int weight: Font.Normal
  property real maxWidth: 160
  property bool running: true
  // How many passes per text: endless by default; 1 slides a new text past
  // once (when it arrives, or as soon as it may run) and then rests at its
  // start with the edge faded.
  property int passes: Animation.Infinite
  property bool pending: true
  readonly property real gap: 28
  // Rest between passes. Scrolling repaints the bar every frame, so the
  // compact pill rests longer than the open card.
  property int pause: 2200
  readonly property bool overflow: first.implicitWidth > maxWidth + 0.5

  implicitWidth: Math.min(maxWidth, Math.ceil(first.implicitWidth))
  implicitHeight: first.implicitHeight
  clip: true

  onTextChanged: { strip.x = 0; pending = true; kick() }
  onRunningChanged: kick()
  onOverflowChanged: kick()
  Component.onCompleted: kick()
  function kick() {
    if (!running || !overflow) { scroll.stop(); return }
    if (!pending) return
    if (passes !== Animation.Infinite) pending = false
    scroll.restart()
  }

  Row {
    id: strip
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.gap

    Text {
      id: first
      text: root.text
      color: root.color
      font.family: root.fontFamily
      font.pointSize: root.pixelSize * 0.75
      font.weight: root.weight
      textFormat: Text.PlainText
    }

    Text {
      text: root.text
      opacity: root.overflow ? 1 : 0
      color: root.color
      font.family: root.fontFamily
      font.pointSize: root.pixelSize * 0.75
      font.weight: root.weight
      textFormat: Text.PlainText
    }
  }

  SequentialAnimation {
    id: scroll
    loops: root.passes
    onStopped: strip.x = 0
    PropertyAction { target: strip; property: "x"; value: 0 }
    PauseAnimation { duration: root.pause }
    NumberAnimation {
      target: strip
      property: "x"
      to: -(first.implicitWidth + root.gap)
      duration: Math.max(2000, (first.implicitWidth + root.gap) * 30)
      easing.type: Easing.Linear
    }
  }

  Rectangle {
    visible: root.overflow && strip.x < 0
    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
    width: 10
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: root.fadeColor }
      GradientStop { position: 1; color: Qt.rgba(root.fadeColor.r, root.fadeColor.g, root.fadeColor.b, 0) }
    }
  }

  Rectangle {
    visible: root.overflow
    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
    width: 12
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: Qt.rgba(root.fadeColor.r, root.fadeColor.g, root.fadeColor.b, 0) }
      GradientStop { position: 1; color: root.fadeColor }
    }
  }
}
