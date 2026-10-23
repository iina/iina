import Cocoa

struct TestUI {
  func localized(_ key: String) -> String { key }
  func hStack(spacing: CGFloat, _ views: NSView...) -> NSStackView { NSStackView(views: views) }
}
fileprivate let ui = TestUI()
enum AppData { static let cropsInPanel = ["None", "4:3", "16:9", "21:9"] }
extension Notification.Name {
  static let iinaVideoParamsChanged = Self("test.video")
  static let iinaTrackSettingsChanged = Self("test.settings")
}
class PlayerCore {
  struct Info { struct State { var active = true }; var state = State() }
  struct VideoSettings { var cropDescription = "None" }
  class Window {
    struct Editor { var isActive = false }
    class Sidebars { func hideAllSideBars(_ done: () -> Void) { done() } }
    var interactiveMode = Editor()
    var sidebars = Sidebars()
  }
  enum OSD { case crop(String) }
  var info = Info()
  var settings = VideoSettings()
  var mainWindow: Window! = Window()
  var observers: [Notification.Name: [(Notification) -> Void]] = [:]
  func observe(_ name: Notification.Name, _ callback: @escaping (Notification) -> Void) {
    observers[name, default: []].append(callback)
  }
  func post(_ name: Notification.Name) { observers[name]?.forEach { $0(Notification(name: name)) } }
  func scopedVideoSettings() -> VideoSettings { settings }
  @discardableResult
  func performSidebarChange<T>(_ action: () -> T) -> T { action() }
  func setScopedCrop(_ value: String) { settings.cropDescription = value; post(.iinaTrackSettingsChanged) }
  func openScopedCustomCrop() {}
  func sendOSD(_ value: OSD) {}
}
class HorizontalScrollViewWithIndicator: NSView {
  let scrollView = NSScrollView()
  override init(frame: NSRect) { super.init(frame: frame); addSubview(scrollView) }
  required init?(coder: NSCoder) { fatalError() }
  func setDocumentContent(_ value: NSStackView) { scrollView.documentView = value }
}
extension NSView {
  @discardableResult func size(height: CGFloat) -> Self { frame.size.height = height; return self }
}
// PRODUCTION_CROP_VIEW

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
  precondition(condition(), label); checks += 1
}
fileprivate func control(_ view: CropView) -> NSSegmentedControl {
  (view.scrollView.documentView as! NSStackView).arrangedSubviews[0] as! NSSegmentedControl
}
let player = PlayerCore()
player.settings.cropDescription = "Custom"
fileprivate let reopened = CropView(player: player)
check(control(reopened).selectedSegment == 4, "Reopening a sidebar with an existing custom crop selects Custom immediately")
player.settings.cropDescription = "None"
player.post(.iinaTrackSettingsChanged)
check(control(reopened).selectedSegment == 0, "Committed Reset selects None")
player.settings.cropDescription = "Custom"
player.post(.iinaTrackSettingsChanged)
check(control(reopened).selectedSegment == 4, "Committed Custom selects Custom without needing a later video notification")
player.settings.cropDescription = "4:3"
fileprivate let preset = CropView(player: player)
check(control(preset).selectedSegment == 1, "Reopening a named preset selects its own segment")
player.settings.cropDescription = "Custom"
player.post(.iinaTrackSettingsChanged)
check(control(preset).selectedSegment == 4, "Switching the scoped settings target updates the selection")
player.mainWindow.interactiveMode.isActive = true
fileprivate let editing = CropView(player: player)
check(!control(editing).isEnabled, "New controls reflect an active editor immediately")
player.mainWindow.interactiveMode.isActive = false
player.post(.iinaTrackSettingsChanged)
check(control(editing).isEnabled, "Editor exit re-enables the crop selector")
control(editing).selectedSegment = 2
_ = control(editing).sendAction(control(editing).action, to: control(editing).target)
check(player.settings.cropDescription == "16:9" && control(reopened).selectedSegment == 2,
      "A preset action still commits through the scoped settings owner")
print("Crop selector: \(checks) native control checks passed")
