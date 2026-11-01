// Island Notch notification server, part 3: whether to serve, Do Not
// Disturb at the door, and each notification to the notch and history, held
// a while for a click or a reply, then let go.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

import "../NotificationLogic.js" as NotificationLogic

NotifPayload {
  id: service

  // ---- whether to serve: not while another notifications service is on
  // (checked at start and every 30 s, so enabling or removing one switches
  // over). The scoped registry a plugin gets only sees the plugin itself.
  property bool serverOn: false
  Process {
    id: serverProbe
    command: ["omarchy", "plugin", "list", "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var list = JSON.parse(String(text || "[]"))
          service.serverOn = !list.some(function(p) {
            return p.enabled === true && p.id !== "io.github.hugorolimf.island"
              && (p.id === "omarchy.notifications" || p.clonedFrom === "omarchy.notifications")
          })
        } catch (e) {}
      }
    }
  }
  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!serverProbe.running) serverProbe.running = true
  }

  // Live Notification objects by originalId, kept in a JS map: a QObject
  // held anywhere else becomes a dangling pointer once the server drops it.
  property var liveRefs: ({})

  // Omarchy's own action toasts and bare notify-send critical alerts get
  // through Do Not Disturb; chat apps that mark everything critical don't.
  function shouldBypassDnd(notification) {
    return NotificationLogic.shouldBypassDnd(notification, NotificationUrgency.Critical)
  }

  // Not worth keeping in history: transient, notify-send without an app,
  // Omarchy's action toasts.
  function isEphemeral(notification) {
    var transient = false
    try { transient = !!(notification.hints && notification.hints["transient"]) } catch (e) { transient = false }
    return transient || NotificationLogic.isEphemeralApp(String(notification.appName || ""))
  }

  function handleNotification(notification) {
    // Untracked, the object dies when this handler returns.
    notification.tracked = true
    var snapshot = NotificationLogic.snapshotOf(notification, Date.now())
    liveRefs[snapshot.originalId] = notification
    notification.closed.connect(function() {
      if (service.liveRefs[snapshot.originalId] === notification)
        delete service.liveRefs[snapshot.originalId]
    })

    if (service.doNotDisturb && !shouldBypassDnd(notification)) {
      // Silenced: only history keeps it.
      if (!isEphemeral(notification)) {
        writeSilenced(notification, snapshot)
        return
      }
      delete liveRefs[snapshot.originalId]
      notification.tracked = false
      return
    }
    showInNotch(notification, snapshot)
  }

  // The most recent notification shown, for invokeLast.
  property var lastShown: null

  function deliverToNotch(notification, snapshot) {
    lastShown = { originalId: snapshot.originalId, notification: notification, app: String(snapshot.app || "") }
    service.notchNotification(notchPayload(notification, snapshot))
    var resend = function() {
      if (service.liveRefs[snapshot.originalId] !== notification) return
      var fresh = null
      try { fresh = NotificationLogic.replacementSnapshot(notification, snapshot.originalId, snapshot.timestamp) } catch (e) { fresh = null }
      if (!fresh) return
      service.notchNotification(service.notchPayload(notification, fresh))
      if (!service.isEphemeral(notification)) service.writeHistoryFile(service.filedSnapshot(notification, fresh), null)
    }
    try {
      notification.summaryChanged.connect(function() { Qt.callLater(resend) })
      notification.bodyChanged.connect(function() { Qt.callLater(resend) })
    } catch (e) {}
    // Into history at once (the bell's panel shows it right away).
    if (!isEphemeral(notification)) writeHistoryFile(filedSnapshot(notification, snapshot), null)
    var held = notchHeld.slice()
    // 10 min: long enough for a click, a reply or the bell's panel later on
    held.push({ notification: notification, snapshot: snapshot, due: Date.now() + 600000 })
    notchHeld = held
  }

  function invokeAction(originalId, identifier) {
    var ref = liveRefs[originalId]
    if (!ref) return "gone"
    try {
      for (var i = 0; i < ref.actions.length; i++) {
        if (String(ref.actions[i].identifier) === identifier) {
          ref.actions[i].invoke()
          return "ok"
        }
      }
    } catch (e) {
      return "gone"
    }
    return "none"
  }

  // The last notification's main action, else its app's window.
  function invokeLast() {
    var last = lastShown
    if (!last) return "none"
    service.notchCommand("dismissOne")
    if (invokeAction(last.originalId, "default") === "ok") return "ok"
    if (last.app) Quickshell.execDetached([Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-hyprland-focus-app", last.app])
    return "ok"
  }

  Timer {
    interval: 1000
    repeat: true
    running: service.notchHeld.length > 0
    onTriggered: {
      var now = Date.now()
      var keep = []
      var due = []
      for (var i = 0; i < service.notchHeld.length; i++) {
        var h = service.notchHeld[i]
        if (h.due <= now) due.push(h)
        else keep.push(h)
      }
      service.notchHeld = keep
      for (var j = 0; j < due.length; j++) service.release(due[j].notification, due[j].snapshot.originalId)
    }
  }

  // A silenced notification is held until its content is stable: untracking
  // tells the sender it closed (Chromium then deletes its avatar), and an
  // update lands on this object without a second onNotification.
  function writeSilenced(notification, written) {
    writeHistoryFile(written, function() {
      var updated = null
      try {
        updated = NotificationLogic.replacementSnapshot(notification, written.originalId, written.timestamp)
      } catch (e) {}
      if (updated && NotificationLogic.popupRowChanged(written, updated)) {
        service.writeSilenced(notification, updated)
        return
      }
      service.release(notification, written.originalId)
    })
  }

  function release(notification, originalId) {
    if (liveRefs[originalId] === notification) delete liveRefs[originalId]
    try { notification.tracked = false } catch (e) {}
  }
}
