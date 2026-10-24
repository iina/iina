import Cocoa

enum AccessibilityPreferences {
  static var factor: Double = 0
  static var motionReductionEnabled = false
  static func adjustedDuration(_ value: TimeInterval) -> TimeInterval { value * factor }
}
enum Preference { enum Key { case disableAnimations }; static func bool(for key: Key) -> Bool { false } }
enum MPVProperty { static let vf = "vf"; static let videoOutParams = "video-out-params" }
enum LoggerLevel { case verbose }
final class MPVFixture {
  var options = ["vf": "", "lavfi-complex": ""]
  var commands: [String] = []
  func getString(_ name: String) -> String? { options[name] ?? (name == "video-crop" ? "" : "0") }
  func command(rawString: String, level: LoggerLevel) -> Int32 { commands.append(rawString); return 0 }
  var outputSize = NSSize(width: 50, height: 60)
  func getInt(_ name: String) -> Int { Int(name.hasSuffix("/w") ? outputSize.width : outputSize.height) }
}
final class PlayerFixture {
  enum Notice { case iinaTrackSettingsChanged }
  var settingsUpdates = 0
  func postNotification(_ notice: Notice) { settingsUpdates += 1 }
  struct State: Equatable { var active = true; static let paused = State() }
  final class Info { var state = State(); var trackSelectionGeneration = 1; var justStartedFile = false; var cropFilter: Int? = 1 }
  let info = Info(), mpv = MPVFixture()
  var nativeRequests = 0
  func requestNativeCropFrame() { nativeRequests += 1 }
  var isRefreshingPausedCrop = false
  var canAnimateCropSource = true
  var disableWindowAnimation = false
  func onVideoReconfig() {}
  var videoSizeForDisplay: (Int, Int) { (Int(mpv.outputSize.width), Int(mpv.outputSize.height)) }
  func interactiveVideoGeometry(uncropped: Bool) -> TestGeometry { TestGeometry() }
  func removeCropFilter() { info.cropFilter = nil }
  var presentation: CropTransitionOverlay.PlayerFrame?
  var presentationRequests: [NSRect] = []
  func cropTransitionFrame(in bounds: NSRect) -> CropTransitionOverlay.PlayerFrame? {
    presentationRequests.append(bounds)
    return presentation ?? .init(selection: NSRect(x: 0, y: 0, width: 1, height: 1), videoRect: CropTransitionOverlay.fit(mpv.outputSize, in: bounds), viewport: bounds)
  }
}
struct TestGeometry {
  let sourceSize = NSSize(width: 100, height: 60)
  let selectionSize = NSSize(width: 100, height: 60)
  let displaySize = NSSize(width: 100, height: 60)
  func filterRect(for rect: NSRect) -> NSRect { rect }
}
final class LayerFixture {
  var isInCropTransition = false
  var withholdFrames = false
  func afterNextCropFrame(_ completion: @escaping (Bool) -> Void) { DispatchQueue.main.async { completion(true) } }
  func afterNextPreparedCropFrame(_ completion: @escaping (Bool) -> Void) {
    if !withholdFrames { DispatchQueue.main.async { completion(true) } }
  }
  func cancelCropFrameRequests() {}
  var isAnimatingWindowResize = false
  func update(force: Bool) {}
  var isPreparingCropFrame = false
  func setCropFramePreparation(_ preparing: Bool) { isPreparingCropFrame = preparing }
  func withCropFrameUpdate(_ body: () -> Void) { body() }
  func withCropFrameHandoff(_ body: () -> Void) { body(); isPreparingCropFrame = false }
  func displayForCropHandoff(allowCachedFrame: Bool = false) {}
}
final class VideoFixture: NSView { let videoLayer = LayerFixture() }
final class EditorFixture {
  var isActive = true
  var isEntering = false
  func finishEntryTransition(outputIsReady: Bool = false) {}
  func beginNativeExitPresentation() {}
  func cancelEntryTransition() { isEntering = false }
  func exit() { isActive = false; isEntering = false }
  var restorations = 0
  func restoreExitPresentation() { if isActive { restorations += 1 } }
}
final class LiveTextFixture { func requestAnalysis() {} }
// PRODUCTION_OVERLAY
final class TransitionWindow: NSWindow {
  var visibleForTesting = true
  var occludedForTesting = false
  var usesClockScreenForTesting = false
  var pausesAnimationDisplayLinkForTesting = false
  var animationDisplayLinkRequests = 0
  weak var animationDisplayLinkTarget: AnyObject?
  var willSetFrameForTesting: ((NSRect) -> Void)?
  override var isVisible: Bool { visibleForTesting }
  override var occlusionState: NSWindow.OcclusionState { occludedForTesting ? [] : [.visible] }
  override var screen: NSScreen? { usesClockScreenForTesting ? NSScreen.main : super.screen }
  override func setFrame(_ frameRect: NSRect, display flag: Bool) {
    willSetFrameForTesting?(frameRect)
    super.setFrame(frameRect, display: flag)
  }
  @available(macOS 14.0, *)
  override func displayLink(target: Any, selector: Selector) -> CADisplayLink {
    animationDisplayLinkRequests += 1
    animationDisplayLinkTarget = target as AnyObject
    let link = super.displayLink(target: target, selector: selector)
    if pausesAnimationDisplayLinkForTesting { link.isPaused = true }
    return link
  }
}
final class ProjectionObservingLayer: CALayer {
  var didSetTransform: (() -> Void)?
  override var transform: CATransform3D { didSet { didSetTransform?() } }
}
final class MainWindowController {
  let player = PlayerFixture()
  let interactiveMode = EditorFixture()
  let videoView = VideoFixture()
  let liveText = LiveTextFixture()
  enum OSCPosition { case floating, bottom }
  var oscPosition = OSCPosition.bottom
  final class Floating {
    var didPrepareForResize: ((NSSize) -> Void)?
    var didUpdatePosition: ((Bool, Bool) -> Void)?
    func prepareForResize(to size: NSSize) { didPrepareForResize?(size) }
    func updatePosition(deferringFinalLayout: Bool = false, afterPreparedResize: Bool = false) {
      didUpdatePosition?(deferringFinalLayout, afterPreparedResize)
    }
  }
  let oscFloatingView = Floating()
  func invalidateFloatingOSCLayout() {}
  let videoViewContainer = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
  var videoViewConstraints: [NSLayoutConstraint.Attribute: NSLayoutConstraint] = [:]
  var cropExitOverlay: CropTransitionOverlay?
  private var pendingPlayerCropChange: (() -> Void)?
  var isCropTransitionInProgress: Bool { cropExitOverlay != nil || interactiveMode.isEntering }
  var isPlayerCropTransitionInProgress: Bool { cropExitOverlay?.isPlayerTransition == true }
  var loaded = true
  enum WindowState {
    case windowed, fullscreen, animating
    mutating func startAnimatingToFullScreen(legacy: Bool, priorWindowedFrame: NSRect) { self = .animating }
    mutating func startAnimatingToWindow() { self = .animating }
  }
  enum PIPStatus { case notInPIP, inPIP }
  var fsState = WindowState.windowed, pipStatus = PIPStatus.notInPIP
  var isApplyingVideoTransformWindowFrame = false
  var window: NSWindow? = TransitionWindow(contentRect: NSRect(x: 50, y: 50, width: 400, height: 240),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
  var target = NSRect(x: 100, y: 100, width: 300, height: 360)
  init() {
    window!.isReleasedWhenClosed = false
    window!.contentView = videoViewContainer
    videoView.frame = videoViewContainer.bounds
    videoView.autoresizingMask = [.width, .height]
    videoView.wantsLayer = true
    videoViewContainer.addSubview(videoView)
  }
  func hideOSD() {}
  func log(_ text: String) {}
  var onFullscreenBegin: (() -> Void)?
  func beginFullscreenVideoTransition() { onFullscreenBegin?() }
  func durationForTesting(_ value: TimeInterval) -> TimeInterval { cropTransitionDuration(value) }
  func handleVideoSizeChange(keepWindowSize: Bool) { cropExitOverlay?.targetWindowFrame = target }
  func finishVideoAspectTransition() {}
  // Geometry-motion cancellation is a separate transaction fixture boundary.
  func cancelVideoGeometryTransition(settleWindowFrame: Bool = true) {}
  func updateWindowParametersForMPV(withFrame: NSRect? = nil) {}
  // PRODUCTION_TRANSITION
}
extension Notification.Name { static let iinaLegacyFullScreen = Notification.Name("fixture.legacy-fullscreen") }
typealias Lock = NSLock
@propertyWrapper final class Atomic<Value> {
  var wrappedValue: Value
  init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
enum Logger { static func log(_ message: String) {} }
final class SnapshotFixture: CALayer {
  let mpvGLQueue = DispatchQueue(label: "crop-deadline-test")
  var videoView: NSObject?
  var bufferDepth = 8
  let cglPixelFormat: Int
  let cglContext: Int
  let displayLock: NSLocking
  @Atomic var isHostedInPIP = false
  @Atomic var isAnimatingWindowResize = false
  @Atomic var fullscreenTransition = (generation: 0, active: false, finishing: false)
  @Atomic var fullscreenDisplayQueued = false
  @Atomic var isDrawingGeometryHandoff = false
  @Atomic var isInCropTransition = false
  @Atomic var isPreparingCropFrame = false
  @Atomic var skippedEmptyCropFrame = false
  @Atomic var lastRenderedPixelSize: CGSize? = nil
  @Atomic var forceDraw = false
  @Atomic var needsFlip = false
  var cropSurfaceState = NSObject()
  var inLiveResize = false
  var isAsynchronous = false
  override init() {
    cglPixelFormat = 0
    cglContext = 0
    displayLock = NSRecursiveLock()
    super.init()
  }
  required init?(coder: NSCoder) { fatalError() }
  // PRODUCTION_CROP_FRAME_STATE
  func deferNativeFrame(until target: Int64, now: Int64) -> Bool { deferCropDisplay(until: target, now: now) }
  func deliverNative() { takeCropFrameHandlers().forEach { $0(true) } }
  func deliverPrepared() { takePreparedCropFrameHandlers().forEach { $0(true) } }
  // PRODUCTION_SNAPSHOT_STATE
  // PRODUCTION_LAYER_COPY
  var updates = 0
  func update(force: Bool) { updates += 1; if force { forceDraw = true } }
  func deliver(_ image: NSImage?) { takeSnapshotHandlers().forEach { $0(image) } }
  // PRODUCTION_SNAPSHOT
}
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
  precondition(value(), message); checks += 1; print("PASS:", message)
}
func pump(_ predicate: () -> Bool) {
  let deadline = Date().addingTimeInterval(3)
  while !predicate() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.001)) }
  precondition(predicate(), "asynchronous crop boundary timed out")
}

