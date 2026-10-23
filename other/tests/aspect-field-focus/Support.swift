import Cocoa

// Compile the production AspectRatioView with only unrelated player/layout stubs.
struct TestUI {
  func localized(_ key: String) -> String { key }
  func hStack(spacing: CGFloat, _ views: NSView...) -> NSStackView {
    NSStackView(views: views)
  }
}
fileprivate let ui = TestUI()
enum AppData { static let aspectsInPanel = ["Default", "4:3", "16:9"] }
extension Notification.Name {
  static let iinaVideoParamsChanged = Self("test.video")
  static let iinaTrackSettingsChanged = Self("test.settings")
}
enum TestOSD { case aspect(String) }
class PlayerCore {
  @discardableResult func performSidebarChange<T>(_ action: () -> T) -> T { action() }
  struct Info {
    struct State { var active = true }
    var state = State()
    var unsureAspect = "Default"
  }
  var info = Info()
  var aspectWrites: [String] = []
  struct Window { struct Editor { var isActive = false }; var interactiveMode = Editor() }
  var mainWindow = Window()
  struct VideoSettings { var aspect = "Default" }
  func scopedVideoSettings() -> VideoSettings { VideoSettings(aspect: info.unsureAspect) }
  func setScopedVideoAspect(_ value: String) { setVideoAspect(value) }
  func observe(_ name: Notification.Name, _ callback: @escaping (Notification) -> Void) {}
  func setVideoAspect(_ value: String) { info.unsureAspect = value; aspectWrites.append(value) }
  func sendOSD(_ osd: TestOSD) {}
}
class HorizontalScrollViewWithIndicator: NSView {
  let scrollView = NSScrollView()
  override init(frame: NSRect) {
    super.init(frame: frame)
    addSubview(scrollView)
  }
  required init?(coder: NSCoder) { fatalError() }
  func setDocumentContent(_ content: NSStackView) { scrollView.documentView = content }
}
extension NSView {
  @discardableResult func size(width: CGFloat? = nil, height: CGFloat? = nil) -> Self {
    if let width { frame.size.width = width }
    if let height { frame.size.height = height }
    return self
  }
}
