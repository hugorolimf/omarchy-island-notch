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

  Cover { root: mediaPage.root
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

  EqBars { root: mediaPage.root
    id: bigEq
    anchors.right: parent.right
    anchors.rightMargin: mediaPage.pad
    anchors.verticalCenter: bigCover.verticalCenter
    span: root.u(20)
    barW: root.px(3)
    spacing: root.px(4)
  }

  // progress: elapsed · bar · remaining
  Item {
    id: progressRow
    x: mediaPage.pad
    y: root.u(88)
    width: parent.width - 2 * mediaPage.pad
    height: root.u(14)
    visible: root.trackLength > 0
    Sub { root: mediaPage.root
      id: posText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: root.trackClock(mediaPage.shownProgress * root.trackLength)
      font.features: ({ "tnum": 1 })
    }
    Sub { root: mediaPage.root
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
    ControlButton { root: mediaPage.root
      anchors.verticalCenter: parent.verticalCenter
      path: Icons.previousFill
      iconSize: root.u(22)
      enabledAction: root.player !== null && root.player.canGoPrevious
      onActivated: root.mediaPrevious()
    }
    ControlButton { root: mediaPage.root
      anchors.verticalCenter: parent.verticalCenter
      path: root.playing ? Icons.pauseFill : Icons.playFill
      iconSize: root.u(28)
      enabledAction: root.player !== null && root.player.canTogglePlaying
      onActivated: root.mediaToggle()
    }
    ControlButton { root: mediaPage.root
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
