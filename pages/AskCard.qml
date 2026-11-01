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

// F10 tap (or a click on an answer): the conversation with the assistant.
// The day's thread scrolls above the box, your messages on the right in a
// soft bubble, its answers as plain text on the left, and the live state
// (Pensando…, Não entendi) at its end. Enter sends and the card stays;
// holding F10 talks inside it (the box turns into the mic). NOVA starts
// another conversation, ABRIR opens the day's note. Keys, as in a pinned
// notification: ↑↓ scroll the thread (once the cursor is on the box's
// first/last line), PgUp/PgDn a page; with the box empty ←→ walk NOVA and
// ABRIR and Enter acts; Shift+Enter breaks the line; Tab, Esc or a click
// elsewhere closes.
Item {
  id: askCard
  property var root
  readonly property var thread: root.askThread
  readonly property string st: root.askState
  readonly property string pending: root.askBusy && root.ask ? String(root.ask.heard || "") : ""
  implicitWidth: root.u(440)
  implicitHeight: askCardCol.implicitHeight + root.u(26)
  function takeFocus() { askBox.input.forceActiveFocus() }
  function send() { if (root.sendAsk(askBox.input.text)) askBox.input.text = "" }
  // the header buttons the arrows walk; "" = none (the ring is off)
  property string sel: ""
  readonly property var buttons: {
    var b = ["pensar"]
    if (askNova.visible) b.push("nova")
    if (askAbrir.visible) b.push("abrir")
    return b
  }
  onButtonsChanged: if (buttons.indexOf(sel) < 0) sel = ""
  function walk(step) {
    var n = buttons.length
    if (n === 0) return
    var i = buttons.indexOf(sel)
    sel = buttons[i < 0 ? (step > 0 ? 0 : n - 1) : (i + step + n) % n]
  }
  function act(name) {
    sel = ""
    if (name === "pensar") { root.cycleAskEffort(1); askThink.pop(); sel = "pensar"; return }
    if (name === "nova") { root.newAsk(); askBox.input.forceActiveFocus() }
    else if (name === "abrir") { root.openAsk(); root.closeCard() }
  }
  function scrollTo(y) {
    askThread.scrollAnim.to = Math.max(0, Math.min(Math.max(0, askThread.scroll.contentHeight - askThread.scroll.height), y))
    askThread.scrollAnim.restart()
  }
  // passive (the voice chat): the first click takes the card over for
  // the keyboard and still reaches what is under it; a right click
  // lets it go
  MouseArea {
    anchors.fill: parent
    z: 10
    enabled: root.cardPassive
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onPressed: function(mouse) {
      if (mouse.button === Qt.RightButton) { root.closeCard(); return }
      root.activateCard()
      mouse.accepted = false
    }
  }
  function viaLabel(m) {
    var v = String(m.via || "")
    return v === "voz" ? root.tr("VOZ") : v === "texto" ? root.tr("TEXTO") : v.toUpperCase()
  }

  Column {
    id: askCardCol
    x: root.u(20)
    y: root.u(13)
    width: parent.width - root.u(40)
    spacing: root.u(10)

    Item {
      width: parent.width
      height: Math.max(askCardHead.implicitHeight, root.u(22))
      Row {
        id: askCardHead
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.u(8)
        AskMark { root: askCard.root; anchors.verticalCenter: parent.verticalCenter; busy: askCard.st === "thinking" }
        Label { root: askCard.root; anchors.verticalCenter: parent.verticalCenter; text: root.tr("Assistente") }
      }
      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.u(6)
        // PENSAMENTO: the level as five bars, like a signal meter, that
        // spring up and settle down as it changes; the pill squeezes and
        // springs back on each step
        AskEffortPill { root: askCard.root; id: askThink; askCard: askCard }
        ActionPill { root: askCard.root
          id: askNova
          visible: askCard.thread.length > 0 && !root.askBusy
          label: root.tr("NOVA")
          selected: askCard.sel === "nova"
          onActivated: askCard.act("nova")
        }
        ActionPill { root: askCard.root
          id: askAbrir
          visible: root.ask !== null && String(root.ask.open || "") !== ""
          label: root.tr("ABRIR")
          selected: askCard.sel === "abrir"
          onActivated: askCard.act("abrir")
        }
      }
    }

    Sub { root: askCard.root
      visible: askThread.contentHeight === 0
      width: parent.width
      wrapMode: Text.Wrap
      lineHeight: 1.15
      text: root.tr("Escreva ou segure o F10 e fale. Ele lembra do que vocês já conversaram hoje.")
    }

    // the thread; it keeps to its end as messages come in
    AskThread { root: askCard.root; id: askThread; askCard: askCard; askBox: askBox }

    AskBox { root: askCard.root; id: askBox; askCard: askCard; askScroll: askThread.scroll; askScrollAnim: askThread.scrollAnim }

    Sub { root: askCard.root
      anchors.horizontalCenter: parent.horizontalCenter
      font.pointSize: root.fontPt(9)
      text: root.cardPassive ? root.tr("tab ou clique para escrever · segure F10 para falar")
        : askBox.input.text === "" ? root.tr("segure F10 para falar · ↑↓ rola · ←→ botões · tab fecha")
        : root.tr("enter envia · shift+enter quebra a linha · tab fecha")
    }
  }
}
