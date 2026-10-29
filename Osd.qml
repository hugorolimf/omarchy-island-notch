import QtQuick
import Quickshell
import Quickshell.Io
import "OsdModel.js" as OsdModel

// On-screen display (volume, brightness, microphone, keyboard, …) shown in
// the notch instead of a card of its own: the same `osd show <json>` the
// Omarchy scripts send (omarchy-osd) is read here and handed to the notch (BarWidget.qml),
// which draws it as a Dynamic Island style indicator. Part of Island Notch.
Item {
  id: root

  property bool opened: false

  function open(payloadJson) {
    var p = null
    try { p = JSON.parse(payloadJson || "{}") } catch (e) { return }
    var next = OsdModel.stateForShow(p.icon || "", p.message || "", p.value === undefined ? "" : String(p.value),
      p.max === undefined ? "100" : String(p.max), p.progressText || "", p.duration === undefined ? "1200" : String(p.duration))
    Quickshell.execDetached(["omarchy-shell", "-q", "io.github.hugorolimf.island", "hud", JSON.stringify({
      key: next.iconKey,
      value: next.hasProgress ? next.value / next.maxValue : -1,
      message: next.hasProgress ? "" : next.message,
      duration: next.duration
    })])
    opened = true
    hideTimer.interval = Math.max(300, next.duration)
    hideTimer.restart()
  }

  function close() {
    opened = false
    Quickshell.execDetached(["omarchy-shell", "-q", "io.github.hugorolimf.island", "hud", "{}"])
  }

  Timer {
    id: hideTimer
    onTriggered: root.opened = false
  }

  IpcHandler {
    target: "osd"
    function show(payloadJson: string): string {
      root.open(payloadJson)
      return "ok"
    }
    function close(): string { root.close(); return "ok" }
    function state(): string { return root.opened ? "open" : "closed" }
    function ping(): string { return "ok" }
  }
}
