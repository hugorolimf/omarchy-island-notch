import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Ui
import "Icons.js" as Icons
import "Shared.js" as Shared

// Dynamic Island for the bar center, in the anatomy language (thin mono
// strokes, colour only for state, one easing curve for every transition).
//
// Shaped like a MacBook notch: flat top flush with the screen edge, concave
// ears blending into the bar, rounded bottom. Idle it does not exist (zero
// width); when something is live — dictation, screen recording, media — it
// sprouts down from the edge, a few px below the bar, and grows further for
// hover details or on-demand cards (weather). It shows on the focused
// monitor only; one leader instance runs the status processes for all.
//
// The notch is drawn on its own layer surface on top of the bar, mapped only
// while it is visible, with input limited to the notch body. The bar slot
// only reserves the notch's width; it draws nothing.
BarWidget {
  id: root
  moduleName: "io.github.hugorolimf.island"
  // Portuguese, or English for every other locale.
  readonly property bool portuguese: Qt.locale().name.indexOf("pt") === 0
  readonly property var enText: ({"RESPONDER": "REPLY", "ABRIR": "OPEN", "ABRIR APP": "OPEN APP", "ABRIR IPHONE": "OPEN IPHONE", "FECHAR": "CLOSE", "COPIADO": "COPIED", "COPIAR": "COPY", "Gravando": "Recording", "Transcrevendo…": "Transcribing…", "Ditando…": "Dictating…", "Responder…": "Reply…", "GRAVANDO TELA": "RECORDING SCREEN", "PARAR": "STOP", "  ·  agora": "  ·  now", "Lembrete": "Reminder", "Ouvindo…": "Listening…", "Pensando…": "Thinking…", "Não entendi": "Didn't catch that", "Assistente": "Assistant", "Você: ": "You: ", "clique para abrir a conversa": "click to open the conversation",
    "Pensando…": "Thinking…", "Esperando você": "Waiting for you", "Pronto": "Done", "Trabalhando": "Working",
    "Edita": "Edits", "Escreve": "Writes", "Lê": "Reads", "Roda:": "Runs:", "Busca": "Searches", "Procura": "Finds",
    "Delega:": "Delegates:", "Abre": "Opens", "Pesquisa": "Looks up", "Atualiza as tarefas": "Updates the to-dos",
    "Pergunta para você": "Asks you", "Mostra o plano": "Shows the plan", "Usa a skill": "Uses the skill",
    "Agente terminou:": "Agent done:", "Usa": "Uses"})
  function tr(text) { return portuguese || enText[text] === undefined ? text : enText[text] }

  // ---- anatomy tokens
  readonly property string monoFont: "JetBrainsMono Nerd Font"
  readonly property string sansFont: "Adwaita Sans"
  readonly property color plate: "#000000"
  readonly property color strong: "#e6e6e6"
  readonly property color muted: "#6e6e6e"
  readonly property color hi: "#d4d4d4"
  readonly property color faint: "#2a2a2a"
  readonly property color red: "#ff6b6b"
  readonly property color blue: "#6b9bff"
  readonly property color amber: "#f5b84a"
  readonly property color green: "#6be0a0"
  readonly property var ease: [0.32, 0.72, 0, 1, 1, 1]
  readonly property int morphMs: 550
  readonly property int fadeMs: 250

  // ---- one island for the whole shell
  property var leader: null
  readonly property bool isLeader: leader === root
  readonly property string focusedMonitor: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
  readonly property string screenName: QsWindow.window && QsWindow.window.screen ? QsWindow.window.screen.name : ""
  readonly property bool isHost: screenName !== "" && screenName === focusedMonitor

  // ---- dictation (voxtype status stream, event driven; written on the leader)
  property string srcDictState: "idle"
  property string srcDictModel: ""
  property string srcDictBackend: ""
  readonly property string dictState: leader ? leader.srcDictState : "idle"
  readonly property string dictModel: leader ? leader.srcDictModel : ""
  readonly property string dictBackend: leader ? leader.srcDictBackend : ""

  // ---- live microphone level while dictating (PipeWire peak meter; off otherwise)
  readonly property bool listening: activity === "dictation" || view === "askListen"
  property var micHistory: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

  PwObjectTracker { objects: root.listening && Pipewire.defaultAudioSource ? [Pipewire.defaultAudioSource] : [] }

  PwNodePeakMonitor {
    id: micPeak
    node: Pipewire.defaultAudioSource
    enabled: root.listening
  }

  // Levels follow the voice, calibrated on real dictation (mic-peaks log,
  // 2026-10-29): the meter's peak sits around 0.42–0.47 in silence, 0.6–0.95
  // when speaking and clips at 1.0 on loud syllables. A fixed scale saturated,
  // so each tick is placed between a moving noise floor (p10 of the last 4 s)
  // and a moving speech level (p90 of the last 2 s); below 15 % of that span
  // is treated as noise, the rest goes through a square root. Result on the
  // recording: silence ≈ 8 %, speech ≈ 65 %, only clipped peaks reach 100 %.
  property var micWindow: []

  function percentile(list, p) {
    var sorted = list.slice().sort(function(a, b) { return a - b })
    return sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))]
  }

  // Newest level first; each bar shows a different instant of this history.
  Timer {
    interval: 40
    repeat: true
    running: root.listening
    onTriggered: {
      var x = Math.max(0, micPeak.peak)
      var win = root.micWindow
      win.push(x)
      if (win.length > 100) win.shift()
      var floor = root.percentile(win, 0.1)
      var top = Math.max(floor + 0.15, root.percentile(win.slice(-50), 0.9))
      var t = Math.max(0, ((x - floor) / (top - floor) - 0.15) / 0.85)
      var level = Math.min(1, 0.06 + 0.74 * Math.sqrt(t))
      root.micHistory = [level].concat(root.micHistory.slice(0, 12))
    }
    onRunningChanged: if (!running) { root.micHistory = root.quietHistory(); root.micWindow = [] }
  }

  function quietHistory() {
    var h = []
    for (var i = 0; i < 13; i++) h.push(0)
    return h
  }

  // ---- screen recording (inotify on the recorder's marker file + 1 s check while live)
  property bool srcScreenRecording: false
  property real srcScreenStartMs: 0
  readonly property bool screenRecording: leader ? leader.srcScreenRecording : false
  readonly property real screenStartMs: leader ? leader.srcScreenStartMs : 0
  property real nowMs: Date.now()
  readonly property string screenElapsed: screenStartMs > 0 ? formatClock(Math.max(0, (nowMs - screenStartMs) / 1000)) : "00:00"

  // ---- reminders (omarchy-reminder; the nearest one counts down in the notch)
  property var srcReminder: null
  readonly property var reminder: leader ? leader.srcReminder : null
  readonly property string reminderLeft: reminder ? formatClock(Math.max(0, reminder.at - nowMs / 1000)) : ""

  // ---- Claude Code sessions: claude-hook.py keeps one private file per
  // session in $XDG_RUNTIME_DIR/island-notch/claude/ (state, the last steps,
  // title, project, how to reach its terminal); the leader watches the folder.
  // The most recently active session shows, the others count as "+N"; the
  // one on screen stays while it moved in the last 10 s, so two busy sessions
  // don't take turns at every step.
  // ---- voice assistant (F10): ~/Projects/ferramentas/assistente writes its
  // state to $XDG_RUNTIME_DIR/assistente/notch.json (listening, thinking,
  // missed, answer); only the leader watches it. Drawn like dictation.
  readonly property string askDir: Quickshell.env("XDG_RUNTIME_DIR") + "/assistente"
  property var srcAsk: null
  readonly property var ask: leader ? leader.srcAsk : null
  property real askNow: Date.now()
  property real askDismissedTs: 0
  property bool askHold: false
  readonly property int askAnswerMs: ask ? Math.min(30000, Math.max(9000, String(ask.answer || "").length * 70)) : 0
  readonly property string askState: {
    var a = ask
    if (!a || a.ts === askDismissedTs) return ""
    var age = askNow - a.ts
    if (a.state === "listening") return age < 100000 ? "listening" : ""
    if (a.state === "thinking") return age < 300000 ? "thinking" : ""
    if (a.state === "missed") return age < 2500 ? "missed" : ""
    if (a.state === "answer") return (askHold || age < askAnswerMs) ? "answer" : ""
    return ""
  }
  Timer {
    interval: 400
    repeat: true
    running: root.askState !== ""
    onTriggered: root.askNow = Date.now()
  }
  function dismissAsk() { if (ask) askDismissedTs = ask.ts; askHold = false }
  function openAsk() {
    var uri = ask ? String(ask.open || "") : ""
    dismissAsk()
    if (uri.indexOf("obsidian://") === 0) Quickshell.execDetached(["xdg-open", uri])
  }

  readonly property string claudeDir: Quickshell.env("XDG_RUNTIME_DIR") + "/island-notch/claude"
  property var srcClaudeSessions: []
  readonly property var claudeSessions: leader ? leader.srcClaudeSessions : []
  readonly property int claudeDoneMs: 4500
  property real claudeNow: Date.now()
  readonly property var claudeLive: {
    var now = claudeNow
    return claudeSessions.filter(function(s) {
      if (now - (s.updated || 0) > 6 * 3600000) return false  // left behind
      return s.state === "working" || s.state === "waiting" || (s.state === "done" && now - (s.doneAt || 0) < claudeDoneMs)
    }).sort(function(a, b) { return (b.updated || 0) - (a.updated || 0) })
  }
  property string claudeStickyId: ""
  readonly property var claudeSession: {
    var live = claudeLive
    if (live.length === 0) return null
    for (var i = 0; i < live.length; i++) {
      var s = live[i]
      if (s.id === claudeStickyId && claudeNow - (s.updated || 0) < 10000) return s
    }
    return live[0]
  }
  readonly property bool claudeActive: claudeSession !== null
  readonly property int claudeExtra: Math.max(0, claudeLive.length - 1)
  // What the notch draws: kept while the activity folds away.
  property var shownClaude: null
  onClaudeSessionChanged: {
    if (!claudeSession) return
    shownClaude = claudeSession
    var id = String(claudeSession.id)
    Qt.callLater(function() { root.claudeStickyId = id })  // not from inside the binding's own update
  }
  readonly property string claudeState: shownClaude ? String(shownClaude.state) : ""
  readonly property var claudeSteps: shownClaude && Array.isArray(shownClaude.steps) ? shownClaude.steps : []
  readonly property string claudeTitle: shownClaude ? String(shownClaude.title || shownClaude.project || "Claude") : ""
  // tool → verb; the hook keeps only the tool and a short target
  readonly property var claudeVerbs: ({ "Edit": "Edita", "MultiEdit": "Edita", "NotebookEdit": "Edita", "Write": "Escreve",
    "Read": "Lê", "Bash": "Roda:", "Grep": "Busca", "Glob": "Procura", "Task": "Delega:", "Agent": "Delega:",
    "WebFetch": "Abre", "WebSearch": "Pesquisa", "TodoWrite": "Atualiza as tarefas", "AskUserQuestion": "Pergunta para você",
    "ExitPlanMode": "Mostra o plano", "Skill": "Usa a skill", "_subagentDone": "Agente terminou:" })
  function claudeStep(st) {
    if (!st) return ""
    var verb = claudeVerbs[st.tool]
    var target = String(st.target || "")
    var head = verb === undefined ? tr("Usa") + " " + String(st.tool || "") : tr(verb)
    return head + (target ? " " + target : "")
  }
  readonly property string claudeLine: claudeState === "waiting" ? tr("Esperando você")
    : claudeState === "done" ? tr("Pronto") + " · " + claudeTitle
    : claudeSteps.length > 0 ? claudeStep(claudeSteps[claudeSteps.length - 1]) : tr("Pensando…")

  // ---- media (MPRIS, signal driven)
  readonly property var players: Mpris.players ? Mpris.players.values : []
  property string lastPlayingKey: ""
  property bool pauseLinger: false
  readonly property var player: pickPlayer(players, lastPlayingKey)
  readonly property bool playing: player ? player.isPlaying : false
  readonly property string title: player ? (player.trackTitle || "") : ""
  readonly property string artist: player ? (player.trackArtist || "") : ""
  readonly property string artUrl: player && player.trackArtUrl ? player.trackArtUrl : ""
  readonly property real trackLength: player && player.lengthSupported ? Math.max(0, player.length) : 0
  property real trackPos: 0
  readonly property real progress: trackLength > 0 ? Math.max(0, Math.min(1, trackPos / trackLength)) : 0
  readonly property bool mediaActive: player !== null && title !== "" && (playing || pauseLinger || hoverExpanded || mediaPinned)
  // A click on the compact player pins it expanded until a click elsewhere.
  property bool mediaPinned: false

  // ---- equalizer: the bars follow what the speakers actually play (peak
  // meter on the default output), normalised to the last few seconds so
  // quiet and loud tracks both move; flat while paused.
  readonly property bool eqLive: activity === "media" && playing && overlay.visible
  PwObjectTracker { objects: root.eqLive && Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : [] }
  PwNodePeakMonitor {
    id: sinkPeak
    node: Pipewire.defaultAudioSink
    enabled: root.eqLive
  }
  property var eqLevels: [0.15, 0.15, 0.15, 0.15, 0.15]
  property var eqWindow: []
  Timer {
    interval: 70
    repeat: true
    running: root.eqLive
    onTriggered: {
      var x = Math.max(0, sinkPeak.peak)
      var win = root.eqWindow
      win.push(x)
      if (win.length > 45) win.shift()
      // between the quiet parts (p25) and the peaks (p98) of the last ~3 s
      var floor = root.percentile(win, 0.25)
      var top = Math.max(floor + 0.04, root.percentile(win, 0.98))
      var level = Math.max(0, Math.min(1, (x - floor) / (top - floor)))
      var out = []
      for (var i = 0; i < 5; i++) {
        var target = 0.28 + 0.72 * Math.sqrt(level) * (0.5 + Math.random() * 0.5)
        out.push(root.eqLevels[i] * 0.35 + target * 0.65)
      }
      root.eqLevels = out
    }
    onRunningChanged: if (!running) { root.eqLevels = [0.15, 0.15, 0.15, 0.15, 0.15]; root.eqWindow = [] }
  }

  // ---- the album's colour (for the bars), averaged from the cover with a
  // bias to its most saturated pixels, then lifted to read on black.
  property color artColor: hi
  Canvas {
    id: artSampler
    width: 12
    height: 12
    visible: false
    renderStrategy: Canvas.Cooperative
    property string src: root.artUrl
    onSrcChanged: { root.artColor = root.hi; if (src !== "") loadImage(src) }
    onImageLoaded: requestPaint()
    onPaint: {
      if (src === "" || !isImageLoaded(src)) return
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, 12, 12)
      ctx.drawImage(src, 0, 0, 12, 12)
      var d = ctx.getImageData(0, 0, 12, 12).data
      var r = 0, g = 0, b = 0, w = 0
      for (var i = 0; i < d.length; i += 4) {
        var mx = Math.max(d[i], d[i + 1], d[i + 2]), mn = Math.min(d[i], d[i + 1], d[i + 2])
        var sat = mx === 0 ? 0 : (mx - mn) / mx
        var weight = 0.05 + sat * sat * (mx / 255)
        r += d[i] * weight; g += d[i + 1] * weight; b += d[i + 2] * weight; w += weight
      }
      if (w <= 0) return
      var c = Qt.rgba(r / w / 255, g / w / 255, b / w / 255, 1)
      root.artColor = Qt.hsla(c.hslHue < 0 ? 0 : c.hslHue, Math.max(0.55, c.hslSaturation), 0.64, 1)
    }
  }

  // ---- notifications: a short pulse for each notification (Glass
  // Notifications calls `io.github.hugorolimf.island notify <json>`). The latest one is shown; earlier
  // ones that arrived while it was up only add to the "+N" count.
  property var notif: null
  property int notifExtra: 0
  readonly property bool notifActive: notif !== null
  // Every notification uses the macOS-like card and its mini form.
  readonly property bool notifWide: shownNotif !== null
  readonly property bool shownIphone: shownNotif !== null && shownNotif.kind === "iphone"
  // iPhone: the app's own icon (cached); others: the notification's image or
  // the app's icon; with none, a stroke glyph.
  // Claude's own notifications (and the voice assistant's) carry its mark,
  // drawn as the bar draws it, in Claude's orange, instead of an image.
  readonly property color claudeOrange: "#D97757"
  readonly property bool cardClaude: shownNotif !== null
    && /^(claude|claude code|assistente)$/i.test(String(shownNotif.app || ""))
  readonly property string cardIcon: cardClaude ? "" : shownIphone ? iphoneIcon : notifIcon
  readonly property string cardGlyph: shownIphone ? Icons.phone
    : shownNotif && shownNotif.kind === "message" ? Icons.message : Icons.bell
  // The iPhone app's own icon, fetched once by Island iPhone (app-icon.sh).
  // The first notification of a new app can beat the download: retried.
  readonly property string iphoneIconDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/island-iphone/icons/"
  property string iphoneIcon: ""
  property int iphoneIconTries: 0
  function loadIphoneIcon() {
    iphoneIcon = ""
    // read it directly: notifWide may not have caught up in the handler
    var n = shownNotif
    if (!n || n.kind !== "iphone") return
    iphoneIcon = "file://" + iphoneIconDir + encodeURIComponent(String(n.app).replace(/\//g, "_")) + ".png"
  }
  // What the notch draws: the last notification, kept while it folds away
  // so its text leaves with the closing animation instead of blanking first.
  property var shownNotif: null
  onNotifChanged: {
    if (!notif) { notifPeek = false; peekTimer.stop() }
    if (notif) shownNotif = notif
    replySent = false
    replyFailed = false
    if (tabWanted) setTabBind(true)  // re-arms the 30 s guard for a new one
  }
  onShownNotifChanged: { iphoneIconTries = 0; loadIphoneIcon() }
  Timer {
    id: iphoneIconRetry
    interval: 1200
    onTriggered: { root.iphoneIconTries++; root.loadIphoneIcon() }
  }

  // Optional extras: `copy` (text behind a COPIAR button — codes stay up
  // longer), `open` (argv run on click instead of focusing the app) and
  // `kind` ("message" draws a speech bubble when there is no icon).
  property bool notifCopied: false

  // A notification arrives in its mini form; hovering expands it, leaving
  // folds it back. A click pins it expanded, with its actions, until a click
  // elsewhere (the same focus grab as the cards) or Esc. Its lifetime waits
  // while it is hovered or pinned.
  property bool notifPinned: false
  // as shownNotif: the buttons stay while a pinned notification folds away
  property bool shownPinned: false
  onNotifPinnedChanged: {
    if (notif) shownPinned = notifPinned
    if (!notifPinned) notifKeys = false
  }
  // A new notification arrives in the big card, long enough to read, then
  // folds to its one-line form; hover or a click open the card again.
  property bool notifPeek: false
  readonly property bool notifOpen: notifPinned || notifPeek || (hoverExpanded && activity === "notif")

  // Keyboard: while a notification is up, Tab opens it as a click does (Tab
  // is bound in Hyprland only meanwhile; the rest of the time it is the
  // apps') and Tab again folds it back, as Esc. Open, the arrows walk its
  // buttons, ↑ from the first one goes to the reply field and ↓ back, Enter
  // acts on the selected one.
  property bool notifKeys: false        // the selection ring shows
  property bool notifReplyFocus: false
  property int notifSel: 0
  readonly property bool notifHasOpen: shownNotif !== null && !!(shownNotif.open || (shownNotif.kind !== "iphone" && (shownNotif.app || shownNotif.desktopEntry)))
  readonly property int notifActionCount: shownNotif && shownNotif.actions ? shownNotif.actions.length : 0
  readonly property int notifButtonCount: (notifHasOpen ? 1 : 0) + notifActionCount + 1
  function notifRing(i) { return notifKeys && notifPinned && !notifReplyFocus && notifSel === i }

  readonly property bool tabWanted: activity === "notif" && !notifPinned
  onTabWantedChanged: setTabBind(tabWanted)
  // One entry per screen in a Lua table, so two notches don't unbind each
  // other; a shell that dies with Tab bound gives it back after 30 s.
  function setTabBind(on) {
    var key = "island_tab[" + JSON.stringify(screenName || "?") + "]"
    Quickshell.execDetached(["hyprctl", "eval", on
      ? "island_tab = island_tab or {} "
        + "if next(island_tab) == nil then hl.bind('TAB', function() hl.exec_cmd('omarchy-shell -q io.github.hugorolimf.island pinKeys') end, { description = 'Island Notch: open the notification' }) end "
        + key + " = true "
        + "island_tab_gen = (island_tab_gen or 0) + 1 local g = island_tab_gen "
        + "hl.timer(function() if island_tab_gen == g and next(island_tab) then island_tab = {} hl.unbind('TAB') end end, { timeout = 30000, type = 'oneshot' })"
      : "if island_tab and " + key + " then " + key + " = nil if next(island_tab) == nil then hl.unbind('TAB') end end"])
  }

  function pinNotificationByKeys() {
    if (!notif) return
    notifSel = 0
    pinNotification()
    notifKeys = true
    focusPrime = true
    primeTimer.restart()
  }

  // Keys of a pinned notification (on keyCatcher; the reply field hands ↓
  // over and folds on Tab too). The first arrow after a click only shows the
  // ring.
  function notifKey(key) {
    if (!notifPinned || !shownNotif) return false
    var n = notifButtonCount
    if (key === Qt.Key_Tab) {
      unpinNotification()
    } else if (key === Qt.Key_Right || key === Qt.Key_Down) {
      if (notifKeys) notifSel = (notifSel + 1) % n
      notifKeys = true
    } else if (key === Qt.Key_Up && notifSel === 0 && replyBox.visible) {
      replyInput.forceActiveFocus()
    } else if (key === Qt.Key_Left || key === Qt.Key_Up) {
      if (notifKeys) notifSel = (notifSel + n - 1) % n
      notifKeys = true
    } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
      activateNotifButton(notifSel)
    } else {
      return false
    }
    return true
  }

  function notifFocusButtons() {
    notifSel = 0
    notifKeys = true
    keyCatcher.forceActiveFocus()
  }

  function activateNotifButton(i) {
    var n = shownNotif
    if (!n) return
    var a = i - (notifHasOpen ? 1 : 0)
    if (notifHasOpen && i === 0) focusNotificationApp()
    else if (a >= 0 && a < notifActionCount) { Quickshell.execDetached(n.actions[a].open); dismissNotification() }
    else dismissNotification()
  }

  // ---- on-screen indicators (volume, brightness, mic, keyboard), sent by
  // Osd.qml for every `omarchy-osd`. A level shows as icon + bar + number;
  // a message as icon + text. Brief, so it sits over notifications and music.
  property bool hudActive: false
  property string hudKey: ""
  property real hudValue: -1
  property string hudMessage: ""
  readonly property bool hudBar: hudValue >= 0
  readonly property bool hudMuted: hudKey.indexOf("mute") >= 0 || hudKey.indexOf("off") >= 0 || (hudBar && hudValue <= 0 && hudKey.indexOf("volume") === 0)
  function showHud(h) {
    if (!h || !h.key && h.value === undefined && !h.message) { hudActive = false; return }
    hudKey = String(h.key || "")
    hudValue = typeof h.value === "number" ? h.value : -1
    hudMessage = String(h.message || "")
    hudActive = true
    hudTimer.interval = Math.max(700, Number(h.duration) || 1200) + 300
    hudTimer.restart()
  }
  Timer { id: hudTimer; onTriggered: root.hudActive = false }
  readonly property var hudPaths: {
    var k = hudKey
    if (k.indexOf("volume") === 0 || k === "mute" || k === "muted") {
      if (hudMuted) return [Icons.hudSpeaker, Icons.hudMute]
      var v = hudValue
      return [Icons.hudSpeaker].concat(v > 0.66 ? [Icons.hudWave1, Icons.hudWave2, Icons.hudWave3] : v > 0.33 ? [Icons.hudWave1, Icons.hudWave2] : [Icons.hudWave1])
    }
    if (k.indexOf("mic") === 0) return hudMuted ? [Icons.hudMic, Icons.hudSlash] : [Icons.hudMic]
    if (k === "brightness" || k === "display") return [Icons.hudSun]
    if (k === "keyboard") return [Icons.hudKeyboard]
    if (k.indexOf("touch") === 0) return [Icons.hudTouchpad]
    if (k.indexOf("media") === 0 || k.indexOf("player") === 0) return [Icons.hudNote]
    if (k === "reboot" || k === "restart" || k === "shutdown" || k === "power" || k === "poweroff" || k === "logout") return [Icons.hudPower]
    return [Icons.bell]
  }

  // While dictating (or transcribing) the notch belongs to the voice: a
  // notification waits here and shows the moment dictation ends, with how
  // many more came meanwhile. Its lifetime only starts once it is shown.
  readonly property bool dictating: dictState === "recording" || dictState === "transcribing"
  property var heldNotif: null
  property int heldExtra: 0
  onDictatingChanged: {
    if (dictating && notif) {
      // already on screen when dictation starts: it comes back afterwards
      heldNotif = notif
      heldExtra = notifExtra
      notifTimer.stop()
      notif = null
      notifPinned = false
      notifExtra = 0
    } else if (!dictating && heldNotif) {
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

  function showNotification(n) {
    if (dictating) {
      if (heldNotif && !(n.uid !== "" && heldNotif.uid === n.uid)) heldExtra++
      heldNotif = n
      return
    }
    // the same notification updated (a new track, progress) is not a new one
    var same = notif !== null && n.uid !== "" && notif.uid === n.uid
    notifExtra = same ? notifExtra : notif !== null ? notifExtra + 1 : 0
    var pinned = same && notifPinned
    notif = n
    notifCopied = false
    notifPinned = pinned
    copiedTimer.stop()
    notifTimer.interval = n.urgent ? 20000 : n.copy ? 12000 : n.kind === "iphone" ? 9000 : 7000
    if (!pinned) notifTimer.restart()
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
    if (notif) { notifTimer.interval = 3500; notifTimer.restart() }
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
    notifTimer.stop()
    notif = null
    notifPinned = false
    notifExtra = 0
    if (activity !== "media") hoverExpanded = false
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
    : claudeActive ? "claude"
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

  // ---- geometry (body size in real pixels; the ears hang outside)
  // Per-monitor size: every measure is the notebook's (1536 px wide logical
  // screen) times k, capped at 1.35, and drawn natively at that size — no
  // transform scaling, so shapes and text stay sharp. Fonts only grow by
  // 1 px (2 px for big numbers) on the bigger screen.
  readonly property real screenWidth: QsWindow.window && QsWindow.window.screen ? QsWindow.window.screen.width : 1536
  readonly property real k: Math.max(1, Math.min(1.35, screenWidth / 1536))
  readonly property bool big: k > 1.05
  function u(v) { return v * k }
  function fontPx(base) { return big ? (base >= 20 ? base + 2 : Math.floor(base) + 1) : base }
  // pixel sizes like 10.5 need pointSize (pixelSize is an int); 0.75 pt/px
  function fontPt(base) { return fontPx(base) * 0.75 }

  // The notch starts flush with the bar's edge and hangs a few px below it.
  readonly property real barH: Math.max(20, barSize)
  readonly property real compactH: barH + u(6)
  readonly property real ear: u(7)
  readonly property real targetW: {
    if (view === "card") return cardLoader.item ? cardLoader.item.implicitWidth : u(340)
    if (view === "mediaX") return u(400)
    if (view === "screenX") return u(280)
    if (view === "claudeX") return u(380)
    if (view === "askListen") return u(196)
    if (view === "askThink") return u(320)
    if (view === "askMissed") return askMissedRow.implicitWidth + u(32)
    if (view === "askAnswer") return u(380)
    if (view === "claude") return u(300)
    if (view === "iphone") return u(380)
    if (view === "iphoneMini") return iphoneMiniRow.implicitWidth + u(32)
    if (view === "notifX") return Math.max(u(300), notifRowX.implicitWidth + u(32))
    if (view === "notif") return notifRow.implicitWidth + u(32)
    if (view === "dictation") return u(196)
    if (view === "transcribing") return transRow.implicitWidth + u(32)
    if (view === "screen") return screenRow.implicitWidth + u(32)
    if (view === "reminder") return reminderRow.implicitWidth + u(32)
    if (view === "media") return u(260)
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

  // ---- cards (generic: add a Component below and a case in cardComponent)
  function cardComponent(name) {
    if (name === "weather") return weatherCardComponent
    return null
  }

  function openCard(name) {
    if (!cardComponent(name)) return "unknown card: " + name
    cardName = name
    hoverExpanded = false
    return "ok"
  }

  function closeCard() {
    cardName = ""
  }

  function toggleCard(name) {
    if (cardName === name) { closeCard(); return "closed" }
    // A click on the bar button that summoned the card first clears the focus
    // grab (closing it), then asks to toggle: that is a close, not a reopen.
    if (Date.now() - grabClosedAt < 450 && grabClosedName === name) return "closed"
    return openCard(name)
  }

  onCardNameChanged: {
    if (cardName === "") return
    focusPrime = true
    primeTimer.restart()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
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
    Shared.register(root)
  }

  // Stop the children explicitly: a reload must not leave a status
  // follower behind.
  Component.onDestruction: {
    if (tabWanted) setTabBind(false)
    voxProc.running = false
    recWatch.running = false
    claudeWatch.running = false
    Shared.unregister(root)
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
      if (root.notifActive && !root.notifPinned) notifTimer.restart()
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
    id: askWatch
    command: ["setpriv", "--pdeathsig", "TERM", "sh", "-c",
      "umask 077; mkdir -p \"$1\" && chmod 700 \"$1\" || exit 1; echo $PPID > \"$1/notch.watching\"; "
      + "exec inotifywait -m -q -e close_write,moved_to --format %f \"$1\"", "sh", root.askDir]
    running: root.isLeader
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

    // Tab while a notification is up (bound only then): pin it for the keyboard.
    function pinKeys(): string {
      var items = root.bar && typeof root.bar.moduleWidgets === "function" ? root.bar.moduleWidgets(root.moduleName) : [root]
      if (!items || items.length === 0) items = [root]
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

  component Label: Text {
    color: root.strong
    font.family: root.monoFont
    font.pointSize: root.fontPt(10.5)
    font.weight: Font.Medium
    textFormat: Text.PlainText
  }

  component Sub: Text {
    color: root.muted
    font.family: root.monoFont
    font.pointSize: root.fontPt(10)
    textFormat: Text.PlainText
  }

  // One line of text that rolls over when it changes: the old line rises and
  // fades, the new one comes up from below (the steps of a Claude session).
  component Ticker: Item {
    id: ticker
    property string text: ""
    property color color: root.strong
    property bool flip: false
    implicitHeight: lineA.implicitHeight
    height: implicitHeight
    clip: true
    Label { id: lineA; width: ticker.width; elide: Text.ElideRight; color: ticker.color }
    Label { id: lineB; width: ticker.width; elide: Text.ElideRight; color: ticker.color; opacity: 0 }
    Component.onCompleted: lineA.text = text
    onTextChanged: {
      var current = flip ? lineB : lineA
      if (current.text === text) return
      if (roll.running) roll.complete()
      var next = flip ? lineA : lineB
      next.text = text
      roll.into = next
      roll.away = current
      flip = !flip
      roll.start()
    }
    ParallelAnimation {
      id: roll
      property Item into: null
      property Item away: null
      NumberAnimation { target: roll.into; property: "y"; from: root.u(9); to: 0; duration: 380; easing.type: Easing.Bezier; easing.bezierCurve: root.ease }
      NumberAnimation { target: roll.into; property: "opacity"; from: 0; to: 1; duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: root.ease }
      NumberAnimation { target: roll.away; property: "y"; to: -root.u(9); duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: root.ease }
      NumberAnimation { target: roll.away; property: "opacity"; to: 0; duration: 200 }
    }
  }

  // Claude's state: a pulse while it works, amber while it waits for you, a
  // check when the turn is done.
  // The assistant's mark: Claude's, drawn as the bar draws it; breathes while it thinks.
  component AskMark: Item {
    id: askMark
    property bool busy: false
    implicitWidth: root.u(16)
    implicitHeight: root.u(16)
    ClaudeLogo {
      anchors.centerIn: parent
      size: parent.width
    }
    SequentialAnimation on opacity {
      running: askMark.busy
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { to: 0.35; duration: 650; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutSine }
    }
  }

  // Claude's own mark: breathes while it works, still while it waits for
  // you, and gives way to a check when the turn is done.
  component ClaudeMark: Item {
    implicitWidth: root.u(14)
    implicitHeight: root.u(14)
    ClaudeLogo {
      id: claudeLogoMark
      anchors.centerIn: parent
      visible: root.claudeState !== "done"
      size: root.u(14)
      readonly property bool working: root.claudeState === "working" && (root.view === "claude" || root.view === "claudeX")
      SequentialAnimation on opacity {
        running: claudeLogoMark.working
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
      }
    }
    StrokeIcon {
      anchors.centerIn: parent
      visible: root.claudeState === "done"
      size: root.u(14)
      strokeWidth: 1.5
      color: root.green
      path: "M5.5 12.5l4 4 9-9.5"
    }
  }

  // One page per view. Never hidden with `visible` (positioners inside
  // would report zero size); a faded page just stops taking input. Content
  // fades in once the morph is under way and out at once.
  component Page: Item {
    property string key: ""
    readonly property bool active: root.view === key
    property int inPause: active ? 150 : 0
    readonly property int fadeOut: root.view === "idle" ? 150 : 300
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    opacity: active ? 1 : 0
    enabled: active
    Behavior on opacity {
      SequentialAnimation {
        PauseAnimation { duration: inPause }
        NumberAnimation { duration: active ? 300 : fadeOut; easing.type: Easing.Bezier; easing.bezierCurve: root.ease }
      }
    }
    // content drops in from just above as the notch opens up under it
    property real drop: active ? 0 : -root.u(6)
    Behavior on drop {
      SequentialAnimation {
        PauseAnimation { duration: inPause }
        NumberAnimation { duration: 380; easing.type: Easing.Bezier; easing.bezierCurve: root.ease }
      }
    }
    transform: Translate { y: drop }
  }

  // Bars mirrored from the centre over the last mic levels. On the bigger
  // screen there are more of them, not thicker ones.
  component LiveBars: Row {
    id: liveBars
    property int count: root.big ? 13 : 9
    property real barWidth: 1.5
    property real span: root.u(12)
    readonly property int mid: Math.floor(count / 2)
    spacing: root.big ? 2 : 1.5
    height: 2 + span
    Repeater {
      model: liveBars.count
      Rectangle {
        required property int index
        // mirrored from the centre, 80 ms of history apart, so the bars differ
        readonly property real level: root.micHistory[Math.min(12, 2 * Math.abs(index - liveBars.mid))] || 0
        anchors.verticalCenter: parent.verticalCenter
        width: liveBars.barWidth
        height: 2 + level * liveBars.span
        radius: width / 2
        color: root.hi
        Behavior on height { NumberAnimation { duration: 70; easing.type: Easing.Bezier; easing.bezierCurve: root.ease } }
      }
    }
  }

  // Pill button of a pinned notification (same look as COPIAR).
  component ActionPill: Rectangle {
    id: pill
    property string label: ""
    property bool accent: false
    property bool selected: false  // keyboard selection
    signal activated()
    width: pillText.implicitWidth + root.u(18)
    height: root.u(22)
    radius: height / 2
    color: pillArea.containsMouse || selected ? Qt.rgba(1, 1, 1, 0.09) : (accent ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
    border.width: selected ? 1.2 : 0.6
    border.color: Qt.rgba(root.hi.r, root.hi.g, root.hi.b, selected ? 0.9 : accent ? 0.5 : 0.25)
    Behavior on color { ColorAnimation { duration: root.fadeMs } }
    Text {
      id: pillText
      anchors.centerIn: parent
      text: pill.label
      color: pill.accent ? root.strong : root.hi
      font.family: root.monoFont
      font.pointSize: root.fontPt(9.5)
      font.weight: Font.Medium
      font.letterSpacing: 0.5
      textFormat: Text.PlainText
    }
    MouseArea {
      id: pillArea
      anchors.fill: parent
      anchors.margins: -root.u(3)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pill.activated()
    }
  }

  // The actions of a pinned notification: its own (reply, open) and close.
  component NotifActions: Row {
    spacing: root.u(8)
    ActionPill {
      label: root.notifActionLabel
      accent: true
      // an iPhone notification only has the phone's own actions
      visible: root.notifHasOpen
      selected: root.notifRing(0)
      onActivated: root.focusNotificationApp()
    }
    Repeater {
      model: root.shownNotif && root.shownNotif.actions ? root.shownNotif.actions : []
      delegate: ActionPill {
        required property var modelData
        required property int index
        label: String(modelData.label).toUpperCase()
        selected: root.notifRing((root.notifHasOpen ? 1 : 0) + index)
        onActivated: {
          Quickshell.execDetached(modelData.open)
          root.dismissNotification()
        }
      }
    }
    ActionPill {
      label: root.tr("FECHAR")
      selected: root.notifRing(root.notifButtonCount - 1)
      onActivated: root.dismissNotification()
    }
  }

  // App icon + "App · title" (+N), shared by the compact and hover views.
  component NotifRow: Row {
    spacing: root.u(7)
    Item {
      anchors.verticalCenter: parent.verticalCenter
      width: root.u(17)
      height: width
      Image {
        anchors.fill: parent
        source: root.cardClaude ? "" : root.notifIcon
        visible: !root.cardClaude && root.notifIcon !== ""
        sourceSize.width: 64
        sourceSize.height: 64
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
      }
      ClaudeLogo {
        anchors.centerIn: parent
        visible: root.cardClaude
        size: parent.width
      }
      StrokeIcon {
        anchors.fill: parent
        visible: !root.cardClaude && root.notifIcon === ""
        size: parent.width
        color: root.hi
        path: root.shownNotif && root.shownNotif.kind === "message" ? Icons.message : Icons.bell
      }
    }
    Sub {
      anchors.verticalCenter: parent.verticalCenter
      text: root.notifAppName
    }
    Label {
      readonly property bool code: root.shownNotif !== null && root.shownNotif.copy !== ""
      anchors.verticalCenter: parent.verticalCenter
      visible: root.shownNotif !== null && root.shownNotif.title !== ""
      width: Math.min(implicitWidth, root.u(240))
      elide: Text.ElideRight
      // a code to copy reads as the code itself, big and spaced
      font.pointSize: root.fontPt(code ? 13 : 10.5)
      font.letterSpacing: code ? 1.5 : 0
      text: (code ? "" : "· ") + (root.shownNotif ? root.shownNotif.title : "")
    }
    Sub {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.notifExtra > 0
      text: "+" + root.notifExtra
    }
    // COPIAR → COPIADO (green), then the pulse folds
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.shownNotif !== null && root.shownNotif.copy !== ""
      width: copyLabel.implicitWidth + root.u(14)
      height: root.u(18)
      radius: height / 2
      color: copyArea.containsMouse && !root.notifCopied ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
      border.width: 0.6
      border.color: root.notifCopied ? root.green : Qt.rgba(root.hi.r, root.hi.g, root.hi.b, 0.4)
      Behavior on color { ColorAnimation { duration: root.fadeMs } }
      Text {
        id: copyLabel
        anchors.centerIn: parent
        text: root.tr(root.notifCopied ? "COPIADO" : "COPIAR")
        color: root.notifCopied ? root.green : root.hi
        font.family: root.monoFont
        font.pointSize: root.fontPt(9.5)
        font.weight: Font.Medium
        font.letterSpacing: 0.5
        textFormat: Text.PlainText
      }
      MouseArea {
        id: copyArea
        anchors.fill: parent
        anchors.margins: -root.u(3)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.copyNotification()
      }
    }
  }

  // Equalizer bars in the album's colour, from eqLevels (mirrored so the
  // middle bars move most, like the phone's).
  component EqBars: Row {
    id: eq
    property real span: root.u(14)
    property real barW: root.u(2.6)
    spacing: root.u(2.2)
    height: span
    Repeater {
      model: 5
      Rectangle {
        required property int index
        readonly property real level: root.eqLevels[[3, 1, 0, 2, 4][index]] || 0
        anchors.verticalCenter: parent.verticalCenter
        width: eq.barW
        height: Math.max(eq.barW, level * eq.span)
        radius: width / 2
        color: root.artColor
        opacity: root.playing ? 1 : 0.55
        Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
        Behavior on color { ColorAnimation { duration: 600 } }
      }
    }
  }

  // Solid round-hit media button (play/pause, skip), like the phone's.
  component ControlButton: Item {
    id: control
    property string path: ""
    property real iconSize: root.u(22)
    property bool enabledAction: true
    signal activated()
    width: iconSize + root.u(18)
    height: width
    opacity: enabledAction ? 1 : 0.3
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: Qt.rgba(1, 1, 1, controlArea.containsMouse && control.enabledAction ? (controlArea.pressed ? 0.16 : 0.08) : 0)
      Behavior on color { ColorAnimation { duration: root.fadeMs } }
    }
    FillIcon {
      anchors.centerIn: parent
      size: control.iconSize
      color: root.strong
      path: control.path
      scale: controlArea.pressed ? 0.86 : 1
      Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
    }
    MouseArea {
      id: controlArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: control.enabledAction ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (control.enabledAction) control.activated()
    }
  }

  component Cover: Rectangle {
    property real size: root.u(14)
    property real rounding: root.u(4)
    width: size
    height: size
    radius: rounding
    color: root.faint
    clip: true
    StrokeIcon {
      anchors.centerIn: parent
      visible: coverImg.status !== Image.Ready
      size: parent.size * 0.7
      strokeWidth: 1
      color: root.hi
      path: "M9 17.5V6l10-2v11.5M9 17.5a2.5 2.5 0 1 1-5 0a2.5 2.5 0 1 1 5 0zM19 15.5a2.5 2.5 0 1 1-5 0a2.5 2.5 0 1 1 5 0z"
    }
    Image {
      id: coverImg
      anchors.fill: parent
      source: root.artUrl
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      sourceSize.width: 128
      sourceSize.height: 128
      opacity: status === Image.Ready ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: root.fadeMs } }
    }
  }

  component IconButton: Item {
    id: iconButton
    property string path: ""
    property real iconSize: root.u(14)
    property bool enabledAction: true
    signal activated()
    width: root.u(26)
    height: root.u(26)
    opacity: enabledAction ? 1 : 0.35
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: Qt.rgba(1, 1, 1, area.containsMouse && iconButton.enabledAction ? (area.pressed ? 0.14 : 0.07) : 0)
      Behavior on color { ColorAnimation { duration: root.fadeMs } }
    }
    StrokeIcon {
      anchors.centerIn: parent
      size: iconButton.iconSize
      strokeWidth: 1.25
      color: root.hi
      path: iconButton.path
      opacity: area.pressed ? 0.7 : 1
    }
    MouseArea {
      id: area
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: iconButton.enabledAction ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (iconButton.enabledAction) iconButton.activated()
    }
  }

  Component {
    id: weatherCardComponent
    WeatherCard {
      active: root.cardName === "weather"
      k: root.k
      sansFont: root.sansFont
      monoFont: root.monoFont
      strong: root.strong
      muted: root.muted
      hi: root.hi
      blue: root.blue
    }
  }

  // =====================================================================
  // The notch, on its own layer above the bar.

  // Room the notch takes at the top of this monitor, for snapping and
  // arranging windows (hypr/windowing.lua), like the dock's at the bottom.
  // Always the resting (compact) height, even while idle, so layouts don't
  // shift every time the notch comes and goes.
  readonly property string monitorName: QsWindow.window && QsWindow.window.screen ? QsWindow.window.screen.name : ""
  readonly property int coverHeight: bar !== null && bar.position === "top" ? Math.ceil(compactH) : 0
  function publishCover() {
    if (monitorName !== "" && coverFile.path !== "") coverFile.setText(String(coverHeight) + "\n")
  }
  onCoverHeightChanged: publishCover()
  // after the file's path has followed the new name
  onMonitorNameChanged: Qt.callLater(publishCover)
  Timer { id: coverKick; interval: 200; running: true; onTriggered: root.publishCover() }
  FileView {
    id: coverFile
    path: root.monitorName !== "" ? (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
      + "/omarchy/io.github.hugorolimf.island/cover-" + root.monitorName : ""
  }

  PanelWindow {
    id: overlay
    screen: root.QsWindow.window ? root.QsWindow.window.screen : null
    visible: root.shown && root.bar !== null && root.bar.position === "top"
    anchors { top: true; left: true; right: true }
    implicitHeight: 600
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    surfaceFormat.opaque: false
    WlrLayershell.namespace: "island-notch"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: root.cardName !== ""
      ? (root.focusPrime ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)
      : root.notifPinned || root.mediaPinned ? (root.focusPrime ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand) : WlrKeyboardFocus.None
    // input only on the notch body
    mask: Region { item: body }

    onVisibleChanged: if (visible) Qt.callLater(root.pushTargets)

    // Armed a moment after the card shows: a grab requested before the
    // window exists is cleared at once, which closed the card as it opened.
    property bool grabArmed: false
    Timer {
      interval: 200
      running: (root.cardName !== "" || root.notifPinned || root.mediaPinned) && overlay.visible
      onTriggered: overlay.grabArmed = true
    }
    Connections {
      target: root
      function onCardNameChanged() { if (root.cardName === "" && !root.notifPinned) overlay.grabArmed = false }
      function onNotifPinnedChanged() {
        if (root.notifPinned) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
        else if (root.cardName === "" && !root.mediaPinned) overlay.grabArmed = false
      }
      function onMediaPinnedChanged() {
        if (root.mediaPinned) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
        else if (root.cardName === "" && !root.notifPinned) overlay.grabArmed = false
      }
    }

    // A click anywhere else closes a card, or lets a pinned notification go.
    HyprlandFocusGrab {
      active: overlay.grabArmed && (root.cardName !== "" || root.notifPinned || root.mediaPinned)
      windows: [overlay]
      onCleared: {
        if (root.cardName !== "") {
          root.grabClosedAt = Date.now()
          root.grabClosedName = root.cardName
          root.closeCard()
        } else if (root.notifPinned) {
          root.unpinNotification()
        } else {
          root.mediaPinned = false
          root.hoverExpanded = false
        }
      }
    }

    NotchShape {
      x: Math.round(root.centerX - width / 2)
      y: 0
      bodyWidth: root.notchW
      bodyHeight: root.notchH
      radius: root.notchR
      ear: root.ear
      color: root.plate
    }

    Item {
      id: body
      x: Math.round(root.centerX - width / 2)
      y: 0
      width: Math.max(0, root.notchW)
      height: Math.max(0, root.notchH)
      clip: true

      HoverHandler { onHoveredChanged: root.hovered = hovered }

      Item {
        id: keyCatcher
        focus: true
        Keys.onEscapePressed: { root.closeCard(); root.unpinNotification(); root.mediaPinned = false; root.hoverExpanded = false }
        Keys.onPressed: function(event) { if (root.notifKey(event.key)) event.accepted = true }
      }

      // ---------------- compact views

      // On-screen indicator: icon, a rounded bar easing to the new level and
      // the number; or icon + message (Caps Lock, layout, …).
      Page {
        key: "hud"
        width: root.hudBar ? root.u(260) - root.u(36) : hudRow.implicitWidth
        height: root.compactH
        Row {
          id: hudRow
          visible: !root.hudBar
          anchors.verticalCenter: parent.verticalCenter
          spacing: root.u(9)
          StrokeIcon {
            anchors.verticalCenter: parent.verticalCenter
            size: root.u(16)
            strokeWidth: 1.4
            color: root.strong
            path: root.hudPaths.join(" ")
          }
          Label {
            anchors.verticalCenter: parent.verticalCenter
            text: root.hudMessage
          }
        }
        Item {
          visible: root.hudBar
          anchors.fill: parent
          StrokeIcon {
            id: hudIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            size: root.u(16)
            strokeWidth: 1.4
            color: root.hudMuted ? root.muted : root.strong
            path: root.hudPaths.join(" ")
          }
          Text {
            id: hudNumber
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: root.u(26)
            horizontalAlignment: Text.AlignRight
            text: Math.round(Math.max(0, root.hudValue) * 100)
            color: root.hudMuted ? root.muted : root.hi
            font.family: root.monoFont
            font.pointSize: root.fontPt(10.5)
            font.features: ({ "tnum": 1 })
            textFormat: Text.PlainText
          }
          Rectangle {
            id: hudTrack
            anchors.left: hudIcon.right
            anchors.leftMargin: root.u(11)
            anchors.right: hudNumber.left
            anchors.rightMargin: root.u(10)
            anchors.verticalCenter: parent.verticalCenter
            height: root.u(5)
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.14)
            Rectangle {
              width: Math.max(parent.height, parent.width * Math.max(0, Math.min(1, root.hudValue)))
              height: parent.height
              radius: height / 2
              color: root.hudMuted ? root.muted : root.strong
              opacity: root.hudValue > 0 ? 1 : 0.4
              Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.Bezier; easing.bezierCurve: root.ease } }
              Behavior on color { ColorAnimation { duration: root.fadeMs } }
            }
          }
        }
      }

      // Compact player, like the phone's island: the cover at one end, the
      // equalizer at the other, black in between.
      Page {
        key: "media"
        width: root.u(260) - root.u(28)
        height: root.compactH
        Cover {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          size: root.u(19)
          rounding: root.u(5)
          opacity: root.playing ? 1 : 0.7
          Behavior on opacity { NumberAnimation { duration: root.fadeMs } }
        }
        EqBars {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          span: root.u(13)
        }
        MouseArea {
          anchors.fill: parent
          anchors.leftMargin: -root.u(14)
          anchors.rightMargin: -root.u(14)
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton
          cursorShape: Qt.PointingHandCursor
          onClicked: function(mouse) {
            if (mouse.button === Qt.MiddleButton) root.mediaNext()
            else root.mediaPinned = true
          }
          onWheel: function(wheel) { root.mediaWheel(wheel.angleDelta.y) }
        }
      }

      Page {
        key: "screen"
        width: screenRow.implicitWidth
        height: root.compactH
        Row {
          id: screenRow
          anchors.verticalCenter: parent.verticalCenter
          spacing: root.u(7)
          PulseDot { anchors.verticalCenter: parent.verticalCenter; size: root.u(6); color: root.red; running: root.view === "screen" }
          Label { anchors.verticalCenter: parent.verticalCenter; text: root.tr("Gravando") }
          Sub { anchors.verticalCenter: parent.verticalCenter; text: root.screenElapsed; font.features: ({ "tnum": 1 }) }
        }
      }

      // Claude Code at work: its state and the current step, rolling over.
      Page {
        key: "claude"
        width: root.u(300) - root.u(32)
        height: root.compactH
        ClaudeMark {
          id: claudeMark
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }
        Ticker {
          anchors.left: claudeMark.right
          anchors.leftMargin: root.u(8)
          anchors.right: claudeMore.left
          anchors.rightMargin: root.claudeExtra > 0 ? root.u(8) : 0
          anchors.verticalCenter: parent.verticalCenter
          text: root.claudeLine
          color: root.claudeState === "waiting" ? root.amber : root.strong
        }
        Sub {
          id: claudeMore
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.claudeExtra > 0 ? "+" + root.claudeExtra : ""
        }
        MouseArea {
          anchors.fill: parent
          anchors.leftMargin: -root.u(16)
          anchors.rightMargin: -root.u(16)
          cursorShape: Qt.PointingHandCursor
          onClicked: root.focusClaude()
        }
      }

      Page {
        key: "reminder"
        width: reminderRow.implicitWidth
        height: root.compactH
        Row {
          id: reminderRow
          anchors.verticalCenter: parent.verticalCenter
          spacing: root.u(7)
          StrokeIcon {
            anchors.verticalCenter: parent.verticalCenter
            size: root.u(14)
            color: root.amber
            path: Icons.alarm
          }
          Label {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.u(170))
            elide: Text.ElideRight
            text: root.reminder ? (root.reminder.message || root.tr("Lembrete")) : ""
          }
          Sub { anchors.verticalCenter: parent.verticalCenter; text: root.reminderLeft; font.features: ({ "tnum": 1 }) }
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.run("omarchy-reminder show")
        }
      }

      Page {
        key: "transcribing"
        width: transRow.implicitWidth
        height: root.compactH
        Row {
          id: transRow
          anchors.verticalCenter: parent.verticalCenter
          spacing: root.u(7)
          Waves {
            anchors.verticalCenter: parent.verticalCenter
            mode: "travel"
            count: root.big ? 13 : 9
            barWidth: 1.5
            spacing: root.big ? 2 : 1.5
            maxHeight: root.u(16)
            color: root.blue
            running: root.view === "transcribing"
          }
          Label { anchors.verticalCenter: parent.verticalCenter; text: root.tr("Transcrevendo…") }
        }
      }

      // voice assistant (F10): listening, like dictation but with Claude's mark
      Page {
        key: "askListen"
        width: root.u(196)
        height: root.barH + root.u(14)
        Row {
          anchors.centerIn: parent
          spacing: root.u(8)
          AskMark { anchors.verticalCenter: parent.verticalCenter }
          LiveBars { anchors.verticalCenter: parent.verticalCenter; span: root.u(20) }
          Label { anchors.verticalCenter: parent.verticalCenter; text: root.tr("Ouvindo…") }
        }
      }

      Page {
        key: "askThink"
        width: root.u(320) - root.u(32)
        height: askThinkCol.implicitHeight + root.u(18)
        Column {
          id: askThinkCol
          y: root.u(9)
          width: parent.width
          spacing: root.u(3)
          Row {
            spacing: root.u(8)
            AskMark { anchors.verticalCenter: parent.verticalCenter; busy: root.view === "askThink" }
            Label { anchors.verticalCenter: parent.verticalCenter; text: root.tr("Pensando…") }
          }
          Sub {
            visible: text !== ""
            width: parent.width
            elide: Text.ElideRight
            text: root.ask && root.ask.heard ? "«" + root.ask.heard + "»" : ""
          }
        }
      }

      Page {
        key: "askMissed"
        width: askMissedRow.implicitWidth
        height: root.compactH
        Row {
          id: askMissedRow
          anchors.verticalCenter: parent.verticalCenter
          spacing: root.u(8)
          AskMark { anchors.verticalCenter: parent.verticalCenter }
          Label { anchors.verticalCenter: parent.verticalCenter; color: root.amber; text: root.tr("Não entendi") }
        }
      }

      // the answer, in the big card; a click opens the day's conversation
      Page {
        key: "askAnswer"
        width: root.u(380) - root.u(40)
        height: askCol.implicitHeight + root.u(26)
        Column {
          id: askCol
          y: root.u(13)
          width: parent.width
          spacing: root.u(4)
          Row {
            spacing: root.u(8)
            AskMark { anchors.verticalCenter: parent.verticalCenter }
            Label { anchors.verticalCenter: parent.verticalCenter; text: root.tr("Assistente") }
          }
          Sub {
            visible: text !== ""
            width: parent.width
            elide: Text.ElideRight
            text: root.ask && root.ask.heard ? root.tr("Você: ") + root.ask.heard : ""
          }
          Text {
            width: parent.width
            topPadding: root.u(2)
            text: root.ask ? String(root.ask.answer || "") : ""
            color: root.ask && root.ask.ok === false ? root.amber : root.strong
            font.family: root.sansFont
            font.pointSize: root.fontPt(12)
            wrapMode: Text.Wrap
            maximumLineCount: 9
            elide: Text.ElideRight
            lineHeight: 1.08
            textFormat: Text.PlainText
          }
          Sub {
            visible: root.ask && String(root.ask.open || "") !== ""
            topPadding: root.u(2)
            font.pointSize: root.fontPt(9)
            text: root.tr("clique para abrir a conversa")
          }
        }
        MouseArea {
          anchors.fill: parent
          anchors.margins: -root.u(10)
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onContainsMouseChanged: root.askHold = containsMouse
          onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) root.dismissAsk()
            else root.openAsk()
          }
        }
      }

      // dictation: the notch hangs lower while the user speaks; bars follow the voice
      Page {
        key: "dictation"
        width: root.u(196)
        height: root.barH + root.u(14)
        Row {
          anchors.centerIn: parent
          spacing: root.u(8)
          Rectangle { anchors.verticalCenter: parent.verticalCenter; width: root.u(6); height: width; radius: width / 2; color: root.blue }
          LiveBars { anchors.verticalCenter: parent.verticalCenter; span: root.u(20) }
          Label { anchors.verticalCenter: parent.verticalCenter; text: root.tr("Ditando…") }
        }
      }

      Page {
        key: "notif"
        width: notifRow.implicitWidth
        height: root.compactH
        NotifRow { id: notifRow; anchors.verticalCenter: parent.verticalCenter }
        MouseArea {
          z: -1
          anchors.fill: parent
          anchors.leftMargin: -root.u(16)
          anchors.rightMargin: -root.u(16)
          cursorShape: Qt.PointingHandCursor
          onClicked: root.pinNotification()
        }
      }

      // ---------------- expanded views (hover)

      // iPhone, mini: the app's icon, who sent it and the start of the text
      Page {
        key: "iphoneMini"
        width: iphoneMiniRow.implicitWidth
        height: root.compactH
        Row {
          id: iphoneMiniRow
          readonly property bool code: root.shownNotif !== null && root.shownNotif.copy !== ""
          anchors.verticalCenter: parent.verticalCenter
          spacing: root.u(7)
          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: root.u(17)
            height: width
            Image {
              id: miniIcon
              anchors.fill: parent
              source: root.cardIcon
              visible: status === Image.Ready
              cache: false
              asynchronous: true
              smooth: true
              mipmap: true
              sourceSize.width: 64
              sourceSize.height: 64
            }
            ClaudeLogo {
              anchors.centerIn: parent
              visible: root.cardClaude
              size: parent.width
            }
            StrokeIcon {
              anchors.fill: parent
              visible: !root.cardClaude && miniIcon.status !== Image.Ready
              size: parent.width
              color: root.hi
              path: root.cardGlyph
            }
          }
          Label {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.u(130))
            elide: Text.ElideRight
            text: root.shownNotif ? (iphoneMiniRow.code ? root.shownNotif.body : root.shownNotif.title) : ""
          }
          Sub {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.u(170))
            elide: Text.ElideRight
            visible: text !== "· "
            text: "· " + (root.shownNotif ? (iphoneMiniRow.code ? root.shownNotif.copy : root.shownNotif.body) : "")
          }
          Sub {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.notifExtra > 0
            text: "+" + root.notifExtra
          }
        }
        MouseArea {
          z: -1
          anchors.fill: parent
          anchors.leftMargin: -root.u(16)
          anchors.rightMargin: -root.u(16)
          cursorShape: Qt.PointingHandCursor
          onClicked: root.pinNotification()
        }
      }

      // iPhone notification, read like a macOS banner: the app's icon, who
      // sent it in bold, app and time on the right, the text below in sans.
      Page {
        key: "iphone"
        width: root.u(380) - root.u(36)
        height: iphoneCard.implicitHeight

        Item {
          id: iphoneCard
          readonly property bool code: root.shownNotif !== null && root.shownNotif.copy !== ""
          width: parent.width
          implicitHeight: Math.max(appTile.y + appTile.height, iphoneText.y + iphoneText.height) + root.u(13)

          // app icon (or a drawn tile while it has none)
          Rectangle {
            id: appTile
            y: root.u(10)
            // Claude's mark sits beside the name, as in the one-line view
            width: root.cardClaude ? root.u(19) : root.u(34)
            height: width
            radius: root.u(8)
            color: appImage.status === Image.Ready || root.cardClaude ? "transparent" : root.faint
            Image {
              id: appImage
              anchors.fill: parent
              source: root.cardIcon
              visible: status === Image.Ready
              cache: false
              asynchronous: true
              smooth: true
              mipmap: true
              sourceSize.width: 128
              sourceSize.height: 128
              onStatusChanged: if (status === Image.Error && root.iphoneIconTries < 2) iphoneIconRetry.restart()
            }
            // centred on the text beside it (sender and message together)
            ClaudeLogo {
              anchors.horizontalCenter: parent.horizontalCenter
              y: Math.round(iphoneText.y + (iphoneText.height - height) / 2 - appTile.y)
              visible: root.cardClaude
              size: root.u(19)
            }
            StrokeIcon {
              anchors.centerIn: parent
              visible: !root.cardClaude && appImage.status !== Image.Ready
              size: root.u(17)
              color: root.hi
              path: root.cardGlyph
            }
          }

          Column {
            id: iphoneText
            x: appTile.width + root.u(11)
            y: root.u(9)
            width: parent.width - x
            spacing: root.u(2)

            Item {
              width: parent.width
              height: Math.max(senderLabel.implicitHeight, appLabel.implicitHeight)
              Text {
                id: senderLabel
                width: parent.width - appLabel.implicitWidth - root.u(10)
                // a code: who sent it; otherwise the sender (the title)
                text: root.shownNotif ? (iphoneCard.code ? root.shownNotif.body : root.shownNotif.title) : ""
                color: root.strong
                font.family: root.sansFont
                font.pointSize: root.fontPt(13)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                textFormat: Text.PlainText
              }
              Text {
                id: appLabel
                anchors.right: parent.right
                anchors.baseline: senderLabel.baseline
                text: root.notifAppName + (root.notifExtra > 0 ? "  +" + root.notifExtra : "") + root.tr("  ·  agora")
                color: root.muted
                font.family: root.monoFont
                font.pointSize: root.fontPt(9.5)
                textFormat: Text.PlainText
              }
            }

            Text {
              visible: !iphoneCard.code && text !== ""
              width: parent.width
              text: root.shownNotif ? root.shownNotif.body : ""
              color: "#bdbdbd"
              font.family: root.sansFont
              font.pointSize: root.fontPt(12)
              lineHeight: 1.12
              wrapMode: Text.Wrap
              // pinned (clicked): the whole message
              maximumLineCount: root.shownPinned ? 18 : 3
              elide: Text.ElideRight
              textFormat: Text.PlainText
            }

            // reply box (pinned, when the sender takes replies — Tether
            // sends it through the iPhone); Enter sends, Esc lets go
            Rectangle {
              id: replyBox
              visible: root.shownPinned && root.shownNotif !== null && root.shownNotif.reply === true
              width: parent.width
              height: root.u(30)
              radius: height / 2
              color: Qt.rgba(1, 1, 1, 0.06)
              border.width: 0.6
              border.color: replyInput.activeFocus ? Qt.rgba(root.hi.r, root.hi.g, root.hi.b, 0.45) : Qt.rgba(1, 1, 1, 0.1)
              Behavior on border.color { ColorAnimation { duration: root.fadeMs } }
              TextInput {
                id: replyInput
                anchors.left: parent.left
                anchors.right: sendButton.left
                anchors.leftMargin: root.u(13)
                anchors.rightMargin: root.u(8)
                anchors.verticalCenter: parent.verticalCenter
                color: root.strong
                selectionColor: Qt.rgba(root.blue.r, root.blue.g, root.blue.b, 0.35)
                font.family: root.sansFont
                font.pointSize: root.fontPt(12)
                clip: true
                enabled: !root.replySent
                Keys.onReturnPressed: root.sendReply(text)
                Keys.onEnterPressed: root.sendReply(text)
                Keys.onEscapePressed: root.unpinNotification()
                Keys.onDownPressed: root.notifFocusButtons()
                Keys.onTabPressed: root.unpinNotification()
                onActiveFocusChanged: root.notifReplyFocus = activeFocus
                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  visible: parent.text === "" && !root.replySent
                  text: root.shownNotif && root.shownNotif.replyHint ? root.shownNotif.replyHint : root.tr("Responder…")
                  color: root.muted
                  font: parent.font
                }
              }
              // send: a small round arrow, only once there is something to
              // send (Enter does the same); a green check once it went out
              Rectangle {
                id: sendButton
                anchors.right: parent.right
                anchors.rightMargin: root.u(4)
                anchors.verticalCenter: parent.verticalCenter
                width: root.u(22)
                height: width
                radius: width / 2
                readonly property bool ready: replyInput.text.trim() !== "" && !root.replySent
                opacity: ready || root.replySent || root.replyFailed ? 1 : 0
                scale: opacity > 0 ? 1 : 0.6
                color: root.replySent ? root.green : root.replyFailed ? root.red : root.strong
                Behavior on opacity { NumberAnimation { duration: root.fadeMs } }
                Behavior on scale { NumberAnimation { duration: root.fadeMs; easing.type: Easing.OutBack } }
                Behavior on color { ColorAnimation { duration: root.fadeMs } }
                StrokeIcon {
                  anchors.centerIn: parent
                  size: root.u(13)
                  strokeWidth: 1.8
                  color: root.plate
                  path: root.replySent ? "M6 12.5l4 4 8-9" : "M12 18V6M7 11l5-5 5 5"
                }
                MouseArea {
                  anchors.fill: parent
                  enabled: sendButton.ready
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.sendReply(replyInput.text)
                }
              }
              // the draft belongs to one notification: another one starts empty
              property string draftUid: ""
              Connections {
                target: root
                function onShownPinnedChanged() {
                  if (root.shownPinned && replyBox.visible) Qt.callLater(function() { replyInput.forceActiveFocus() })
                  if (!root.shownPinned) replyInput.text = ""
                }
                function onShownNotifChanged() {
                  var uid = root.shownNotif ? String(root.shownNotif.uid || "") : ""
                  if (uid === "" || uid !== replyBox.draftUid) replyInput.text = ""
                  replyBox.draftUid = uid
                }
              }
            }

            // verification code: the digits big, with COPIAR
            Row {
              visible: iphoneCard.code
              spacing: root.u(10)
              topPadding: root.u(2)
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.shownNotif ? root.shownNotif.copy : ""
                color: root.strong
                font.family: root.monoFont
                font.pointSize: root.fontPt(18)
                font.weight: Font.Medium
                font.letterSpacing: 3
                textFormat: Text.PlainText
              }
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: iphoneCopy.implicitWidth + root.u(16)
                height: root.u(22)
                radius: height / 2
                color: iphoneCopyArea.containsMouse && !root.notifCopied ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                border.width: 0.6
                border.color: root.notifCopied ? root.green : Qt.rgba(root.hi.r, root.hi.g, root.hi.b, 0.4)
                Behavior on color { ColorAnimation { duration: root.fadeMs } }
                Text {
                  id: iphoneCopy
                  anchors.centerIn: parent
                  text: root.tr(root.notifCopied ? "COPIADO" : "COPIAR")
                  color: root.notifCopied ? root.green : root.hi
                  font.family: root.monoFont
                  font.pointSize: root.fontPt(9.5)
                  font.weight: Font.Medium
                  font.letterSpacing: 0.5
                  textFormat: Text.PlainText
                }
                MouseArea {
                  id: iphoneCopyArea
                  anchors.fill: parent
                  anchors.margins: -root.u(3)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.copyNotification()
                }
              }
            }
            NotifActions {
              visible: root.shownPinned
              topPadding: root.u(8)
            }
          }

          MouseArea {
            z: -1
            anchors.fill: parent
            anchors.leftMargin: -root.u(18)
            anchors.rightMargin: -root.u(18)
            cursorShape: Qt.PointingHandCursor
            onClicked: root.pinNotification()
          }
        }
      }

      Page {
        key: "notifX"
        width: Math.max(root.u(300), notifRowX.implicitWidth + root.u(32)) - root.u(32)
        height: root.compactH + root.u(18) + (root.shownPinned ? notifActionsX.height + root.u(10) : 0)
        NotifRow { id: notifRowX; y: (root.compactH - height) / 2 }
        Sub {
          y: root.compactH - root.u(4)
          width: parent.width
          elide: Text.ElideRight
          maximumLineCount: 1
          text: root.shownNotif ? root.shownNotif.body : ""
        }
        NotifActions {
          id: notifActionsX
          y: root.compactH + root.u(18)
          opacity: root.shownPinned ? 1 : 0
          visible: opacity > 0
          Behavior on opacity { NumberAnimation { duration: root.fadeMs } }
        }
        MouseArea {
          z: -1
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.pinNotification()
        }
      }

      // Expanded player: cover, title and artist with the equalizer, the
      // progress with both times (drag to seek), and solid controls.
      Page {
        id: mediaPage
        key: "mediaX"
        width: root.u(400)
        height: root.u(168)
        readonly property real pad: root.u(20)
        property bool seeking: false
        property real seekTo: 0
        readonly property real shownProgress: seeking ? seekTo : root.progress

        Cover {
          id: bigCover
          x: mediaPage.pad
          y: root.u(16)
          size: root.u(58)
          rounding: root.u(13)
        }
        MouseArea {
          anchors.fill: bigCover
          cursorShape: Qt.PointingHandCursor
          onClicked: root.focusPlayer()
        }

        Column {
          anchors.left: bigCover.right
          anchors.leftMargin: root.u(13)
          anchors.right: bigEq.left
          anchors.rightMargin: root.u(12)
          anchors.verticalCenter: bigCover.verticalCenter
          spacing: root.u(3)
          Marquee {
            text: root.title
            maxWidth: parent.width
            color: root.strong
            fadeColor: root.plate
            fontFamily: root.sansFont
            pixelSize: root.fontPx(15)
            weight: Font.DemiBold
            running: root.view === "mediaX"
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: root.artist || (root.player ? (root.player.identity || "") : "")
            color: root.muted
            font.family: root.sansFont
            font.pointSize: root.fontPt(13)
            textFormat: Text.PlainText
          }
        }

        EqBars {
          id: bigEq
          anchors.right: parent.right
          anchors.rightMargin: mediaPage.pad
          anchors.verticalCenter: bigCover.verticalCenter
          span: root.u(20)
          barW: root.u(3)
          spacing: root.u(2.6)
        }

        // progress: elapsed · bar · remaining
        Item {
          id: progressRow
          x: mediaPage.pad
          y: root.u(88)
          width: parent.width - 2 * mediaPage.pad
          height: root.u(14)
          visible: root.trackLength > 0
          Sub {
            id: posText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.trackClock(mediaPage.shownProgress * root.trackLength)
            font.features: ({ "tnum": 1 })
          }
          Sub {
            id: lenText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "-" + root.trackClock(root.trackLength * (1 - mediaPage.shownProgress))
            font.features: ({ "tnum": 1 })
          }
          Rectangle {
            id: track
            anchors.left: posText.right
            anchors.right: lenText.left
            anchors.leftMargin: root.u(10)
            anchors.rightMargin: root.u(10)
            anchors.verticalCenter: parent.verticalCenter
            height: seekArea.containsMouse || mediaPage.seeking ? root.u(6) : root.u(4)
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.16)
            Behavior on height { NumberAnimation { duration: root.fadeMs; easing.type: Easing.Bezier; easing.bezierCurve: root.ease } }
            Rectangle {
              width: Math.max(parent.height, parent.width * mediaPage.shownProgress)
              height: parent.height
              radius: height / 2
              color: seekArea.containsMouse || mediaPage.seeking ? root.strong : Qt.rgba(1, 1, 1, 0.72)
              Behavior on width { enabled: !mediaPage.seeking; NumberAnimation { duration: 500; easing.type: Easing.Linear } }
              Behavior on color { ColorAnimation { duration: root.fadeMs } }
            }
            MouseArea {
              id: seekArea
              anchors.fill: parent
              anchors.margins: -root.u(7)
              hoverEnabled: true
              enabled: root.player !== null && root.player.canSeek && root.trackLength > 0
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              function at(mx) { return Math.max(0, Math.min(1, (mx - root.u(7)) / track.width)) }
              onPressed: function(mouse) { mediaPage.seekTo = at(mouse.x); mediaPage.seeking = true }
              onPositionChanged: function(mouse) { if (pressed) mediaPage.seekTo = at(mouse.x) }
              onReleased: {
                root.player.position = mediaPage.seekTo * root.trackLength
                root.trackPos = mediaPage.seekTo * root.trackLength
                mediaPage.seeking = false
              }
              onCanceled: mediaPage.seeking = false
            }
          }
        }

        // controls
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          y: root.u(110)
          spacing: root.u(26)
          ControlButton {
            anchors.verticalCenter: parent.verticalCenter
            path: Icons.previousFill
            iconSize: root.u(22)
            enabledAction: root.player !== null && root.player.canGoPrevious
            onActivated: root.mediaPrevious()
          }
          ControlButton {
            anchors.verticalCenter: parent.verticalCenter
            path: root.playing ? Icons.pauseFill : Icons.playFill
            iconSize: root.u(28)
            enabledAction: root.player !== null && root.player.canTogglePlaying
            onActivated: root.mediaToggle()
          }
          ControlButton {
            anchors.verticalCenter: parent.verticalCenter
            path: Icons.nextFill
            iconSize: root.u(22)
            enabledAction: root.player !== null && root.player.canGoNext
            onActivated: root.mediaNext()
          }
        }

        MouseArea {
          anchors.fill: parent
          z: -1
          acceptedButtons: Qt.MiddleButton
          onClicked: root.mediaNext()
          onWheel: function(wheel) { root.mediaWheel(wheel.angleDelta.y) }
        }
      }

      Page {
        key: "screenX"
        width: root.u(280)
        height: root.u(62)
        PulseDot {
          x: root.u(20); y: root.u(31) - height / 2
          size: root.u(7)
          color: root.red
          running: root.view === "screenX"
        }
        Column {
          x: root.u(38); y: root.u(14)
          spacing: 1
          Sub { text: root.tr("GRAVANDO TELA") }
          Text {
            textFormat: Text.PlainText
            text: root.screenElapsed
            color: root.strong
            font.family: root.monoFont
            font.pixelSize: root.fontPx(16)
            font.weight: Font.Medium
            font.features: ({ "tnum": 1 })
          }
        }
        Rectangle {
          x: root.u(280 - 16) - width; y: root.u(18)
          width: stopRow.implicitWidth + root.u(22)
          height: root.u(28)
          radius: height / 2
          color: Qt.rgba(1, 1, 1, stopArea.pressed ? 0.14 : (stopArea.containsMouse ? 0.08 : 0.04))
          border.width: 0.6
          border.color: Qt.rgba(root.red.r, root.red.g, root.red.b, 0.5)
          Behavior on color { ColorAnimation { duration: root.fadeMs } }
          Row {
            id: stopRow
            anchors.centerIn: parent
            spacing: root.u(6)
            StrokeIcon { anchors.verticalCenter: parent.verticalCenter; size: root.u(12); color: root.red; path: Icons.stop }
            Label { anchors.verticalCenter: parent.verticalCenter; text: root.tr("PARAR"); color: root.red }
          }
          MouseArea {
            id: stopArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.run("omarchy-capture-screenrecording --stop-recording")
              root.hoverExpanded = false
            }
          }
        }
      }

      // Claude Code, on hover: the session's title, project and state, and
      // its last three steps (the newest at the bottom). A click goes to its
      // terminal.
      Page {
        id: claudePage
        key: "claudeX"
        width: root.u(380) - root.u(40)
        height: claudeCol.implicitHeight + root.u(26)
        readonly property var recent: root.claudeSteps.slice(-3)
        Column {
          id: claudeCol
          y: root.u(13)
          width: parent.width
          spacing: root.u(3)
          Item {
            width: parent.width
            height: claudeTitleText.implicitHeight
            ClaudeMark {
              id: claudeMarkX
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }
            Label {
              id: claudeTitleText
              anchors.left: claudeMarkX.right
              anchors.leftMargin: root.u(8)
              anchors.right: claudeMoreX.left
              anchors.rightMargin: root.u(8)
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: root.claudeTitle
            }
            Sub {
              id: claudeMoreX
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.claudeExtra > 0 ? "+" + root.claudeExtra : ""
            }
          }
          Sub {
            x: root.u(22)
            width: parent.width - x
            elide: Text.ElideRight
            color: root.claudeState === "waiting" ? root.amber : root.muted
            text: (root.shownClaude ? String(root.shownClaude.project || "") + "  ·  " : "")
              + (root.claudeState === "waiting" ? root.tr("Esperando você") : root.claudeState === "done" ? root.tr("Pronto") : root.tr("Trabalhando"))
          }
          Item { width: 1; height: root.u(5) }
          Repeater {
            model: claudePage.recent.length > 0 ? claudePage.recent : [null]
            delegate: Item {
              required property var modelData
              required property int index
              readonly property bool newest: index === claudePage.recent.length - 1 || modelData === null
              readonly property bool live: newest && root.claudeState !== "done"
              x: root.u(22)
              width: claudeCol.width - x
              height: root.u(18)
              StrokeIcon {
                id: stepIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                size: root.u(10)
                strokeWidth: 1.4
                color: live ? root.hi : root.muted
                path: live ? "M9 6l6 6-6 6" : "M5.5 12.5l4 4 9-9.5"
              }
              Text {
                anchors.left: stepIcon.right
                anchors.leftMargin: root.u(7)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                textFormat: Text.PlainText
                font.family: root.monoFont
                font.pointSize: root.fontPt(live ? 10.5 : 10)
                color: live ? root.strong : root.muted
                text: modelData ? root.claudeStep(modelData) : root.tr("Pensando…")
              }
            }
          }
        }
        MouseArea {
          anchors.fill: parent
          z: -1
          cursorShape: Qt.PointingHandCursor
          onClicked: root.focusClaude()
        }
      }

      // ---------------- on-demand cards (a click anywhere folds the notch back)
      Page {
        key: "card"
        width: cardLoader.item ? cardLoader.item.implicitWidth : 0
        height: cardLoader.item ? cardLoader.item.implicitHeight : 0
        Loader {
          id: cardLoader
          // Keep the last card loaded while the notch folds back, so it
          // fades instead of vanishing.
          property string loadedName: ""
          active: loadedName !== ""
          sourceComponent: root.cardComponent(loadedName)
          Connections {
            target: root
            function onCardNameChanged() { if (root.cardName !== "") cardLoader.loadedName = root.cardName }
            function onShownChanged() { if (!root.shown) cardLoader.loadedName = "" }
          }
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.closeCard()
        }
      }
    }
  }
}
