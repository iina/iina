import Cocoa
extension Notification.Name { static let iinaTrackSettingsChanged = Self("scopedSettings") }

struct Preference {
  enum Key: String { case customCropAspectPresets }
  static let suiteName = "org.iina.custom-crop-tests.\(UUID().uuidString)"
  static let ud = UserDefaults(suiteName: suiteName)!
  static func array(for key: Key) -> [Any]? { ud.array(forKey: key.rawValue) }
  static func set(_ value: Any?, for key: Key) { ud.set(value, forKey: key.rawValue) }
}

struct AccessibilityPreferences {
  static var motionReductionEnabled = false
  static var disableAnimations = true
  static func adjustedDuration(_ duration: TimeInterval) -> TimeInterval { disableAnimations ? 0 : duration }
}
struct LayoutValue {
  let value: CGFloat
  func get() -> CGFloat { value }
  func use(_ block: @escaping (CGFloat) -> Void, applyNow: Bool = true) { if applyNow { block(value) } }
}
class UIHelper {
  static let shared = UIHelper()
  func localized(_ key: String) -> String {
    ["crop.save": "Save", "crop.reset": "Reset", "crop.original": "Original", "crop.custom": "Custom",
     "crop.width": "Width in pixels", "crop.height": "Height in pixels", "crop.aspect": "Crop aspect ratio",
     "crop.add_preset": "Add…", "crop.delete_preset": "Delete", "crop.delete_selected_preset": "Delete…", "crop.selection": "Crop selection", "crop.zoom": "Preview zoom", "crop.zoom_fit": "Fit",
     "general.cancel": "Cancel", "general.done": "Done"][key] ?? key
  }
  func button(_ key: String, target: NSObject?, action: Selector?) -> NSButton {
    let button = NSButton(title: localized(key), target: target, action: action)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }
  func hStack(spacing: CGFloat, _ views: NSView...) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing = spacing
    return stack
  }

}
class Aspect {
  let value: CGFloat
  init(size: NSSize) { value = size.width / size.height }
  init?(string: String) {
    let parts = string.split(separator: ":").compactMap { Double($0) }
    guard parts.count == 2, parts[1] > 0 else { return nil }
    value = CGFloat(parts[0] / parts[1])
  }
}
extension NSSize {
  func crop(withAspect aspect: Aspect) -> NSSize {
    width / height > aspect.value ? NSSize(width: height * aspect.value, height: height) :
      NSSize(width: width, height: width / aspect.value)
  }
  func shrink(toSize size: NSSize) -> NSSize {
    let scale = min(size.width / width, size.height / height)
    return NSSize(width: width * scale, height: height * scale)
  }
}
struct FilterPresetInstance {
  struct Preset { let name: String }
  let preset: Preset
  let params: [String: NSNumber]
}
struct Logger {
  enum Level { case warning }
  static func log(_ text: String, level: Level) {}
}
extension String { var mpvFixedLengthQuoted: String { "%\(utf8.count)%\(self)" } }
extension Array { subscript(at index: Int) -> Element? { indices.contains(index) ? self[index] : nil } }
struct Constants { struct FilterName { static let delogo = "delogo"; static let crop = "crop" } }
struct Utility {
  static var alerts: [String] = []
  static func showAlert(_ key: String) { alerts.append(key) }
}
struct ScopedCropFixture {
  var id = 1
  var originalTrack = VideoTrackProcessing()
  var geometry = CropVideoGeometry(sourceSize: NSSize(width: 960, height: 540), displaySize: NSSize(width: 960, height: 540), rotation: 0)
  var filter: MPVFilter? { originalTrack.crop.map { MPVFilter.crop(w: $0.width, h: $0.height, x: $0.x, y: $0.y, exact: true) } }
}
struct CropTrackFixture {
  var id = 1; var title: String? = "Camera"
  func readableString() -> String { title ?? "" }
}
enum MPVProperty { static let videoOutParams = "video-out-params" }
class PlayerFixture {
  var isRefreshingPausedCrop = false
  var canAnimateCropSource = true
  private func beginPausedCropRefresh() {}
  private func finishPausedCropRefresh() {}
  weak var mainWindow: MainWindowController!
  enum State { case paused, playing, stopped; var active: Bool { self != .stopped } }
  enum OSD { case crop(String) }
  class Info {
    var state = State.paused
    var trackSelectionGeneration = 1
    var unsureCrop = "None"
    var delogoFilter: MPVFilter?
    var cropFilter: MPVFilter?
    var videoTracks = [CropTrackFixture()]
    var videoTrackOrder: [Int] = []
    enum TrackType { case video }
    func orderedTrackList(_ type: TrackType) -> [CropTrackFixture] {
      videoTrackOrder.compactMap { id in videoTracks.first { $0.id == id } }
        + videoTracks.filter { !videoTrackOrder.contains($0.id) }
    }
  }
  var scopedCropPreview: ScopedCropFixture?
  var savedScopedCrop: TrackVideoCrop?
  var scopedCropSaves = 0, scopedCropCancels = 0
  var scopedCropApplySucceeds = true
  @discardableResult func finishScopedCustomCrop(crop: TrackVideoCrop? = nil, applying: Bool = false) -> Bool {
    if applying && !scopedCropApplySucceeds { return false }
    if applying { savedScopedCrop = crop; scopedCropSaves += 1 } else { scopedCropCancels += 1 }
    scopedCropPreview = nil
    return true
  }
  var publishedCropDescriptions: [String] = []
  func postNotification(_ name: Notification.Name) {
    if name == .iinaTrackSettingsChanged { publishedCropDescriptions.append(info.unsureCrop) }
  }
  let info = Info()
  final class Engine {
    var size = NSSize(width: 960, height: 540)
    func getInt(_ property: String) -> Int { Int(property.hasSuffix("/w") ? size.width : size.height) }
  }
  let mpv = Engine()
  var videoSizeForDisplay: (Int, Int) { (Int(mpv.size.width), Int(mpv.size.height)) }

