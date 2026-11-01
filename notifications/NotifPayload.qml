// Island Notch notification server, part 2: what the notch is handed for a
// notification, and iPhone ones read as their WhatsApp group.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

import "../NotificationLogic.js" as NotificationLogic

NotifStore {
  id: service

  function isIphone(notification) {
    var entry = ""
    try { entry = String(notification.desktopEntry || "") } catch (e) { entry = "" }
    return entry === "tether-gtk"
      || NotificationLogic.stringHint(notification.hints, "x-kde-origin-name") === "iPhone"
  }

  // What the notch draws: app, title, text, icon. A click runs its main
  // action (an Omarchy exec hint, the "default" action, else the app's own
  // window); a pinned notification offers up to two more of its actions. It
  // stays tracked a while so a click or a reply still reaches the sender,
  // then is let go. Updates (a new track, progress) refresh the notch.
  property var notchHeld: []

  function notchPayload(notification, snapshot) {
    var iphone = isIphone(notification)
    var acts = []
    try {
      for (var i = 0; i < notification.actions.length; i++)
        acts.push({ id: String(notification.actions[i].identifier), text: String(notification.actions[i].text || "") })
    } catch (e) { acts = [] }
    var ids = acts.map(function(a) { return a.id })
    // Only ids travel in these commands, never what the notification says.
    var invoke = function(id) { return ["omarchy-shell", "-q", "notifications", "invokeAction", String(snapshot.originalId), id] }

    var title = snapshot.summary
    var body = String(snapshot.body || "")
    var copy = ""
    if (ids.indexOf("copy-code") >= 0) {
      var code = /(?:^|\D)(\d{4,8})(?!\d)/.exec(title + " " + body)
      if (code) { copy = code[1]; body = title; title = code[1] }
    }

    var desktopEntry = ""
    try { desktopEntry = String(notification.desktopEntry || "") } catch (e) { desktopEntry = "" }
    // Once the notification is gone its actions do nothing, so the click
    // falls back to the app's window.
    var focusApp = desktopEntry || snapshot.app || ""
    var orFocus = function(id) {
      return ["bash", "-c", "r=$(omarchy-shell notifications invokeAction \"$1\" \"$2\"); [ \"$r\" = ok ] || { [ -n \"$3\" ] && \"$OMARCHY_PATH/bin/omarchy-hyprland-focus-app\" \"$3\"; }",
              "--", String(snapshot.originalId), id, iphone ? "" : focusApp]
    }
    var open = null
    var main = ""
    var argv = NotificationLogic.parseExecArgv(snapshot.execArgv || "")
    // iPhone: messages take a reply (the reply box); other apps only let
    // the phone clear the notification (CLEAR ON IPHONE below).
    if (argv) open = argv
    else if (ids.indexOf("default") >= 0) { open = orFocus("default"); main = "default" }

    var extra = []
    for (var k = 0; k < acts.length && extra.length < 2; k++) {
      var a = acts[k]
      if (a.id === main || a.id === "default" || a.id === "inline-reply" || a.id === "copy-code" || a.text === "") continue
      if (iphone && (a.id === "reply" || a.id === "open-app")) continue
      extra.push({ label: a.text, open: invoke(a.id) })
    }
    if (iphone && snapshot.phoneUid && snapshot.phoneClearable)
      extra.unshift({ label: Qt.locale().name.indexOf("pt") === 0 ? "LIMPAR NO IPHONE" : "CLEAR ON IPHONE", open: ["omarchy-shell", "-q", "io.github.hugorolimf.iphone", "dismiss", String(snapshot.phoneUid)] })

    var critical = false
    try { critical = notification.urgency === NotificationUrgency.Critical } catch (e) { critical = false }
    // stays in the notch until answered or closed (claude-notch-notify)
    var sticky = false
    try { sticky = critical && notification.hints["x-island-sticky"] === true } catch (e) { sticky = false }
    return {
      uid: String(snapshot.originalId),
      app: iphone ? (NotificationLogic.stringHint(notification.hints, "x-kde-display-appname") || "iPhone") : snapshot.app,
      title: title, body: body,
      icon: iphone ? (snapshot.appIcon || "tether") : (snapshot.image || snapshot.appIcon),
      desktopEntry: desktopEntry, kind: iphone ? "iphone" : "",
      copy: copy, open: open, actions: extra, urgent: critical, sticky: sticky,
      openLabel: "",
      reply: notification.hasInlineReply === true,
      replyHint: String(notification.inlineReplyPlaceholder || "")
    }
  }

  // History keeps iPhone ones under the phone's app (WhatsApp, …) with its
  // cached icon ("iphone:<app>", resolved by the Island Inbox), not Tether.
  function filedSnapshot(notification, snapshot) {
    if (!isIphone(notification)) return snapshot
    var app = NotificationLogic.stringHint(notification.hints, "x-kde-display-appname") || "iPhone"
    return Object.assign({}, snapshot, { app: app, appIcon: "iphone:" + app })
  }

  // ---- iPhone groups. Tether's popup carries the sender and text but not
  // the subtitle, where iOS puts a WhatsApp group's name; Island iPhone keeps
  // the phone's own copy of each notification in the runtime dir. An iPhone
  // notification waits a moment for it and, with a subtitle, reads as the
  // group: "Person: text".
  property var iphoneQueue: []
  FileView {
    id: ancsRecent
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/island-iphone-recent.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }
  Timer {
    id: iphoneQueueTimer
    interval: 400
    onTriggered: {
      var q = service.iphoneQueue
      service.iphoneQueue = []
      ancsRecent.reload()
      for (var i = 0; i < q.length; i++) service.deliverToNotch(q[i].notification, service.withPhoneContext(q[i].notification, q[i].snapshot))
    }
  }

  function withPhoneContext(notification, snapshot) {
    var list = []
    try { list = JSON.parse(ancsRecent.text() || "[]") } catch (e) { list = [] }
    var app = NotificationLogic.stringHint(notification.hints, "x-kde-display-appname")
    var title = String(snapshot.summary || "")
    var body = String(snapshot.body || "")
    var now = Date.now()
    for (var i = list.length - 1; i >= 0; i--) {
      var n = list[i]
      if (!n || now - Number(n.at || 0) > 30000) continue
      if (app && n.app !== app) continue
      if (n.title !== title) continue
      if (n.body && body && body.indexOf(n.body.slice(0, 40)) !== 0) continue
      var sub = String(n.subtitle || "").trim()
      var phone = { phoneUid: Number(n.uid || 0), phoneClearable: n.clearable === true }
      if (!sub || sub === title) return Object.assign({}, snapshot, phone)
      return Object.assign({}, snapshot, phone, { summary: sub, body: title + ": " + body })
    }
    return snapshot
  }

  function showInNotch(notification, snapshot) {
    if (isIphone(notification)) {
      var q = iphoneQueue.slice()
      q.push({ notification: notification, snapshot: snapshot })
      iphoneQueue = q
      iphoneQueueTimer.restart()
      return
    }
    deliverToNotch(notification, snapshot)
  }
}
