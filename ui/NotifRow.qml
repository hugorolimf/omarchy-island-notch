import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import ".."
import "../Icons.js" as Icons

// App icon + "App · title" (+N), shared by the compact and hover views.
Row {
  id: notifRow
  property var root
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
  Sub { root: notifRow.root
    anchors.verticalCenter: parent.verticalCenter
    text: root.notifAppName
  }
  Label { root: notifRow.root
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
  Sub { root: notifRow.root
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
