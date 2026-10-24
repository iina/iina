// AppKit window and pointer fixtures around the production resize delegate methods.
enum Preference {
  enum OSCPosition { case floating, bottom }
  static var unlockWindowAspectRatio = false
}
enum FullscreenState { case windowed, fullscreen }
class ResizeWindow: NSWindow {
  var live = true
  var flags: NSEvent.ModifierFlags = []
  override var inLiveResize: Bool { live }
  override var resizeFlags: NSEvent.ModifierFlags { flags }
}
class VideoLayer { var inLiveResize = false }
class Video { var videoLayer = VideoLayer() }
class LiveText { func clearAnalysis() {}; func requestAnalysis() {} }
class State { var active = true }
class Info { var state = State() }
class Player { var info = Info() }
class Panel { func updatePosition() {} }
class Editor { var isActive = false }
class DelegateFixture {
  var loaded = true
  var isApplyingVideoTransformWindowFrame = false
  var isCropTransitionInProgress = false
  var isFullscreenTransitionInProgress = false
  var finishedAspectTransitions = 0
  func interruptPlayerCropTransition(settleWindowFrame: Bool = true) {}
  func finishVideoAspectTransition() { finishedAspectTransitions += 1 }
  func rememberVideoTransformWindowResize() {}
  var window: NSWindow?
  var fsState = FullscreenState.windowed
  var windowResizeSession: WindowResizeSession?
  var videoTransformWindowDisplaySize: NSSize?
  var testMouse = NSPoint.zero
  var oscPosition = Preference.OSCPosition.floating
  let minimumWindowSize = NSSize(width: 400, height: 225)
  // PRODUCTION_ASPECT_HELPERS
  let videoView = Video()
  let interactiveMode = Editor()
  let liveText = LiveText()
  let player = Player()
  let oscFloatingView = Panel()
  var layoutInvalidations = 0
  func invalidateFloatingOSCLayout() { layoutInvalidations += 1 }
  func updateWindowParametersForMPV() {}
  func windowFrameConstrainedToScreen(_ frame: NSRect, screenFrame: NSRect?) -> NSRect { frame }
  // PRODUCTION_METHODS
}
let app = NSApplication.shared
let window = ResizeWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 450),
                          styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
window.aspectRatio = NSSize(width: 16, height: 9)
let fixture = DelegateFixture()
fixture.window = window
let start = NSPoint(x: window.frame.maxX - 2, y: window.frame.maxY - 2)
let startNotification = Notification(name: NSWindow.willStartLiveResizeNotification, object: window)
let endNotification = Notification(name: NSWindow.didEndLiveResizeNotification, object: window)
let nativeProposal = NSSize(width: 550, height: 309.375)
var checks = 0
func check(_ result: @autoclosure () -> Bool, _ label: String) {
  precondition(result(), label)
  checks += 1
}
fixture.testMouse = start
fixture.windowWillStartLiveResize(startNotification)
check(fixture.windowResizeSession != nil, "Locked live resize captures its initial grip")
for dx: CGFloat in [-100, -50, 0, 50, 100, -50, 0] {
  for dy: CGFloat in [-200, 0, 200] {
    fixture.testMouse = NSPoint(x: start.x + dx, y: start.y + dy)
    let expected = NSSize(width: 800 + dx, height: (800 + dx) * 9 / 16)
    let size = fixture.windowWillResize(window, to: nativeProposal)
    check(size == expected, "Delegate must follow pointer displacement regardless of native aspect proposals")
    // Simulate intermediate native frames: subsequent calls must still use the initial grip.
    window.setFrame(NSRect(origin: window.frame.origin, size: size), display: false)
  }
}
fixture.testMouse = NSPoint(x: start.x - 600, y: start.y)
check(fixture.windowWillResize(window, to: nativeProposal) == fixture.minimumWindowSize,
      "Pointer-based corner resize still honors both minimum dimensions")
window.maxSize = NSSize(width: 900, height: 600)
fixture.testMouse = NSPoint(x: start.x + 400, y: start.y)
check(fixture.windowWillResize(window, to: nativeProposal) == NSSize(width: 900, height: 506.25),
      "Pointer-based resize respects native maximum size without breaking the ratio")
window.live = false
check(fixture.windowWillResize(window, to: nativeProposal) == nativeProposal, "Programmatic resizing keeps its native proposal")
window.live = true
Preference.unlockWindowAspectRatio = true
check(fixture.windowWillResize(window, to: nativeProposal) == nativeProposal, "Unlocking the aspect ratio bypasses proportional pointer tracking")
fixture.windowWillStartLiveResize(startNotification)
check(fixture.windowResizeSession == nil, "Unlocked resize cannot retain a prior locked session")
Preference.unlockWindowAspectRatio = false
fixture.fsState = .fullscreen
fixture.windowWillStartLiveResize(startNotification)
check(fixture.windowResizeSession == nil, "Fullscreen transitions bypass windowed resize tracking")
fixture.fsState = .windowed
window.flags = .option
fixture.windowWillStartLiveResize(startNotification)
check(fixture.windowResizeSession == nil, "Option resizing retains the native symmetric resize policy")
window.flags = []
fixture.testMouse = NSPoint(x: window.frame.maxX, y: window.frame.maxY)
fixture.windowWillStartLiveResize(startNotification)
check(fixture.windowResizeSession != nil, "A later gesture captures a fresh grip")
fixture.isApplyingVideoTransformWindowFrame = true
let finishedBeforeAutomaticResize = fixture.finishedAspectTransitions
fixture.windowWillStartLiveResize(startNotification)
check(fixture.windowResizeSession == nil && fixture.finishedAspectTransitions == finishedBeforeAutomaticResize,
      "Automatic frame animation cannot capture pointer resize or cancel aspect fill")
