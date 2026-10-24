import AppKit

enum OSDFeedbackOrigin { case command, sidebar }
enum OSDMessage { case fileStart, normal
  var isSettingFeedback: Bool { false }
  var alwaysEnabled: Bool { false }
  var isDisabled: Bool { false }
}
enum Preference { enum Key { case enableOSD }; static func bool(for: Key) -> Bool { true } }
final class WindowFixture {
  var loaded = true
  var messages = 0
  var engineClosed = false
  func displayOSD(_ message: OSDMessage, autoHide: Bool, forcedTimeout: Float?, accessoryView: NSView?, context: Any?) {
    precondition(!engineClosed, "OSD accessed the closed engine")
    messages += 1
  }
}
final class PlayerFixture {
  final class Info {
    struct State { var active = true }
    var state = State()
    var disableOSDForFileLoading = false
  }
  let info = Info(), mainWindow = WindowFixture()
  var isInMiniPlayer = false
  var currentOSDFeedbackOrigin = OSDFeedbackOrigin.command
  // PRODUCTION_OSD_DELIVERY
}
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message); checks += 1; print("PASS:", message)
}
func drain() {
  var drained = false
  DispatchQueue.main.async { drained = true }
  let deadline = Date().addingTimeInterval(2)
  while !drained && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.001)) }
  precondition(drained)
}
let active = PlayerFixture()
active.sendOSD(.normal)
check(active.mainWindow.messages == 0, "OSD stays queued until delivery")
drain()
check(active.mainWindow.messages == 1, "active playback receives its queued message")
let stopped = PlayerFixture()
stopped.sendOSD(.normal)
stopped.info.state.active = false
stopped.mainWindow.engineClosed = true
drain()
check(stopped.mainWindow.messages == 0, "Stop between enqueue and delivery cannot query a closed engine")
let closed = PlayerFixture()
closed.info.state.active = false
closed.mainWindow.engineClosed = true
closed.sendOSD(.fileStart)
drain()
check(closed.mainWindow.messages == 0, "an already closed player cannot enqueue an OSD")
print("Completed \(checks) production OSD delivery checks.")
