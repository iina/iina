import Cocoa
import Darwin
setbuf(stdout, nil)

// Playback, preferences and UI side effects are fixture boundaries. The native
// frame calculation, frame application, scale action and aspect lock are production.
enum Preference {
  enum Key { case resizeWindowTiming, resizeWindowOption, usePhysicalResolution, disableAnimations, edgeToEdgeVideo, dockedControlBarAndTitlebar }
  enum ResizeWindowTiming { case always, onlyWhenOpen, never }
  enum ResizeWindowOption {
    case fitScreen, half, normal, oneAndHalf, double
    var ratio: Double {
      switch self { case .fitScreen: -1; case .half: 0.5; case .normal: 1; case .oneAndHalf: 1.5; case .double: 2 }
    }
  }
  enum OSCPosition { case floating, top, bottom }
  static var unlockWindowAspectRatio = false
  static var physical = false
  static var animationsDisabled = true
  static var resizeTiming = ResizeWindowTiming.never
  static var resizeOption = ResizeWindowOption.normal
  static func bool(for key: Key) -> Bool { key == .usePhysicalResolution ? physical : (key == .disableAnimations && animationsDisabled) || key == .edgeToEdgeVideo }
  static func `enum`<T>(for key: Key) -> T {
    (key == .resizeWindowTiming ? resizeTiming as Any : resizeOption as Any) as! T
  }
}
struct FullscreenState: Equatable {
  var isFullscreen = false
  var priorWindowedFrame: NSRect?
  static let windowed = FullscreenState()
}
class InteractiveFixture { var isActive = false; var resizes = 0; func resize() { resizes += 1 } }
struct TrackFixture { var id = 0; static let noneAudioTrack = TrackFixture() }
enum MPVTrack { enum TrackType { case video, audio, sub, secondSub } }
class InfoFixture {
 struct State { var active = true; var loaded = true }
 var state = State()
 var justStartedFile = false, justOpenedFile = false
 var trackSelectionGeneration = 0
 var unsureAspect = "Default"
 var displayWidth: Int? = 1280, displayHeight: Int? = 720
 var mixedAudioTrackIDs: Set<Int> = []
 var rotation = 0, aid = 1
 var videoWidth: Int? = 1280
 var cachedWindowScale = 0.0
 func currentTrack(_ type: MPVTrack.TrackType) -> TrackFixture? { nil }
 func orderedTrackList(_ type: MPVTrack.TrackType) -> [TrackFixture] { [] }
 func activeTrackIDs(_ type: MPVTrack.TrackType) -> Set<Int> { mixedAudioTrackIDs.isEmpty ? (aid > 0 ? [aid] : []) : mixedAudioTrackIDs }
}
enum MPVOption {
 enum Window { static let windowScale = "window-scale" }
 enum PlaybackControl { static let pause = "pause" }
 enum Video { static let panscan = "panscan"; static let videoAspectOverride = "video-aspect-override"; static let videoRotate = "video-rotate" }
 enum TrackSelection { static let aid = "aid", vid = "vid", sid = "sid" }
 enum Subtitles { static let secondarySid = "secondary-sid" }
 enum Miscellaneous { static let lavfiComplex = "lavfi-complex" }
}
enum MPVProperty { static let dwidth = "dwidth", dheight = "dheight", coreIdle = "core-idle" }
enum NotificationFixture { case iinaAIDChanged, iinaSIDChanged }
enum AccessibilityPreferences { static func adjustedDuration(_ value: TimeInterval) -> TimeInterval { value } }
enum OSDFixture { case track(TrackFixture, position: Int? = nil), custom(String) }
class MPVFixture {
  enum LogLevel { case verbose }
  var scaleWrites = 0
  func setDouble(_ name: String, _ value: Double, level: LogLevel) { scaleWrites += 1 }
  var mutation: ((String, String) -> Void)?
  var writes: [(String, String)] = []
  var integers: [String: Int] = [:]
  var idle = false
  var panscan = 0.0
  var stringResult: Int32 = 0
  func getInt(_ key: String) -> Int { integers[key] ?? 0 }
  func getString(_ key: String) -> String? { nil }
  func getFlag(_ key: String) -> Bool { key == "pause" || idle }
  func getDouble(_ key: String) -> Double { key == "panscan" ? panscan : -1 }
  @discardableResult func setString(_ name: String, _ value: String) -> Int32 {
    if stringResult < 0 { return stringResult }
    writes.append((name,value))
    if name == "file-local-options/panscan" { panscan = Double(value)! }
    mutation?(name,value)
    return 0
  }
  func setInt(_ name: String, _ value: Int) { writes.append((name, String(value))); mutation?(name, String(value)) }
}
class EventsFixture { enum Event { case windowSizeAdjusted }; var count = 0; func emit(_ event: Event, data: NSRect) { count += 1 } }
class PlayerFixture {
  enum OSDFeedbackOrigin { case command, sidebar }
  var currentOSDFeedbackOrigin: OSDFeedbackOrigin { .command }
  func preservingOSDFeedbackOrigin<T>(_ action: @escaping () -> T) -> () -> T { action }
  weak var mainWindow: CropWindowFixture!
  let mpv = MPVFixture()
  private func reconcileTrackGraph() {}
  func setVideoTracks(_ ids: Set<Int>) -> Bool { mpv.setInt(MPVOption.TrackSelection.vid,ids.first ?? 0); getSelectedTracks(); return true }
  func setAudioTracks(_ ids: Set<Int>) -> Bool {
    mpv.setInt(MPVOption.TrackSelection.aid, ids.first ?? 0)
    getSelectedTracks()
    return true
  }
  private enum CropRefreshUpdate { case video }
  private func deferCropRefreshUpdate(_ update: CropRefreshUpdate) -> Bool { false }
  // PRODUCTION_PLAYER_TRANSFORMS
  var videoSizeForDisplay = (3840, 924)
  var sourceDisplaySize: NSSize?
  struct Geometry { let displaySize: NSSize }
  func interactiveVideoGeometry(uncropped: Bool) -> Geometry {
    Geometry(displaySize: sourceDisplaySize ?? NSSize(width: videoSizeForDisplay.0, height: videoSizeForDisplay.1))
  }
  var geometry: GeometryDef?
  func getGeometry() -> GeometryDef? { geometry }
  var info = InfoFixture()
  var events = EventsFixture()
  var disableWindowAnimation = true
  func generateThumbnails() {}
  var notifications = 0, selectedRefreshes = 0
  func getSelectedTracks() { selectedRefreshes += 1 }
  func postNotification(_ name: NotificationFixture) { notifications += 1 }
  func sendOSD(_ message: OSDFixture) {}
  func notifyWindowVideoSizeChanged() { mainWindow.handleVideoSizeChange(keepWindowSize: false) }
  // PRODUCTION_OUTPUT_CHANGE
}
class PIPFixture { var aspectRatio = NSSize.zero }
struct MemoryUsage { static let shared = MemoryUsage(); func logUsage(_ text: String) {} }
extension NSWindow { func selectDefaultScreen() -> NSScreen { screen ?? NSScreen.main! } }
// PRODUCTION_CONSTANTS
// PRODUCTION_EXTENSIONS
class TransitionLayerFixture {
 var updates = 0, isAnimatingWindowResize = false
 func update(force: Bool) { updates += 1 }
}
class TransitionVideoFixture {
 var active = 0, idle = 0; let videoLayer = TransitionLayerFixture()
 func displayActive() { active += 1 }; func displayIdle() { idle += 1 }
}
class CropExitFixture: NSView { var targetWindowFrame: NSRect?; var isPreparingSource = false; var isCommitting = false; var targetDisplaySize = NSSize.zero }
class LiveTextFixture { func requestAnalysis() {} }
class CropWindowFixture {
  let liveText = LiveTextFixture()
  final class Floating { func updatePosition() {} }
  let oscFloatingView = Floating()
  func invalidateFloatingOSCLayout() {}
  var cropExitOverlay: CropExitFixture?
  // Animation is a fixture boundary here; production geometry-motion sequencing
  // has its own suite. Keep the real frame calculation under transition ownership.
  enum VideoGeometryChange { case aspect, rotation }
  final class GeometryMotionFixture {
    var waitingForFrame = true
    var targetDisplaySize: NSSize?
    var targetWindowFrame: NSRect?
  }
  var geometryMotion: GeometryMotionFixture?
  var geometryRequests: [VideoGeometryChange] = []
  var isCropTransitionInProgress: Bool { cropExitOverlay != nil || geometryMotion != nil }
  func enqueueVideoGeometryChange(_ kind: VideoGeometryChange, request: @escaping () -> Void) -> Bool { false }
  func performVideoGeometryChange(_ kind: VideoGeometryChange, apply: @escaping () -> Bool) {
    geometryRequests.append(kind)
    let motion = GeometryMotionFixture()
    geometryMotion = motion
    _ = apply()
    geometryMotion = nil
    if let target = motion.targetWindowFrame { window?.setFrame(target, display: false) }
  }
  func geometryVideoOutputDidChange() {}
  var cropReadySignals = 0
  func finishCropExitTransition(outputIsReady: Bool = false) { if outputIsReady { cropReadySignals += 1 } }
  var cropAnimationTargets: [(NSRect, NSRect)] = []
  func startCropExitAnimation(to frame: NSRect, duration: TimeInterval) {
    cropAnimationTargets.append((frame, window!.frame))
  }
  var window: NSWindow?
  var loaded = true
  var interactiveMode = InteractiveFixture()
  var player = PlayerFixture()
  var fsState = FullscreenState.windowed
  var oscPosition = Preference.OSCPosition.floating
  private var isApplyingVideoTransformWindowFrame = false
  private var videoTransformWindowReferenceSize: NSSize?
  private var videoTransformWindowSize: NSSize?
  private var videoTransformWindowDisplaySize: NSSize?
  private var videoTransformWindowGeneration: Int?
  private var windowSizingFileGeneration: Int?
  private var videoAspectTransition: (panscan: Double, mediaGeneration: Int)?
  enum PIPStatus { case notInPIP, inPIP }
  var pipStatus = PIPStatus.notInPIP
  let videoView = TransitionVideoFixture()
  var pip = PIPFixture()
  var titleBarView = NSView()
  var oscBottomView = NSView()
  var muteButton = NSButton(), volumeSlider = NSSlider()
  var shouldApplyInitialWindowSize = false
  var cachedGeometry: GeometryDef?
  var isVideoLoaded = true
  var scaleUpdates: Int { player.mpv.scaleWrites }
  func log(_ text: String) {}
  func notifyLiveResize() { rememberVideoTransformWindowResize() }
  func beginWindowSession(at frame: NSRect) {
    windowSizingFileGeneration = nil
    videoTransformWindowReferenceSize = nil
    videoTransformWindowSize = nil
    videoTransformWindowDisplaySize = nil
    videoTransformWindowGeneration = nil
    window!.setFrame(frame, display: false)
  }
  func determineScreenToUse(_ window: NSWindow) -> NSScreen { window.selectDefaultScreen() }
  func updateMinimumWindowSize() {}
  func updatePlayTime(withDuration: Bool, andProgressBar: Bool) {}
  // PRODUCTION_CONTROLLER_METHODS
}
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
  precondition(value(),message); checks += 1; print("PASS: \(message)")
}
func near(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 1) -> Bool { abs(a-b) <= tolerance }
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let controller = CropWindowFixture()
let screen = NSScreen.main!.visibleFrame
let original = NSRect(x: screen.midX - 250, y: screen.midY - 150, width: 500, height: 300)
class ResizeNotifyingWindow: NSWindow {
 var onFrame: (() -> Void)?
 override func setFrame(_ rect: NSRect, display: Bool) { super.setFrame(rect,display:display); onFrame?() }
 override func setFrame(_ rect: NSRect, display: Bool, animate: Bool) { super.setFrame(rect,display:display,animate:animate); onFrame?() }
}
let window = ResizeNotifyingWindow(contentRect: original, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
controller.window = window
controller.player.mainWindow = controller
window.onFrame = { controller.notifyLiveResize() }
Preference.unlockWindowAspectRatio = false
let referenceFrame = NSRect(x: screen.midX - 480, y: screen.midY - 270, width: 960, height: 540)
controller.beginWindowSession(at: referenceFrame)
controller.player.sourceDisplaySize = NSSize(width: 3840, height: 2160)
controller.player.videoSizeForDisplay = (600, 600)
controller.shouldApplyInitialWindowSize = true
controller.player.info.justStartedFile = true
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.width, 600) && near(window.frame.height, 600), "Opening an already cropped file respects the initial displayed size")
controller.player.videoSizeForDisplay = (3840, 2160)
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.width, 600 * 16 / 9) && near(window.frame.height, 600),
      "Reset on an initially cropped square reconstructs original 16:9 geometry at the same limiting height")