  var originalVideoSize = (960, 540)
  var displaySizeOverride: NSSize?
  var rotation = 0
  func interactiveVideoGeometry(uncropped: Bool) -> CropVideoGeometry {
    let size = NSSize(width: originalVideoSize.0, height: originalVideoSize.1)
    return CropVideoGeometry(sourceSize: size, displaySize: displaySizeOverride ?? size, rotation: rotation)
  }
  var savedCrop: MPVFilter?
  var removedCropCount = 0
  var pausedCount = 0
  var resumedCount = 0
  var savedDelogo: MPVFilter?
  func pause() { pausedCount += 1; info.state = .paused }
  func resume() { resumedCount += 1; info.state = .playing }
  var filterRemovalSucceeds = true
  func removeVideoFilter(_ filter: MPVFilter) -> Bool {
    if filter.name == "crop" {
      removedCropCount += 1
      if filterRemovalSucceeds { savedCrop = nil }
    }
    return filterRemovalSucceeds
  }
  var filterAdditionSucceeds = true
  func addVideoFilter(_ filter: MPVFilter) -> Bool {
    guard filterAdditionSucceeds else { return false }
    if filter.name == "crop" { savedCrop = filter } else { savedDelogo = filter }
    return true
  }
  func sendOSD(_ osd: OSD) {}
}
class LiveTextFixture {
  var requests = 0
  func clearAnalysis() {}
  func requestAnalysis() { requests += 1 }
}
class MainWindowController {
  var cropExitOverlay: CropTransitionOverlay?
  // PRODUCTION_DEFER_CROP_RESTORATION
  private var forcedCropTransition = false
  var isCropTransitionInProgress: Bool {
    get { forcedCropTransition || interactiveMode.isEntering }
    set { forcedCropTransition = newValue }
  }
  func cancelCropExitTransition() {
    forcedCropTransition = false
    interactiveMode.cancelEntryTransition()
    interactiveMode.restoreExitPresentation()
  }
  var entryDuration: TimeInterval = 0
  func cropTransitionDuration(_ duration: TimeInterval) -> TimeInterval { entryDuration }
  func finishPendingNativeCropFrame(_ overlay: CropTransitionOverlay) {}
  func afterNativeCropFrame(_ overlay: CropTransitionOverlay, preparing: Bool = false,
                            outputIsReady: Bool = false, completion: @escaping () -> Void) {
    DispatchQueue.main.async(execute: completion)
  }
  func bindCropVideo(_ overlay: CropTransitionOverlay, pixelSize: NSSize) {
    overlay.useNativeVideo(videoView, in: videoViewContainer, pixelSize: pixelSize)
  }

