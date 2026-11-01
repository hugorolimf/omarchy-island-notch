import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import ".."
import "../ui"
import "../Icons.js" as Icons

// Compact views: indicators, music, recording, Claude, reminders, transcribing.
Item {
  id: compactPages
  property var root
  anchors.fill: parent
  readonly property var refs: ({ hudRow: hudRow, screenRow: screenRow, claudeMini: claudeMini, mediaMini: mediaMini, reminderRow: reminderRow, transRow: transRow })

  // On-screen indicator: icon, a rounded bar easing to the new level and
  // the number; or icon + message (Caps Lock, layout, …).
  Page { root: compactPages.root
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
      Label { root: compactPages.root
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
  // equalizer at the other and, between them, the title sliding past with
  // the artist under it (smaller, dimmer).
  Page { root: compactPages.root
    id: mediaMini
    key: "media"
    // hugs the longer line, up to a cap; a longer title slides past
    readonly property real textCap: root.u(118)
    readonly property real textW: Math.min(textCap, Math.max(mediaTitle.implicitWidth, Math.ceil(artistSize.advanceWidth)))
    width: Math.max(root.u(140), mediaCover.width + root.u(10) + textW + root.u(12) + mediaEq.width)
    height: root.mediaMiniH
    Cover { root: compactPages.root
      id: mediaCover
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      size: root.u(24)
      rounding: root.u(6)
      opacity: root.playing ? 1 : 0.7
      Behavior on opacity { NumberAnimation { duration: root.fadeMs } }
    }
    Column {
      anchors.left: mediaCover.right
      anchors.leftMargin: root.u(10)
      anchors.verticalCenter: parent.verticalCenter
      width: mediaMini.textW
      spacing: 0
      Marquee {
        id: mediaTitle
        text: root.title
        maxWidth: mediaMini.textCap
        color: root.playing ? root.strong : root.muted
        fadeColor: root.plate
        fontFamily: root.sansFont
        pixelSize: root.fontPx(12)
        weight: Font.DemiBold
        // one pass per track: a strip that keeps moving pulls the eye
        passes: 1
        pause: 1200
        running: root.view === "media" && root.playing
      }
      Text {
        id: mediaArtist
        width: parent.width
        elide: Text.ElideRight
        text: root.artist
        visible: text !== ""
        color: root.muted
        font.family: root.sansFont
        font.pointSize: root.fontPt(10.5)
        textFormat: Text.PlainText
      }
    }
    TextMetrics { id: artistSize; font: mediaArtist.font; text: root.artist }
    EqBars { root: compactPages.root
      id: mediaEq
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      span: root.u(13)
    }
    MouseArea {
      anchors.fill: parent
      anchors.leftMargin: -root.u(12)
      anchors.rightMargin: -root.u(12)
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        if (mouse.button === Qt.MiddleButton) root.mediaNext()
        else root.mediaPinned = true
      }
      onWheel: function(wheel) { root.mediaWheel(wheel.angleDelta.y) }
    }
  }

  Page { root: compactPages.root
    key: "screen"
    width: screenRow.implicitWidth
    height: root.compactH
    Row {
      id: screenRow
      anchors.verticalCenter: parent.verticalCenter
      spacing: root.u(7)
      PulseDot { anchors.verticalCenter: parent.verticalCenter; size: root.u(6); color: root.red; running: root.view === "screen" }
      Label { root: compactPages.root; anchors.verticalCenter: parent.verticalCenter; text: root.tr("Gravando") }
      Sub { root: compactPages.root; anchors.verticalCenter: parent.verticalCenter; text: root.screenElapsed; font.features: ({ "tnum": 1 }) }
    }
  }

  // Claude Code at work: its state and the current step, rolling over.
  Page { root: compactPages.root
    id: claudeMini
    key: "claude"
    // mark + current step + count, up to the old fixed size
    width: Math.min(root.u(300) - root.u(32), claudeMark.width + root.u(8) + claudeTicker.textWidth
      + (root.claudeExtra > 0 ? root.u(8) + claudeMore.implicitWidth : 0))
    height: root.compactH
    ClaudeMark { root: compactPages.root
      id: claudeMark
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }
    Ticker { root: compactPages.root
      id: claudeTicker
      anchors.left: claudeMark.right
      anchors.leftMargin: root.u(8)
      anchors.right: claudeMore.left
      anchors.rightMargin: root.claudeExtra > 0 ? root.u(8) : 0
      anchors.verticalCenter: parent.verticalCenter
      text: root.claudeLine
      color: root.claudeState === "waiting" ? root.amber : root.strong
    }
    Sub { root: compactPages.root
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

  Page { root: compactPages.root
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
      Label { root: compactPages.root
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root.u(170))
        elide: Text.ElideRight
        text: root.reminder ? (root.reminder.message || root.tr("Lembrete")) : ""
      }
      Sub { root: compactPages.root; anchors.verticalCenter: parent.verticalCenter; text: root.reminderLeft; font.features: ({ "tnum": 1 }) }
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.run("omarchy-reminder show")
    }
  }

  Page { root: compactPages.root
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
      Label { root: compactPages.root; anchors.verticalCenter: parent.verticalCenter; text: root.tr("Transcrevendo…") }
    }
  }
}