fixture.isApplyingVideoTransformWindowFrame = false
fixture.player.info.state.active = false
fixture.windowDidEndLiveResize(endNotification)
check(fixture.windowResizeSession == nil, "Ending resize clears tracking even when playback has stopped")
window.maxSize = NSSize(width: 4000, height: 4000)
window.setFrame(NSRect(x: 100, y: 100, width: 800, height: 225), display: false)
window.aspectRatio = window.frame.size
fixture.player.info.state.active = true
fixture.testMouse = NSPoint(x: window.frame.maxX - 2, y: window.frame.midY)
fixture.windowWillStartLiveResize(startNotification)
check(window.aspectRatio == .zero, "Pointer tracking temporarily removes native aspect/minimum coupling")
fixture.testMouse.x -= 160
let smaller = fixture.windowWillResize(window, to: nativeProposal)
check(smaller == NSSize(width: 640, height: 225), "A letterboxed window can shrink in width without growing or violating minimum height")
window.setFrame(NSRect(origin: window.frame.origin, size: smaller), display: false)
fixture.windowDidEndLiveResize(endNotification)
check(fixture.windowResizeSession == nil && window.aspectRatio == smaller,
      "Ending a minimum-clamped gesture restores native aspect locking to the actual window")
fixture.testMouse = NSPoint(x: window.frame.maxX - 2, y: window.frame.midY)
fixture.windowWillStartLiveResize(startNotification)
fixture.testMouse.x += 160
let enlarged = fixture.windowWillResize(window, to: nativeProposal)
check(enlarged == NSSize(width: 800, height: 281.25), "A subsequent gesture uses the new window proportions")
fixture.windowDidEndLiveResize(endNotification)
print("Window resize delegate: \(checks) checks passed")

fixture.isApplyingVideoTransformWindowFrame = true
let invalidations = fixture.layoutInvalidations
_ = fixture.windowWillResize(window, to: NSSize(width: 720, height: 450))
check(fixture.layoutInvalidations == invalidations, "automatic crop steps do not force layout of the previous frame")
fixture.isApplyingVideoTransformWindowFrame = false
_ = fixture.windowWillResize(window, to: NSSize(width: 720, height: 450))
check(fixture.layoutInvalidations == invalidations + 1, "manual or rejected resize proposals retain the native control repair")

print("Window resize delegate including automatic-step checks: \(checks) passed")

window.setFrame(NSRect(x: 100, y: 100, width: 400, height: 225), display: false)
window.aspectRatio = window.frame.size
fixture.videoTransformWindowDisplaySize = NSSize(width: 5, height: 4)
fixture.testMouse = NSPoint(x: window.frame.maxX - 2, y: window.frame.midY)
fixture.windowWillStartLiveResize(startNotification)
let recoveryStart = fixture.testMouse
check(fixture.windowWillResize(window, to: nativeProposal) == window.frame.size,
      "minimum padding does not jump to the video aspect on mouse-down")
fixture.testMouse.x += 200
let recovered = fixture.windowWillResize(window, to: nativeProposal)
check(recovered == NSSize(width: 600, height: 480), "enlarging a clamped crop recovers its actual video aspect")
window.setFrame(NSRect(origin: window.frame.origin, size: recovered), display: false)
fixture.windowDidEndLiveResize(endNotification)
fixture.testMouse = NSPoint(x: window.frame.maxX - 2, y: window.frame.midY)
fixture.windowWillStartLiveResize(startNotification)
fixture.testMouse.x -= 200
let minimumCrop = fixture.windowWillResize(window, to: nativeProposal)
check(minimumCrop == NSSize(width: 400, height: 320), "a recovered crop keeps its ratio on the next gesture")
fixture.interactiveMode.isActive = true
fixture.windowDidEndLiveResize(endNotification)
window.setFrame(NSRect(x: 100, y: 100, width: 800, height: 450), display: false)
window.aspectRatio = window.frame.size
fixture.testMouse = NSPoint(x: window.frame.maxX - 2, y: window.frame.midY)
fixture.windowWillStartLiveResize(startNotification)
fixture.testMouse.x += 160
check(fixture.windowWillResize(window, to: nativeProposal) == NSSize(width: 960, height: 540),
      "the Custom editor retains its own window aspect instead of the committed crop aspect")
fixture.windowDidEndLiveResize(endNotification)
print("Adaptive crop resize delegate: \(checks) checks passed")
