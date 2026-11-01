import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "../Icons.js" as Icons
import "../Shared.js" as Shared

// Island Notch: the notch's size and its morph, and the player helpers.
IslandNotify {
  id: root
  // ---- geometry (body size in real pixels; the ears hang outside)
  // Per-monitor size: every measure is the notebook's (1536 px wide logical
  // screen) times k, capped at 1.35, and drawn natively at that size — no
  // transform scaling, so shapes and text stay sharp. Fonts only grow by
  // 1 px (2 px for big numbers) on the bigger screen.
  readonly property real screenWidth: QsWindow.window && QsWindow.window.screen ? QsWindow.window.screen.width : 1536
  readonly property real k: Math.max(1, Math.min(1.35, screenWidth / 1536))
  readonly property bool big: k > 1.05
  function u(v) { return v * k }
  // Device pixels, for thin strokes: snapped to them they stay sharp on a
  // fractional scale (at 1.25 a 3.5 px bar spreads over 4.4 pixels, blurred).
  readonly property real dpr: {
    var m = QsWindow.window && QsWindow.window.screen ? Hyprland.monitorFor(QsWindow.window.screen) : null
    return m && m.scale > 0 ? m.scale : 1
  }
  function px(n) { return n / dpr }
  function fontPx(base) { return big ? (base >= 20 ? base + 2 : Math.floor(base) + 1) : base }
  // pixel sizes like 10.5 need pointSize (pixelSize is an int); 0.75 pt/px
  function fontPt(base) { return fontPx(base) * 0.75 }

  // The notch starts flush with the bar's edge and hangs a few px below it.
  readonly property real barH: Math.max(20, barSize)
  readonly property real compactH: barH + u(6)
  // the compact player holds two lines (title over artist)
  readonly property real mediaMiniH: compactH + u(8)
  readonly property real ear: u(7)
  readonly property real targetW: {
    if (view === "card") return cardLoader.item ? cardLoader.item.implicitWidth : u(340)
    if (view === "mediaX") return u(400)
    if (view === "screenX") return u(280)
    if (view === "claudeX") return u(380)
    if (view === "askListen") return Math.min(u(196), askListenRow.implicitWidth + u(32))
    if (view === "askThink") return askThinkPage.width + u(32)
    if (view === "askMissed") return askMissedRow.implicitWidth + u(32)
    if (view === "askAnswer") return u(380)
    if (view === "claude") return claudeMini.width + u(32)
    if (view === "iphone") return u(380)
    if (view === "iphoneMini") return iphoneMiniRow.implicitWidth + u(32)
    if (view === "notifX") return Math.max(u(300), notifRowX.implicitWidth + u(32))
    if (view === "notif") return notifRow.implicitWidth + u(32)
    if (view === "dictation") return Math.min(u(290), dictRow.implicitWidth + u(32))
    if (view === "transcribing") return transRow.implicitWidth + u(32)
    if (view === "screen") return screenRow.implicitWidth + u(32)
    if (view === "reminder") return reminderRow.implicitWidth + u(32)
    if (view === "media") return mediaMini.width + u(24)
    if (view === "hud") return hudBar ? u(260) : hudRow.implicitWidth + u(36)
    return 0
  }
  readonly property real targetH: {
    if (view === "card") return cardLoader.item ? cardLoader.item.implicitHeight : u(124)
    if (view === "mediaX") return u(168)
    if (view === "screenX") return u(62)
    if (view === "claudeX") return claudeCol.implicitHeight + u(26)
    if (view === "askListen") return barH + u(14)
    if (view === "askThink") return askThinkCol.implicitHeight + u(18)
    if (view === "askAnswer") return askCol.implicitHeight + u(26)
    if (view === "iphone") return iphoneCard.implicitHeight
    if (view === "notifX") return compactH + u(18) + (shownPinned ? notifActionsX.height + u(10) : 0)
    if (view === "dictation") return barH + u(14)
    if (view === "idle") return barH
    if (view === "media") return mediaMiniH
    return compactH
  }
  readonly property real targetR: u(view === "mediaX" ? 26
    : (view === "card" || view === "screenX" || view === "claudeX" || view === "iphone" || view === "askAnswer") ? 20
    : view === "dictation" || view === "notifX" || view === "askListen" || view === "askThink" ? 14 : 10)

  property real notchW: 0
  property real notchH: barH
  property real notchR: u(10)
  // Going back to rest is its own move: the content fades first, then the
  // body folds away on a soft in-out curve. The opening curve starts so fast
  // that the body would swallow the content before it had faded.
  property bool closing: false
  Behavior on notchW {
    SequentialAnimation {
      PauseAnimation { duration: root.closing ? 130 : 0 }
      NumberAnimation { id: wAnim; duration: root.closing ? 420 : root.morphMs; easing.type: root.closing ? Easing.InOutCubic : Easing.Bezier; easing.bezierCurve: root.ease }
    }
  }
  // Dictation drops in with a slight overshoot (it replaces voxtype's own
  // pill and should be noticed); everything else uses the anatomy curve.
  Behavior on notchH {
    SequentialAnimation {
      PauseAnimation { duration: root.closing ? 130 : 0 }
      NumberAnimation { id: hAnim; duration: root.closing ? 420 : root.morphMs; easing.type: root.closing ? Easing.InOutCubic : root.view === "dictation" ? Easing.OutBack : Easing.Bezier; easing.overshoot: 1.4; easing.bezierCurve: root.ease }
    }
  }
  Behavior on notchR { NumberAnimation { duration: root.morphMs; easing.type: Easing.Bezier; easing.bezierCurve: root.ease } }

  // Targets are pushed once the overlay is mapped, so the first morph is seen.
  function pushTargets() {
    closing = view === "idle" && targetW < notchW
    notchW = targetW
    notchH = targetH
    notchR = targetR
  }
  onTargetWChanged: if (overlay.visible || targetW > 0) Qt.callLater(pushTargets)
  onTargetHChanged: Qt.callLater(pushTargets)
  onTargetRChanged: Qt.callLater(pushTargets)

  readonly property bool wanted: !vertical && (activity !== "idle" || cardName !== "")
  readonly property bool shown: wanted || notchW > 0.5 || wAnim.running

  implicitWidth: vertical ? 0 : Math.max(0, notchW)
  implicitHeight: barSize

  // =====================================================================
  // Helpers

  function formatClock(seconds) {
    var s = Math.floor(seconds)
    var h = Math.floor(s / 3600)
    var m = Math.floor((s % 3600) / 60)
    var r = s % 60
    return (h > 0 ? h + ":" : "") + (m < 10 ? "0" + m : m) + ":" + (r < 10 ? "0" + r : r)
  }

  function trackClock(seconds) {
    var s = Math.max(0, Math.floor(seconds))
    var m = Math.floor(s / 60)
    var r = s % 60
    return m + ":" + (r < 10 ? "0" + r : r)
  }

  function isProxy(p) {
    return String(p && p.dbusName || "").toLowerCase().indexOf("playerctld") !== -1
  }

  function keyOf(p) {
    return p ? String(p.dbusName || p.identity || "") : ""
  }

  function pickPlayer(list, preferredKey) {
    var preferred = null
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (!p || isProxy(p)) continue
      if (p.isPlaying && (p.trackTitle || "") !== "") return p
      if (keyOf(p) === preferredKey) preferred = p
    }
    return preferred
  }

  function run(command) {
    if (root.bar && typeof root.bar.run === "function") root.bar.run(command)
    else Quickshell.execDetached(["sh", "-c", command])
  }

  function focusPlayer() {
    var id = player ? String(player.desktopEntry || player.identity || "") : ""
    mediaPinned = false
    hoverExpanded = false
    if (id) Quickshell.execDetached([Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-hyprland-focus-app", id])
  }
  function mediaToggle() { if (player && player.canTogglePlaying) player.togglePlaying() }
  function mediaNext() { if (player && player.canGoNext) player.next() }
  function mediaPrevious() { if (player && player.canGoPrevious) player.previous() }

  property real wheelAcc: 0
  property real lastWheelAt: 0
  function mediaWheel(dy) {
    wheelAcc += dy
    if (Math.abs(wheelAcc) < 120) return
    var now = Date.now()
    var dir = wheelAcc
    wheelAcc = 0
    if (now - lastWheelAt < 400) return
    lastWheelAt = now
    if (dir > 0) mediaPrevious()
    else mediaNext()
  }

  // The notch sits at the centre of the screen's top edge, like the bar's
  // centre section it belongs to. (Mapping the slot lags: the centre section
  // re-centres itself after the slot's width changes.)
  readonly property real centerX: overlay.width / 2
}
