import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "../Icons.js" as Icons
import "../Shared.js" as Shared

// Island Notch: showing, pinning, answering and dismissing notifications; what the notch
// shows (activity and view).
IslandMedia {
  id: root
  // used by the other parts of the notch
  readonly property var peekTimer: peekTimer
  readonly property var notifTimer: notifTimer

  // While dictating (or transcribing) the notch belongs to the voice: a
  // notification waits here and shows the moment dictation ends, with how
  // many more came meanwhile. Its lifetime only starts once it is shown.
  readonly property bool dictating: dictState === "recording" || dictState === "transcribing"
  // Typing in a card (correcting the last dictation, asking the assistant)
  // holds notifications the same way, so the card isn't knocked away.
  readonly property bool holdingNotifs: dictating || cardName === "ask"
  property var heldNotif: null
  property int heldExtra: 0
  onHoldingNotifsChanged: {
    if (holdingNotifs && notif) {
      // already on screen when dictation starts: it comes back afterwards
      heldNotif = notif
      heldExtra = notifExtra
      notifTimer.stop()
      notif = null
      notifPinned = false
      notifExtra = 0
    } else if (!holdingNotifs && heldNotif) {
      Qt.callLater(releaseHeld)
    }
  }
  function releaseHeld() {
    var n = heldNotif, extra = heldExtra
    heldNotif = null
    heldExtra = 0
    if (!n) return
    showNotification(n)
    notifExtra = extra
  }

  // A notice waiting on you (sticky: Claude asking for permission or an
  // answer) stays until it is answered or closed, and comes back after
  // anything that showed over it: covered ones wait here, latest last.
  property var stickyBack: []
  function keepSticky(n) {
    if (!n || !n.sticky) return
    stickyBack = dropSticky(n.uid).concat([n])
  }
  function dropSticky(uid) {
    return stickyBack.filter(function(s) { return String(s.uid) !== String(uid) })
  }

  function showNotification(n) {
    if (n.uid !== "") stickyBack = dropSticky(n.uid)
    if (holdingNotifs) {
      if (heldNotif && !(n.uid !== "" && heldNotif.uid === n.uid)) { keepSticky(heldNotif); heldExtra++ }
      heldNotif = n
      return
    }
    // the same notification updated (a new track, progress) is not a new one
    var same = notif !== null && n.uid !== "" && notif.uid === n.uid
    notifExtra = same ? notifExtra : notif !== null ? notifExtra + 1 : 0
    var pinned = same && notifPinned
    if (!same) keepSticky(notif)
    notif = n
    notifCopied = false
    notifPinned = pinned
    copiedTimer.stop()
    notifTimer.interval = n.urgent ? 20000 : n.copy ? 12000 : n.kind === "iphone" ? 9000 : 7000
    if (n.sticky) notifTimer.stop()
    else if (!pinned) notifTimer.restart()
    if (!same && !pinned) { notifPeek = true; peekTimer.restart() }
  }
  Timer {
    id: peekTimer
    interval: 3500
    onTriggered: root.notifPeek = false
  }

  function pinNotification() {
    if (!notif || notifPinned) return
    notifPeek = false
    notifPinned = true
    notifTimer.stop()
  }

  function unpinNotification() {
    if (!notifPinned) return
    notifPinned = false
    hoverExpanded = false
    if (notif && !notif.sticky) { notifTimer.interval = 3500; notifTimer.restart() }
  }

  // What the main button of a pinned notification says, from its action.
  readonly property string notifActionLabel: {
    var n = notif
    if (!n) return ""
    if (n.openLabel) return n.openLabel
    var open = n.open || []
    var last = open.length ? String(open[open.length - 1]) : ""
    if (last === "default") return tr(n.kind === "iphone" ? "RESPONDER" : "ABRIR")
    if (last === "open-app") return tr("ABRIR APP")
    if (last === "toggle") return tr("ABRIR IPHONE")
    return tr("ABRIR")
  }

  // Reply typed in a pinned notification (NotificationService.qml passes it to
  // the sender as an inline reply). The text never goes in a process's
  // arguments, which other accounts can read: it goes through stdin into a
  // private file under $XDG_RUNTIME_DIR, and only that path is passed on.
  property bool replySent: false
  property bool replyFailed: false
  function sendReply(text) {
    var t = String(text || "").trim()
    if (!t || !notif || replySent) return
    replyProc.command = ["sh", "-c",
      "umask 077; d=\"${XDG_RUNTIME_DIR:?}/island-notch\"; mkdir -p \"$d\" && chmod 700 \"$d\" || exit 1; "
      + "f=$(mktemp \"$d/reply.XXXXXX\") || exit 1; cat > \"$f\"; "
      + "r=$(omarchy-shell notifications replyFile \"$1\" \"$f\"); rm -f \"$f\"; printf '%s' \"$r\"",
      "island-reply", String(notif.uid || "")]
    replyText = t
    replyProc.stdinEnabled = true
    replyProc.running = true
  }
  property string replyText: ""
  Process {
    id: replyProc
    onStarted: { write(root.replyText); stdinEnabled = false; root.replyText = "" }
    stdout: StdioCollector {
      onStreamFinished: {
        var ok = String(text || "").trim() === "ok"
        root.replySent = ok
        root.replyFailed = !ok
        // "ENVIADO" for a moment, then the notification folds away
        if (ok) { notifTimer.stop(); copiedTimer.restart() }
      }
    }
  }

  // Clipboard writes go through wl-copy's stdin: an argument would show the
  // text to any account that can read process command lines.
  property string clipboardText: ""
  function copyText(text) {
    clipboardText = String(text || "")
    clipboardProc.stdinEnabled = true
    clipboardProc.running = true
  }
  Process {
    id: clipboardProc
    command: ["wl-copy"]
    onStarted: { write(root.clipboardText); stdinEnabled = false; root.clipboardText = "" }
  }

  function copyNotification() {
    if (!notif || !notif.copy) return
    copyText(notif.copy)
    notifCopied = true
    notifTimer.stop()
    copiedTimer.restart()
  }

  Timer {
    id: copiedTimer
    interval: 1500
    onTriggered: root.dismissNotification()
  }

  function dismissNotification() {
    var back = stickyBack.length ? stickyBack[stickyBack.length - 1] : null
    if (back) stickyBack = stickyBack.slice(0, -1)
    notifTimer.stop()
    notif = null
    notifPinned = false
    notifExtra = 0
    if (activity !== "media") hoverExpanded = false
    if (back) Qt.callLater(function() { root.showNotification(back) })
  }

  function focusNotificationApp() {
    var n = notif
    dismissNotification()
    if (!n) return
    // Through ~/.local/bin/hugo-present-after when it exists (the window it
    // lands on arrives animated), else straight.
    var present = ["sh", "-c", 'p="$HOME/.local/bin/hugo-present-after"; if [ -x "$p" ]; then exec "$p" "$@"; else exec "$@"; fi', "sh"]
    if (n.open && n.open.length > 0) {
      Quickshell.execDetached(present.concat(n.open))
      return
    }
    var app = n.desktopEntry || n.app
    if (!app) return
    Quickshell.execDetached(present.concat([Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-hyprland-focus-app", String(app)]))
  }

  // ~3 s on screen; hovering holds it, leaving gives it a moment more.
  Timer {
    id: notifTimer
    interval: 3200
    onTriggered: { if (root.hovered || root.notifPinned) return; root.dismissNotification() }
  }

  // Same lookup as the notification cards: a path or URL as is, a themed
  // icon only if it exists, then the app's .desktop icon; "" = draw a bell.
  function resolveIcon(name) {
    var value = String(name || "")
    if (value === "") return ""
    if (value.indexOf("image://icon/") === 0) value = value.slice(13)
    else if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return "file://" + value
    return Quickshell.iconPath(value, true)
  }

  readonly property string notifIcon: {
    var n = shownNotif
    if (!n) return ""
    var direct = resolveIcon(n.icon)
    if (direct) return direct
    void DesktopEntries.applications.values
    var candidates = [n.desktopEntry, n.app, String(n.app || "").toLowerCase()]
    for (var i = 0; i < candidates.length; i++) {
      if (!candidates[i]) continue
      var entry = DesktopEntries.heuristicLookup(candidates[i])
      if (entry && entry.icon) {
        var path = resolveIcon(entry.icon)
        if (path) return path
      }
    }
    return ""
  }

  readonly property string notifAppName: {
    var n = shownNotif
    if (!n) return ""
    var value = String(n.app || "")
    if (value === "notify-send" || value === "omarchy-action" || value === "") return "Omarchy"
    if (n.kind === "iphone") return value
    var entry = DesktopEntries.heuristicLookup(value)
    if (entry && entry.name) return entry.name
    // "foot" → "Foot", but a name that already has capitals ("iPhone") stays
    return /[A-Z]/.test(value) ? value : value.charAt(0).toUpperCase() + value.slice(1)
  }

  function plain(text) {
    return String(text || "").replace(/<[^>]*>/g, "").replace(/&amp;/g, "&").replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&#39;/g, "'").replace(/\s+/g, " ").trim()
  }

  // ---- what the notch shows
  readonly property string activity: !isHost ? "idle"
    : dictState === "recording" ? "dictation"
    : dictState === "transcribing" ? "transcribing"
    : askState !== "" ? "ask"
    : hudActive ? "hud"
    : notifActive ? "notif"
    : screenRecording ? "screen"
    // music playing goes over Claude at work (its notifications still win)
    : claudeActive && !mediaActive ? "claude"
    : reminder ? "reminder"
    : mediaActive ? "media" : "idle"

  // ---- hover / cards
  property string cardName: ""
  property bool hovered: false
  property bool hoverExpanded: false
  property real grabClosedAt: 0
  property string grabClosedName: ""
  readonly property bool expandable: activity === "media" || activity === "screen" || activity === "notif" || activity === "claude"
  // compact page key, expanded page key or "card"
  readonly property string view: cardName !== "" ? "card"
    : activity === "ask" ? (askState === "answer" ? "askAnswer" : askState === "thinking" ? "askThink" : askState === "missed" ? "askMissed" : "askListen")
    : activity === "notif" ? (notifWide ? (notifOpen ? "iphone" : "iphoneMini") : (notifOpen ? "notifX" : "notif"))
    : ((hoverExpanded && expandable) || (activity === "media" && mediaPinned)) ? activity + "X"
    : activity
}
