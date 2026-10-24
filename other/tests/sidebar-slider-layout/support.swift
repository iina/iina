import Cocoa
struct LayoutValue {
  let value: CGFloat
  init(_ value: CGFloat) { self.value = value }
  func get() -> CGFloat { value }
  func use(_ body: @escaping (CGFloat) -> Void, applyNow: Bool = true) { if applyNow { body(value) } }
}
final class PlayerCore {
  @discardableResult func performSidebarChange<T>(_ action: () -> T) -> T { action() }
  struct Info { struct State { let active = true }; let state = State() }
  let info = Info()
  func observe(_ key: Notification.Name, _ handler: @escaping (Notification) -> Void) {}
}
final class UIHelper {
  static let shared = UIHelper()
  func label(_ key: String, font: NSFont) -> NSTextField {
    let label = NSTextField(labelWithString: key)
    label.font = font; label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }
  func flexibleSpace() -> NSView {
    let view = NSView(); view.translatesAutoresizingMaskIntoConstraints = false
    view.heightAnchor.constraint(equalToConstant: 0).isActive = true
    view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return view
  }
  func image(_ image: NSImage?, size: CGFloat, scaleUp: Bool) -> NSImageView {
    let view = NSImageView(image: image ?? NSImage())
    view.translatesAutoresizingMaskIntoConstraints = false
    view.widthAnchor.constraint(equalToConstant: size).isActive = true
    view.heightAnchor.constraint(equalToConstant: size).isActive = true
    return view
  }
  func hStack(spacing: CGFloat, _ views: NSView...) -> NSStackView { hStack(spacing: spacing, views) }
  func hStack(spacing: CGFloat, _ views: [NSView]) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing = spacing
    return stack
  }
}