controller.cachedGeometry = GeometryDef.parse("800x450+80+100")
controller.shouldApplyInitialWindowSize = true
controller.player.videoSizeForDisplay = (600, 600)
controller.handleVideoSizeChange(keepWindowSize: false)
let explicitStartup = window.frame
check(near(explicitStartup.width, 800) && near(explicitStartup.height, 450) &&
      near(explicitStartup.minX, screen.minX + 80) && near(explicitStartup.minY, screen.minY + 100),
      "Both explicit startup dimensions and their position take priority over an existing square crop")
controller.handleVideoSizeChange(keepWindowSize: false)
check(window.frame == explicitStartup, "Repeated first-frame geometry cannot shrink or recenter the explicitly configured window")
controller.player.videoSizeForDisplay = (3840, 2160)
controller.handleVideoSizeChange(keepWindowSize: false)
check(window.frame == explicitStartup, "Reset restores both size and center of an explicit 800x450 startup around a preloaded crop")
controller.setUserWindowFrame(NSRect(x: screen.minX, y: screen.minY, width: 1800, height: 1012))
controller.resetWindowSizingForNewSession()
controller.player.geometry = GeometryDef.parse("800x450+80+100")
controller.player.info.trackSelectionGeneration += 1
controller.player.videoSizeForDisplay = (600, 600)
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.width, 800) && near(window.frame.height, 450) &&
      near(window.frame.minX, screen.minX + 80) && near(window.frame.minY, screen.minY + 100),
      "a reused closed player reapplies startup size and position around an already cropped file")