let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
  NSColor.red.setFill(); rect.fill(); return true
}
let nextImage = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
  NSColor.blue.setFill(); rect.fill(); return true
}
let red = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let blue = nextImage.cgImage(forProposedRect: nil, context: nil, hints: nil)!
func close(_ a: NSRect, _ b: NSRect) -> Bool {
  abs(a.minX-b.minX)<0.001 && abs(a.minY-b.minY)<0.001
    && abs(a.width-b.width)<0.001 && abs(a.height-b.height)<0.001
}
func allLayers(_ layer: CALayer) -> [CALayer] { [layer] + (layer.sublayers ?? []).flatMap(allLayers) }

let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 225))
container.wantsLayer = true
let native = NSView(frame: container.bounds)
native.wantsLayer = true
container.addSubview(native)
let layer = native.layer!
layer.contentsFormat = .RGBA16Float
layer.contentsScale = 2
layer.contentsGravity = .resizeAspectFill
layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
let parent = layer.superlayer
var acquisitions = 0, restorations = 0
let motion = CropTransitionOverlay(frame: container.bounds)
let full = NSRect(x: 0, y: 0, width: 1, height: 1)
motion.showPlayerFrame(frame: .init(selection: full, videoRect: container.bounds, viewport: container.bounds))
motion.useNativeVideo(native, in: container, pixelSize: NSSize(width: 16, height: 9),
                      beginLayout: { acquisitions += 1 }, restoreLayout: { restorations += 1 })
