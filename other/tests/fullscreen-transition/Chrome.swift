import Cocoa

extension Notification.Name { static let iinaLegacyFullScreen = Notification.Name("legacy") }
enum ScreenState {
  case windowed, fullscreen(legacy: Bool, priorWindowedFrame: NSRect)
  case animating(toFullscreen: Bool, legacy: Bool, priorWindowedFrame: NSRect)
  mutating func startAnimatingToFullScreen(legacy: Bool, priorWindowedFrame: NSRect) {
    self = .animating(toFullscreen: true, legacy: legacy, priorWindowedFrame: priorWindowedFrame)
  }
  mutating func startAnimatingToWindow() {
    guard case .fullscreen(let legacy, let frame) = self else { fatalError("unexpected state") }
    self = .animating(toFullscreen: false, legacy: legacy, priorWindowedFrame: frame)
  }
  mutating func finishAnimating() {
    guard case .animating(let toFullscreen, let legacy, let frame) = self else { fatalError("unexpected state") }
    self = toFullscreen ? .fullscreen(legacy: legacy, priorWindowedFrame: frame) : .windowed
  }
}
enum Level { case warning, error }
class LiveText { func requestAnalysis() {} }
class Controller {
  var window: NSWindow?
  var fsState = ScreenState.windowed
  let liveText = LiveText()
  var began: (() -> Void)?
  var interruptedCrop = false
  func interruptPlayerCropTransition() { interruptedCrop = true }
  func log(_ message: String, level: Level = .warning) {}
  func beginFullscreenVideoTransition() { began?() }
  func finishFullscreenVideoTransition() {}
  // PRODUCTION_CHROME
}

var checks = 0
func check(_ value: Bool, _ message: String) {
  if !value { print("FAILED: " + message); exit(1) }; checks += 1
}
let app = NSApplication.shared
let window = NSWindow(contentRect: NSRect(x: 200, y: 280, width: 600, height: 375),
                      styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
window.titlebarAppearsTransparent = true
let fixture = Controller(); fixture.window = window
let original = window.frame
fixture.began = {
  check(fixture.interruptedCrop, "crop motion ownership ends before fullscreen video layout starts")
  guard case .animating(let entering, _, let prior) = fixture.fsState else {
    check(false, "fullscreen state is set before video layout"); return
  }
  check(entering && prior == original, "the window reference is captured before layout can resize it")
  window.setContentSize(NSSize(width: 700, height: 400))
}
fixture.windowWillEnterFullScreen(Notification(name: NSWindow.willEnterFullScreenNotification, object: window))
fixture.fsState.finishAnimating()
window.titlebarAppearsTransparent = false
fixture.began = {
  guard case .animating(let entering, _, _) = fixture.fsState else {
    check(false, "exit state is set before video layout"); return
  }
  check(!entering, "layout during exit sees an active transition")
  check(window.titlebarAppearsTransparent, "the fullscreen blur is removed before shrinking the window")
}
fixture.windowWillExitFullScreen(Notification(name: NSWindow.willExitFullScreenNotification, object: window))
fixture.windowDidFailToExitFullScreen(window)
check(!window.titlebarAppearsTransparent, "a failed exit restores the native fullscreen titlebar")
check(!window.styleMask.contains(.fullSizeContentView), "a failed exit retains native header separation")
print("Passed \(checks) fullscreen chrome ordering checks")