controller.resetWindowSizingForNewSession()
controller.player.geometry = GeometryDef.parse("640x360+120+80")
controller.player.info.trackSelectionGeneration += 1
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.width, 640) && near(window.frame.height, 360) &&
      near(window.frame.minX, screen.minX + 120) && near(window.frame.minY, screen.minY + 80),
      "reopening reads changed startup geometry rather than the prior session cache")
controller.player.geometry = nil

for (geometry, output, startup, reset) in [
  ("640+100+100", (3840, 414), NSSize(width: 640, height: 225), NSSize(width: 640, height: 360)),
  ("x400+100+100", (600, 600), NSSize(width: 400, height: 400), NSSize(width: 400 * 16 / 9, height: 400)),
  ("800x450+100+100", (1782, 1302), NSSize(width: 800, height: 450), NSSize(width: 800, height: 450))
] {
  controller.cachedGeometry = GeometryDef.parse(geometry)
  controller.shouldApplyInitialWindowSize = true
  controller.player.videoSizeForDisplay = output
  controller.handleVideoSizeChange(keepWindowSize: false)
  check(near(window.frame.width, startup.width) && near(window.frame.height, startup.height),
        "Initial geometry \(geometry) uses its specified axes and the actual cropped output")
  let firstFrame = window.frame
  for _ in 0..<3 { controller.handleVideoSizeChange(keepWindowSize: false) }
  check(window.frame == firstFrame, "Repeated startup output leaves \(geometry) stable")
  controller.player.videoSizeForDisplay = (3840, 2160)
  controller.handleVideoSizeChange(keepWindowSize: false)
  check(near(window.frame.width, reset.width) && near(window.frame.height, reset.height),
        "Reset derives original geometry at the initial crop's visible scale for \(geometry)")
}
controller.cachedGeometry = nil
controller.player.sourceDisplaySize = nil
controller.player.info.justStartedFile = false

controller.beginWindowSession(at: referenceFrame)
controller.player.sourceDisplaySize = NSSize(width: 3840, height: 2160)
controller.player.videoSizeForDisplay = (3840, 2160)
controller.handleVideoSizeChange(keepWindowSize: false)
window.onFrame = nil
let resizedBeforeEditor = window.frame.centeredResize(to: NSSize(width: 1200, height: 675))
window.setFrame(resizedBeforeEditor, display: false)
window.onFrame = { controller.notifyLiveResize() }
controller.prepareVideoTransformWindowReference()
controller.cropExitOverlay = CropExitFixture(frame: NSRect(origin: .zero, size: resizedBeforeEditor.size))
controller.player.videoSizeForDisplay = (1782, 1302)
controller.handleVideoSizeChange(keepWindowSize: false)
let cropAfterNativeResize = controller.cropExitOverlay!.targetWindowFrame!
check(near(cropAfterNativeResize.height, resizedBeforeEditor.height) &&
      near(cropAfterNativeResize.width, resizedBeforeEditor.height * 1782 / 1302),
      "Preparing editor entry captures a native/external resize before an arbitrary inner selection")
window.setFrame(resizedBeforeEditor.centeredResize(to: NSSize(width: 1100, height: 610)), display: false)
controller.handleVideoSizeChange(keepWindowSize: false)
let repeatedCropTarget = controller.cropExitOverlay!.targetWindowFrame!
check(repeatedCropTarget.size == cropAfterNativeResize.size &&
      near(repeatedCropTarget.midX, cropAfterNativeResize.midX) && near(repeatedCropTarget.midY, cropAfterNativeResize.midY),
      "An intermediate animation frame cannot replace the captured reference: \(cropAfterNativeResize) -> \(repeatedCropTarget)")
window.setFrame(cropAfterNativeResize, display: false)
controller.cropExitOverlay = nil
controller.player.videoSizeForDisplay = (3840, 2160)
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.width, resizedBeforeEditor.width) && near(window.frame.height, resizedBeforeEditor.height),
      "The arbitrary crop/Reset sequence restores the full enlarged window without cumulative shrink")
controller.player.sourceDisplaySize = nil
controller.beginWindowSession(at: referenceFrame)
controller.player.videoSizeForDisplay = (3840, 2160)
controller.handleVideoSizeChange(keepWindowSize: false)
controller.interactiveMode.isActive = true
window.setFrame(window.frame.centeredResize(to: NSSize(width: 800, height: 450)), display: false)
controller.interactiveMode.isActive = false
controller.player.videoSizeForDisplay = (1782, 1302)
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.height, 450), "Manually resizing the open editor updates the original reference without sampling preview geometry")
controller.player.videoSizeForDisplay = (3840, 2160)
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.width, 800) && near(window.frame.height, 450),
      "Reset retains a manual resize made while the editor was open")
let reportedFrame = referenceFrame.centeredResize(to: NSSize(width: 640, height: 360))
controller.beginWindowSession(at: reportedFrame)
for output in [(3840, 679), (3840, 414), (3840, 679)] {
  controller.player.videoSizeForDisplay = output
  controller.handleVideoSizeChange(keepWindowSize: false)
  check(near(window.frame.width, 640) && near(window.frame.height, 225),
        "reported narrow crop preserves 640pt width and 225pt minimum without expanding to the screen")
  check(near(window.aspectRatio.aspect, window.frame.size.aspect, tolerance: 0.0001),
        "native resize lock follows the letterboxed window rather than forcing the image ratio")
}
controller.player.videoSizeForDisplay = (3840, 2160)
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.width, 640) && near(window.frame.height, 360),
      "Reset after a height-clamped crop restores the original reference")
