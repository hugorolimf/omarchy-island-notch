import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Ui as OUi
import "../Icons.js" as Icons
import "../Shared.js" as Shared

// Island Notch: tokens, the leader, and the state of dictation, the microphone, screen recording,
// reminders, the voice assistant and Claude Code sessions.
OUi.BarWidget {
  id: root
  moduleName: "io.github.hugorolimf.island"
  // Portuguese, or English for every other locale.
  readonly property bool portuguese: Qt.locale().name.indexOf("pt") === 0
  readonly property var enText: ({"RESPONDER": "REPLY", "ABRIR": "OPEN", "ABRIR APP": "OPEN APP", "ABRIR IPHONE": "OPEN IPHONE", "FECHAR": "CLOSE", "COPIADO": "COPIED", "COPIAR": "COPY", "Gravando": "Recording", "Transcrevendo…": "Transcribing…", "Ditando…": "Dictating…", "Responder…": "Reply…", "GRAVANDO TELA": "RECORDING SCREEN", "PARAR": "STOP", "  ·  agora": "  ·  now", "Lembrete": "Reminder", "Ouvindo…": "Listening…", "Pensando…": "Thinking…", "Não entendi": "Didn't catch that", "Assistente": "Assistant", "Você: ": "You: ", "clique para abrir a conversa": "click to open the conversation", "Pergunte ao assistente…": "Ask the assistant…", "Responda ao assistente…": "Reply to the assistant…", "enter envia · esc fecha": "enter sends · esc closes", 
    "Pensando…": "Thinking…", "Esperando você": "Waiting for you", "Pronto": "Done", "Trabalhando": "Working",
    "Edita": "Edits", "Escreve": "Writes", "Lê": "Reads", "Roda:": "Runs:", "Busca": "Searches", "Procura": "Finds",
    "Delega:": "Delegates:", "Abre": "Opens", "Pesquisa": "Looks up", "Atualiza as tarefas": "Updates the to-dos",
    "Pergunta para você": "Asks you", "Mostra o plano": "Shows the plan", "Usa a skill": "Uses the skill",
    "Agente terminou:": "Agent done:", "Usa": "Uses",
    "NOVA": "NEW", "VOZ": "VOICE", "TEXTO": "TEXT", "PENSAMENTO": "THINKING", "BAIXO": "LOW", "MÉDIO": "MEDIUM", "ALTO": "HIGH", "EXTRA": "EXTRA", "MÁXIMO": "MAX",
    "tab ou clique para responder · segure F10 para falar": "tab or click to reply · hold F10 to talk",
    "segure F10 para falar · ↑↓ rola · ←→ botões · tab fecha": "hold F10 to talk · ↑↓ scroll · ←→ buttons · tab closes",
    "enter envia · shift+enter quebra a linha · tab fecha": "enter sends · shift+enter new line · tab closes",
    "tab ou clique para escrever · segure F10 para falar": "tab or click to type · hold F10 to talk",
    "Escreva ou segure o F10 e fale. Ele lembra do que vocês já conversaram hoje.": "Type, or hold F10 and talk. It remembers what you've said today."})
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
    || (cardName === "ask" && askState === "listening")
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
  // ---- voice assistant, optional: a script writes its state to
  // $XDG_RUNTIME_DIR/assistente/notch.json (listening, thinking, missed,
  // answer); only the leader watches it. Drawn like dictation. Without
  // assistente-voz on the PATH all of this stays asleep.
  property bool askInstalled: false
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
  readonly property bool askBusy: askState === "listening" || askState === "thinking"
  // The day's conversation (assistente keeps it; notch.json carries it),
  // oldest first: {quem: voce|claude, texto, hora, via|ok}. Yesterday's
  // thread is not shown: the next question starts a new one.
  readonly property var askThread: {
    var a = ask
    if (!a || !Array.isArray(a.thread)) return []
    return a.dia === Qt.formatDate(new Date(askNow), "yyyy-MM-dd") ? a.thread : []
  }
  // A state written here before the scripts answer keeps the thread on screen.
  function setAsk(state, heard) {
    if (!leader) return
    var a = leader.srcAsk || {}
    leader.srcAsk = { state: state, heard: heard || "", answer: "", ok: state !== "missed", open: a.open || "",
      dia: a.dia || "", thread: Array.isArray(a.thread) ? a.thread : [], esforco: a.esforco || "", ts: Date.now() }
    leader.askNow = Date.now()
  }
  // How hard it thinks (PENSAMENTO in the card): Claude's five effort
  // levels; assistente keeps the choice and echoes it in notch.json. A click
  // steps up (after the top, back to the bottom), a right click steps down.
  readonly property var askEfforts: ["low", "medium", "high", "xhigh", "max"]
  readonly property string askEffort: ask && askEfforts.indexOf(ask.esforco) >= 0 ? ask.esforco : "high"
  readonly property var askEffortLabel: ({ "low": "BAIXO", "medium": "MÉDIO", "high": "ALTO", "xhigh": "EXTRA", "max": "MÁXIMO" })
  function cycleAskEffort(step) {
    var order = askEfforts
    var next = order[(order.indexOf(askEffort) + (step || 1) + order.length) % order.length]
    if (leader) {
      var a = leader.srcAsk || {}
      var copy = {}
      for (var k in a) copy[k] = a[k]
      copy.esforco = next
      leader.srcAsk = copy
    }
    Quickshell.execDetached(["sh", "-c", "PATH=\"$PATH:$HOME/.local/bin\"; exec assistente --esforco \"$1\" </dev/null >/dev/null 2>&1", "sh", next])
  }

  // The conversation card (F10 tap, card "ask"): the question goes to a
  // private file through the shell's stdin, never a command line;
  // assistente-voz texto reads and deletes it. The card stays open: the
  // question shows in the thread at once, then the answer under it.
  // Holding F10 with the card open talks inside it too.
  property string askText: ""
  function sendAsk(text) {
    var t = String(text || "").trim()
    if (!t || askBusy) return false
    askText = t
    askSend.stdinEnabled = true
    askSend.running = true
    setAsk("thinking", t)
    return true
  }
  // NOVA: forget the conversation (assistente --nova), the next question
  // opens another Claude session; the old one stays in the day's note.
  function newAsk() {
    if (askBusy) return
    if (leader && leader.srcAsk) {
      var a = leader.srcAsk
      leader.srcAsk = { state: "idle", heard: "", answer: "", ok: true, open: a.open || "", dia: a.dia || "", thread: [], esforco: a.esforco || "", ts: Date.now() }
    }
    Quickshell.execDetached(["sh", "-c", "PATH=\"$PATH:$HOME/.local/bin\"; exec assistente --nova </dev/null >/dev/null 2>&1"])
  }
  Process {
    id: askSend
    command: ["sh", "-c",
      "umask 077; PATH=\"$PATH:$HOME/.local/bin\"; command -v assistente-voz >/dev/null || exit 1; "
      + "d=\"${XDG_RUNTIME_DIR:?}/assistente\"; mkdir -p \"$d\" && chmod 700 \"$d\" || exit 1; "
      + "f=$(mktemp \"$d/texto.XXXXXX\") || exit 1; cat > \"$f\"; "
      + "setsid -f assistente-voz texto \"$f\" </dev/null >/dev/null 2>&1"]
    onStarted: { write(root.askText); stdinEnabled = false; root.askText = "" }
    onExited: function(code) { if (code !== 0) root.setAsk("missed", "") }
  }
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
      if (s.id === claudeStickyId && (hoverExpanded || claudeNow - (s.updated || 0) < 10000)) return s
    }
    return live[0]
  }
  // "claudeWork": false in the widget's shell.json entry keeps Claude at work
  // out of the notch; its notifications still show
  readonly property bool claudeShown: setting("claudeWork", true) !== false
  readonly property bool claudeActive: claudeShown && claudeSession !== null
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
}
