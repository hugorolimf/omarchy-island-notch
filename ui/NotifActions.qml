import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import ".."
import "../Icons.js" as Icons

// The actions of a pinned notification: its own (reply, open) and close.
Row {
  id: notifActions
  property var root
  spacing: root.u(8)
  ActionPill { root: notifActions.root
    label: root.notifActionLabel
    accent: true
    // an iPhone notification only has the phone's own actions
    visible: root.notifHasOpen
    selected: root.notifRing(0)
    onActivated: root.focusNotificationApp()
  }
  Repeater {
    model: root.shownNotif && root.shownNotif.actions ? root.shownNotif.actions : []
    delegate: ActionPill { root: notifActions.root
      required property var modelData
      required property int index
      label: String(modelData.label).toUpperCase()
      selected: root.notifRing((root.notifHasOpen ? 1 : 0) + index)
      onActivated: {
        Quickshell.execDetached(modelData.open)
        root.dismissNotification()
      }
    }
  }
  ActionPill { root: notifActions.root
    label: root.tr("FECHAR")
    selected: root.notifRing(root.notifButtonCount - 1)
    onActivated: root.dismissNotification()
  }
}