let end = NSRect(x: 59.375, y: 0, width: 281.25, height: 225)
motion.setPlayerTargetFrame(.init(selection: NSRect(x: 0.1484375, y: 0, width: 0.703125, height: 1), videoRect: end, viewport: container.bounds))
var framesStayLive = true, aperturesFollow = true, sourceAspectIsStable = true, rasterIsStable = true
let rasterBounds = layer.bounds
for step in 0...100 {
  let current = step.isMultiple(of: 2) ? red : blue
  layer.contents = current
  motion.presentPlayerTransition(progress: CGFloat(step)/100)
  framesStayLive = framesStayLive && native.layer === layer && (layer.contents as AnyObject?) === current
    && layer.superlayer === parent && !native.isHidden
  let mask = layer.mask!.frame, transform = layer.transform
  let origin = NSPoint(x: layer.position.x - layer.bounds.width * layer.anchorPoint.x * transform.m11 + transform.m41,
                       y: layer.position.y - layer.bounds.height * layer.anchorPoint.y * transform.m22 + transform.m42)
  let visible = NSRect(x: origin.x + mask.minX * transform.m11, y: origin.y + mask.minY * transform.m22,
                       width: mask.width * transform.m11, height: mask.height * transform.m22)
  aperturesFollow = aperturesFollow && close(visible,
    CropTransitionOverlay.interpolate(container.bounds, end, CGFloat(step)/100))
  sourceAspectIsStable = sourceAspectIsStable && abs(native.frame.width/native.frame.height - 16/9.0) < 0.00001
  rasterIsStable = rasterIsStable && layer.bounds == rasterBounds
}
check(framesStayLive && rasterIsStable, "101 live frames keep the original native layer with constant raster bounds")
check(aperturesFollow, "minimum fields follow the aperture while the native source keeps its aspect")
check(sourceAspectIsStable && acquisitions == 1, "native layout is acquired once and cannot apply a second source-aspect crop")
check(allLayers(motion.layer!).allSatisfy { $0.contents == nil }, "the transition owns no video image or retained source frame")
check(layer.contentsFormat == .RGBA16Float && layer.contentsScale == 2, "native output precision and backing scale remain intact")
motion.releaseNativeVideo()
check(layer.contentsGravity == .resizeAspectFill && (layer.contents as AnyObject?) === red,
      "completion restores gravity while preserving the newest native frame")
check(restorations == 1 && native.frame == container.bounds && layer.mask == nil, "completion restores native layout and releases the aperture")

let bounded = NativeCropVideoPresentation(view: native, container: container, pixelSize: NSSize(width:3840,height:2160))
bounded.present(frame: NSRect(x:-100000,y:-50000,width:200000,height:112500), clip:container.bounds)
check(layer.bounds.width*layer.contentsScale <= 3840.01 && layer.bounds.height*layer.contentsScale <= 2160.01,
      "a tiny source selection cannot allocate a crop-sized giant GL surface")
bounded.restore()
check(layer.contentsScale == 2 && layer.contentsFormat == .RGBA16Float,
      "bounded raster sizing restores native screen scale without changing precision")

let resizedParent = NativeCropVideoPresentation(view: native, container: container, pixelSize: NSSize(width:3840,height:2160))
resizedParent.present(frame: container.bounds, clip: container.bounds)
check(layer.autoresizingMask.isEmpty,
      "full-source presentation owns native layer dimensions instead of the parent's automatic sizing")
let fixedRaster = layer.bounds
container.layer!.bounds.size.width = 300
container.layer!.layoutIfNeeded()
check(layer.bounds == fixedRaster,
      "resizing the native parent cannot change full-source raster bounds or introduce internal video bars")
resizedParent.restore()
container.layer!.bounds.size.width = 400
check(layer.autoresizingMask == [.layerWidthSizable, .layerHeightSizable],
      "crop completion restores normal native layer resizing")

let editorTransform = CATransform3DMakeTranslation(80, 20, 0)
layer.transform = editorTransform
let exitingEditor = NativeCropVideoPresentation(view: native, container: container, pixelSize: NSSize(width:3840,height:2160))
exitingEditor.present(frame: container.bounds, clip: container.bounds)
// InteractiveMode.exit installs the normal player transform and mask before
// the prepared canonical frame releases temporary crop presentation.
layer.transform = CATransform3DIdentity
let playerMask = CALayer()
layer.mask = playerMask
exitingEditor.restore()
check(CATransform3DIsIdentity(layer.transform) && layer.mask === playerMask,
      "canonical Save handoff cannot restore the editor's obsolete preview transform over the player")
layer.mask = nil

let feedback = CropTransitionOverlay(frame: container.bounds)
check(CropTransitionOverlay.preparationFeedbackDelay == 0.5 && CropTransitionOverlay.preparationBreathingDuration == 1,
      "100–200ms crop preparation stays below the feedback threshold and a complete breath lasts one second")
for (ready, end) in [(0.01,1.0),(0.5,1.0),(0.99,1.0),(1.0,1.0),(1.01,2.0),(2.8,3.0)] {
  check(CropTransitionOverlay.preparationCycleEnd(startedAt: 10, readyAt: 10 + ready) == 10 + end,
        "readiness at phase \(ready) finishes at the current breath's transparent endpoint")
}
feedback.beginPreparationFeedback(pulse: true)
let feedbackLayer = feedback.layer!.sublayers!.first { $0.name == "cropPreparationFeedback" }!
let vignetteLayer = feedbackLayer.sublayers!.first!
feedback.beginPreparationFeedback(pulse: true)
check(feedback.isShowingPreparationFeedback && feedbackLayer.opacity == 0 && vignetteLayer.animationKeys() == nil,
      "preparation stays transparent until its layer has a real presentation")
feedback.endPreparationFeedback()
check(feedbackLayer.opacity == 0 && feedbackLayer.animationKeys() == nil && !feedback.isShowingPreparationFeedback,
      "a request ready before its first presentation cannot flash a fully visible vignette")
var fastFeedbackCompleted = false
feedback.beginPreparationFeedback(pulse: true)
feedback.finishPreparationFeedback { fastFeedbackCompleted = true }
check(fastFeedbackCompleted && !feedback.isShowingPreparationFeedback && feedbackLayer.opacity == 0,
      "fast native readiness cancels the delayed feedback without waiting for a breath")
feedback.beginPreparationFeedback(pulse: false)
feedback.endPreparationFeedback(animated: false)
RunLoop.main.run(until: Date().addingTimeInterval(0.04))
check(feedbackLayer.opacity == 0 && feedbackLayer.animationKeys() == nil && vignetteLayer.animationKeys() == nil,
      "a cancelled pending activation cannot later dim the player")

