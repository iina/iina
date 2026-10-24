import Cocoa
typealias AccentSegmentedControl = NSSegmentedControl
struct AccessibilityPreferences {
  static var motionReductionEnabled = false
  static var disableAnimations = false
  static func adjustedDuration(_ duration: TimeInterval) -> TimeInterval { disableAnimations ? 0 : duration }
}
struct LayoutValue {
  let value: CGFloat
  init(_ value: CGFloat) { self.value = value }
  func get() -> CGFloat { value }
  func use(_ block: @escaping (CGFloat) -> Void, applyNow: Bool = true) { if applyNow { block(value) } }
  static let sidebarContainerPadding = LayoutValue(12)
  static let sidebarMargin = LayoutValue(10)
}
enum Preference {
  enum Key: String { case sidebarPluginsDisplayAtLeading, lastSelectedPlugin }
  static let domain = ProcessInfo.processInfo.environment["PLUGIN_SELECTOR_TEST_DOMAIN"]!
  static let ud = UserDefaults(suiteName: domain)!
  static func string(for key: Key) -> String? { ud.string(forKey: key.rawValue) }
  static func set(_ value: String, for key: Key) { ud.set(value, forKey: key.rawValue) }
}
enum SidebarController { enum ViewType { case plugins } }
extension Notification.Name { static let iinaPluginChanged = Self("plugins.changed") }
extension NSImage {
  static let puzzlepieceExtensionFill = NSImage(systemSymbolName: "puzzlepiece.extension.fill", accessibilityDescription: nil)!
  static func sf(_ name: String, withConfiguration config: NSImage.SymbolConfiguration? = nil) -> NSImage? {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
    return config.flatMap { image?.withSymbolConfiguration($0) } ?? image
  }
}
extension NSMenu {
  func addItem(withTitle title: String, action: Selector, target: AnyObject, obj: Any) {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = target; item.representedObject = obj; addItem(item)
  }
}
class UIHelper {
  static let shared = UIHelper()
  func label(_ text: String, wrapping: Bool, isSmall: Bool, isSecondary: Bool, canCompress: Bool) -> NSTextField {
    let view = NSTextField(wrappingLabelWithString: text)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }
  func separator() -> NSBox {
    let view = NSBox(); view.boxType = .separator
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }
}
class SidebarScrollView {
  class Container: NSView {
    init(_ content: NSView, configure: (NSView) -> Void) {
      super.init(frame: .zero); addSubview(content); configure(content)
    }
    required init?(coder: NSCoder) { fatalError() }
  }
}
class PluginInstance {
  struct Plugin { let identifier: String; var sidebarTabName: String? }
  var plugin: Plugin
  let sidebarTabView = NSView()
  init(_ id: String, _ name: String?) {
    plugin = Plugin(identifier: id, sidebarTabName: name)
    sidebarTabView.translatesAutoresizingMaskIntoConstraints = false
  }
}
class PlayerFixture {
  var plugins: [PluginInstance] = []
  func observe(_ notification: Notification.Name, _ callback: @escaping (Notification) -> Void) {}
}
class PluginWindowFixture {
  func trackPluginMenu(_ body: () -> Void) { body() }
}
class SidebarViewController: NSViewController {
  let mainWindow = PluginWindowFixture()
  struct TabType {
    var tag: Int; var name: String; var image: NSImage
    init(_ tag: Int, _ name: String, _ image: NSImage) { self.tag = tag; self.name = name; self.image = image }
  }
  var sidebarType: SidebarController.ViewType { .plugins }
  var leadingPrefKey: Preference.Key { .sidebarPluginsDisplayAtLeading }
  var allTabs: [TabType] { [] }
  var defaultTab: TabType { .pluginPlaceholder }
  var useTabView: Bool { true }
  lazy var currentTab = defaultTab
  let player = PlayerFixture()
  var tabButtonsSegmentControl: NSSegmentedControl!
  let tabButtonsStackView = NSStackView()
  var tabButtonsHeightConstraint: NSLayoutConstraint!
  var closeSidebarBtnSizeConstraint: NSLayoutConstraint!
  let closeSidebarBtn = NSButton(title: "Close", target: nil, action: nil)
  let iconConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
  let compactIconConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
  var isLeading = true; var isCompact = false
  override func loadView() {
    view = NSView()
    view.addSubview(tabButtonsStackView)
    tabButtonsSegmentControl = makeTabSegmentControl()
    tabButtonsStackView.addArrangedSubview(tabButtonsSegmentControl)
    tabButtonsHeightConstraint = tabButtonsStackView.heightAnchor.constraint(equalToConstant: 52)
    closeSidebarBtnSizeConstraint = closeSidebarBtn.widthAnchor.constraint(equalToConstant: 36)
    closeSidebarBtnSizeConstraint.isActive = true
    setupTabs(); updateTabButtonSize(); updateTabButtonLayout()
  }
  func makeTabSegmentControl() -> NSSegmentedControl { NSSegmentedControl() }
  func setupTabs() {}
  func updateTabActiveStatus() {}
  func updateTabButtonSize() {}
  func updateTabButtonLayout() {
    tabButtonsStackView.arrangedSubviews.forEach {
      tabButtonsStackView.removeArrangedSubview($0); $0.removeFromSuperview()
    }
    for item in isLeading ? [tabButtonsSegmentControl!, closeSidebarBtn] : [closeSidebarBtn, tabButtonsSegmentControl!] {
      tabButtonsStackView.addArrangedSubview(item)
    }
  }
  func switchToTab(_ tab: TabType) {}
  func tabBtnSegmentControlAction(_ sender: NSSegmentedControl) {}
}
class WheelEvent: NSEvent {
  var dy: CGFloat = 0; var dx: CGFloat = 0
  var precise = false; var gesturePhase: Phase = []; var inertia: Phase = []
  var time: TimeInterval = 0
  override var scrollingDeltaY: CGFloat { dy }
  override var scrollingDeltaX: CGFloat { dx }
  override var hasPreciseScrollingDeltas: Bool { precise }
  override var phase: Phase { gesturePhase }
  override var momentumPhase: Phase { inertia }
  override var timestamp: TimeInterval { time }
}
