import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import ".."
import "../Icons.js" as Icons

// One line of text that rolls over when it changes: the old line rises and
// fades, the new one comes up from below (the steps of a Claude session).
Item {
  id: ticker
  property var root
  property string text: ""
  property color color: root.strong
  property bool flip: false
  implicitHeight: lineA.implicitHeight
  // natural width of the line on show, so the notch can hug it
  readonly property real textWidth: Math.ceil(lineSize.advanceWidth)
  TextMetrics { id: lineSize; font: lineA.font; text: ticker.text }
  height: implicitHeight
  clip: true
  Label { root: ticker.root; id: lineA; width: ticker.width; elide: Text.ElideRight; color: ticker.color }
  Label { root: ticker.root; id: lineB; width: ticker.width; elide: Text.ElideRight; color: ticker.color; opacity: 0 }
  Component.onCompleted: lineA.text = text
  onTextChanged: {
    var current = flip ? lineB : lineA
    if (current.text === text) return
    if (roll.running) roll.complete()
    var next = flip ? lineA : lineB
    next.text = text
    roll.into = next
    roll.away = current
    flip = !flip
    roll.start()
  }
  ParallelAnimation {
    id: roll
    property Item into: null
    property Item away: null
    NumberAnimation { target: roll.into; property: "y"; from: root.u(9); to: 0; duration: 380; easing.type: Easing.Bezier; easing.bezierCurve: root.ease }
    NumberAnimation { target: roll.into; property: "opacity"; from: 0; to: 1; duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: root.ease }
    NumberAnimation { target: roll.away; property: "y"; to: -root.u(9); duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: root.ease }
    NumberAnimation { target: roll.away; property: "opacity"; to: 0; duration: 200 }
  }
}
