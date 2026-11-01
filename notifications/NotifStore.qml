// Island Notch notification server, part 1: where things are kept. History
// files (a serialized queue of private shell jobs) and Do Not Disturb, in the
// same places and format as Omarchy's own notifications service.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

import "../NotificationLogic.js" as NotificationLogic

Item {
  id: service

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
}
