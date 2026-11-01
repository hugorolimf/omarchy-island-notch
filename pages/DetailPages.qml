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

// On hover: recording and Claude; and the on-demand cards.
Item {
  id: detailPages
  property var root
  anchors.fill: parent
  readonly property var refs: ({ claudeCol: claudeCol, cardLoader: cardLoader })

  Page { root: detailPages.root
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
      Sub { root: detailPages.root; text: root.tr("GRAVANDO TELA") }
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
        Label { root: detailPages.root; anchors.verticalCenter: parent.verticalCenter; text: root.tr("PARAR"); color: root.red }
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
  Page { root: detailPages.root
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
        ClaudeMark { root: detailPages.root
          id: claudeMarkX
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }
        Label { root: detailPages.root
          id: claudeTitleText
          anchors.left: claudeMarkX.right
          anchors.leftMargin: root.u(8)
          anchors.right: claudeMoreX.left
          anchors.rightMargin: root.u(8)
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          text: root.claudeTitle
        }
        Sub { root: detailPages.root
          id: claudeMoreX
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.claudeExtra > 0 ? "+" + root.claudeExtra : ""
        }
      }
      Sub { root: detailPages.root
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
  Page { root: detailPages.root
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
      // the text box cards are used with the mouse too
      enabled: root.cardName !== "ask"
      cursorShape: Qt.PointingHandCursor
      onClicked: root.closeCard()
    }
  }
}
