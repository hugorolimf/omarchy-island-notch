.pragma library

// State shared by every Island Notch instance in the shell (the bar makes one
// per monitor). The first live instance is the leader: only it runs the
// status processes; the others read its properties.

var instances = []

function alive(item) {
  try { return !!item && item.moduleName === "io.github.hugorolimf.island" } catch (e) { return false }
}

function elect() {
  instances = instances.filter(alive)
  var leader = instances.length > 0 ? instances[0] : null
  for (var i = 0; i < instances.length; i++) instances[i].leader = leader
}

function register(item) {
  if (instances.indexOf(item) === -1) instances.push(item)
  elect()
}

function unregister(item) {
  var i = instances.indexOf(item)
  if (i !== -1) instances.splice(i, 1)
  elect()
}

// The leader, for NotificationService.qml: it hands notifications over here,
// in process, so what they say never sits in a process's arguments. (A
// replacement bar such as Island Bar gives its widgets no handle on services,
// so the service reaches the widgets instead.) null while no notch is up.
function leaderItem() {
  instances = instances.filter(alive)
  return instances.length > 0 ? instances[0] : null
}
