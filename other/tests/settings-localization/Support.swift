import Cocoa

// Only unrelated UIHelper dependencies are fixtures. Localization uses a real
// main bundle with the repository's production resources and no defaults writes.
struct LayoutValue {
  let value: CGFloat
  init(_ value: CGFloat) { self.value = value }
  func get() -> CGFloat { value }
  func use(_ action: @escaping (CGFloat) -> Void) { action(value) }
}
struct Preference {
  struct Key { let rawValue: String }
}
class MPVColorStringTransformer: ValueTransformer {}
extension NSImage {
  static func sf(_ names: [String], withConfiguration configuration: NSImage.SymbolConfiguration? = nil) -> NSImage? {
    names.compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }.first
  }
  static func sf(_ names: String..., withConfiguration configuration: NSImage.SymbolConfiguration? = nil) -> NSImage? {
    sf(names, withConfiguration: configuration)
  }
}