controller.beginWindowSession(at: referenceFrame.centeredResize(to: NSSize(width: 800, height: 450)))
controller.player.videoSizeForDisplay = (3840, 414)
controller.handleVideoSizeChange(keepWindowSize: false)
window.setFrame(window.frame.centeredResize(to: NSSize(width: 640, height: 225)), display: false)
controller.player.videoSizeForDisplay = (3840, 2160)
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.width, 640) && near(window.frame.height, 360),
      "Manual width reduction at minimum height scales the original reference for Reset")
controller.player.videoSizeForDisplay = (3840, 414)
controller.handleVideoSizeChange(keepWindowSize: false)
controller.setWindowScale(0.125)
check(near(window.frame.width, 480) && near(window.frame.height, 225),
      "Explicit scale also clamps height independently instead of growing the narrow image")
controller.player.videoSizeForDisplay = (3840, 2160)
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.width, 480) && near(window.frame.height, 270),
      "Reset follows the reference scale after explicitly resizing a letterboxed crop")
controller.beginWindowSession(at: referenceFrame)
window.setFrame(referenceFrame, display: false)
controller.player.videoSizeForDisplay = (3840, 2160)
controller.handleVideoSizeChange(keepWindowSize: false)
controller.player.videoSizeForDisplay = (3840, 960)
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.width, 960) && near(window.frame.height, 240),
      "wide crop fits the original window bounds instead of preserving area")
for _ in 0..<4 {
  for size in [(3840, 2160), (1440, 1080), (3840, 960)] {
    controller.player.videoSizeForDisplay = size
    controller.handleVideoSizeChange(keepWindowSize: false)
  }
  check(near(window.frame.width, 960) && near(window.frame.height, 240),
        "successive aspect and crop changes use one reference without cumulative shrinking")
}
controller.player.videoSizeForDisplay = (3840, 2160)
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.width, 960) && near(window.frame.height, 540),
      "Reset returns to the original proportions and reference size")

let largeReference = referenceFrame.centeredResize(to: NSSize(width: 1280, height: 720))
controller.beginWindowSession(at: largeReference)
controller.player.videoSizeForDisplay = (3840, 960)
controller.handleVideoSizeChange(keepWindowSize: false)
window.setFrame(window.frame.centeredResize(to: NSSize(width: 960, height: 240)), display: false)
controller.player.videoSizeForDisplay = (3840, 2160)
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.width, 960) && near(window.frame.height, 540),
      "manually shrinking a cropped window scales its original reference instead of adopting the crop bounds")
controller.player.videoSizeForDisplay = (3840, 960)
controller.handleVideoSizeChange(keepWindowSize: false)
window.setFrame(window.frame.centeredResize(to: NSSize(width: 1200, height: 300)), display: false)
controller.player.videoSizeForDisplay = (3840, 2160)
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.width, 1200) && near(window.frame.height, 675),
      "manually enlarging a cropped window scales both dimensions of its original reference")

controller.beginWindowSession(at: referenceFrame)
controller.player.videoSizeForDisplay = (900, 1600)
controller.handleVideoSizeChange(keepWindowSize: false)
let portraitFrame = window.frame
check(near(portraitFrame.width, 400) && near(portraitFrame.height, 540),
      "portrait width minimum adds side fields while preserving reference height")
window.setFrame(portraitFrame.centeredResize(to: portraitFrame.size.multiply(1.0625)), display: false)
controller.player.videoSizeForDisplay = (3840, 2160)
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.width, 1020) && near(window.frame.height, 573.75),
      "manual resize from a minimum-clamped portrait scales the original landscape reference")

controller.beginWindowSession(at: NSRect(x: 100, y: 100, width: 400, height: 225))
controller.player.videoSizeForDisplay = (3840, 2160)
controller.handleVideoSizeChange(keepWindowSize: false)
controller.player.videoSizeForDisplay = (2700, 2160)
controller.handleVideoSizeChange(keepWindowSize: false)
window.setFrame(window.frame.centeredResize(to: NSSize(width: 600, height: 480)), display: false)
controller.player.videoSizeForDisplay = (3840, 2160)
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.width, 853.333333) && near(window.frame.height, 480),
      "removing minimum fields by hand updates the original scale from visible video, not padded window bounds")

controller.beginWindowSession(at: referenceFrame)
controller.player.videoSizeForDisplay = (3840, 960)
controller.handleVideoSizeChange(keepWindowSize: false)
controller.setWindowScale(0.3125)
controller.player.videoSizeForDisplay = (3840, 2160)
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.width, 1200) && near(window.frame.height, 675),
      "explicit scale while cropped updates the original reference proportionally")

controller.beginWindowSession(at: referenceFrame)
controller.cropExitOverlay = CropExitFixture(frame: NSRect(origin: .zero, size: referenceFrame.size))
controller.player.videoSizeForDisplay = (3840, 960)
controller.handleVideoSizeChange(keepWindowSize: false)
let deferred = controller.cropExitOverlay!.targetWindowFrame!
check(near(deferred.width, 960) && near(deferred.height, 240) && window.frame == referenceFrame,
      "crop transition prepares a fitted target without resizing the covered player")
window.setFrame(referenceFrame.centeredResize(to: NSSize(width: 960, height: 390)), display: false)
controller.handleVideoSizeChange(keepWindowSize: false)
check(controller.cropExitOverlay!.targetWindowFrame!.size == deferred.size,
      "an intermediate animated frame cannot scale the reference on another output notification")
window.setFrame(deferred, display: false)
controller.cropExitOverlay = nil
controller.player.videoSizeForDisplay = (3840, 2160)
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.width, 960) && near(window.frame.height, 540),
      "completed crop transition retains the original reference for Reset")

