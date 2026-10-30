// Island Notch's notification server: every notification shows in the notch,
// lands in the history the Island Inbox reads, and Do Not Disturb, actions
// and inline replies work as with Omarchy's own notifications service, whose
// `notifications` IPC (and therefore its keybindings) it keeps.
//
// It only serves while no other notifications service does (Omarchy's
// omarchy.notifications, or a clone of it): two servers in one shell would
// show every notification twice. See README, "Install".
//
// Nothing a notification says is ever put in a process's arguments, which
// other accounts can read: the notch is handed it in process (through Shared.js), and history files are
// written from stdin into folders only this account can open.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

import "NotificationLogic.js" as NotificationLogic
import "Shared.js" as Shared

Item {
  id: service

  // Injected by omarchy-shell (the service loader).
  property var shell: null

  // The notch (BarWidget.qml) shows them, reached in process through
  // Shared.js. Without a notch up they still land in history.
  function notchNotification(payload) {
    var notch = Shared.leaderItem()
    if (notch) notch.deliverNotification(payload)
  }
  // "dismissOne" | "dismissAll", from the keybindings.
  function notchCommand(name) {
    var notch = Shared.leaderItem()
    if (notch) notch.dismissNotifications(name === "dismissOne")
  }

  readonly property string home: Quickshell.env("HOME")
  // The same places Omarchy's notifications service uses, so the history
  // carries over and the Island Inbox reads it unchanged.
  readonly property string stateDir: home + "/.local/state/omarchy/"
  readonly property string settingsPath: stateDir + "notifications.json"
  readonly property string notificationsDir: stateDir + "notifications/"
  readonly property string historyDir: notificationsDir + "history/"
  readonly property string imagesDir: notificationsDir + "images/"

  // How many notifications history keeps (the Island Inbox shows them).
  readonly property int historyLimit: 100

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

  // ---- Do Not Disturb, persisted in notifications.json (same file and
  // format as Omarchy's service).
  PersistentProperties {
    id: persisted
    reloadableId: "island-notch-notifications"
    property bool doNotDisturb: false
    onDoNotDisturbChanged: {
      if (service._hydrating) return
      service.scheduleSettingsSave()
    }
  }
  property bool _hydrating: false
  readonly property alias doNotDisturb: persisted.doNotDisturb
  function setDoNotDisturb(value) { persisted.doNotDisturb = !!value }

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
    return {
      uid: String(snapshot.originalId),
      app: iphone ? (NotificationLogic.stringHint(notification.hints, "x-kde-display-appname") || "iPhone") : snapshot.app,
      title: title, body: body,
      icon: iphone ? (snapshot.appIcon || "tether") : (snapshot.image || snapshot.appIcon),
      desktopEntry: desktopEntry, kind: iphone ? "iphone" : "",
      copy: copy, open: open, actions: extra, urgent: critical,
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

  // ---------------------------------------------------- history files
  //
  // One serialized queue of shell jobs, so a burst of updates can't race.
  // Each job runs under umask 077, and a notification's JSON reaches it on
  // stdin: arguments only ever carry paths and file names.

  property var fileQueue: []
  property var runningJob: null

  function enqueueFileJob(command, input, done) {
    fileQueue = fileQueue.concat([{ command: command, input: input || "", done: done || null }])
    runNextFileJob()
  }

  function runNextFileJob() {
    if (fileProc.running || fileQueue.length === 0) return
    var job = fileQueue[0]
    fileQueue = fileQueue.slice(1)
    runningJob = job
    fileProc.command = ["bash", "-c", "umask 077\n" + job.command[0]].concat(["--"]).concat(job.command.slice(1))
    fileProc.stdinEnabled = true
    fileProc.running = true
  }

  Process {
    id: fileProc
    onStarted: {
      var job = service.runningJob
      if (job && job.input) write(job.input)
      stdinEnabled = false
    }
    onExited: {
      var job = service.runningJob
      service.runningJob = null
      if (job && job.done) {
        try { job.done() } catch (e) { console.warn("island notifications: file job callback failed:", e) }
      }
      service.runNextFileJob()
    }
  }

  // Remaining args as from/to pairs: bounded copy into a temp file, then
  // renamed. The source path is the sender's and may grow, block or be a FIFO.
  readonly property string copyImagesScript:
    "while (( $# >= 2 )); do\n" +
    "  if [[ -f $1 ]] && timeout 5 head -c 5242881 -- \"$1\" > \"$2.tmp\" 2>/dev/null &&\n" +
    "     (( $(stat -c%s -- \"$2.tmp\") <= 5242880 )); then mv -f -- \"$2.tmp\" \"$2\"; else rm -f -- \"$2.tmp\"; fi\n" +
    "  shift 2\n" +
    "done\n"

  // Everything but the newest $limit files goes, image copies included.
  readonly property string trimHistoryScript:
    "ls -1 \"$hist\" 2>/dev/null | sort -n | head -n \"-$limit\" | while IFS= read -r stale; do rm -f \"$hist/$stale\" \"$imgs/${stale%.json}\"-*; done"

  // The folders private: created 0700, and older ones (Omarchy's service
  // created them 0755 with 0644 files) tightened along with what's in them.
  readonly property string privateDirsScript:
    "mkdir -p \"$hist\" \"$imgs\" || exit 0\n" +
    "chmod 700 \"$base\" \"$hist\" \"$imgs\" 2>/dev/null\n"

  function writeHistoryFile(entry, done) {
    if (!entry) {
      if (done) done()
      return
    }
    var persistable = NotificationLogic.persistablePopup(entry, imagesDir)
    var command = [
      "base=\"$1\" hist=\"$2\" limit=\"$3\" name=\"$4\" imgs=\"$5\"\n" +
      privateDirsScript +
      "shift 5\n" +
      copyImagesScript +
      "cat > \"$hist/$name.tmp\" && mv -f -- \"$hist/$name.tmp\" \"$hist/$name\" || { rm -f -- \"$hist/$name.tmp\"; exit 0; }\n" +
      trimHistoryScript,
      notificationsDir,
      historyDir,
      String(historyLimit),
      NotificationLogic.popupFileName(entry),
      imagesDir]
    for (var i = 0; i < persistable.copies.length; i++)
      command.push(persistable.copies[i].from, persistable.copies[i].to)
    enqueueFileJob(command, NotificationLogic.serializePopup(persistable.entry, NotificationUrgency.Normal) + "\n", done)
  }

  function clearHistory() {
    enqueueFileJob([
      "for f in \"$1\"/*.json; do\n" +
      "  [[ -e $f ]] || continue\n" +
      "  stale=\"${f##*/}\"\n" +
      "  rm -f \"$f\" \"$2/${stale%.json}\"-*\n" +
      "done", historyDir, imagesDir])
  }

  // At start: make the folders private (and what's already in them), and
  // sweep image copies whose JSON is gone (a restart between a copy and its
  // JSON write). Leftover on-screen files from Omarchy's service go to history.
  function prepareFiles() {
    enqueueFileJob([
      "base=\"$1\" hist=\"$2\" imgs=\"$3\"\n" +
      privateDirsScript +
      "for f in \"$base\"/*.json; do [[ -f $f ]] && mv -f -- \"$f\" \"$hist/\"; done\n" +
      "chmod 600 \"$hist\"/* \"$imgs\"/* 2>/dev/null\n" +
      "chmod 600 \"$4\" 2>/dev/null\n" +
      "for img in \"$imgs\"/*; do\n" +
      "  [[ -e $img ]] || continue\n" +
      "  [[ $img == *.tmp ]] && { rm -f -- \"$img\"; continue; }\n" +
      "  stem=\"${img##*/}\"\n" +
      "  stem=\"${stem%-*}\"\n" +
      "  [[ -e $hist/$stem.json ]] || rm -f \"$img\"\n" +
      "done", notificationsDir, historyDir, imagesDir, settingsPath])
  }

  // ---------------------------------------------------- settings

  FileView {
    id: settingsFile
    path: service.settingsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadSettings(text())
    // First run: no file yet, and saving must still work.
    onLoadFailed: service.loadSettings("")
  }

  Timer {
    id: settingsSaveTimer
    interval: 200
    onTriggered: service.flushSettings()
  }

  function scheduleSettingsSave() {
    if (!service.settingsLoaded) return
    settingsSaveTimer.restart()
  }

  property bool settingsLoaded: false

  function loadSettings(raw) {
    if (service.settingsLoaded) return
    var parsed = NotificationLogic.parseSettings(raw)
    if (parsed.error) console.warn("island notifications: settings parse failed:", parsed.errorMessage || "")
    if (parsed.dnd !== null) {
      service._hydrating = true
      persisted.doNotDisturb = parsed.dnd
      service._hydrating = false
    }
    service.settingsLoaded = true
    if (parsed.legacy) service.scheduleSettingsSave()
  }

  function flushSettings() {
    settingsFile.setText(JSON.stringify({ version: 3, dnd: persisted.doNotDisturb }, null, 2) + "\n")
  }

  Component.onCompleted: {
    prepareFiles()
    Qt.callLater(function() { settingsFile.reload() })
  }

  // ---------------------------------------------------- IPC
  //
  // The same `notifications` target as Omarchy's service: its keybindings
  // (Super+, and friends) and the Island Inbox keep working. Registered only
  // while this service is the one serving.

  // Reads the private reply file handed over by replyFile().
  FileView {
    id: replyReader
    blockLoading: true
    printErrors: false
  }

  Loader {
    active: service.serverOn
    sourceComponent: Item {
      IpcHandler {
        target: "notifications"

        function dndState(): string { return service.doNotDisturb ? "on" : "off" }

        function toggleDnd(): string {
          service.setDoNotDisturb(!service.doNotDisturb)
          return dndState()
        }

        function setDnd(value: string): string {
          var v = String(value || "").toLowerCase()
          service.setDoNotDisturb(v === "true" || v === "1" || v === "on" || v === "yes")
          return dndState()
        }

        function isDnd(): string { return dndState() }

        // The history is the Island Inbox's panel (the bell).
        function showHistory(): string {
          Quickshell.execDetached(["omarchy-shell", "-q", "io.github.hugorolimf.inbox", "toggle"])
          return "ok"
        }

        // Forgets the recorded history.
        function clear(): string {
          service.clearHistory()
          return "ok"
        }

        function dismissAll(): string {
          service.notchCommand("dismissAll")
          return "ok"
        }

        function dismissOne(): string {
          service.notchCommand("dismissOne")
          return "ok"
        }

        function invokeLast(): string { return service.invokeLast() }

        // Answer a notification that offers a reply field.
        function reply(id: string, text: string): string {
          var ref = service.liveRefs[id]
          if (!ref || !ref.hasInlineReply) return "gone"
          try { ref.sendInlineReply(String(text || "")) } catch (e) { return "error" }
          return "ok"
        }

        // Same reply, the text in a private file under
        // $XDG_RUNTIME_DIR/island-notch (the notch's reply box writes it):
        // read here and removed.
        function replyFile(id: string, path: string): string {
          var p = String(path || "")
          var dir = Quickshell.env("XDG_RUNTIME_DIR") + "/island-notch/"
          if (p.indexOf(dir) !== 0 || p.indexOf("..") !== -1) return "error"
          replyReader.path = p
          var t = replyReader.text()
          replyReader.path = ""
          Quickshell.execDetached(["rm", "-f", "--", p])
          return reply(id, t)
        }

        function invokeAction(id: string, identifier: string): string {
          return service.invokeAction(id, String(identifier || ""))
        }

        function ping(): string { return "ok" }
      }

      NotificationServer {
        keepOnReload: false
        imageSupported: true
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        persistenceSupported: true
        // Senders may offer a reply field (Tether: SMS / iMessage replies go
        // out through the iPhone); the notch draws it.
        inlineReplySupported: true

        onNotification: function(notification) {
          service.handleNotification(notification)
        }
      }
    }
  }
}
