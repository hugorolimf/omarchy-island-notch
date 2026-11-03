import QtQuick
import Quickshell.Io

// Paste for a text field without Qt itself reading the clipboard. Qt's own
// paste reads whatever another app streams, all of it and in the shell's
// thread; here `wl-paste` reads it in a child process, cut at MAX_BYTES and
// stopped after two seconds, and only that text reaches the field.
//
// Put it inside the TextEdit/TextInput it guards (it fills it) and call
// key(event) first in the field's Keys.onPressed. It also takes the middle
// click (primary selection paste) and drops of text, which would go through
// Qt's own reading.
Item {
  id: guard

  required property Item field
  // single-line fields get newlines as spaces
  property bool singleLine: false
  readonly property int maxBytes: 16384

  anchors.fill: parent

  // Ctrl+V, Shift+Insert, Ctrl+Shift+V and the Paste key: true when taken.
  function key(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var paste = event.matches(StandardKey.Paste) || event.key === Qt.Key_Paste
      || (ctrl && event.key === Qt.Key_V)
      || ((event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_Insert)
    if (!paste) return false
    if (!field.readOnly && !reader.running) reader.running = true
    return true
  }

  function insert(text) {
    if (!text || field.readOnly) return
    if (singleLine) text = text.replace(/[\r\n]+/g, " ")
    if (field.selectedText !== "") field.remove(field.selectionStart, field.selectionEnd)
    field.insert(field.cursorPosition, text)
  }

  Process {
    id: reader
    command: ["sh", "-c", "timeout 2 wl-paste --no-newline --type text 2>/dev/null | head -c " + guard.maxBytes]
    stdout: StdioCollector { onStreamFinished: guard.insert(text) }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.MiddleButton
  }

  DropArea {
    anchors.fill: parent
    onEntered: function(drag) { drag.accepted = true }
    onDropped: function(drop) { drop.accepted = true }
  }
}