for unlocked in [false,true] {
  Preference.unlockWindowAspectRatio = unlocked
  for physical in [false,true] {
    Preference.physical = physical
    for size in [(3840,924), (1080,1920), (3840,2160), (2,1), (1,2)] {
      controller.beginWindowSession(at: original)
      controller.player.videoSizeForDisplay = size
      controller.handleVideoSizeChange(keepWindowSize: false)
      if unlocked {
        check(window.frame == original, "unlocked crop keeps the freely chosen frame (physical=\(physical))")
        check(window.aspectRatio == .zero, "unlocked window stays unlocked")
      } else {
        let fitted = NSSize(width: size.0, height: size.1).shrink(toSize: original.size)
        check(near(window.frame.width, max(fitted.width, 400)) && near(window.frame.height, max(fitted.height, 225)),
              "locked window fits the image inside reference bounds with independent minimums for \(size)")
        check(window.frame.width < 1000 && window.frame.height < 1000,
              "crop sizing derives from the 500pt window rather than source pixels")
        check(near(window.frame.midX, original.midX) && near(window.frame.midY, original.midY),
              "crop resize retains window center")
        check(near(window.aspectRatio.aspect, window.frame.size.aspect, tolerance: 0.005), "native Lock follows the actual window including any minimum fields")
      }
      check(controller.pip.aspectRatio == NSSize(width:size.0,height:size.1), "PiP tracks crop display geometry independently")
      let settled = window.frame
      controller.handleVideoSizeChange(keepWindowSize: false)
      check(near(window.frame.width, settled.width) && near(window.frame.height, settled.height),
            "repeated reconfiguration is stable for \(size): \(settled) -> \(window.frame) (unlocked=\(unlocked))")
    }
  }
}
// Repeated aspect switches preserve the user's scale, including a minimum-size clamp.
Preference.unlockWindowAspectRatio = false
let roundTrip = NSRect(x: screen.midX-270, y: screen.midY-152, width:540, height:304)
controller.beginWindowSession(at: roundTrip)
for _ in 0..<4 {
  for size in [(1280,720), (960,720), (720,1280), (1280,720)] {
    controller.player.videoSizeForDisplay = size
    controller.handleVideoSizeChange(keepWindowSize:false)
    if size.0 == 720 {
      // Native titled windows may finish rounding one point after animation.
      let rounded = window.frame.centeredResize(to:NSSize(width:window.frame.width,height:window.frame.height+1))
      window.onFrame = nil
      window.setFrame(rounded,display:false)
      window.onFrame = { controller.notifyLiveResize() }
    }
  }
  check(near(window.frame.width,540) && near(window.frame.height,303.75),
        "landscape/4:3/portrait round trips preserve the reference bounds through minimum constraints")
}
Preference.unlockWindowAspectRatio = false
Preference.physical = false
controller.player.videoSizeForDisplay = (80000,1000)
controller.handleVideoSizeChange(keepWindowSize:false)
controller.player.videoSizeForDisplay = (1280,720)
controller.handleVideoSizeChange(keepWindowSize:false)
check(near(window.frame.width,540) && near(window.frame.height,304), "return from a screen-constrained aspect restores the reference bounds")
controller.player.videoSizeForDisplay = (3840,2160)
controller.beginWindowSession(at: NSRect(x: original.minX, y: original.minY, width: 874, height: 525))
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.width, 874) && near(window.frame.height, 491.625) && near(window.frame.size.aspect, 16.0/9, tolerance: 0.005),
      "reported 874x525 window fits 16:9 inside its reference bounds")
Preference.unlockWindowAspectRatio = false
Preference.physical = false
controller.player.videoSizeForDisplay = (3840,924)
controller.beginWindowSession(at: original)
controller.fsState = FullscreenState(isFullscreen: true, priorWindowedFrame: original)
window.setFrame(screen,display:false)
let fullscreenFrame = window.frame
controller.handleVideoSizeChange(keepWindowSize: false)
check(window.frame == fullscreenFrame && controller.fsState.priorWindowedFrame!.width < 1000 &&
      near(controller.fsState.priorWindowedFrame!.width, 500) && near(controller.fsState.priorWindowedFrame!.height, 225),
      "fullscreen stays fullscreen while its prior window fits the crop at the user's scale")
controller.fsState = .windowed
controller.beginWindowSession(at: original)
controller.interactiveMode.isActive = true
controller.handleVideoSizeChange(keepWindowSize: false)
check(window.frame == original && controller.interactiveMode.resizes == 1,
      "uncropping while the editor is open only lays out its preview")
controller.interactiveMode.isActive = false
controller.handleVideoSizeChange(keepWindowSize: true)
check(near(window.frame.width, 500) && near(window.frame.height, 225),
      "full-source exit refresh can adapt the window from its current scale")
controller.player.info.justStartedFile = true
controller.player.info.justOpenedFile = true
controller.shouldApplyInitialWindowSize = true
controller.player.videoSizeForDisplay = (960,540)
controller.handleVideoSizeChange(keepWindowSize: false)
check(window.frame.size == NSSize(width:960,height:540),
      "a fresh window keeps explicit startup sizing")
// Do not resize retains the established scale for manual and playlist loads,
// including repeated first-frame notifications before playback-restart clears flags.
for unlocked in [false, true] {
  Preference.unlockWindowAspectRatio = unlocked
  for manuallyOpened in [false, true] {
    window.aspectRatio = .zero
    controller.beginWindowSession(at: original)
    for source in [(3840,2160), (1080,1920), (3840,924), (3840,2160)] {
      controller.player.info.trackSelectionGeneration += 1
      controller.player.info.justStartedFile = true
      controller.player.info.justOpenedFile = manuallyOpened
      controller.player.videoSizeForDisplay = source
      controller.handleVideoSizeChange(keepWindowSize: false)
      let settled = window.frame
      controller.handleVideoSizeChange(keepWindowSize: false)
      check(near(window.frame.width, settled.width) && near(window.frame.height, settled.height),
            "repeated file-start geometry is stable")
      if unlocked {
        check(window.frame == original, "manual/playlist loads retain a freely sized window")
      } else {
        check(window.frame.width < 1000 && window.frame.height < 1000,
              "manual/playlist loads never expand an existing 500pt window to 4K pixels")
        let fitted = NSSize(width: source.0, height: source.1).shrink(toSize: original.size)
        check(near(window.frame.width, max(fitted.width, 400)) && near(window.frame.height, max(fitted.height, 225)),
              "new media fits the existing scale and respects independent minimums")
      }
    }
    if !unlocked {
      check(near(window.frame.width, original.width) && near(window.frame.height, original.width * 9 / 16),
            "playlist round trips retain the reference bounds across minimum-size clamps")
    }
  }
}
Preference.unlockWindowAspectRatio = false
controller.player.info.justStartedFile = false
controller.player.info.justOpenedFile = false
controller.player.videoSizeForDisplay = (960,540)
controller.setWindowScale(0.75)
check(window.frame.size == NSSize(width:720,height:405) && near(window.aspectRatio.aspect, window.frame.size.aspect, tolerance: 0.001),
      "explicit video scale still changes size with the video aspect locked")
