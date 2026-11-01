import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "notch"
import "pages"
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
//
// The logic lives in notch/, one concern per file, each extending the one
// before it (IslandState → IslandMedia → … → IslandIpc); the pages are in
// pages/ and the small shared pieces in ui/.
IslandIpc {
  id: root

  // Registered from this file, not from notch/: imported as "../Shared.js" the
  // library loads as a second copy, and NotificationService.qml and
  // NotchBridge.qml, which import it as "Shared.js", would find no notch.
  Component.onCompleted: Shared.register(root)
  Component.onDestruction: Shared.unregister(root)

  // what the logic (notch/) reaches in the window and the pages
  readonly property var overlay: overlay
  readonly property var body: body
  readonly property var keyCatcher: keyCatcher
  readonly property var weatherCardComponent: weatherCardComponent
  readonly property var askCardComponent: askCardComponent
  readonly property var hudRow: compactPages.refs.hudRow
  readonly property var screenRow: compactPages.refs.screenRow
  readonly property var claudeMini: compactPages.refs.claudeMini
  readonly property var mediaMini: compactPages.refs.mediaMini
  readonly property var reminderRow: compactPages.refs.reminderRow
  readonly property var transRow: compactPages.refs.transRow
  readonly property var askListenRow: voicePages.refs.askListenRow
  readonly property var askThinkPage: voicePages.refs.askThinkPage
  readonly property var askThinkCol: voicePages.refs.askThinkCol
  readonly property var askMissedRow: voicePages.refs.askMissedRow
  readonly property var askCol: voicePages.refs.askCol
  readonly property var dictRow: voicePages.refs.dictRow
  readonly property var iphoneMiniRow: notifPages.refs.iphoneMiniRow
  readonly property var notifActionsX: notifPages.refs.notifActionsX
  readonly property var claudeCol: detailPages.refs.claudeCol
  readonly property var cardLoader: detailPages.refs.cardLoader
  readonly property var iphoneCard: iphonePage.refs.iphoneCard
  readonly property var replyBox: iphonePage.refs.replyBox
  readonly property var replyInput: iphonePage.refs.replyInput

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

  // Inside a Component "root" names the object made from it, so the card
  // gets the notch through this other name.
  readonly property var island: root
  Component {
    id: askCardComponent
    AskCard { root: island }
  }

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
    WlrLayershell.keyboardFocus: root.cardName !== "" && !root.cardPassive
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
      active: overlay.grabArmed && ((root.cardName !== "" && !root.cardPassive) || root.notifPinned || root.mediaPinned)
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

      // the pages, one per view (pages/)
      CompactPages { id: compactPages; root: root }
      VoicePages { id: voicePages; root: root }
      NotifPages { id: notifPages; root: root }
      DetailPages { id: detailPages; root: root }
      IphonePage { id: iphonePage; root: root }
      MediaPage { id: mediaPage; root: root }
    }
  }
}
