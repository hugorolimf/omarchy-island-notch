import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "../Icons.js" as Icons
import "../Shared.js" as Shared

// Island Notch: Claude Code sessions, notification delivery and the IPC.
IslandWatch {
  id: root
  // used by the other parts of the notch
  readonly property var claudeWatch: claudeWatch

  // =====================================================================
  // Claude Code: claude-hook.py writes $XDG_RUNTIME_DIR/island-notch/claude/
  // <session>.json on every step; inotify tells the leader when to read the
  // folder again. Everything goes through those private files, nothing
  // through a command line.

  function claudeScan() {
    if (!isLeader) return
    claudeKick.restart()
  }

  Process {
    id: claudeWatch
    command: ["setpriv", "--pdeathsig", "TERM", "sh", "-c",
      "umask 077; mkdir -p \"$1\" || exit 1; exec inotifywait -m -q -e close_write,moved_to,delete \"$1\"", "sh", root.claudeDir]
    running: root.isLeader
    stdout: SplitParser { onRead: function(line) { root.claudeScan() } }
    onRunningChanged: if (running) root.claudeScan()
    onExited: if (root.isLeader) claudeWatchRetry.restart()
  }

  Timer {
    id: claudeWatchRetry
    interval: 15000
    onTriggered: claudeWatch.running = root.isLeader
  }

  // Bursts of steps are read once.
  Timer {
    id: claudeKick
    interval: 120
    onTriggered: {
      if (claudeRead.running) { restart(); return }
      claudeRead.running = true
    }
  }

  // One line per session: "<interrupted>\t<json>". A session whose Claude
  // process is gone is removed; one that is busy but whose transcript ends
  // on "[Request interrupted by user]" (Esc sends no hook) reads as idle.
  Process {
    id: claudeRead
    command: ["sh", "-c",
      "cd \"$1\" 2>/dev/null || exit 0\n" +
      "for f in *.json; do\n" +
      "  [ -f \"$f\" ] || continue\n" +
      "  s=$(head -c 32768 -- \"$f\")\n" +
      "  pid=${s#*\\\"pid\\\":}; pid=${pid%%[!0-9]*}\n" +
      "  if [ -n \"$pid\" ] && [ \"$pid\" != 0 ] && [ ! -d \"/proc/$pid\" ]; then rm -f -- \"$f\" \"${f%.json}.notif\"; continue; fi\n" +
      "  stop=0\n" +
      "  case $s in *'\"state\":\"working\"'*|*'\"state\":\"waiting\"'*)\n" +
      "    t=${s#*\\\"transcript\\\":\\\"}\n" +
      "    if [ \"$t\" != \"$s\" ]; then t=${t%%\\\"*}\n" +
      "      [ -f \"$t\" ] && tail -c 65536 -- \"$t\" | grep -E '\"type\":\"(user|assistant)\"' | tail -n 1 | grep -q 'Request interrupted by user' && stop=1\n" +
      "    fi ;;\n" +
      "  esac\n" +
      "  printf '%s\\t%s\\n' \"$stop\" \"$s\"\n" +
      "done", "sh", root.claudeDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseClaude(text)
    }
  }

  function parseClaude(text) {
    var list = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var tab = lines[i].indexOf("\t")
      if (tab < 0) continue
      try {
        var s = JSON.parse(lines[i].slice(tab + 1))
        if (!s || typeof s !== "object" || !s.id) continue
        if (lines[i].slice(0, tab) === "1") s.state = "idle"
        list.push(s)
      } catch (e) {}
    }
    if (JSON.stringify(list) !== JSON.stringify(srcClaudeSessions)) srcClaudeSessions = list
  }

  // Also on start, and now and then: a session that died without a word,
  // an Esc in the middle of a step.
  Timer {
    interval: root.srcClaudeSessions.length > 0 ? 10000 : 60000
    repeat: true
    running: root.isLeader
    onTriggered: root.claudeScan()
  }

  // "Pronto" stays a few seconds, then the activity folds away.
  Timer {
    interval: 500
    repeat: true
    running: root.claudeSessions.length > 0
    onTriggered: root.claudeNow = Date.now()
    onRunningChanged: root.claudeNow = Date.now()
  }
  onClaudeSessionsChanged: Qt.callLater(function() { root.claudeNow = Date.now() })  // not from inside claudeLive's own update

  // The session's terminal, as claude-notch-notify does it: its tmux pane
  // (window and pane selected, then the window of a client attached to that
  // session), or up the process tree from Claude to a window Hyprland knows.
  function focusClaude() {
    var s = shownClaude
    hoverExpanded = false
    if (!s) return
    var present = ["sh", "-c", 'p="$HOME/.local/bin/hugo-present-after"; if [ -x "$p" ]; then exec "$p" "$@"; else exec "$@"; fi', "sh"]
    Quickshell.execDetached(present.concat(["bash", "-c",
      "pid=$1 pane=$2 sock=$3\n" +
      "clients=$(hyprctl clients -j 2>/dev/null) || exit 0\n" +
      "win_of() { jq -r --argjson p \"$1\" '.[] | select(.pid == $p) | .address' <<<\"$clients\" | head -1; }\n" +
      "find_win() { local p=$1 a; for _ in $(seq 1 20); do [ -n \"$p\" ] && [ \"$p\" -gt 1 ] 2>/dev/null || return; a=$(win_of \"$p\"); [ -n \"$a\" ] && { echo \"$a\"; return; }; p=$(ps -o ppid= -p \"$p\" 2>/dev/null | tr -d ' '); done; }\n" +
      "addr=\n" +
      "if [ -n \"$pane\" ]; then\n" +
      "  T=(tmux); [ -n \"$sock\" ] && T=(tmux -S \"$sock\")\n" +
      "  \"${T[@]}\" select-window -t \"$pane\" 2>/dev/null; \"${T[@]}\" select-pane -t \"$pane\" 2>/dev/null\n" +
      "  sess=$(\"${T[@]}\" display -p -t \"$pane\" '#{session_name}' 2>/dev/null)\n" +
      "  for c in $(\"${T[@]}\" list-clients -t \"$sess\" -F '#{client_pid}' 2>/dev/null); do addr=$(find_win \"$c\"); [ -n \"$addr\" ] && break; done\n" +
      "fi\n" +
      "[ -n \"$addr\" ] || addr=$(find_win \"$pid\")\n" +
      "[ -n \"$addr\" ] && hyprctl dispatch \"hl.dsp.focus({ window = \\\"address:$addr\\\" })\" >/dev/null",
      "bash", String(s.pid || 0), String(s.tmuxPane || ""), String(s.tmuxSocket || "")]))
  }

  // A notification for the notch on the focused monitor: from the `notify` IPC
  // (scripts, claude-hook.py) or, in process, from NotificationService.qml
  // (through Shared.leaderItem()).
  function deliverNotification(n) {
    var items = root.bar && typeof root.bar.moduleWidgets === "function" ? root.bar.moduleWidgets(root.moduleName) : [root]
    if (!items || items.length === 0) items = [root]
    var focused = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    var target = items[0]
    for (var j = 0; j < items.length; j++) if (items[j] && items[j].screenName === focused) target = items[j]
    target.showNotification({
      app: String(n.app || ""),
      title: root.plain(n.title),
      body: root.plain(n.body),
      icon: String(n.icon || ""),
      desktopEntry: String(n.desktopEntry || ""),
      copy: n.copy === undefined || n.copy === null ? "" : String(n.copy),
      open: Array.isArray(n.open) ? n.open.map(function(a) { return String(a) }) : null,
      kind: String(n.kind || ""),
      uid: String(n.uid || ""),
      urgent: n.urgent === true,
      sticky: n.sticky === true,
      openLabel: String(n.openLabel || ""),
      reply: n.reply === true,
      replyHint: String(n.replyHint || ""),
      actions: Array.isArray(n.actions) ? n.actions.filter(function(a) { return a && a.label && Array.isArray(a.open) }).slice(0, 2)
        .map(function(a) { return { label: String(a.label), open: a.open.map(function(x) { return String(x) }) } }) : []
    })
    return "ok"
  }

  // Super+, (dismissOne) and Super+Shift+, (dismissAll), through this
  // plugin's notification server (NotificationService.qml).
  function dismissNotifications(one) {
    var items = root.bar && typeof root.bar.moduleWidgets === "function" ? root.bar.moduleWidgets(root.moduleName) : [root]
    if (!items || items.length === 0) items = [root]
    for (var i = 0; i < items.length; i++) {
      if (!items[i] || !items[i].notif) continue
      items[i].dismissNotification()
      if (one) return
    }
  }

  // =====================================================================
  // IPC: omarchy-shell io.github.hugorolimf.island card weather | card close

  IpcHandler {
    target: "io.github.hugorolimf.island"

    // omarchy-shell io.github.hugorolimf.island notify '{"app":..,"title":..,"body":..,"icon":..,"desktopEntry":..}'
    function notify(json: string): string {
      var n
      try { n = JSON.parse(json) } catch (e) { return "bad json" }
      if (!n || typeof n !== "object") return "bad json"
      return root.deliverNotification(n)
    }

    // omarchy-shell io.github.hugorolimf.island hud '{"key":"volume","value":0.4}' ("{}" hides)
    function hud(json: string): string {
      var h
      try { h = JSON.parse(json) } catch (e) { return "bad json" }
      var items = root.bar && typeof root.bar.moduleWidgets === "function" ? root.bar.moduleWidgets(root.moduleName) : [root]
      if (!items || items.length === 0) items = [root]
      var focused = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
      for (var i = 0; i < items.length; i++) if (items[i]) items[i].showHud(items[i].screenName === focused || items.length === 1 ? h : {})
      return "ok"
    }

    // Tab while a notification is up (bound only then): pin it for the
    // keyboard. An assistant's answer on screen (it hides notifications)
    // opens the conversation instead.
    function pinKeys(): string {
      var items = root.bar && typeof root.bar.moduleWidgets === "function" ? root.bar.moduleWidgets(root.moduleName) : [root]
      if (!items || items.length === 0) items = [root]
      for (var c = 0; c < items.length; c++) if (items[c] && items[c].cardName === "ask" && items[c].cardPassive) { items[c].activateCard(); return "ask" }
      for (var j = 0; j < items.length; j++) if (items[j] && items[j].activity === "ask") { items[j].openCard("ask"); return "ask" }
      for (var i = 0; i < items.length; i++) if (items[i] && items[i].notif) { items[i].pinNotificationByKeys(); return "ok" }
      return "none"
    }

    // Pin the notification on screen (as a click on it does).
    function pin(): string {
      var items = root.bar && typeof root.bar.moduleWidgets === "function" ? root.bar.moduleWidgets(root.moduleName) : [root]
      if (!items || items.length === 0) items = [root]
      for (var i = 0; i < items.length; i++) if (items[i] && items[i].notif) { items[i].pinNotification(); return "ok" }
      for (var j = 0; j < items.length; j++) if (items[j] && items[j].activity === "media") { items[j].mediaPinned = true; return "media" }
      return "none"
    }

    function dismiss(): string {
      var items = root.bar && typeof root.bar.moduleWidgets === "function" ? root.bar.moduleWidgets(root.moduleName) : [root]
      if (!items || items.length === 0) items = [root]
      for (var i = 0; i < items.length; i++) {
        if (!items[i]) continue
        if (items[i].notif) items[i].dismissNotification()
        items[i].mediaPinned = false
        items[i].hoverExpanded = false
      }
      return "ok"
    }

    // A notification its sender took back (claude-hook.py: a "needs your
    // permission" already answered in the terminal) leaves the notch.
    function retract(uid: string): string {
      var items = root.bar && typeof root.bar.moduleWidgets === "function" ? root.bar.moduleWidgets(root.moduleName) : [root]
      if (!items || items.length === 0) items = [root]
      var hit = false
      for (var i = 0; i < items.length; i++) {
        var kept = items[i] ? items[i].dropSticky(uid) : []
        if (items[i] && kept.length !== items[i].stickyBack.length) { items[i].stickyBack = kept; hit = true }
        if (items[i] && items[i].notif && String(items[i].notif.uid) === String(uid)) { items[i].dismissNotification(); hit = true }
      }
      return hit ? "ok" : "none"
    }

    function card(name: string): string {
      var items = root.bar && typeof root.bar.moduleWidgets === "function" ? root.bar.moduleWidgets(root.moduleName) : [root]
      if (!items || items.length === 0) items = [root]
      if (name === "close") {
        for (var i = 0; i < items.length; i++) if (items[i] && items[i].closeCard) items[i].closeCard()
        return "closed"
      }
      var focused = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
      var target = null
      for (var j = 0; j < items.length; j++) if (items[j] && items[j].screenName === focused) target = items[j]
      if (!target) target = items[0]
      for (var k = 0; k < items.length; k++) if (items[k] !== target && items[k].closeCard) items[k].closeCard()
      return target.toggleCard(name)
    }
  }

  // =====================================================================
  // Shared pieces (all sizes already in real pixels)
}
