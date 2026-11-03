import QtQuick
import Quickshell
import Quickshell.Io

// Island Notch: the voice assistant (F10), optional. Its scripts write to
// $XDG_RUNTIME_DIR/assistente: notch.json (listening, thinking, missed,
// answer, and the day's thread), fila.json (what was said while it answered)
// and modelos.json (Claude Code's models and the one chosen). Only the leader
// watches the folder (IslandWatch). Drawn like dictation. Without
// assistente-voz on the PATH all of this stays asleep.
IslandState {
  id: root
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
  // oldest first: {quem: voce|claude, texto, hora, via|ok, parado}.
  // Yesterday's thread is not shown: the next question starts a new one.
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
  function askRun(args) {
    Quickshell.execDetached(["sh", "-c", "PATH=\"$PATH:$HOME/.local/bin\"; exec assistente \"$@\" </dev/null >/dev/null 2>&1", "sh"].concat(args))
  }
  // fila.json and modelos.json changed (IslandWatch's inotify)
  function askFileChanged(name) {
    if (name === "fila.json") queueRead.reload()
    else if (name === "modelos.json") modelsRead.reload()
  }

  // ---- which model answers (the model chip in the card): the list is
  // Claude Code's own (/model), asked again when the card opens and when
  // the list opens, never written here; the choice goes to assistente.
  property var srcModels: null
  readonly property var askModelsInfo: leader ? leader.srcModels : null
  readonly property var askModels: askModelsInfo && Array.isArray(askModelsInfo.modelos) ? askModelsInfo.modelos : []
  readonly property string askModel: askModelsInfo && askModelsInfo.escolhido ? String(askModelsInfo.escolhido) : ""
  readonly property var askModelInfo: {
    var list = askModels
    for (var i = 0; i < list.length; i++) if (list[i].valor === askModel) return list[i]
    return null
  }
  function modelName(m) { return m ? String((portuguese ? m.nome_pt : m.nome) || m.nome || m.valor) : "" }
  function modelNote(m) { return m ? String((portuguese ? m.descricao_pt : m.descricao) || m.descricao || "") : "" }
  // the chip's name: «Padrão (recomendado)» is «Padrão» there
  readonly property string askModelName: askModelInfo ? modelName(askModelInfo).replace(/ \(.*\)$/, "") : askModel
  // no list (a script of your own without one): the card has no model to pick
  readonly property bool askHasModels: askModels.length > 0
  function pickAskModel(value) {
    if (!/^[A-Za-z0-9._:\[\]-]+$/.test(String(value)) || !leader) return
    var copy = {}
    var a = leader.srcModels || {}
    for (var k in a) copy[k] = a[k]
    copy.escolhido = value
    leader.srcModels = copy
    askRun(["--modelo", value])
  }
  // after a while (or on demand) Claude Code is asked again
  function refreshAskModels(force) {
    var info = askModelsInfo
    if (!force && info && Date.now() - (info.ts || 0) < 600000) return
    if (!askRefresh.running) askRefresh.running = true
  }
  Process {
    id: askRefresh
    command: ["sh", "-c", "PATH=\"$PATH:$HOME/.local/bin\"; exec assistente --modelos </dev/null >/dev/null 2>&1"]
  }
  FileView {
    id: modelsRead
    path: root.isLeader && root.askInstalled ? root.askDir + "/modelos.json" : ""
    printErrors: false
    onLoaded: { try { root.srcModels = JSON.parse(text()) } catch (e) {} }
  }

  // ---- how hard it thinks (PENSAMENTO in the card): the levels the chosen
  // model takes, of Claude's five; assistente keeps the choice and echoes it
  // in notch.json. A model without levels hides the pill. A click steps up
  // (after the top, back to the bottom), a right click steps down.
  readonly property var askAllEfforts: ["low", "medium", "high", "xhigh", "max"]
  readonly property var askEfforts: askModelInfo && Array.isArray(askModelInfo.esforcos) ? askModelInfo.esforcos : askAllEfforts
  readonly property bool askHasEffort: askEfforts.length > 0
  // the level it will use: the chosen one, or the nearest below it the model takes
  readonly property string askEffort: {
    var chosen = ask && askAllEfforts.indexOf(ask.esforco) >= 0 ? ask.esforco : "high"
    var levels = askEfforts
    if (levels.indexOf(chosen) >= 0 || levels.length === 0) return chosen
    var best = levels[0]
    for (var i = 0; i < levels.length; i++)
      if (askAllEfforts.indexOf(levels[i]) <= askAllEfforts.indexOf(chosen)) best = levels[i]
    return best
  }
  readonly property var askEffortLabel: ({ "low": "BAIXO", "medium": "MÉDIO", "high": "ALTO", "xhigh": "EXTRA", "max": "MÁXIMO" })
  function cycleAskEffort(step) {
    var order = askEfforts
    if (order.length === 0) return
    var next = order[(order.indexOf(askEffort) + (step || 1) + order.length) % order.length]
    if (leader) {
      var a = leader.srcAsk || {}
      var copy = {}
      for (var k in a) copy[k] = a[k]
      copy.esforco = next
      leader.srcAsk = copy
    }
    askRun(["--esforco", next])
  }

  // ---- the conversation card (F10 tap, card "ask"): the question goes to a
  // private file through the shell's stdin, never a command line;
  // assistente-voz texto reads and deletes it. The card stays open: the
  // question shows in the thread at once, then the answer under it. Sent
  // while it answers, it joins the queue instead (assistente decides).
  // Holding F10 with the card open talks inside it too.
  property string askText: ""
  function sendAsk(text) {
    var t = String(text || "").trim()
    if (!t || askState === "listening" || askSend.running) return false
    askText = t
    askSend.stdinEnabled = true
    askSend.running = true
    if (askState === "thinking") queueLocal(t)
    else setAsk("thinking", t)
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
    askRun(["--nova"])
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

  // ---- the queue, as in Claude Code: sent while it answers, they wait
  // dimmed under the answer and go in together when it ends. A click takes
  // one back to the box to edit it; the stop button puts them all back there.
  property var srcQueue: []
  readonly property var askQueue: leader ? leader.srcQueue : []
  // on its way to the queue, before fila.json says so
  function queueLocal(t) {
    if (leader) leader.srcQueue = leader.srcQueue.concat([{ id: "", texto: t, hora: Qt.formatTime(new Date(), "HH:mm"), via: "texto" }])
  }
  function unqueueAsk(item) {
    if (!leader || !item) return
    leader.srcQueue = leader.srcQueue.filter(function(m) { return m !== item && (item.id === "" || m.id !== item.id) })
    if (/^[0-9a-f]+$/.test(String(item.id))) askRun(["--tirar-da-fila", String(item.id)])
  }
  FileView {
    id: queueRead
    path: root.isLeader && root.askInstalled ? root.askDir + "/fila.json" : ""
    printErrors: false
    onLoaded: { try { var d = JSON.parse(text()); root.srcQueue = Array.isArray(d.fila) ? d.fila : [] } catch (e) {} }
  }

  // ---- the stop button (Esc while it answers): interrupts the answer and
  // drops the queue; returns the queued text, for the box.
  property bool askStopping: false
  onAskStateChanged: if (askState !== "thinking") {
    askStopping = false
    // what was drawn ahead of fila.json: a script without a queue never writes one
    if (isLeader) srcQueue = srcQueue.filter(function(m) { return m.id !== "" })
  }
  function stopAsk() {
    if (askState !== "thinking") return ""
    var back = askQueue.map(function(m) { return String(m.texto || "") }).filter(function(t) { return t !== "" }).join("\n\n")
    if (leader) leader.srcQueue = []
    askStopping = true
    askStop.running = true
    return back
  }
  Process {
    id: askStop
    command: ["sh", "-c", "PATH=\"$PATH:$HOME/.local/bin\"; exec assistente --parar </dev/null >/dev/null 2>&1"]
    // nothing was answering (an old «Pensando…»): just let it go
    onExited: function(code) { if (code !== 0) { root.askStopping = false; root.setAsk("idle", "") } }
  }
}
