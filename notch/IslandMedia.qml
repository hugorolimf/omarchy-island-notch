import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "../Icons.js" as Icons
import "../Shared.js" as Shared

// Island Notch: the player, the equalizer, the album colour, the notification state and the
// on-screen indicators.
IslandState {
  id: root
  // used by the other parts of the notch
  readonly property var iphoneIconRetry: iphoneIconRetry

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

  // The assistant's answer takes Tab the same way: it opens the conversation
  // with the cursor in the box (not while it thinks: that can take minutes).
  readonly property bool tabWanted: (activity === "notif" && !notifPinned)
    || (activity === "ask" && askState === "answer" && cardName === "")
    || (cardName === "ask" && cardPassive && !askBusy)
  onTabWantedChanged: setTabBind(tabWanted)
  // a new answer re-arms the 30 s guard, and so does time while the voice
  // chat stays up (it can stay longer than that)
  onAskChanged: { if (tabWanted) setTabBind(true); if (askLinger.running) askLinger.restart() }
  Timer { interval: 20000; repeat: true; running: root.tabWanted; onTriggered: root.setTabBind(true) }
  // One entry per screen in a Lua table, so two notches don't unbind each
  // other; a shell that dies with Tab bound gives it back after 30 s.
  function setTabBind(on) {
    var key = "island_tab[" + JSON.stringify(screenName || "?") + "]"
    Quickshell.execDetached(["hyprctl", "eval", on
      ? "island_tab = island_tab or {} "
        + "if next(island_tab) == nil then hl.bind('TAB', function() hl.exec_cmd('omarchy-shell -q io.github.hugorolimf.island pinKeys') end, { description = 'Island Notch: open the notification or the conversation' }) end "
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
    // Play, pause, next, previous: the player itself is the feedback (it
    // opens with the cover and the new title), so the track's name is not
    // flashed first. Switching the source still shows.
    var k = String(h.key || "")
    if (player && /^(media|player)(-(play|pause|next|previous))?$/.test(k)) return
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
}