final class PreparationClock {
  var now: TimeInterval = 10
  var presented = true
  private var pending: [(deadline: TimeInterval, action: () -> Void)] = []
  func schedule(_ delay: TimeInterval, _ action: @escaping () -> Void) {
    pending.append((now + delay, action))
  }
  func advance(to target: TimeInterval) {
    while let next = pending.indices.min(by: { pending[$0].deadline < pending[$1].deadline }),
          pending[next].deadline <= target {
      let action = pending.remove(at: next)
      now = action.deadline
      action.action()
    }
    now = target
  }
  func feedback() -> DelayedPreparationFeedback {
    DelayedPreparationFeedback(now: { self.now }, schedule: schedule,
                               hasPresentation: { _ in self.presented })
  }
}
do {
  let clock = PreparationClock(), owner = clock.feedback()
  let token = owner.begin(pulse: true)
  clock.advance(to: 10.499)
  var completions = 0
  check(owner.layer.opacity == 0 && owner.isShowing,
        "shared feedback stays transparent throughout the exact 500ms delay")
  check(owner.finish(token, policy: .afterCurrentBreath) { completions += 1 } && completions == 1,
        "readiness before activation completes synchronously")
  clock.advance(to: 12)
  check(!owner.isShowing && owner.layer.opacity == 0 && completions == 1,
        "late activation cannot flash or repeat a fast operation's completion")
  check(!owner.finish(token, policy: .immediate) { completions += 1 } && completions == 1,
        "a completed token cannot accept another success continuation")
}
do {
  let clock = PreparationClock(), owner = clock.feedback()
  let obsolete = owner.begin(pulse: true)
  let token = owner.begin(pulse: true)
  owner.cancel(obsolete, animated: false)
  check(!owner.finish(obsolete, policy: .immediate) {} && owner.isShowing,
        "stale finish and cancellation cannot dismiss a replacement operation")
  clock.advance(to: 10.5)
  let vignette = owner.layer.sublayers!.first!
  let breathing = vignette.animation(forKey: "breathing") as! CABasicAnimation
  check(owner.layer.opacity == 1 && breathing.duration == 0.5 && breathing.autoreverses &&
        (breathing.fromValue as! NSNumber).floatValue == 0 && (breathing.toValue as! NSNumber).floatValue == 0.7,
        "activation keeps the production zero-to-0.7 full one-second opacity breath")
  clock.advance(to: 10.75)
  var completions = 0
  check(owner.finish(token, policy: .afterCurrentBreath) { completions += 1 } && completions == 0,
        "PiP-style readiness waits for the active breath's transparent endpoint")
  check(!owner.finish(token, policy: .afterCurrentBreath) { completions += 100 },
        "a duplicate in-flight finish cannot replace or duplicate the accepted continuation")
  clock.advance(to: 11.499)
  check(completions == 0 && owner.isShowing, "endpoint readiness cannot complete mid-breath")
  clock.advance(to: 11.5)
  check(completions == 1 && !owner.isShowing && owner.layer.opacity == 0 && vignette.animationKeys() == nil,
        "endpoint completion hides feedback and runs its continuation exactly once")
}
do {
  let clock = PreparationClock(), owner = clock.feedback()
  let token = owner.begin(pulse: true)
  clock.advance(to: 10.5)
  var cancelledCompletions = 0
  owner.finish(token, policy: .afterCurrentBreath) { cancelledCompletions += 1 }
  owner.cancel(token, animated: false)
  let replacement = owner.begin(pulse: true)
  clock.advance(to: 11.5)
  check(cancelledCompletions == 0 && owner.isShowing,
        "cancellation suppresses pending success and its old endpoint cannot hide a new operation")
  var immediateCompletions = 0
  check(owner.finish(replacement, policy: .immediate) { immediateCompletions += 1 } &&
        immediateCompletions == 1 && !owner.isShowing && owner.layer.opacity == 0,
        "capture-style completion dismisses active breathing synchronously without endpoint delay")
}
do {
  let clock = PreparationClock(), owner = clock.feedback()
  clock.presented = false
  let token = owner.begin(pulse: true)
  clock.advance(to: 11)
  var completions = 0
  owner.finish(token, policy: .afterCurrentBreath) { completions += 1 }
  clock.presented = true
  clock.advance(to: 12)
  check(completions == 1 && owner.layer.opacity == 0 && !owner.isShowing,
        "readiness before the first presentation cancels retries without any visible flash")
}
do {
  let clock = PreparationClock(), owner = clock.feedback()
  let token = owner.begin(pulse: false)
  clock.advance(to: 10.5)
  check(owner.layer.opacity == 1 && owner.layer.sublayers!.first!.opacity == 0.5 &&
        owner.layer.sublayers!.first!.animation(forKey: "breathing") == nil,
        "reduced motion retains the existing steady vignette instead of a breath")
  var completions = 0
  check(owner.finish(token, policy: .afterCurrentBreath) { completions += 1 } && completions == 1,
        "reduced-motion readiness completes immediately without inventing a breath")
  let fading = owner.begin(pulse: false)
  clock.advance(to: 11)
  clock.advance(to: 11.2)
  owner.cancel(fading)
  let replacement = owner.begin(pulse: true)
  check(owner.layer.opacity == 0 && owner.layer.animationKeys() == nil,
        "a rapid replacement removes the old fade before starting its invisible delay")
  let independent = clock.feedback()
  check(!independent.finish(replacement, policy: .immediate) {} && !independent.isShowing,
        "opaque operation tokens are isolated across feedback owners")
  owner.cancel(replacement, animated: false)
}
let feedbackHost = PreparationFeedbackView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
check(feedbackHost.hitTest(NSPoint(x: 100, y: 100)) == nil &&
      feedbackHost.feedback.layer.superlayer === feedbackHost.layer,
      "the reusable host exposes its layer owner while passing all pointer input through")

let softCurve = CropTransitionOverlay.AnimationCurve.smoothstep
let legacyCurve = CropTransitionOverlay.AnimationCurve.easeOut
for curve in [legacyCurve, softCurve] {
  let samples = (0...1000).map { curve.progress(at: Double($0) / 1000) }
  check(samples.first == 0 && samples.last == 1 && samples.allSatisfy { (0...1).contains($0) } &&
        zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 },
        "both crop curves move monotonically within bounds and preserve exact source/final endpoints")
}
check(legacyCurve.progress(at: 0.25) == 0.578125 && legacyCurve.progress(at: 0.5) == 0.875 &&
      legacyCurve.progress(at: 0.75) == 0.984375,
      "editor entry and Custom Save retain the existing cubic ease-out samples")
check(softCurve.progress(at: 0.25) == 0.15625 && softCurve.progress(at: 0.5) == 0.5 &&
      softCurve.progress(at: 0.75) == 0.84375,
      "player aspect motion accelerates through a symmetric middle instead of launching at maximum speed")
