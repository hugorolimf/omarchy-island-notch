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

// Notifications: compact, the iPhone strip and pinned.
Item {
  id: notifPages
  property var root
  anchors.fill: parent
  readonly property var refs: ({ iphoneMiniRow: iphoneMiniRow, notifActionsX: notifActionsX })

  Page { root: notifPages.root
    key: "notif"
    width: notifRow.implicitWidth
    height: root.compactH
    NotifRow { root: notifPages.root; id: notifRow; anchors.verticalCenter: parent.verticalCenter }
    MouseArea {
      z: -1
      anchors.fill: parent
      anchors.leftMargin: -root.u(16)
      anchors.rightMargin: -root.u(16)
      cursorShape: Qt.PointingHandCursor
      onClicked: root.pinNotification()
    }
  }

  // iPhone, mini: the app's icon, who sent it and the start of the text
  Page { root: notifPages.root
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
      Label { root: notifPages.root
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root.u(130))
        elide: Text.ElideRight
        text: root.shownNotif ? (iphoneMiniRow.code ? root.shownNotif.body : root.shownNotif.title) : ""
      }
      Sub { root: notifPages.root
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root.u(170))
        elide: Text.ElideRight
        visible: text !== "· "
        text: "· " + (root.shownNotif ? (iphoneMiniRow.code ? root.shownNotif.copy : root.shownNotif.body) : "")
      }
      Sub { root: notifPages.root
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

  Page { root: notifPages.root
    key: "notifX"
    width: Math.max(root.u(300), notifRowX.implicitWidth + root.u(32)) - root.u(32)
    height: root.compactH + root.u(18) + (root.shownPinned ? notifActionsX.height + root.u(10) : 0)
    NotifRow { root: notifPages.root; id: notifRowX; y: (root.compactH - height) / 2 }
    Sub { root: notifPages.root
      y: root.compactH - root.u(4)
      width: parent.width
      elide: Text.ElideRight
      maximumLineCount: 1
      text: root.shownNotif ? root.shownNotif.body : ""
    }
    NotifActions { root: notifPages.root
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
}
