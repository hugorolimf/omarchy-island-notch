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

// iPhone notification, read like a macOS banner: the app's icon, who
// sent it in bold, app and time on the right, the text below in sans.
Page {
  id: page
  readonly property var refs: ({ iphoneCard: iphoneCard, replyBox: replyBox, replyInput: replyInput })
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
        onStatusChanged: if (status === Image.Error && root.iphoneIconTries < 2) root.iphoneIconRetry.restart()
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
      NotifActions { root: page.root
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
