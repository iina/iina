
import Cocoa
let UIAnimationDuration: TimeInterval = 0.25
struct AccessibilityPreferences {
  static let motionReductionEnabled = false
  static func adjustedDuration(_ duration: TimeInterval) -> TimeInterval { 0 }
}

class Window: NSWindow {
  var frontCalls = 0
  override func orderFrontRegardless() { frontCalls += 1; testVisible = true }
  var simulatedFullscreen = false
  override var styleMask: NSWindow.StyleMask {
    get { simulatedFullscreen ? super.styleMask.union(.fullScreen) : super.styleMask }
    set { super.styleMask = newValue }
  }

  var testVisible = true
  var minimized = false
  var orderOutAnimations: [NSWindow.AnimationBehavior] = []
  var onReveal: (() -> Void)?
  override var isVisible: Bool { testVisible }
  override var isMiniaturized: Bool { minimized }
  override func orderOut(_ sender: Any?) { orderOutAnimations.append(animationBehavior); testVisible = false }
  override func makeKeyAndOrderFront(_ sender: Any?) { onReveal?(); testVisible = true }
  override func miniaturize(_ sender: Any?) { minimized = true }
  override func deminiaturize(_ sender: Any?) { minimized = false }
}
class VideoLayer { var isHostedInPIP = false }
class Video: NSView {
 let videoLayer = VideoLayer()
 var handoffs = 0
 var beforeHandoff: (() -> Void)?
 func prepareForPIPDisplay() { beforeHandoff?(); handoffs += 1 }
}
class PiP: NSObject {
  let window = Window(contentRect: NSRect(x: 0, y: 0, width: 240, height: 135), styleMask: [], backing: .buffered, defer: false)
  var playing = false
  var title: String?
  var replacementRect = NSRect.zero
  var replacementWindow: NSWindow?
  static var modern = false
  var completion: (() -> Void)?
  override func responds(to selector: Selector!) -> Bool {
    if selector == NSSelectorFromString("presentViewControllerAsPictureInPicture:completionHandler:") { return PiP.modern }
    return super.responds(to: selector)
  }
  func presentAsPicture(inPicture vc: NSViewController, completionHandler: @escaping () -> Void) {
    completion = completionHandler
    presentAsPicture(inPicture: vc)
  }
  var presented = 0
  var dismissed = 0
  func presentAsPicture(inPicture vc: NSViewController) {
    presented += 1
    let host = NSView(frame: window.contentRect(forFrameRect: window.frame))
    window.contentView = host
    host.addSubview(vc.view)
    vc.view.frame = host.bounds
  }
  func dismiss(_ vc: NSViewController) { dismissed += 1 }
}
typealias PIPViewController = PiP
struct Preference {
  enum WindowBehaviorWhenPip { case doNothing, hide, minimize }
  enum Key { case windowBehaviorWhenPip, pauseWhenPip }
  static var behavior = WindowBehaviorWhenPip.hide
  static func `enum`(for key: Key) -> WindowBehaviorWhenPip { behavior }
  static func bool(for key: Key) -> Bool { false }
}
enum State { case playing, paused, stopped; var active: Bool { self != .stopped } }
class Info { var state = State.paused }
enum Event { case pipChanged }
class Events { func emit(_ event: Event, data: Bool) {} }
class Player {
  let info = Info(); let events = Events(); var disableUI = false
  func pause() {}; func refreshSyncUITimer() {}
}
class LiveText { var isActive = false; func clearAnalysis() {}; func requestAnalysis() {} }
class InteractiveMode { var isActive = false }
class OSC: NSView { func updatePosition() {} }
class Titlebar: NSView {
  var revealCalls: [(Bool, Bool)] = []
  func setRevealed(_ revealed: Bool, animated: Bool) {
    revealCalls.append((revealed, animated)); isHidden = !revealed
  }
  func finishShowing() {}
}
extension Notification.Name { static let iinaPIPStatusChanged = Notification.Name("test.pip") }
class MainWindowController: NSObject {
  func interruptPlayerCropTransition() {}
  var isCropTransitionInProgress = false
  enum PIPStatus { case notInPIP, inPIP, intermediate }
  var pipStatus = PIPStatus.notInPIP
  var pipReturnWindowAlpha: CGFloat?
  var pipPreparationFeedback: UUID?
  var operationFeedbackRequests = Set<UUID>()
  var operationFeedbackView: PreparationFeedbackView?
  var operationFeedbackToken: DelayedPreparationFeedback.Token?
  var isWindowLoaded = true
  func closeFeedback() { cancelOperationFeedback() }
  enum UIAnimationState { case hidden, shown, willShow, willHide }
  var animationState = UIAnimationState.shown
  var uiAnimationGeneration = 0
  var isPluginMenuTracking = false
  var isUIHiddenByOSCClick = false
  let fadeableViews = FadeableViewController()
  let titleBarView = Titlebar()
  let alwaysShownView = NSView()
  let thumbnailPeekView = NSView()
  let timePreviewView = NSView()
  func hideSeekPreview() {
    thumbnailPeekView.isHidden = true
    timePreviewView.isHidden = true
  }
  let standardWindowButtons = [NSButton()]
  struct FSState { var isFullscreen = false }
  var fsState = FSState()
  let player = Player()
  let liveText = LiveText()
  let interactiveMode = InteractiveMode()
  let oscFloatingView = OSC()
  var window: NSWindow? = Window(contentRect: NSRect(x: 0, y: 0, width: 800, height: 450), styleMask: .titled, backing: .buffered, defer: false)
  let videoView = Video()
  var videoViewContainer: NSView! = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 450))
  let pip = PiP()
  var pipVideo: NSViewController!
  let pipOverlayView = NSView()
  var isWindowHidden = false
  var isWindowMiniaturizedDueToPip = false
  override init() {
    super.init()
    window!.contentView = videoViewContainer
    addVideoViewToWindow()
    videoView.autoresizingMask = [.width, .height]
    pipOverlayView.isHidden = true
    fadeableViews.add(titleBarView) { .auto }
    fadeableViews.add(oscFloatingView) { .auto }
    fadeableViews.add(standardWindowButtons[0]) { .auto }
    fadeableViews.add(alwaysShownView) { .alwaysShown }
    fadeableViews.update()
    alwaysShownView.alphaValue = 1
  }
  func addVideoViewToWindow() { videoView.removeFromSuperview(); videoViewContainer.addSubview(videoView); videoView.frame = videoViewContainer.bounds }
  func destroyTimer() {}
  func syncPIPPlaybackState() {}
  func updateTimer() {}
// PRODUCTION_PIP_METHODS
}
