import Cocoa
typealias AccentSegmentedControl = NSSegmentedControl
typealias AccentButton = NSButton
enum AppAccentColor { static var color: NSColor { .controlAccentColor } }

struct LayoutValue {
  let value: CGFloat
  init(_ value: CGFloat) { self.value = value }
  func get() -> CGFloat { value }
  func use(_ block: @escaping (CGFloat) -> Void, applyNow: Bool = true) { if applyNow { block(value) } }
}
extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
extension NSColor { static var sidebarContainerBorder: NSColor { .separatorColor } }
extension NSImage {
  static func sf(_ name: String) -> NSImage? { NSImage(systemSymbolName: name, accessibilityDescription: nil) }
}
class FlippedView: NSView { override var isFlipped: Bool { true } }
class UIHelper {
  static let shared = UIHelper()
  func separator() -> NSBox {
    let view = NSBox(); view.boxType = .separator; view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }
}
struct Preference {
  enum Key { case disableAnimations, compactUI, leadingSidebarWidth, trailingSidebarWidth, sidebarSettingsDisplayAtLeading, sidebarPlaylistDisplayAtLeading }
  static var animationsDisabled = true
  static func bool(for key: Key) -> Bool { key == .disableAnimations && animationsDisabled }
  static func integer(for key: Key) -> Int { 360 }
  class Observer {
    func add(_ key: Key, runNow: Bool, _ block: (Any?) -> Void) { if runNow { block(nil) } }
    func addAll(_ keys: Key..., runNow: Bool = false, _ block: (Key) -> Void) { if runNow { keys.forEach(block) } }
  }
}
struct AccessibilityPreferences {
  static var motionReductionEnabled = false
  static func adjustedDuration(_ duration: TimeInterval) -> TimeInterval { Preference.animationsDisabled ? 0 : duration }
}
struct MPVTrack: Equatable {
  enum TrackType { case video, audio, sub, secondSub }
  let id: Int
  var isExternal = false
  var readableLanguage: String? { nil }
  func readableString(includingLanguage: Bool) -> String { "Track \(id)" }
}
class TrackInfoFixture {
  var trackSelectionGeneration = 0
  var sid: Int? = 0
  var secondSid: Int? = 0
  var videoTrackOrder: [Int] = []
  var audioTrackOrder: [Int] = []
  func orderedTrackList(_ type: MPVTrack.TrackType) -> [MPVTrack] {
    let order = type == .audio ? audioTrackOrder : videoTrackOrder
    return order.compactMap { id in tracks.first { $0.id == id } } + tracks.filter { !order.contains($0.id) }
  }
  func activeTrackIDs(_ type: MPVTrack.TrackType) -> Set<Int> { [] }
  var tracks = (1...50).map { MPVTrack(id: $0) }
  func trackList(_ type: MPVTrack.TrackType) -> [MPVTrack] { tracks }
  func currentTrack(_ type: MPVTrack.TrackType) -> MPVTrack? { nil }
}
class PlayerCore {
  @discardableResult func performSidebarChange<T>(_ action: () -> T) -> T { action() }
  let info = TrackInfoFixture()
  var trackChanges = 0
  func setAudioTracks(_ ids: Set<Int>) -> Bool { trackChanges += 1; return true }
  func setVideoTracks(_ ids: Set<Int>, order: [Int]? = nil) -> Bool { trackChanges += 1; return true }
  private var observers: [Notification.Name: [(Notification?) -> Void]] = [:]
  func observe(_ key: Notification.Name, _ block: @escaping (Notification?) -> Void) {
    observers[key, default: []].append(block)
  }
  func postNotification(_ key: Notification.Name) { observers[key]?.forEach { $0(nil) } }
  func setTrack(_ id: Int, forType type: MPVTrack.TrackType) { trackChanges += 1 }
  func removeExternalTrack(_ id: Int, type: MPVTrack.TrackType, order: [Int]) -> Bool { false }
}
extension Notification.Name { static let iinaTracklistChanged = Self("trackListChanged") }
extension NSUserInterfaceItemIdentifier { static let trackName = Self("TrackName") }
extension Array {
  subscript(at index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
enum Constants { enum String { static let trackNone = "<None>" } }
class SidebarController {
  enum ViewType { case settings, playlist, plugins }
  func hide(_ type: ViewType) {}
}
class MainWindowController {
  let player = PlayerCore()
  let sidebars = SidebarController()
}
class WheelEvent: NSEvent {
  var x: CGFloat = 0, y: CGFloat = 0
  var inputPhase: Phase = [], momentum: Phase = []
  var precise = false
  var time: TimeInterval = 0
  var point: NSPoint = .zero
  var targetWindow: NSWindow?
  var backingEvent: CGEvent?
  override var type: EventType { .scrollWheel }
  override var scrollingDeltaX: CGFloat { x }
  override var scrollingDeltaY: CGFloat { y }
  override var deltaX: CGFloat { x }
  override var deltaY: CGFloat { y }
  override var phase: Phase { inputPhase }
  override var momentumPhase: Phase { momentum }
  override var hasPreciseScrollingDeltas: Bool { precise }
  override var timestamp: TimeInterval { time }
  override var locationInWindow: NSPoint { point }
  override var window: NSWindow? { targetWindow }
  override var windowNumber: Int { targetWindow?.windowNumber ?? 0 }
  override var cgEvent: CGEvent? { backingEvent }
}
