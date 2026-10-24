import Cocoa
import Darwin
setbuf(stdout, nil)
struct LayoutValue {
  let value: CGFloat
  init(_ value: CGFloat) { self.value = value }
  func get() -> CGFloat { value }
  func use(_ block: @escaping (CGFloat) -> Void, applyNow: Bool = true) { if applyNow { block(value) } }
  static let sidebarStackViewSpacing = LayoutValue(18)
}
final class PlayerCore {}
enum TrackSettingsGroup { case audioDelay, videoGeometry }
class SettingsTargetPopUp: NSView {}
final class TrackSettingsPopUp: SettingsTargetPopUp {
  init(player: PlayerCore, group: TrackSettingsGroup) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    widthAnchor.constraint(equalToConstant: 100).isActive = true
    heightAnchor.constraint(equalToConstant: 22).isActive = true
  }
  required init?(coder: NSCoder) { fatalError() }
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
    view.setContentHuggingPriority(.init(1), for: .horizontal)
    return view
  }
  func hStack(_ views: NSView...) -> NSStackView {
    let stack = NSStackView(views: views); stack.orientation = .horizontal
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }
  func vStack(spacing: LayoutValue, wantsToGrow: Bool, _ views: [NSView]) -> NSStackView {
    let stack = NSStackView(views: views); stack.orientation = .vertical
    stack.alignment = .leading; stack.translatesAutoresizingMaskIntoConstraints = false
    spacing.use { [weak stack] in stack?.spacing = $0 }
    return stack
  }
}
