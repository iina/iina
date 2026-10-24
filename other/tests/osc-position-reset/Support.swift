import Cocoa

// This harness compiles the production floating view and translucent wrapper.
// Application preferences and unrelated layout/player services are isolated stubs.
struct LayoutValue {
  let value: CGFloat
  init(_ regular: CGFloat, _ compact: CGFloat) { value = regular }
  func get() -> CGFloat { value }
  func use(_ block: @escaping (CGFloat) -> Void, applyNow: Bool = true) { if applyNow { block(value) } }
}
extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
extension CGPoint {
  func constrained(to rect: NSRect) -> CGPoint {
    CGPoint(x: x.clamped(to: rect.minX...max(rect.minX, rect.maxX)),
            y: y.clamped(to: rect.minY...max(rect.minY, rect.maxY)))
  }
}
extension Notification.Name {
  static let iinaSidebarStatusChanged = Self("harness.sidebar-status")
}
protocol InitializingFromKey: CustomStringConvertible {
  static var defaultValue: Self { get }
  init?(key: Preference.Key)
}
enum Preference {
// PRODUCTION_OSC_CLICK_ACTION
  enum Key: String, CaseIterable {
    case useLiquidGlassOSC, compactUI, oscLeftClickAction, oscRightClickAction, oscDoubleClickAction, disableAnimations
    // Retired production key: only used to verify old stored values cannot restore snapping.
    case controlBarStickToCenter
    case controlBarPositionUsesTravelRatios
    case controlBarPositionIsUserDefined, controlBarPositionUsesTopLeadingAnchor
    case controlBarPositionLeading, controlBarPositionTop
    case controlBarPositionUsesGapRatios, controlBarPositionLeadingGapRatio, controlBarPositionTopGapRatio
    case controlBarPositionHorizontal, controlBarPositionVertical
    case controlBarPositionUsesUnifiedTravelRatios, controlBarPositionIsFactoryDefault, controlBarDefaultPositionIsCustomized
    case controlBarDefaultPlacement, controlBarCurrentPlacement
    case controlBarDefaultPositionHorizontal = "controlBarDefaultPositionHorizontalTravel"
    case controlBarDefaultPositionVertical = "controlBarDefaultPositionVerticalTravel"
  }
  enum Glass { case osc }
  static var defaults = UserDefaults(suiteName: "osc-position-reset-harness")!
  static var isFloatingOSCDefaultPositionCustomized: Bool {
    if defaults.object(forKey: Key.controlBarDefaultPositionIsCustomized.rawValue) != nil {
      return bool(for: .controlBarDefaultPositionIsCustomized)
    }
    return defaults.object(forKey: Key.controlBarDefaultPositionHorizontal.rawValue) != nil ||
      defaults.object(forKey: Key.controlBarDefaultPositionVertical.rawValue) != nil
  }
  static func integer(for key: Key) -> Int {
    if let value = defaults.object(forKey: key.rawValue) as? Int { return value }
    return key == .oscLeftClickAction ? 3 : (key == .oscRightClickAction ? 1 : 2)
  }
  static func dictionary(for key: Key) -> [String: Any]? { defaults.dictionary(forKey: key.rawValue) }
  static func float(for key: Key) -> Float { defaults.float(forKey: key.rawValue) }
  static func bool(for key: Key) -> Bool { defaults.bool(forKey: key.rawValue) }
  static func set(_ value: Any, for key: Key) { defaults.set(value, forKey: key.rawValue) }
  static func liquidGlass(_ part: Glass) -> Bool { false }
  class Observer {
    func add(_ key: Key, runNow: Bool, _ action: (Any?) -> Void) { if runNow { action(nil) } }
  }
}
struct AccessibilityPreferences {
  static var motionReductionEnabled = false
  static func adjustedDuration(_ duration: TimeInterval) -> TimeInterval {
    Preference.bool(for: .disableAnimations) ? 0 : duration
  }
}
class HarnessSidebars {
  var frontRequests = 0
  func bringPanelToFront(_ view: NSView) { frontRequests += 1 }
  var left: CGFloat = 0
  var right: CGFloat = 0
  func floatingOSCSidebarExtents() -> (left: CGFloat, right: CGFloat) { (left, right) }
  func floatingOSCReservedSidebarExtents() -> (left: CGFloat, right: CGFloat) { (left, right) }
  func cancelDeferredPresentation() {}
  func resumeDeferredPresentation() {}
}
class MainWindowController: NSObject {
  struct FullscreenState { var isFullscreen = false }
  var fsState = FullscreenState()
  var hideRequests = 0
  func hideUIFromOSC() { hideRequests += 1 }
  func updateTimer() {}
  func hideSeekPreview() {}
  var window: NSWindow?
  var videoViewContainer: NSView!
  var titleBarView: NSView!
  let sidebars = HarnessSidebars()
  var minimumWindowSize = NSSize(width: 400, height: 225)
  var floatingOSCScale: CGFloat = 1
  var topRowHeight: NSLayoutConstraint?
  var bottomRowHeight: NSLayoutConstraint?
  func updateFloatingOSCScale(scale: CGFloat) {
    floatingOSCScale = scale
    topRowHeight?.constant = 45 * scale
    bottomRowHeight?.constant = 35 * scale
  }
}
class EventSinkView: NSView {
  var downEvents = 0
  var upEvents = 0
  override func mouseDown(with event: NSEvent) { downEvents += 1 }
  override func mouseUp(with event: NSEvent) { upEvents += 1 }
}
// The real VolumeButton is an NSView whose mouseDown consumes its action.
class VolumeButton: NSView {
  var clicks = 0
  override func mouseDown(with event: NSEvent) { clicks += 1 }
}