let firstRefreshTime = (1.0 / 60) / 0.35
let recordedLateRefreshTime = 0.04213379164477145 / 0.35
check(softCurve.progress(at: firstRefreshTime) < 0.01 && legacyCurve.progress(at: firstRefreshTime) > 0.13 &&
      softCurve.progress(at: recordedLateRefreshTime) < 0.05 && legacyCurve.progress(at: recordedLateRefreshTime) > 0.31,
      "soft player motion limits both an ordinary first refresh and the recorded delayed first refresh displacement")
let derivativeStep = 0.0001
check(softCurve.progress(at: derivativeStep) / CGFloat(derivativeStep) < 0.001 &&
      (1 - softCurve.progress(at: 1 - derivativeStep)) / CGFloat(derivativeStep) < 0.001,
      "soft player motion starts and stops with zero endpoint velocity")

let immediateClock = CropTransitionOverlay(frame: .zero)
var immediateProgress: [CGFloat] = [], immediateCompletions = 0
let previousActions = CATransaction.disableActions()
CATransaction.setDisableActions(false)
immediateClock.animate(duration: 0, update: { progress in
  immediateProgress.append(progress)
  check(CATransaction.disableActions(), "clock updates keep unified geometry changes free of implicit actions")
}) { immediateCompletions += 1 }
check(immediateProgress == [1] && immediateCompletions == 1 && !CATransaction.disableActions(),
      "zero-duration motion applies its exact endpoint once and restores transaction actions")
check(CropAnimationObservation.starts.last?.curve == .easeOut,
      "an animation call without a curve argument keeps the editor-entry and Custom Save default")
CATransaction.setDisableActions(previousActions)

let fallbackClock = CropTransitionOverlay(frame: .zero)
var fallbackProgress: [CGFloat] = [], fallbackCompletions = 0
fallbackClock.animate(duration: 0.035, update: { fallbackProgress.append($0) }) { fallbackCompletions += 1 }
pump { fallbackCompletions == 1 }
check(!fallbackProgress.isEmpty && fallbackProgress.last == 1 &&
      zip(fallbackProgress, fallbackProgress.dropFirst()).allSatisfy { $0 <= $1 } &&
      fallbackProgress.allSatisfy { (0...1).contains($0) },
      "a detached overlay uses a bounded monotonic fallback clock and finishes at the exact endpoint")
fallbackProgress = []
fallbackCompletions = 0
fallbackClock.animate(duration: 0.035, curve: .smoothstep, update: { fallbackProgress.append($0) }) { fallbackCompletions += 1 }
pump { fallbackCompletions == 1 }
check(!fallbackProgress.isEmpty && fallbackProgress.last == 1 &&
      zip(fallbackProgress, fallbackProgress.dropFirst()).allSatisfy { $0 <= $1 } &&
      fallbackProgress.allSatisfy { (0...1).contains($0) },
      "soft player motion uses the same bounded fallback clock and completes at its exact endpoint")
var cancelledClockUpdates = 0, cancelledClockCompletions = 0
fallbackClock.animate(duration: 0.02, update: { _ in cancelledClockUpdates += 1 }) { cancelledClockCompletions += 1 }
fallbackClock.stopAnimation()
RunLoop.main.run(until: Date().addingTimeInterval(0.03))
check(cancelledClockUpdates == 0 && cancelledClockCompletions == 0,
      "stopping fallback motion cancels both future geometry updates and completion")
var staleClockCompletions = 0, replacementClockCompletions = 0
fallbackClock.animate(duration: 0, curve: .smoothstep, update: { _ in
  fallbackClock.animate(duration: 0, update: { _ in }) { replacementClockCompletions += 1 }
}) { staleClockCompletions += 1 }
check(staleClockCompletions == 0 && replacementClockCompletions == 1,
      "a replacement started by the final update cannot receive the obsolete clock's completion")
weak var releasedFallbackClock: CropTransitionOverlay?
var abandonedClockCallbacks = 0
autoreleasepool {
  let abandoned = CropTransitionOverlay(frame: .zero)
  releasedFallbackClock = abandoned
  abandoned.animate(duration: 0.02, update: { _ in abandonedClockCallbacks += 1 }) { abandonedClockCallbacks += 1 }
}
RunLoop.main.run(until: Date().addingTimeInterval(0.03))
check(releasedFallbackClock == nil && abandonedClockCallbacks == 0,
      "fallback timer ownership cannot retain a discarded overlay or deliver callbacks after deinit")

if #available(macOS 14.0, *), NSScreen.main != nil {
  let clockWindow = TransitionWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
  clockWindow.isReleasedWhenClosed = false
  clockWindow.usesClockScreenForTesting = true
  clockWindow.pausesAnimationDisplayLinkForTesting = true
  let clockContent = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
  clockWindow.contentView = clockContent
  let watchdogClock = CropTransitionOverlay(frame: clockContent.bounds)
  clockContent.addSubview(watchdogClock)
  var watchdogProgress: [CGFloat] = [], watchdogCompletions = 0
  watchdogClock.animate(duration: 0.035, curve: .smoothstep, update: { watchdogProgress.append($0) }) { watchdogCompletions += 1 }
  check(clockWindow.animationDisplayLinkRequests == 1 && clockWindow.animationDisplayLinkTarget != nil,
        "a visible window creates a native display link with a live weak-callback proxy")
  pump { watchdogCompletions == 1 }
  check(watchdogProgress == [1] && clockWindow.animationDisplayLinkTarget == nil,
        "a display link with no refresh callbacks still completes once and releases its proxy through the deadline watchdog")
  watchdogClock.animate(duration: 0.025, update: { _ in cancelledClockUpdates += 1 }) { cancelledClockCompletions += 1 }
  watchdogClock.stopAnimation()
  RunLoop.main.run(until: Date().addingTimeInterval(0.035))
  check(clockWindow.animationDisplayLinkRequests == 2 && clockWindow.animationDisplayLinkTarget == nil &&
        cancelledClockUpdates == 0 && cancelledClockCompletions == 0,
        "stopping display-linked motion invalidates its link and completion watchdog")
  watchdogClock.removeFromSuperview()
  weak var releasedDisplayClock: CropTransitionOverlay?
  autoreleasepool {
    let abandoned = CropTransitionOverlay(frame: clockContent.bounds)
    releasedDisplayClock = abandoned
    clockContent.addSubview(abandoned)
    abandoned.animate(duration: 0.025, update: { _ in abandonedClockCallbacks += 1 }) { abandonedClockCallbacks += 1 }
    abandoned.removeFromSuperview()
  }
  RunLoop.main.run(until: Date().addingTimeInterval(0.035))
  check(releasedDisplayClock == nil && clockWindow.animationDisplayLinkTarget == nil && abandonedClockCallbacks == 0,
        "display-link proxy and watchdog cannot retain a detached overlay or survive its deinit")
}

