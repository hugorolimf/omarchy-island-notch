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

// The voice assistant (F10) and dictation (F9).
Item {
  id: voicePages
  property var root
  anchors.fill: parent
  readonly property var refs: ({ askListenRow: askListenRow, askThinkPage: askThinkPage, askThinkCol: askThinkCol, askMissedRow: askMissedRow, askCol: askCol, dictRow: dictRow })

  // voice assistant (F10): listening, like dictation but with Claude's mark
  Page { root: voicePages.root
    key: "askListen"
    width: askListenRow.implicitWidth
    height: root.barH + root.u(14)
    Row {
      id: askListenRow
      anchors.centerIn: parent
      spacing: root.u(8)
      AskMark { root: voicePages.root; anchors.verticalCenter: parent.verticalCenter }
      LiveBars { root: voicePages.root; anchors.verticalCenter: parent.verticalCenter; span: root.u(20) }
      Label { root: voicePages.root; anchors.verticalCenter: parent.verticalCenter; text: root.tr("Ouvindo…") }
    }
  }

  Page { root: voicePages.root
    id: askThinkPage
    key: "askThink"
    // as wide as the heard sentence, up to the old fixed size
    width: Math.min(root.u(320) - root.u(32), Math.max(askThinkHead.implicitWidth, askHeard.visible ? Math.ceil(askHeardSize.advanceWidth) : 0))
    // measured apart: the elided line's own width follows the page's
    TextMetrics { id: askHeardSize; font: askHeard.font; text: askHeard.text }
    height: askThinkCol.implicitHeight + root.u(18)
    Column {
      id: askThinkCol
      y: root.u(9)
      width: parent.width
      spacing: root.u(3)
      Row {
        id: askThinkHead
        spacing: root.u(8)
        AskMark { root: voicePages.root; anchors.verticalCenter: parent.verticalCenter; busy: root.view === "askThink" }
        Label { root: voicePages.root; anchors.verticalCenter: parent.verticalCenter; text: root.tr("Pensando…") }
      }
      Sub { root: voicePages.root
        id: askHeard
        visible: text !== ""
        width: parent.width
        elide: Text.ElideRight
        text: root.ask && root.ask.heard ? "«" + root.ask.heard + "»" : ""
      }
      // what it is doing right now (assistente's «passo»)
      Sub { root: voicePages.root
        visible: text !== ""
        width: parent.width
        elide: Text.ElideRight
        text: root.ask && root.ask.passo ? String(root.ask.passo) : ""
      }
    }
  }

  Page { root: voicePages.root
    key: "askMissed"
    width: askMissedRow.implicitWidth
    height: root.compactH
    Row {
      id: askMissedRow
      anchors.verticalCenter: parent.verticalCenter
      spacing: root.u(8)
      AskMark { root: voicePages.root; anchors.verticalCenter: parent.verticalCenter }
      Label { root: voicePages.root; anchors.verticalCenter: parent.verticalCenter; color: root.amber; text: root.tr("Não entendi") }
    }
  }

  // the answer, in the big card; a click opens the day's conversation
  Page { root: voicePages.root
    key: "askAnswer"
    // Hovering keeps an answer on screen, it never brings one back: the
    // area below still tracks the mouse while this page is hidden.
    onActiveChanged: root.askHold = active && askAnswerArea.containsMouse
    width: root.u(380) - root.u(40)
    height: askCol.implicitHeight + root.u(26)
    Column {
      id: askCol
      y: root.u(13)
      width: parent.width
      spacing: root.u(4)
      Row {
        spacing: root.u(8)
        AskMark { root: voicePages.root; anchors.verticalCenter: parent.verticalCenter }
        Label { root: voicePages.root; anchors.verticalCenter: parent.verticalCenter; text: root.tr("Assistente") }
      }
      Sub { root: voicePages.root
        visible: text !== ""
        width: parent.width
        elide: Text.ElideRight
        text: root.ask && root.ask.heard ? root.tr("Você: ") + root.ask.heard : ""
      }
      Text {
        width: parent.width
        topPadding: root.u(2)
        text: root.ask ? String(root.ask.answer || "") : ""
        color: root.ask && root.ask.ok === false ? root.amber : root.strong
        font.family: root.sansFont
        font.pointSize: root.fontPt(12)
        wrapMode: Text.Wrap
        maximumLineCount: 9
        elide: Text.ElideRight
        lineHeight: 1.08
        textFormat: Text.PlainText
      }
      Sub { root: voicePages.root
        topPadding: root.u(2)
        font.pointSize: root.fontPt(9)
        text: root.tr("tab ou clique para responder · segure F10 para falar")
      }
    }
    // a click carries on in the conversation card; right click lets it go
    MouseArea {
      id: askAnswerArea
      anchors.fill: parent
      anchors.margins: -root.u(10)
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: root.askHold = containsMouse && parent.active
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) root.dismissAsk()
        else root.openCard("ask")
      }
    }
  }

  // dictation: the notch hangs lower while the user speaks; bars follow the voice
  Page { root: voicePages.root
    key: "dictation"
    width: dictRow.implicitWidth
    height: root.barH + root.u(14)
    Row {
      id: dictRow
      anchors.centerIn: parent
      spacing: root.u(8)
      Rectangle { anchors.verticalCenter: parent.verticalCenter; width: root.u(6); height: width; radius: width / 2; color: root.blue }
      LiveBars { root: voicePages.root; anchors.verticalCenter: parent.verticalCenter; span: root.u(20) }
      Label { root: voicePages.root; anchors.verticalCenter: parent.verticalCenter; text: root.tr("Ditando…") }
    }
  }
}
