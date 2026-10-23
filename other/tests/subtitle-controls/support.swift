import Cocoa
struct LayoutValue {
  let value: CGFloat
  init(_ value: CGFloat) { self.value = value }
  func get() -> CGFloat { value }
  func use(_ body: @escaping (CGFloat) -> Void, applyNow: Bool = true) { if applyNow { body(value) } }
  static let sidebarItemSpacing = LayoutValue(8)
  static let sidebarStackViewSpacing = LayoutValue(18)
  static let sidebarContainerPadding = LayoutValue(12)
}
struct MPVOption { struct Subtitles {
  static let subScale = "sub-scale", subFont = "sub-font", subFontSize = "sub-font-size"
  static let subColor = "sub-color", subOutlineColor = "sub-outline-color", subBackColor = "sub-back-color", subOutlineSize = "sub-outline-size"
  static let subDelay = "sub-delay", secondarySubDelay = "secondary-sub-delay"
  static let subPos = "sub-pos", secondarySubPos = "secondary-sub-pos"
} }
extension Notification.Name {
  static let iinaAudioDelayChanged = Self("audio-delay")
  static let iinaTrackSettingsChanged = Self("track-settings")
  static let iinaSubScaleChanged = Self("sub-scale")
  static let iinaSubFontChanged = Self("sub-font")
  static let iinaSubtitleStyleChanged = Self("sub-style")
  static let iinaSubDelayChanged = Self("sub-delay")
  static let iinaSubPositionChanged = Self("sub-pos")
}
extension NSImage.SymbolConfiguration { static let sidebarIconConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular) }
extension NSImage {
  static func sf(_ names: String..., withConfiguration config: NSImage.SymbolConfiguration? = nil) -> NSImage? {
    names.compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }.first
  }
}
enum Preference {
  enum Key { case subTextFont, subTextSize, subTextColorString, subBorderSize, subBorderColorString, subShadowColorString }
  static let defaultPreference: [Key: Any] = [
    .subTextFont: "Factory font", .subTextSize: Float(50), .subTextColorString: "1/1/1/1",
    .subBorderSize: Float(3), .subBorderColorString: "0/0/0/1", .subShadowColorString: "0/0/0/0"
  ]
  static var configured: [Key: Any] = [
    .subTextFont: "HelveticaNeue", .subTextSize: Float(48), .subTextColorString: "0.9/0.8/0.7/1",
    .subBorderSize: Float(1.75), .subBorderColorString: "0.2/0.3/0.4/1", .subShadowColorString: "0.1/0.1/0.1/0.5"
  ]
  static func string(for key: Key) -> String? { (configured[key] ?? defaultPreference[key]) as? String }
  static func float(for key: Key) -> Float { (configured[key] ?? defaultPreference[key]) as! Float }
}
final class MPVFixture {
  var supportsIndependentSecondarySubtitleStyle = true
  var values: [String: Double] = ["sub-delay": 0.5, "secondary-sub-delay": -0.7, "sub-pos": 90, "secondary-sub-pos": 10, "audio-delay": 0.25]
  var strings: [String: String] = [:]
  enum Level { case verbose }
  func setDouble(_ key: String, _ value: Double, level: Level = .verbose) { values[key.replacingOccurrences(of: "options/", with: "")] = value }
  func setString(_ key: String, _ value: String) { strings[key.replacingOccurrences(of: "options/", with: "")] = value }
  func getString(_ key: String) -> String? { strings[key] }
  func getDouble(_ key: String) -> Double { values[key] ?? 0 }
  func getInt(_ key: String) -> Int { Int(values[key] ?? 0) }
}
final class PlayerCore {
  @discardableResult func performSidebarChange<T>(_ action: () -> T) -> T { action() }
  struct Info { struct State { let active = true }; let state = State() }
  let info = Info(), mpv = MPVFixture()
  func observe(_ key: Notification.Name, _ handler: @escaping (Notification) -> Void) {}
  func postNotification(_ name: Notification.Name) {}
  func setSubDelay(_ value: Double, forPrimary: Bool = true) { mpv.values[forPrimary ? "sub-delay" : "secondary-sub-delay"] = value }
  func setSubPos(_ value: Int, forPrimary: Bool = true) { mpv.values[forPrimary ? "sub-pos" : "secondary-sub-pos"] = Double(value) }
  func scopedAudioDelay() -> Double { mpv.getDouble("audio-delay") }
  func setScopedAudioDelay(_ value: Double) { mpv.values["audio-delay"] = value }

}
extension UIHelper {
  func vStack(spacing: LayoutValue, wantsToGrow: Bool = false, _ views: NSView...) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing.get()
    return stack
  }
  func space() -> NSView { let view = NSView(); view.size(width: 0, height: 0); return view }
  func image(_ name: String, size: CGFloat, config: NSImage.SymbolConfiguration?) -> NSImageView {
    image(NSImage(systemSymbolName: name, accessibilityDescription: nil), size: size, scaleUp: false)
  }
}

class FlippedView: NSView { override var isFlipped: Bool { true } }
extension NSColor { static var sidebarContainerBorder: NSColor { .separatorColor } }
extension UIHelper {
  func hStack(_ views: [NSView]) -> NSStackView { hStack(spacing: 8, views) }
  func vStack(spacing: CGFloat, wantsToGrow: Bool, _ views: NSView...) -> NSStackView {
    vStack(spacing: spacing, wantsToGrow: wantsToGrow, views)
  }
  func vStack(spacing: CGFloat, wantsToGrow: Bool, _ views: [NSView]) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing
    return stack
  }
}

extension UIHelper {
  func vStack(spacing: LayoutValue, wantsToGrow: Bool, _ views: [NSView]) -> NSStackView {
    vStack(spacing: spacing.get(), wantsToGrow: wantsToGrow, views)
  }
}

typealias RoundedColorWell = NSColorWell
enum Utility {
  static var pendingFont: ((String?) -> Void)?
  static func quickFontPickerWindow(selecting: String?, completion: @escaping (String?) -> Void) { pendingFont = completion }
  static func toDisplaySubScale(fromRealSubScale realScale: Double) -> Double { realScale >= 1 ? realScale : -1 / realScale }
}
extension UIHelper {
  func image(_ names: String..., size: CGFloat, config: NSImage.SymbolConfiguration?) -> NSImageView {
    image(names.compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }.first, size: size, scaleUp: false)
  }
}