AccessibilityPreferences.factor = 0.1
let player = MainWindowController()
player.interactiveMode.isActive = false
let playingLayer = player.videoView.layer!
var mutations = 0
let selected = NSRect(x: 0.1, y: 0, width: 0.8, height: 1)
let targetRect = NSRect(x: 10, y: 0, width: 80, height: 60)
check(player.prepareCropChange({ mutations += 1; player.player.mpv.outputSize = targetRect.size },
  selection: selected, displaySize: targetRect.size, filterRect: targetRect), "a live-source preset transition starts")
check(mutations == 0 && player.cropExitOverlay?.isPreparingSource == true && player.videoView.videoLayer.isPreparingCropFrame,
      "the target crop cannot discard source pixels before the animation")
check(player.cropExitOverlay?.isShowingPreparationFeedback == true,
      "the pending native source provides loading feedback while the window stays still")
playingLayer.contents = blue
player.finishCropExitTransition(outputIsReady: true)
check(player.cropExitOverlay?.isTransforming == false && (playingLayer.contents as AnyObject?) === blue,
      "an old output notification cannot start source-space motion")
check(player.cropExitOverlay?.isShowingPreparationFeedback == true,
      "a stale output notification cannot dismiss the waiting feedback")
player.player.mpv.outputSize = NSSize(width: 100, height: 60)
let waitingOverlay = player.cropExitOverlay!
player.finishCropExitTransition(outputIsReady: true)
pump { waitingOverlay.isTransforming }
check(!waitingOverlay.isShowingPreparationFeedback,
      "native motion starts the feedback fade without extending preparation")
check(CropAnimationObservation.starts.last?.curve == .smoothstep &&
      abs(CropAnimationObservation.starts.last!.duration - 0.04) < 0.000000001,
      "player preset motion uses the soft curve and adjusted 400ms duration")
pump { player.cropExitOverlay == nil }
check(mutations == 1 && player.window!.frame == player.target && player.videoView.layer === playingLayer
      && (playingLayer.contents as AnyObject?) === blue && playingLayer.mask == nil,
      "full-source readiness moves the window, then commits the canonical filter exactly once")
check(!player.videoView.videoLayer.isAnimatingWindowResize && !player.videoView.videoLayer.isPreparingCropFrame, "completion restores native resize scheduling and releases filter presentation")

let currentSource = MainWindowController()
currentSource.interactiveMode.isActive = false
currentSource.oscPosition = .floating
let observingProjection = ProjectionObservingLayer()
currentSource.videoView.layer = observingProjection
var pendingOSCLayout = false, cropGeometryChecks = 0
var preparedOSCContentSize: NSSize?
var preparedFrameWasApplied = false
currentSource.oscFloatingView.didPrepareForResize = { preparedOSCContentSize = $0 }
(currentSource.window as! TransitionWindow).willSetFrameForTesting = { nextFrame in
  let currentFrame = currentSource.window!.frame
  let currentSize = currentSource.videoViewContainer.bounds.size
  check(preparedOSCContentSize == NSSize(width: currentSize.width + nextFrame.width - currentFrame.width,
                                        height: currentSize.height + nextFrame.height - currentFrame.height),
        "crop metrics are prepared for the impending content size before native window resize")
  preparedFrameWasApplied = true
}
currentSource.oscFloatingView.didUpdatePosition = { deferred, prepared in
  if deferred {
    check(prepared && preparedFrameWasApplied, "crop placement reuses the metrics prepared before its frame update")
    preparedFrameWasApplied = false
    pendingOSCLayout = true
    currentSource.videoViewContainer.needsLayout = true
  }
}
observingProjection.didSetTransform = {
  if pendingOSCLayout {
    check(!currentSource.videoViewContainer.needsLayout,
          "the crop tick settles deferred OSC geometry before updating native video projection")
    pendingOSCLayout = false
    cropGeometryChecks += 1
  }
}
currentSource.player.info.cropFilter = nil
currentSource.player.mpv.outputSize = NSSize(width: 100, height: 60)
currentSource.videoView.videoLayer.withholdFrames = true
_ = currentSource.prepareCropChange({
  currentSource.player.mpv.outputSize = targetRect.size
  currentSource.player.info.cropFilter = 1
},
  selection: selected, displaySize: targetRect.size, filterRect: targetRect)
check(currentSource.cropExitOverlay?.isTransforming == true && currentSource.player.nativeRequests == 0,
      "an already-current uncropped source starts preset motion without waiting for a duplicate frame")
pump { currentSource.cropExitOverlay?.isCommitting == true }
check(cropGeometryChecks > 0 && !pendingOSCLayout,
      "floating OSC motion participates in the crop tick's final geometry layout")
check(currentSource.cropExitOverlay?.isAwaitingNativeFrame == true,
      "the canonical filter still waits for an actual refreshed output")
currentSource.finishCropExitTransition(outputIsReady: true)
check(currentSource.cropExitOverlay == nil,
      "playback-restart releases a paused canonical handoff even when no later video frame arrives")

let refreshedSource = MainWindowController()
refreshedSource.interactiveMode.isActive = false
refreshedSource.videoView.videoLayer.withholdFrames = true
_ = refreshedSource.prepareCropChange({ refreshedSource.player.mpv.outputSize = targetRect.size },
  selection: selected, displaySize: targetRect.size, filterRect: targetRect)
refreshedSource.player.mpv.outputSize = NSSize(width: 100, height: 60)
refreshedSource.finishCropExitTransition()
check(refreshedSource.cropExitOverlay?.isAwaitingNativeFrame == true && refreshedSource.cropExitOverlay?.isTransforming == false,
      "a size notification alone cannot present an unprepared source")
refreshedSource.finishCropExitTransition(outputIsReady: true)
check(refreshedSource.cropExitOverlay?.isTransforming == true,
      "the refresh completion starts motion without requiring another seek or render callback")
refreshedSource.cancelCropExitTransition()

