import Cocoa

// Compile the production sheet, UI helper and constraint helper together.
// Only unrelated application services/preferences and image tinting are stubbed.
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
  func tinted(_ color: NSColor) -> NSImage { self }
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
enum Preference {
  enum Key: String, CaseIterable {
    case controlBarPositionHorizontal, controlBarPositionVertical
    case controlBarPositionUsesUnifiedTravelRatios, controlBarPositionIsFactoryDefault, controlBarDefaultPositionIsCustomized
    case controlBarDefaultPlacement, controlBarCurrentPlacement
    case controlBarDefaultPositionHorizontal = "controlBarDefaultPositionHorizontalTravel"
    case controlBarDefaultPositionVertical = "controlBarDefaultPositionVerticalTravel"
  }
  static let defaults = UserDefaults(suiteName: "osc-position-preview-harness")!
  static var writes: [Key] = []
  static func bool(for key: Key) -> Bool { defaults.bool(forKey: key.rawValue) }
  static var isFloatingOSCDefaultPositionCustomized: Bool {
    if defaults.object(forKey: Key.controlBarDefaultPositionIsCustomized.rawValue) != nil {
      return bool(for: .controlBarDefaultPositionIsCustomized)
    }
    return defaults.object(forKey: Key.controlBarDefaultPositionHorizontal.rawValue) != nil ||
      defaults.object(forKey: Key.controlBarDefaultPositionVertical.rawValue) != nil
  }
  static func dictionary(for key: Key) -> [String: Any]? { defaults.dictionary(forKey: key.rawValue) }
  static func float(for key: Key) -> Float { defaults.float(forKey: key.rawValue) }
  static func set(_ value: Any, for key: Key) {
    writes.append(key)
    defaults.set(value, forKey: key.rawValue)
  }
}