  var exitPreparationObserver: ((NSRect, NSRect, NSRect, NSRect, NSImage?) -> Void)?
  func prepareCropExit(selection: NSRect, sourceSize: NSSize, initialFrame: NSRect,
                       initialClip: NSRect, initialSelection: NSRect,
                       controlsImage: NSImage?, controlsFrame: NSRect,
                       completion: @escaping () -> Bool) {
    exitPreparationObserver?(initialFrame, initialClip, initialSelection, controlsFrame, controlsImage)
    _ = completion()
  }
  struct FloatingOSCFixture { func cancelPositionAnimation() {} }
  let oscFloatingView = FloatingOSCFixture()
  let player = PlayerFixture()
  var window: NSWindow?
  var preparedWindowReferences = 0
  func prepareVideoTransformWindowReference() { preparedWindowReferences += 1 }
  var cropGeometryRefreshes = 0
  func handleVideoSizeChange(keepWindowSize: Bool) { cropGeometryRefreshes += 1 }
  let videoViewContainer = NSView()
  lazy var videoView = CropVideoFixture(player: player)
  var standardWindowButtons: [NSButton] = []
  let liveText = LiveTextFixture()
  lazy var interactiveMode = InteractiveModeController(mainWindow: self)
  private var videoViewConstraints: [NSLayoutConstraint.Attribute: NSLayoutConstraint] = [:]
  init(size: NSSize = NSSize(width: 960, height: 620)) {
    player.mainWindow = self
    window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window!.isReleasedWhenClosed = false
    let content = NSView()
    window!.contentView = content
    videoViewContainer.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(videoViewContainer)
    videoViewContainer.padding(.all(0))
    videoView.translatesAutoresizingMaskIntoConstraints = false
    videoView.wantsLayer = true
    videoViewContainer.addSubview(videoView)
    videoViewConstraints = [
      .leading: videoView.leadingAnchor.constraint(equalTo: videoViewContainer.leadingAnchor),
      .trailing: videoViewContainer.trailingAnchor.constraint(equalTo: videoView.trailingAnchor),
      .bottom: videoViewContainer.bottomAnchor.constraint(equalTo: videoView.bottomAnchor),
      .top: videoView.topAnchor.constraint(equalTo: videoViewContainer.topAnchor)
    ]
    NSLayoutConstraint.activate(Array(videoViewConstraints.values))
    content.layoutSubtreeIfNeeded()
  }
  func hideUI(force: Bool) {}
  func hideOSD() {}
  func forceDraw(_ reason: String) {}
// PRODUCTION_VIDEO_CONSTRAINT_UPDATE
}
class WheelEvent: NSEvent {
  var point = NSPoint.zero
  var dy: CGFloat = 0; var dx: CGFloat = 0
  var precise = false; var gesturePhase: Phase = []; var inertia: Phase = []
  var time: TimeInterval = 0
  var modifiers: NSEvent.ModifierFlags = []
  override var modifierFlags: NSEvent.ModifierFlags { modifiers }
  override var scrollingDeltaY: CGFloat { dy }
  override var scrollingDeltaX: CGFloat { dx }
  override var hasPreciseScrollingDeltas: Bool { precise }
  override var phase: Phase { gesturePhase }
  override var momentumPhase: Phase { inertia }
  override var timestamp: TimeInterval { time }
  override var locationInWindow: NSPoint { point }
}

final class CropRenderFixture {
  var isInCropTransition = false
  func cancelCropFrameRequests() {}
  var isPreparingCropFrame = false
  func setCropFramePreparation(_ preparing: Bool) { isPreparingCropFrame = preparing }
  func withCropFrameUpdate(_ body: () -> Void) { body() }
  var didPublishHandoff: (() -> Void)?
  func withCropFrameHandoff(_ body: () -> Void) {
    body()
    isPreparingCropFrame = false
    didPublishHandoff?()
  }
  func displayForCropHandoff(allowCachedFrame: Bool = false) {}
  var isAnimatingWindowResize = false
}

extension PlayerFixture {
  func cropTransitionFrame(in bounds: NSRect) -> CropTransitionOverlay.PlayerFrame? { nil }
}
