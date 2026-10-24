import Cocoa
import QuartzCore

enum Logger { static func log(_ message: String) {} }
struct Preference {
  enum Key { case disableAnimations, enableLiveText }
  static var disabledAnimations = false
  static var liveTextEnabled = false
  static var isLiveTextEnabled = true
  static func bool(for key: Key) -> Bool {
    key == .disableAnimations ? disabledAnimations : liveTextEnabled
  }
  // PRODUCTION_TOOLBAR_TYPES
}
typealias PK = Preference.Key
struct AccessibilityPreferences {
  static var motionReductionEnabled = false
  // PRODUCTION_ADJUSTED_DURATION
}
extension NSImage {
  // PRODUCTION_SF
  // PRODUCTION_TINTED
}
extension NSView {
  func size(width: CGFloat, height: CGFloat) {
    widthAnchor.constraint(equalToConstant: width).isActive = true
    heightAnchor.constraint(equalToConstant: height).isActive = true
  }
}
extension Array {
  subscript(at index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

final class ActionReceiver: NSObject {
  var calls = 0
  var acceptSelection = false
  var onClick: ((OSCToolbarButton) -> Void)?
  @objc func clicked(_ sender: OSCToolbarButton) {
    calls += 1
    onClick?(sender)
    if acceptSelection { sender.setActive(!sender.isActive) }
  }
}

extension Notification.Name { static let iinaSidebarStatusChanged = Self("test-sidebar") }
enum SidebarTab { case settings, playlist, plugins }
final class SidebarFixture {
  var visible = Set<SidebarTab>()
  func isShowing(_ tab: SidebarTab) -> Bool { visible.contains(tab) }
}
enum PIPStatus { case notInPIP, inPIP, intermediate }
final class FadeableFixture { var updates = 0; func update() { updates += 1 } }
enum MPVOption { enum Window { static let fullscreen = "fullscreen" } }
final class ControllerPlayer {
  struct Info { struct State { var active = true }; var state = State() }
  final class Engine { var writes = 0; func setFlag(_ name: String, _ value: Bool) { writes += 1 } }
  var info = Info()
  let mpv = Engine()
}
final class ControllerFixture: NSObject {
  var oscToolbarView: NSStackView! = NSStackView()
  lazy var sidebars = SidebarFixture()
  let player = ControllerPlayer()
  // PRODUCTION_PIP_STATE
  // PRODUCTION_FULLSCREEN_STATE
  // PRODUCTION_FULLSCREEN_PROPERTY
  var floatingOSCToolbarConstraints: [(constraint: NSLayoutConstraint, original: CGFloat)] = []
  let fadeableViews = FadeableFixture()
  func applyFloatingOSCControlScale() {}
  @objc func toolBarButtonAction(_ sender: NSButton) {}
  func rebuild(_ types: [Preference.ToolBarButton]) { setupOSCToolbarButtons(types) }
  func notify(_ notification: Notification) { updateOSCToolbarButtons(notification) }
  func toolbarButton(_ type: Preference.ToolBarButton) -> OSCToolbarButton {
    oscToolbarView.views.first { $0.tag == type.rawValue } as! OSCToolbarButton
  }
  // PRODUCTION_CONTROLLER_METHODS
}