check(controller.player.events.count > 0 && controller.scaleUpdates > 0,
      "geometry change still emits normal UI/MPV synchronization")
for physical in [false, true] {
  Preference.physical = physical
  controller.player.videoSizeForDisplay = (3840,924)
  let scaleFrame = NSRect(x:0,y:0,width:500,height:121)
  controller.updateWindowParametersForMPV(withFrame:scaleFrame)
  let width = physical ? window.convertToBacking(scaleFrame).width : scaleFrame.width
  check(abs(controller.player.info.cachedWindowScale - Double(width)/3840) < 0.000001,
        "MPV scale feedback uses transformed display pixels and the current Retina policy")
}
Preference.physical = false
controller.player.videoSizeForDisplay = (1280,720)
controller.beginWindowSession(at: original)
controller.setWindowScale(100)
check(near(window.frame.width,screen.width) || near(window.frame.height,screen.height),
      "an explicit oversized scale fits the requested video to the screen")
let beforeInvalidScale = window.frame
controller.setWindowScale(.nan); controller.setWindowScale(-1)
check(window.frame == beforeInvalidScale, "invalid explicit scales cannot damage window geometry")
// Exercise the actual user-facing setters through output-geometry notification.
// Geometry resolution is a fixture boundary; the setters and window handling are production.
for unlocked in [false, true] {
  Preference.unlockWindowAspectRatio = unlocked
  for physical in [false, true] {
    Preference.physical = physical
    for action in ["4:3", "Default", "invalid", "0", "90", "180", "270"] {
      var frames: [NSRect] = []
      for source in [(1280, 720), (3840, 2160)] {
        let prior = NSRect(x: screen.midX - 400, y: screen.midY - 225, width: 800, height: 450)
        window.aspectRatio = .zero
        controller.beginWindowSession(at: prior)
        controller.player.videoSizeForDisplay = source
        controller.player.mpv.mutation = { name, value in
          if name == MPVOption.Video.videoRotate {
            let turn = Int(value)!
            controller.player.videoSizeForDisplay = (turn == 90 || turn == 270) ? (source.1, source.0) : source
          } else {
            controller.player.videoSizeForDisplay = value == "-1" ? source : (source.1 * 4 / 3, source.1)
          }
          controller.handleVideoSizeChange(keepWindowSize: false)
        }
        if let degrees = Int(action) { controller.player.setVideoRotate(degrees) }
        else { controller.player.setVideoAspect(action) }
        let actual = window.frame
        let output = controller.player.videoSizeForDisplay
        if unlocked {
          check(actual == prior && window.aspectRatio == .zero,
                "\(action) retains an unlocked frame independent of clip resolution")
        } else {
          check(actual.width < 1000 && actual.height < 1000,
                "\(action) starts from the 800pt window rather than clip pixels")
          let fitted = NSSize(width: output.0, height: output.1).shrink(toSize: prior.size)
          check(near(actual.width, max(fitted.width, 400)) && near(actual.height, max(fitted.height, 225)),
                "\(action) fits transformed geometry within the original bounds and minimums")
          check(near(actual.midX, prior.midX) && near(actual.midY, prior.midY),
                "\(action) retains the current window center")
        }
        frames.append(actual)
        controller.handleVideoSizeChange(keepWindowSize: false)
        check(near(window.frame.width, actual.width) && near(window.frame.height, actual.height),
              "\(action) settles across repeated output notifications")
      }
      check(near(frames[0].width, frames[1].width) && near(frames[0].height, frames[1].height),
            "\(action) produces the same frame for 720p and 4K sources (unlocked=\(unlocked), physical=\(physical))")
    }
  }
}
controller.player.mpv.mutation = nil
let routed = controller.geometryRequests.count
let transformWrites = controller.player.mpv.writes.count
controller.player.mpv.panscan = 0.35
controller.player.setVideoAspect("4:3")
controller.player.setVideoRotate(90)
check(controller.geometryRequests.count == routed + 2 &&
      controller.geometryRequests.suffix(2).elementsEqual([.aspect, .rotation]),
      "explicit Aspect and Rotation setters route through their geometry transaction")
check(controller.player.mpv.writes.count == transformWrites + 2 && controller.player.mpv.panscan == 0.35,
      "explicit transforms perform one option write each without temporary panscan mutation")
controller.player.setVideoAspect("invalid")
let writes = controller.player.mpv.writes.count
controller.player.setVideoRotate(45)
check(controller.player.mpv.writes.count == writes,
      "unsupported rotation leaves MPV and the sizing policy unchanged")
