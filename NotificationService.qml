// Island Notch's notification server: every notification shows in the notch,
// lands in the history the Island Inbox reads, and Do Not Disturb, actions
// and inline replies work as with Omarchy's own notifications service, whose
// `notifications` IPC (and therefore its keybindings) it keeps.
//
// It only serves while no other notifications service does (Omarchy's
// omarchy.notifications, or a clone of it): two servers in one shell would
// show every notification twice. See README, "Install".
//
// Nothing a notification says is ever put in a process's arguments, which
// other accounts can read: the notch is handed it in process (through Shared.js), and history files are
// written from stdin into folders only this account can open.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

import "Shared.js" as Shared
import "notifications"

// The server is split in notifications/: NotifStore (history files, Do Not
// Disturb) <- NotifPayload (what the notch gets) <- NotifDelivery (serving,
// holding, releasing) <- this file (the notch link and the IPC).
NotifDelivery {
  id: service


  // Injected by omarchy-shell (the service loader).
  property var shell: null

  // The notch (BarWidget.qml) shows them, reached in process through
  // Shared.js. Without a notch up they still land in history.
  function notchNotification(payload) {
    var notch = Shared.leaderItem()
    if (notch) notch.deliverNotification(payload)
  }
  // "dismissOne" | "dismissAll", from the keybindings.
  function notchCommand(name) {
    var notch = Shared.leaderItem()
    if (notch) notch.dismissNotifications(name === "dismissOne")
  }

  // ---------------------------------------------------- IPC
  //
  // The same `notifications` target as Omarchy's service: its keybindings
  // (Super+, and friends) and the Island Inbox keep working. Registered only
  // while this service is the one serving.

  // Reads the private reply file handed over by replyFile().
  FileView {
    id: replyReader
    blockLoading: true
    printErrors: false
  }

  Loader {
    active: service.serverOn
    sourceComponent: Item {
      IpcHandler {
        target: "notifications"

        function dndState(): string { return service.doNotDisturb ? "on" : "off" }

        function toggleDnd(): string {
          service.setDoNotDisturb(!service.doNotDisturb)
          return dndState()
        }

        function setDnd(value: string): string {
          var v = String(value || "").toLowerCase()
          service.setDoNotDisturb(v === "true" || v === "1" || v === "on" || v === "yes")
          return dndState()
        }

        function isDnd(): string { return dndState() }

        // The history is the Island Inbox's panel (the bell).
        function showHistory(): string {
          Quickshell.execDetached(["omarchy-shell", "-q", "io.github.hugorolimf.inbox", "toggle"])
          return "ok"
        }

        // Forgets the recorded history.
        function clear(): string {
          service.clearHistory()
          return "ok"
        }

        function dismissAll(): string {
          service.notchCommand("dismissAll")
          return "ok"
        }

        function dismissOne(): string {
          service.notchCommand("dismissOne")
          return "ok"
        }

        function invokeLast(): string { return service.invokeLast() }

        // Answer a notification that offers a reply field.
        function reply(id: string, text: string): string {
          var ref = service.liveRefs[id]
          if (!ref || !ref.hasInlineReply) return "gone"
          try { ref.sendInlineReply(String(text || "")) } catch (e) { return "error" }
          return "ok"
        }

        // Same reply, the text in a private file under
        // $XDG_RUNTIME_DIR/island-notch (the notch's reply box writes it):
        // read here and removed.
        function replyFile(id: string, path: string): string {
          var p = String(path || "")
          var dir = Quickshell.env("XDG_RUNTIME_DIR") + "/island-notch/"
          if (p.indexOf(dir) !== 0 || p.indexOf("..") !== -1) return "error"
          replyReader.path = p
          var t = replyReader.text()
          replyReader.path = ""
          Quickshell.execDetached(["rm", "-f", "--", p])
          return reply(id, t)
        }

        function invokeAction(id: string, identifier: string): string {
          return service.invokeAction(id, String(identifier || ""))
        }

        function ping(): string { return "ok" }
      }

      NotificationServer {
        keepOnReload: false
        imageSupported: true
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        persistenceSupported: true
        // Senders may offer a reply field (Tether: SMS / iMessage replies go
        // out through the iPhone); the notch draws it.
        inlineReplySupported: true

        onNotification: function(notification) {
          service.handleNotification(notification)
        }
      }
    }
  }
}
