import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "../Icons.js" as Icons

// Island Notch: on-demand cards, hover and the lifecycle.
IslandGeometry {
  id: root
  // used by the other parts of the notch
  readonly property var askLinger: askLinger

  // ---- cards (generic: add a Component below and a case in cardComponent)
  function cardComponent(name) {
    if (name === "weather") return weatherCardComponent
    if (name === "ask") return askCardComponent
    return null
  }

  function openCard(name) {
    if (!cardComponent(name)) return "unknown card: " + name
    if (cardName === name && cardPassive) { activateCard(); return "ok" }
    cardPassive = false
    cardName = name
    hoverExpanded = false
    return "ok"
  }

  function closeCard() {
    // the answer was read in the conversation: it doesn't pop up again
    if (cardName === "ask" && (askState === "answer" || askState === "missed")) dismissAsk()
    cardName = ""
    cardPassive = false
  }

  // The voice chat: once a spoken question (asked with nothing open) gets its
  // answer, the conversation card opens passive, without the keyboard (you
  // may be typing elsewhere) and without the click-away grab. It stays while
  // you keep talking and folds on its own a while after the last answer
  // (not while hovered); a click, Tab or an F10 tap take it over for typing,
  // a right click lets it go.
  property bool cardPassive: false
  property bool askVoiceTurn: false
  onAskStateChanged: {
    if (askState === "listening") askVoiceTurn = isHost && cardName === ""
    else if (askState === "answer") {
      // once this change settles: opening the card touches askNow
      if (askVoiceTurn) Qt.callLater(showAskChat)
      askVoiceTurn = false
    } else if (askState !== "thinking") askVoiceTurn = false
  }
  function showAskChat() {
    if (cardName !== "" || !isHost) return
    cardPassive = true
    cardName = "ask"
    hoverExpanded = false
  }
  function activateCard() {
    if (!cardPassive) return
    cardPassive = false
    focusPrime = true
    primeTimer.restart()
    Qt.callLater(function() {
      if (cardLoader.item && typeof cardLoader.item.takeFocus === "function") cardLoader.item.takeFocus()
    })
  }
  Timer {
    id: askLinger
    interval: Math.min(60000, Math.max(25000, (root.ask ? String(root.ask.answer || "").length : 0) * 100))
    running: root.cardName === "ask" && root.cardPassive && !root.askBusy && !root.hovered
    onTriggered: root.closeCard()
  }

  function toggleCard(name) {
    if (name === "ask" && !(leader && leader.askInstalled)) return "no assistant"
    if (cardName === name && cardPassive) { activateCard(); return "ok" }
    if (cardName === name) { closeCard(); return "closed" }
    // A click on the bar button that summoned the card first clears the focus
    // grab (closing it), then asks to toggle: that is a close, not a reopen.
    if (Date.now() - grabClosedAt < 450 && grabClosedName === name) return "closed"
    return openCard(name)
  }

  onCardNameChanged: {
    if (cardName === "") return
    if (cardName === "ask") askNow = Date.now()  // today's thread, not a stale day's
    if (cardPassive) return
    focusPrime = true
    primeTimer.restart()
    // a card with a text box (ask) takes the keys itself
    Qt.callLater(function() {
      if (cardLoader.item && typeof cardLoader.item.takeFocus === "function") cardLoader.item.takeFocus()
      else keyCatcher.forceActiveFocus()
    })
  }

  onActivityChanged: if (activity === "idle") { hoverExpanded = false; mediaPinned = false }

  onHoveredChanged: {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(hovered)
    if (hovered) { closeTimer.stop(); if (!hoverExpanded) openTimer.restart() }
    else { openTimer.stop(); closeTimer.restart() }
  }

  onPlayingChanged: {
    if (playing) {
      pauseLinger = false
      lingerTimer.stop()
      // Deferred: `player` itself depends on lastPlayingKey.
      var key = keyOf(player)
      Qt.callLater(function() { root.lastPlayingKey = key })
    } else if (player) {
      pauseLinger = true
      lingerTimer.restart()
    }
  }

  onIsLeaderChanged: if (isLeader) recCheck()

  Component.onCompleted: {
    if (player) lastPlayingKey = keyOf(player)
  }

  // Stop the children explicitly: a reload must not leave a status
  // follower behind.
  Component.onDestruction: {
    if (tabWanted) setTabBind(false)
    voxProc.running = false
    recWatch.running = false
    claudeWatch.running = false
  }

  property bool focusPrime: false
  Timer { id: primeTimer; interval: 250; onTriggered: root.focusPrime = false }

  Timer {
    id: openTimer
    interval: 180
    onTriggered: if (root.hovered && root.expandable && root.cardName === "") root.hoverExpanded = true
  }

  Timer {
    id: closeTimer
    interval: 300
    onTriggered: {
      if (root.hovered) return
      root.hoverExpanded = false
      if (root.notifActive && !root.notifPinned && !(root.notif && root.notif.sticky)) notifTimer.restart()
    }
  }

  Timer {
    id: lingerTimer
    interval: 30000
    onTriggered: root.pauseLinger = false
  }

  // MPRIS does not push the position; read it once a second, only while it
  // is on screen and moving.
  Timer {
    interval: 500
    repeat: true
    triggeredOnStart: true
    running: root.activity === "media" && root.playing
    onTriggered: {
      if (!root.player) return
      root.player.positionChanged()
      root.trackPos = root.player.position
    }
  }
  onPlayerChanged: trackPos = player ? player.position : 0
}
