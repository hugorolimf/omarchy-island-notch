import QtQuick
import "Shared.js" as Shared

// In-process door to the notch for other plugins (Island iPhone): they load
// this file with a Loader by relative path, so a missing notch is a failed
// Loader rather than a broken import, and call deliver() with the payload of
// the `notify` IPC. Nothing passes through a process's arguments. Returns
// false while no notch is up.
Item {
  function deliver(payload) {
    var notch = Shared.leaderItem()
    if (!notch || typeof notch.deliverNotification !== "function" || !payload || typeof payload !== "object") return false
    return notch.deliverNotification(payload) === "ok"
  }
}