let resetSource = MainWindowController()
resetSource.interactiveMode.isActive = false
resetSource.videoView.videoLayer.withholdFrames = true
let fullRect = NSRect(x: 0, y: 0, width: 100, height: 60)
let noneStarts = CropAnimationObservation.starts.count
_ = resetSource.prepareCropChange({}, selection: NSRect(x: 0, y: 0, width: 1, height: 1),
  displaySize: fullRect.size, filterRect: fullRect)
resetSource.player.mpv.outputSize = fullRect.size
resetSource.finishCropExitTransition(outputIsReady: true)
pump { resetSource.cropExitOverlay == nil }
check(resetSource.player.nativeRequests == 0,
      "paused None finishes on its existing full source without waiting for a nonexistent second refresh")
check(CropAnimationObservation.starts.count == noneStarts + 1 &&
      CropAnimationObservation.starts.last?.curve == .smoothstep &&
      abs(CropAnimationObservation.starts.last!.duration - 0.04) < 0.000000001,
      "None window motion uses the same soft curve and adjusted 400ms duration")

for failure in ["media", "inactive", "cancel"] {
  let fixture = MainWindowController(); fixture.interactiveMode.isActive = false
  var applies = 0
  _ = fixture.prepareCropChange({ applies += 1 }, selection: selected, displaySize: targetRect.size, filterRect: targetRect)
  if failure == "media" { fixture.player.info.trackSelectionGeneration += 1 }
  else if failure == "inactive" { fixture.player.info.state.active = false }
  else { fixture.cancelCropExitTransition() }
  fixture.finishCropExitTransition(outputIsReady: true)
  check(fixture.cropExitOverlay == nil && applies == (failure == "cancel" ? 1 : 0) && !fixture.videoView.videoLayer.isAnimatingWindowResize,
        "\(failure) cannot mutate a new file or leave temporary geometry active")
}
let superseded = MainWindowController(); superseded.interactiveMode.isActive = false
var order: [Int] = []
_ = superseded.prepareCropChange({ order.append(1); superseded.player.mpv.outputSize = targetRect.size }, selection: selected, displaySize: targetRect.size, filterRect: targetRect)
let first = superseded.cropExitOverlay!
_ = superseded.prepareCropChange({ order.append(2); superseded.player.mpv.outputSize = targetRect.size }, selection: selected, displaySize: targetRect.size, filterRect: targetRect)
check(order.isEmpty && superseded.cropExitOverlay === first,
      "rapid changes coalesce behind the current native handoff")
superseded.player.mpv.outputSize = NSSize(width: 100, height: 60)
superseded.finishCropExitTransition(outputIsReady: true)
pump { order.count == 1 && superseded.cropExitOverlay !== first }
superseded.player.mpv.outputSize = NSSize(width: 100, height: 60)
superseded.finishCropExitTransition(outputIsReady: true)
pump { superseded.cropExitOverlay == nil }
check(order == [1,2], "the latest queued preset commits after the previous source finishes")
let rejected = MainWindowController()
rejected.player.mpv.outputSize = NSSize(width: 100, height: 60)
let saveStarts = CropAnimationObservation.starts.count
rejected.prepareCropExit(selection: NSRect(x: 0, y: 0, width: 50, height: 60),
  sourceSize: NSSize(width: 100, height: 60), initialFrame: rejected.videoViewContainer.bounds,
  initialClip: rejected.videoViewContainer.bounds, initialSelection: .zero,
  controlsImage: nil, controlsFrame: .zero) { false }
pump { rejected.cropExitOverlay == nil }
check(rejected.interactiveMode.isActive && rejected.videoView.layer?.mask == nil,
      "a rejected Save restores native editor geometry and remains usable")
check(CropAnimationObservation.starts.count == saveStarts + 1 &&
      CropAnimationObservation.starts.last?.curve == .easeOut &&
      abs(CropAnimationObservation.starts.last!.duration - 0.035) < 0.000000001,
      "Custom Save retains the cubic ease-out and adjusted 350ms duration")

let snapshots = SnapshotFixture()
check(!snapshots.deferNativeFrame(until: 100, now: 100) && !snapshots.deferNativeFrame(until: 0, now: 100),
      "redraw and expired native timestamps do not postpone presentation")
let deadlineStart = Date()
check(snapshots.deferNativeFrame(until: 20_000_000, now: 0) && snapshots.deferNativeFrame(until: 20_000_000, now: 0),
      "future video timestamps defer drawing without blocking the caller")
pump { snapshots.updates == 1 }
check(Date().timeIntervalSince(deadlineStart) >= 0.015 && Date().timeIntervalSince(deadlineStart) < 0.5,
      "native nanosecond deadlines wait milliseconds rather than seconds or microseconds")
RunLoop.main.run(until: Date().addingTimeInterval(0.03))
check(snapshots.updates == 1, "duplicate native deadlines queue one render update")
let timedShadow = SnapshotFixture(layer: snapshots)
_ = snapshots.deferNativeFrame(until: 30_000_000, now: 0)
timedShadow.cancelCropFrameRequests()
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
check(snapshots.updates == 1, "cancellation from a CA shadow invalidates a pending timed update")
_ = snapshots.deferNativeFrame(until: 40_000_000, now: 0)
_ = snapshots.deferNativeFrame(until: 10_000_000, now: 0)
pump { snapshots.updates == 2 }
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
check(snapshots.updates == 2, "a newer native timestamp supersedes the old scheduled update")
snapshots.updates = 0
var replies: [NSImage?] = []
var readersStarted = 0
for _ in 0..<2 { Task { @MainActor in
  readersStarted += 1
  replies.append(await snapshots.captureSnapshot())
} }
pump { readersStarted == 2 }
check(replies.isEmpty, "concurrent crop and Live Text captures remain pending until a draw")
snapshots.deliver(image)
pump { replies.count == 2 }
check(replies.allSatisfy { $0 === image } && snapshots.updates == 1,
      "concurrent readers share one forced draw and one image without cancelling one another")
Task { @MainActor in replies.append(await snapshots.captureSnapshot()) }
pump { snapshots.updates == 2 }
snapshots.cancelSnapshots()
pump { replies.count == 3 }
check(replies[2] == nil, "render shutdown releases pending image continuations")
Task { @MainActor in replies.append(await snapshots.captureSnapshot()) }
pump { replies.count == 4 }
check(replies[3] == nil && snapshots.updates == 2, "a capture after render shutdown completes without queueing a draw")