check(controller.player.info.unsureAspect == "Default", "invalid aspect continues to select the existing Default behavior")
// Track selection can reconfigure video without ever passing through an aspect,
// rotation or crop setter. Exercise the actual track and reconfig methods.
for unlocked in [false, true] {
  Preference.unlockWindowAspectRatio = unlocked
  for physical in [false, true] {
    Preference.physical = physical
    for source in [(1280, 720), (3840, 2160), (1080, 1920)] {
      let prior = NSRect(x: screen.midX - 400, y: screen.midY - 225, width: 800, height: 450)
      window.aspectRatio = .zero
      controller.beginWindowSession(at: prior)
      controller.player.info.displayWidth = 1280
      controller.player.info.displayHeight = 720
      controller.player.mpv.mutation = { name, value in
        guard name == MPVOption.TrackSelection.vid else { return }
        let output = value == "0" ? (640, 360) : source
        controller.player.videoSizeForDisplay = output
        controller.player.mpv.integers[MPVProperty.dwidth] = output.0
        controller.player.mpv.integers[MPVProperty.dheight] = output.1
        controller.player.onVideoReconfig()
      }
      for id in [0, 1, 0, 1] {
        let before = window.frame
        controller.player.setTrack(id, forType: .video)
        if unlocked {
          check(window.frame == prior, "video track/None retains the freely chosen window")
        } else {
          check(window.frame.width < 1000 && window.frame.height < 1000,
                "video track/None stays at the current scale instead of clip pixels")
          let output = controller.player.videoSizeForDisplay
          let fitted = NSSize(width: output.0, height: output.1).shrink(toSize: prior.size)
          check(near(window.frame.width, max(fitted.width, 400)) && near(window.frame.height, max(fitted.height, 225)),
                "video track/None fits display geometry while retaining independent minimums")
          check(near(window.frame.midX, before.midX) && near(window.frame.midY, before.midY),
                "video track/None retains the window center")
        }
        let settled = window.frame
        controller.player.onVideoReconfig()
        check(window.frame == settled, "repeated track output notifications do not change window scale")
      }
      // Direct MPV output changes use the same policy even without setTrack.
      window.aspectRatio = .zero; controller.beginWindowSession(at: prior)
      controller.player.videoSizeForDisplay = (3840, 2160)
      controller.player.mpv.integers[MPVProperty.dwidth] = 3840
      controller.player.mpv.integers[MPVProperty.dheight] = 2160
      controller.player.info.displayWidth = 0; controller.player.info.displayHeight = 0
      controller.player.onVideoReconfig()
      check(window.frame == prior, "direct video reconfig retains current frame at unchanged aspect")
    }
  }
}
controller.player.mpv.mutation = { name, value in
  if name == MPVOption.TrackSelection.aid {
    controller.player.mpv.integers[name] = Int(value)!
    controller.player.aidChanged()
  }
}
for unlocked in [false, true] {
  Preference.unlockWindowAspectRatio = unlocked
  let before = window.frame
  for id in [0, 1, 2, 0, 1] {
    controller.player.setTrack(id, forType: .audio)
    check(window.frame == before,
          "audio track/None leaves window geometry and video sizing policy unchanged")
    check(controller.muteButton.isHidden == (id == 0) && controller.volumeSlider.isHidden == (id == 0),
          "audio track/None still updates native volume control visibility")
  }
}
check(controller.player.notifications == 10, "audio selection retains all track-change notifications")
controller.player.mpv.mutation = nil
// Legacy output-notification fallback ownership, still used for non-explicit
// output changes. Explicit Aspect/Rotation routing is checked above.
Preference.unlockWindowAspectRatio = false
Preference.animationsDisabled = false
controller.player.disableWindowAnimation = false
controller.player.info.justStartedFile = false
controller.player.mpv.panscan = 0.35
window.orderFrontRegardless()
check(controller.beginVideoAspectTransition() && controller.player.mpv.panscan == 1,
      "legacy output-change fallback fills the viewport before applying window geometry")
check(!controller.beginVideoAspectTransition(), "overlapping changes retain one original fill value")
controller.finishVideoAspectTransition()
check(controller.player.mpv.panscan == 0.35, "completion restores the exact prior pan-and-scan setting")
controller.beginVideoAspectTransition()
controller.player.mpv.panscan = 0.2
controller.finishVideoAspectTransition()
check(controller.player.mpv.panscan == 0.2, "a user's intervening fill change is preserved")
controller.player.mpv.panscan = 0.35
var filledDuringFrameApplication = false
var asynchronousDuringFrameApplication = false
window.onFrame = {
  filledDuringFrameApplication = filledDuringFrameApplication || controller.player.mpv.panscan == 1
  asynchronousDuringFrameApplication = asynchronousDuringFrameApplication || controller.videoView.videoLayer.isAnimatingWindowResize
  controller.notifyLiveResize()
}
controller.player.videoSizeForDisplay = (720,1280)
controller.beginVideoAspectTransition()
controller.handleVideoSizeChange(keepWindowSize:false)
check(filledDuringFrameApplication && controller.player.mpv.panscan == 0.35,
      "fill covers the animated frame application and is restored after it")
check(asynchronousDuringFrameApplication && !controller.videoView.videoLayer.isAnimatingWindowResize,
      "native frame animation owns asynchronous video display only until completion")
window.onFrame = { controller.notifyLiveResize() }
controller.player.mpv.stringResult = -4
check(!controller.beginVideoAspectTransition() && controller.player.mpv.panscan == 0.35,
      "failed temporary fill does not take ownership")
controller.player.mpv.stringResult = 0
for blocked in 0..<6 {
  Preference.unlockWindowAspectRatio = blocked == 0
  Preference.animationsDisabled = blocked == 1
  controller.player.disableWindowAnimation = blocked == 2
  controller.fsState = blocked == 3 ? FullscreenState(isFullscreen:true,priorWindowedFrame:window.frame) : .windowed
  controller.pipStatus = blocked == 4 ? .inPIP : .notInPIP
  controller.interactiveMode.isActive = blocked == 5
  let before = controller.player.mpv.writes.count
  check(!controller.beginVideoAspectTransition() && controller.player.mpv.writes.count == before,
        "free-aspect/disabled-animation/fullscreen/PiP/crop mode does not acquire temporary fill")
}
Preference.unlockWindowAspectRatio = false
Preference.animationsDisabled = false
controller.player.disableWindowAnimation = false
controller.fsState = .windowed
controller.pipStatus = .notInPIP
controller.interactiveMode.isActive = false
controller.beginVideoAspectTransition()
controller.player.info.trackSelectionGeneration += 1
controller.player.mpv.panscan = 0.7
controller.finishVideoAspectTransition()
check(controller.player.mpv.panscan == 0.7, "completion from an old file cannot restore its fill into a new file")
controller.beginVideoAspectTransition()
controller.finishVideoAspectTransition(restore:false)
controller.player.mpv.panscan = 0 // mpv automatically resets file-local options on unload
controller.beginVideoAspectTransition()
controller.finishVideoAspectTransition()
check(controller.player.mpv.panscan == 0, "a new-file cancellation cannot leak the prior file's saved fill")
Preference.unlockWindowAspectRatio = false
controller.fsState = .windowed
controller.beginWindowSession(at: original)
controller.cropExitOverlay = CropExitFixture(frame: NSRect(origin: .zero, size: original.size))
controller.player.videoSizeForDisplay = (2902, 1421)
controller.handleVideoSizeChange(keepWindowSize: false)
check(window.frame == original,
      "crop output geometry cannot resize the window before the presentation is ready")
check(controller.cropExitOverlay!.targetWindowFrame != original,
      "crop output records its target for the shared image and window transition")
let signals = controller.cropReadySignals
controller.player.onVideoReconfig()
check(controller.cropReadySignals == signals,
      "an intermediate video-reconfig event cannot mark the old output as ready")
controller.player.videoOutputSizeChanged()
check(controller.cropReadySignals == signals + 1,
      "changed filtered output can finish a playing crop without a playback-restart event")
