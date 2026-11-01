import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "../Icons.js" as Icons
import "../Shared.js" as Shared

// Island Notch: the status processes: dictation, screen recording, reminders and the
// voice assistant.
IslandCards {
  id: root
  // used by the other parts of the notch
  readonly property var voxProc: voxProc
  readonly property var recWatch: recWatch

  // =====================================================================
  // Dictation: `voxtype status --follow` pushes a JSON line per change.

  Process {
    id: voxProc
    command: ["omarchy-voxtype-status"]
    running: root.isLeader
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var d = JSON.parse(line)
          root.srcDictState = String(d.alt || d["class"] || "idle")
          root.srcDictModel = String(d.model || "")
          root.srcDictBackend = String(d.backend || "")
        } catch (e) {}
      }
    }
    onExited: { root.srcDictState = "idle"; if (root.isLeader) voxRetry.restart() }
  }

  Timer {
    id: voxRetry
    interval: 15000
    onTriggered: voxProc.running = root.isLeader
  }

  // =====================================================================
  // Screen recording: omarchy-capture-screenrecording writes and removes
  // /tmp/omarchy-screenrecord-filename; inotify tells us when to look.

  function recCheck() {
    if (!isLeader || recProc.running) return
    recProc.running = true
  }

  Process {
    id: recWatch
    command: ["setpriv", "--pdeathsig", "TERM", "inotifywait", "-m", "-q",
      "-e", "create,close_write,delete,moved_to", "--include", "omarchy-screenrecord-filename", "/tmp"]
    running: root.isLeader
    stdout: SplitParser { onRead: function(line) { root.recCheck() } }
    onExited: if (root.isLeader) recWatchRetry.restart()
  }

  Timer {
    id: recWatchRetry
    interval: 15000
    onTriggered: recWatch.running = root.isLeader
  }

  Process {
    id: recProc
    command: ["sh", "-c", "pid=$(pgrep -of '^gpu-screen-recorder') || exit 1; ps -o etimes= -p \"$pid\""]
    stdout: StdioCollector { id: recOut; waitForEnd: true }
    onExited: function(code) {
      if (code === 0) {
        var secs = parseInt(String(recOut.text).trim(), 10) || 0
        var start = Date.now() - secs * 1000
        if (!root.srcScreenRecording || Math.abs(start - root.srcScreenStartMs) > 2500) root.srcScreenStartMs = start
        root.srcScreenRecording = true
      } else {
        root.srcScreenRecording = false
      }
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.screenRecording
    onTriggered: { root.nowMs = Date.now(); root.recCheck() }
    onRunningChanged: root.nowMs = Date.now()
  }

  // =====================================================================
  // Reminders: omarchy-reminder calls `omarchy-shell omarchy.indicators
  // refresh` when one is set, fires or is cleared. The bar's indicators
  // widget is gone, so the notch answers that target itself.

  function reminderCheck() {
    if (!isLeader) { if (leader) leader.reminderCheck(); return }
    if (!reminderProc.running) reminderProc.running = true
  }

  IpcHandler {
    target: "omarchy.indicators"
    function refresh(): void { root.reminderCheck() }
  }

  Process {
    id: reminderProc
    command: ["omarchy-reminder", "show", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = null
        try {
          var list = JSON.parse(text).reminders || []
          for (var i = 0; i < list.length; i++) if (!next || list[i].at < next.at) next = list[i]
        } catch (e) {}
        root.srcReminder = next
      }
    }
  }

  // also on start, and once a minute in case a refresh call was missed
  Timer {
    interval: 60000
    repeat: true
    triggeredOnStart: true
    running: root.isLeader
    onTriggered: root.reminderCheck()
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.reminder !== null && !root.screenRecording
    onTriggered: {
      root.nowMs = Date.now()
      if (root.reminder && root.reminder.at * 1000 <= root.nowMs - 2000) root.reminderCheck()
    }
    onRunningChanged: root.nowMs = Date.now()
  }

  // =====================================================================
  // Voice assistant: the folder is watched; the marker holds the shell's pid,
  // so assistente-voz knows the notch draws its states (and sends no
  // notifications). Read through a FileView, never a command line.

  Process {
    command: ["sh", "-c", "PATH=\"$PATH:$HOME/.local/bin\"; command -v assistente-voz >/dev/null"]
    running: root.isLeader
    onExited: function(code) { root.askInstalled = code === 0 }
  }

  Process {
    id: askWatch
    command: ["setpriv", "--pdeathsig", "TERM", "sh", "-c",
      "umask 077; mkdir -p \"$1\" && chmod 700 \"$1\" || exit 1; echo $PPID > \"$1/notch.watching\"; "
      + "exec inotifywait -m -q -e close_write,moved_to --format %f \"$1\"", "sh", root.askDir]
    running: root.isLeader && root.askInstalled
    stdout: SplitParser { onRead: function(line) { if (line === "notch.json") askRead.reload() } }
    onRunningChanged: if (running) askRead.reload()
    onExited: if (root.isLeader) askWatchRetry.restart()
  }

  Timer {
    id: askWatchRetry
    interval: 15000
    onTriggered: askWatch.running = root.isLeader
  }

  FileView {
    id: askRead
    path: root.isLeader ? root.askDir + "/notch.json" : ""
    printErrors: false
    onLoaded: {
      try {
        var d = JSON.parse(text())
        root.askNow = Date.now()
        root.srcAsk = d
      } catch (e) {}
    }
  }
}
