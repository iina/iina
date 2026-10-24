import Cocoa
typealias AccentSwitch = NSButton

struct LayoutValue {
  let value: CGFloat
  init(_ value: CGFloat, _ compact: CGFloat? = nil) { self.value = value }
  func get() -> CGFloat { value }
  func use(_ block: @escaping (CGFloat) -> Void) { block(value) }
}
extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
class MPVColorStringTransformer: ValueTransformer {}
extension NSImage {
  static func sf(_ names: [String], withConfiguration config: NSImage.SymbolConfiguration? = nil) -> NSImage? {
    names.compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }.first
  }
  static func sf(_ names: String..., withConfiguration config: NSImage.SymbolConfiguration? = nil) -> NSImage? {
    sf(names, withConfiguration: config)
  }
}
class SettingsUIHelper: UIHelper {
  static let sharedUI = SettingsUIHelper(scope: "settings")
  private static let strings: [String: String] = {
    let path = ProcessInfo.processInfo.environment["IINA_TEST_LOCALIZATION_PATH"]!
    let data = try! Data(contentsOf: URL(fileURLWithPath: path))
    return try! PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: String]
  }()
  override func localized(_ key: String) -> String {
    Self.strings["settings.\(key)"] ?? super.localized(key)
  }
}
struct AppData {
  static let mainWindowMinSize = NSSize(width: 285, height: 120)
  static let floatingOSCWindowMinSize = NSSize(width: 400, height: 225)
}
struct AccessibilityPreferences {
  static var animationsDisabled = true
  static var motionReductionEnabled = false
  static func adjustedDuration(_ duration: TimeInterval) -> TimeInterval { animationsDisabled ? 0 : duration }
}
enum Preference {
  enum Key: String { case initialWindowSizePosition, oscPosition, compactUI }
  enum OSCPosition { case floating, top, bottom }
  static var unlockWindowAspectRatio = false
  static var oscPosition = OSCPosition.bottom
  static var compactUI = false
  static func bool(for key: Key) -> Bool { compactUI }
  static func `enum`(for key: Key) -> OSCPosition { oscPosition }
  static let suiteName = "window-geometry-preview-harness-\(UUID().uuidString)"
  static let defaults = UserDefaults(suiteName: suiteName)!
  static var writes: [String] = []
  static func string(for key: Key) -> String? { defaults.string(forKey: key.rawValue) }
  static func set(_ value: Any, for key: Key) {
    writes.append(value as! String)
    defaults.set(value, forKey: key.rawValue)
  }
}