// Loading policy is independent of output transforms. Exercise the actual native
// handler with all UI timing/scale choices and repeated loading notifications.
controller.cropExitOverlay = nil
controller.geometryMotion = nil
controller.player.disableWindowAnimation = true
Preference.animationsDisabled = true
controller.player.sourceDisplaySize = nil
controller.cachedGeometry = nil
controller.player.geometry = nil
controller.shouldApplyInitialWindowSize = false
let policySource = NSSize(width: 960, height: 540)
let policyStart = NSRect(x: screen.midX - 320, y: screen.midY - 180, width: 640, height: 360)
for timing in [Preference.ResizeWindowTiming.always, .onlyWhenOpen, .never] {
  Preference.resizeTiming = timing
  for manuallyOpened in [false, true] {
    for option in [Preference.ResizeWindowOption.half, .normal, .oneAndHalf, .double, .fitScreen] {
      Preference.resizeOption = option
      for physical in [false, true] {
        Preference.physical = physical
        for unlocked in [false, true] {
          Preference.unlockWindowAspectRatio = unlocked
          for fullscreen in [false, true] {
            controller.fsState = .windowed
            controller.beginWindowSession(at: policyStart)
            controller.player.info.trackSelectionGeneration += 1
            controller.player.info.justStartedFile = true
            controller.player.info.justOpenedFile = manuallyOpened
            controller.player.videoSizeForDisplay = (960, 540)
            if fullscreen {
              controller.fsState = FullscreenState(isFullscreen: true, priorWindowedFrame: policyStart)
              window.setFrame(screen, display: false)
            }
            let visibleBefore = window.frame
            let shouldResize = (timing == .always || (timing == .onlyWhenOpen && manuallyOpened))
              && (!unlocked || manuallyOpened)
            var expectedSize = policyStart.size
            if shouldResize {
              let logical = physical ? window.convertFromBacking(NSRect(origin: .zero, size: policySource)).size : policySource
              expectedSize = option == .fitScreen ? logical.shrink(toSize: screen.size) : logical.multiply(CGFloat(option.ratio))
              expectedSize = expectedSize.satisfyMaxSizeWithSameAspectRatio(screen.size)
                .satisfyMinSizeWithSameAspectRatio(controller.minimumWindowSize)
            }
            controller.handleVideoSizeChange(keepWindowSize: false)
            let sizedFrame = fullscreen ? controller.fsState.priorWindowedFrame! : window.frame
            check(near(sizedFrame.width, expectedSize.width) && near(sizedFrame.height, expectedSize.height),
                  "timing=\(timing), manual=\(manuallyOpened), scale=\(option), physical=\(physical), unlocked=\(unlocked), fullscreen=\(fullscreen) obey the file resize policy")
            if fullscreen { check(window.frame == visibleBefore, "file resize updates fullscreen return geometry without leaving fullscreen") }
            // Loading flags remain true until playback-restart. A duplicate and
            // a subsequent crop must use the newly established reference.
            controller.handleVideoSizeChange(keepWindowSize: false)
            let repeated = fullscreen ? controller.fsState.priorWindowedFrame! : window.frame
            check(repeated == sizedFrame, "duplicate first-frame notifications keep the selected file size")
            controller.player.videoSizeForDisplay = (960, 270)
            controller.handleVideoSizeChange(keepWindowSize: false)
            let cropped = fullscreen ? controller.fsState.priorWindowedFrame! : window.frame
            check(cropped.width <= sizedFrame.width + 1 && cropped.height <= sizedFrame.height + 1,
                  "crop during loading retains the selected window scale in every timing mode")
            controller.player.videoSizeForDisplay = (960, 540)
            controller.handleVideoSizeChange(keepWindowSize: false)
            let restored = fullscreen ? controller.fsState.priorWindowedFrame! : window.frame
            check(near(restored.width, sizedFrame.width) && near(restored.height, sizedFrame.height),
                  "Reset returns to the selected file size without reviving an earlier reference")
          }
        }
      }
    }
  }
}
Preference.resizeTiming = .never
Preference.resizeOption = .normal
Preference.physical = false
Preference.unlockWindowAspectRatio = false
controller.fsState = .windowed
// Fresh/reused windows retain startup geometry in every timing mode. Restart
// restoration overrides it once, even while loading flags remain set.
for timing in [Preference.ResizeWindowTiming.always, .onlyWhenOpen, .never] {
  Preference.resizeTiming = timing
  controller.beginWindowSession(at: policyStart)
  controller.resetWindowSizingForNewSession()
  controller.player.info.trackSelectionGeneration += 1
  controller.player.info.justStartedFile = true
  controller.player.info.justOpenedFile = true
  controller.player.videoSizeForDisplay = (960, 540)
  controller.player.geometry = GeometryDef.parse("800x450+80+100")
  controller.handleVideoSizeChange(keepWindowSize: false)
  let startupFrame = window.frame
  check(near(startupFrame.width, 800) && near(startupFrame.height, 450),
        "all timing modes retain explicit initial geometry on a reused core")
  controller.handleVideoSizeChange(keepWindowSize: false)
  check(window.frame == startupFrame, "duplicate load notifications cannot override explicit initial geometry")
  controller.applyRestartWindowFrame(policyStart)
  controller.handleVideoSizeChange(keepWindowSize: false)
  check(window.frame == policyStart, "restart geometry overrides every file resize timing during the same load")
  controller.player.geometry = nil
}
// A layout-only refresh does not consume the subsequent new-file resize. A
// preference changed during playback takes effect at the next file, not now.
controller.cachedGeometry = nil
Preference.resizeTiming = .always
controller.beginWindowSession(at: policyStart)
controller.player.info.trackSelectionGeneration += 1
controller.handleVideoSizeChange(keepWindowSize: true)
check(window.frame == policyStart, "keepWindowSize layout refresh does not apply the file size preference")
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.width, 960), "the next output notification still applies the pending new-file policy")
controller.player.info.justStartedFile = false
controller.player.info.justOpenedFile = false
controller.setUserWindowFrame(policyStart)
controller.handleVideoSizeChange(keepWindowSize: false)
check(window.frame == policyStart, "Always does not reapply source size during ordinary playback")
controller.player.info.trackSelectionGeneration += 1
controller.player.info.justStartedFile = true
Preference.resizeTiming = .never
controller.handleVideoSizeChange(keepWindowSize: false)
check(window.frame == policyStart, "switching to Do not resize preserves the user frame on the next playlist item")
Preference.resizeTiming = .always
controller.handleVideoSizeChange(keepWindowSize: false)
check(window.frame == policyStart, "changing the timing after a file was sized waits for a new file")
controller.player.info.trackSelectionGeneration += 1
controller.handleVideoSizeChange(keepWindowSize: false)
check(near(window.frame.width, 960), "the next playlist item applies the newly selected Always mode")
window.close()
print("Completed \(checks) native crop/rotation/aspect/track window checks.")