let modelLayer = SnapshotFixture()
modelLayer.bufferDepth = 16
let renderLayer = SnapshotFixture(layer: modelLayer)
check(renderLayer.bufferDepth == 16, "native CA shadows retain the selected floating-point output depth")
var sharedReplies: [NSImage?] = []
Task { @MainActor in sharedReplies.append(await modelLayer.captureSnapshot()) }
pump { modelLayer.updates == 1 }
check(renderLayer.forceDraw, "a forced paused-frame request reaches the CA shadow that owns the drawable")
renderLayer.forceDraw = false
check(!modelLayer.forceDraw, "the shadow consumes the same force request before the native-frame handoff")
renderLayer.deliver(image)
pump { sharedReplies.count == 1 }
check(sharedReplies[0] === image, "a Core Animation shadow draw fulfills a capture queued on its model layer")
Task { @MainActor in sharedReplies.append(await renderLayer.captureSnapshot()) }
pump { renderLayer.updates == 1 }
modelLayer.deliver(image)
pump { sharedReplies.count == 2 }
check(sharedReplies[1] === image, "model and shadow draws share the same exactly-once capture queue")
Task { @MainActor in sharedReplies.append(await modelLayer.captureSnapshot()) }
pump { modelLayer.updates == 2 }
renderLayer.cancelSnapshots()
pump { sharedReplies.count == 3 }
modelLayer.deliver(image)
renderLayer.deliver(image)
Task { @MainActor in sharedReplies.append(await modelLayer.captureSnapshot()) }
pump { sharedReplies.count == 4 }
check(sharedReplies[2] == nil && sharedReplies[3] == nil && modelLayer.updates == 2,
      "render shutdown from either layer releases shared captures once and closes both aliases")

let mixedModel = SnapshotFixture()
let mixedShadow = SnapshotFixture(layer: mixedModel)
var mixedStarted = 0
var mixedReplies = 0
for index in 0..<20 { Task { @MainActor in
  mixedStarted += 1
  let result = await (index.isMultiple(of: 2) ? mixedModel : mixedShadow).captureSnapshot()
  if result === image { mixedReplies += 1 }
} }
pump { mixedStarted == 20 }
check(mixedModel.updates + mixedShadow.updates == 1,
      "concurrent captures across model and shadow queue only one forced draw")

let nativeModel = SnapshotFixture(), nativeShadow: SnapshotFixture
nativeShadow = SnapshotFixture(layer: nativeModel)
var nativeReplies: [Bool] = []
nativeModel.afterNextCropFrame { nativeReplies.append($0) }
nativeShadow.afterNextCropFrame { nativeReplies.append($0) }
nativeShadow.deliverNative()
check(nativeReplies == [true, true], "native model and CA shadow wait for the same real video draw")
nativeModel.deliverNative()
check(nativeReplies.count == 2, "one native draw completes each presentation waiter once")
nativeModel.afterNextCropFrame { nativeReplies.append($0) }
nativeShadow.cancelCropFrameRequests()
pump { nativeReplies.count == 3 }
check(nativeReplies.last == false, "occlusion or cancellation releases native readiness without inventing a draw")
nativeModel.afterNextCropFrame { nativeReplies.append($0) }
nativeShadow.cancelCropFrameRequests(close: true)
pump { nativeReplies.count == 4 }
let nativeUpdates = nativeModel.updates
nativeModel.afterNextCropFrame { nativeReplies.append($0) }
check(nativeReplies.suffix(2).allSatisfy { !$0 } && nativeModel.updates == nativeUpdates, "render shutdown closes both native aliases and rejects late draw requests")
nativeModel.isPreparingCropFrame = true
check(nativeShadow.isPreparingCropFrame, "native filter preparation is shared across CA shadow copies")

let preparedModel = SnapshotFixture(), preparedShadow: SnapshotFixture
preparedShadow = SnapshotFixture(layer: preparedModel)
var preparedReplies: [Bool] = [], drawnReplies: [Bool] = []
preparedModel.afterNextPreparedCropFrame { preparedReplies.append($0) }
preparedModel.afterNextCropFrame { drawnReplies.append($0) }
preparedShadow.deliverPrepared()
check(preparedReplies == [true] && drawnReplies.isEmpty,
      "a prepared native frame does not pretend that the new viewport has been drawn")
preparedShadow.deliverNative()
check(drawnReplies == [true], "the native draw boundary completes independently after viewport publication")
preparedModel.afterNextPreparedCropFrame { preparedReplies.append($0) }
preparedShadow.cancelCropFrameRequests(close: true)
pump { preparedReplies.count == 2 }
preparedModel.afterNextPreparedCropFrame { preparedReplies.append($0) }
check(preparedReplies.suffix(2).allSatisfy { !$0 }, "shutdown cancels prepared-frame waiters and closes both layer aliases")

for entering in [true, false] {
  let boundary = MainWindowController()
  boundary.interactiveMode.isActive = false
  boundary.player.mpv.outputSize = NSSize(width: 100, height: 60)
  boundary.videoView.videoLayer.withholdFrames = true
  var cropCommits = 0
  boundary.prepareCropExit(selection: NSRect(x: 10, y: 0, width: 50, height: 60),
    sourceSize: NSSize(width: 100, height: 60), initialFrame: boundary.videoViewContainer.bounds,
    initialClip: boundary.videoViewContainer.bounds, initialSelection: .zero,
    controlsImage: nil, controlsFrame: .zero) { cropCommits += 1; return true }
  check(boundary.cropExitOverlay != nil && boundary.videoView.videoLayer.isInCropTransition,
        "a real Custom Crop handoff owns the native surface before fullscreen \(entering ? "entry" : "exit")")
  boundary.onFullscreenBegin = {
    check(boundary.cropExitOverlay == nil && !boundary.videoView.videoLayer.isInCropTransition &&
          !boundary.videoView.videoLayer.isAnimatingWindowResize && cropCommits == 1,
          "fullscreen layout receives a settled Custom Crop surface and one committed crop")
  }
  if entering {
    boundary.windowWillEnterFullScreen(Notification(name: NSWindow.willEnterFullScreenNotification))
  } else {
    boundary.fsState = .fullscreen
    boundary.windowWillExitFullScreen(Notification(name: NSWindow.willExitFullScreenNotification))
  }
  let fullscreenFrame = boundary.window!.frame
  RunLoop.main.run(until: Date().addingTimeInterval(0.02))
  check(boundary.window!.frame == fullscreenFrame && boundary.cropExitOverlay == nil && cropCommits == 1,
        "a stale Custom Crop frame cannot resume window sizing after the fullscreen boundary")
}

print("Completed \(checks) native live crop and OCR ownership checks.")
