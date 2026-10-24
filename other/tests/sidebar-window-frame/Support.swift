import Cocoa

struct LayoutValue {
  let value: CGFloat
  init(_ value: CGFloat, _ compact: CGFloat? = nil) { self.value = value }
  func get() -> CGFloat { value }
  func use(_ block: @escaping (CGFloat) -> Void, applyNow: Bool = true) { if applyNow { block(value) } }
  static let panelCornerRadius = LayoutValue(0)
}
extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
extension Notification.Name { static let iinaSidebarStatusChanged = Self("harness.sidebar.status") }
extension NSEvent {
  func inAnyOf(_ views: [NSView?]) -> Bool {
    views.compactMap { $0 }.contains { $0.bounds.contains($0.convert(locationInWindow, from: nil)) }
  }
}
protocol InitializingFromKey: CustomStringConvertible {
  static var defaultValue: Self { get }
  init?(key: Preference.Key)
}
enum Preference {
// PRODUCTION_OSC_CLICK_ACTION
  enum Key: String { case oscLeftClickAction, oscRightClickAction, oscDoubleClickAction, settingsLeading, playlistLeading, pluginsLeading, useLiquidGlassSidebar,
    useLiquidGlassOSC, dockedControlBarAndTitlebar, edgeToEdgeVideo, disableAnimations,
    leadingSidebarWidth, trailingSidebarWidth, alwaysShowOnTopIcon, compactUI, enableControlBarAutoHide, controlBarAutoHideTimeout }
  enum Glass { case sidebar, osc }
  static var values: [Key: Any] = [:]
  static func integer(for key: Key) -> Int { values[key] as? Int ?? (key == .oscLeftClickAction ? 3 : (key == .oscRightClickAction ? 1 : 2)) }
  static func float(for key: Key) -> Float { values[key] as? Float ?? 2.5 }
  static func bool(for key: Key) -> Bool { values[key] as? Bool ?? false }
  static func set(_ value: Any, for key: Key) { values[key] = value; Observer.emit(key) }
  static func liquidGlass(_ part: Glass) -> Bool { bool(for: part == .sidebar ? .useLiquidGlassSidebar : .useLiquidGlassOSC) }
  static var unlockWindowAspectRatio = true
  static var floatingOSCDefaultPosition: FloatingOSCPosition { .initial }
  static var isDocked: Bool { bool(for: .dockedControlBarAndTitlebar) && !bool(for: .edgeToEdgeVideo) }
  class Observer {
    static var subscriptions: [UUID: ([Key], (Key) -> Void)] = [:]
    var ids: [UUID] = []
    func addAll(_ keys: [Key], _ action: @escaping (Key) -> Void) {
      let id = UUID(); ids.append(id); Self.subscriptions[id] = (keys, action)
    }
    func addAll(_ keys: Key..., runNow: Bool = false, _ action: @escaping (Key) -> Void) {
      addAll(keys, action); if runNow { keys.forEach(action) }
    }
    func add(_ key: Key, runNow: Bool, _ action: @escaping (Key) -> Void) {
      // Each fixture observer needs multiple independent subscriptions.
      addAll([key], action); if runNow { action(key) }
    }
    static func emit(_ key: Key) { Array(subscriptions.values).forEach { if $0.0.contains(key) { $0.1(key) } } }
    deinit { ids.forEach { Self.subscriptions.removeValue(forKey: $0) } }
  }
}
typealias PK = Preference.Key
struct AccessibilityPreferences {
  static var motionReductionEnabled = false
  static func adjustedDuration(_ duration: TimeInterval) -> TimeInterval { Preference.bool(for: .disableAnimations) ? 0 : duration }
}
class TestVideoView: NSView { var lastEventId = -1 }
struct InteractiveMode { var isActive = false }
class VolumeButton: NSView {}
class PluginSidebarView: NSView {}
protocol HeaderInsets {
  func setLeadingConstraint(_ value: CGFloat, animated: Bool)
  func setTrailingConstraint(_ value: CGFloat, animated: Bool)
}
class MainWindowController: NSObject {
  func updateOSCToolbarButtonStates() {}
  var floatingOSCScale: CGFloat = 1
  var isCropTransitionInProgress = false
  enum UIAnimationState { case hidden, shown, willShow, willHide }
  var window: NSWindow?
  var interactiveMode = InteractiveMode()
  var isOntop = false
  struct Player {
    struct PreviewTime {
      var second: Double
      var stringRepresentation: String { String(format: "%02d:%02d", Int(second) / 60, Int(second) % 60) }
      static func * (lhs: PreviewTime, rhs: Double) -> PreviewTime { PreviewTime(second: lhs.second * rhs) }
    }
    struct Info {
      var isNetworkResource = false
      var currentURL: URL?
      var videoDuration: PreviewTime? = PreviewTime(second: 300)
      var chapterTitle: String?
      struct Chapter { let title: String }
      func getChapter(forVideoTime: PreviewTime) -> Chapter? { chapterTitle.map(Chapter.init) }
    }
    var disableUI = false
    func refreshSyncUITimer() {}
    var info = Info()
    func getMediaTitle() -> String { "Preview media" }
  }
  var player = Player()
  enum LogLevel { case warning }
  func log(_ message: String, level: LogLevel) {}
  var mouseExitEnterCount = 0
  var isMouseInWindow = true
  var isMomentumScrollingAllowed = false
  var currentControlBar: NSView? { oscFloatingView }
  let playSlider = NSSlider(frame: NSRect(x: 20, y: 8, width: 400, height: 20))
  let thumbnailPeekView = ThumbnailPeekView()
  lazy var timePreviewView = TimePreviewView(mainWindow: self)
  lazy var chapterPreviewView = TimePreviewView(mainWindow: self)
  private var seekPreviewHover: SeekPreviewHoverController?
  var isSeekingWithSlider = false
  var seekPreviewUpdates = 0
  var lastSeekPreviewPoint: NSPoint?
  func updateTimePreviewAndThumbnail(_ point: NSPoint) {
    seekPreviewUpdates += 1
    lastSeekPreviewPoint = point
    thumbnailPeekView.isHidden = false
    timePreviewView.isHidden = false
    chapterPreviewView.isHidden = false
  }
  var liveText = InteractiveMode()
  enum PIPStatus { case notInPIP, inPIP }
  var pipStatus = PIPStatus.notInPIP
  var pipReturnWindowAlpha: CGFloat?
  var animationState = UIAnimationState.shown
  private var uiAnimationGeneration = 0
  private var isUIHiddenByOSCClick = false
  private var isPluginMenuTracking = false
  var hideControlTimer: Timer?
  let fadeableViews = FadeableViewController()
  var isFullscreenTransitionInProgress = false
  enum FullscreenState { case windowed, fullscreen; var isFullscreen: Bool { self == .fullscreen } }
  var fsState = FullscreenState.windowed
  enum OSCPosition { case floating, top, bottom }
  var oscPosition = OSCPosition.floating
// PRODUCTION_SEEK_PREVIEW_LAYOUT
// PRODUCTION_HEADER_VISIBILITY

  @objc func ontopButtonAction() {}
  @objc func removeVideoViewBlackBars() {}
  let videoView = TestVideoView()
  var videoViewContainer: NSView! = NSView()
  let osdView = NSView()
  let additionalInfoView = NSView()
  var titleBarView: NSView!
  var oscBottomView: ChromeFixture!
  lazy var oscFloatingView = OSCFloatingView(mainWindow: self)
  var minimumWindowSize = FloatingOSCMetrics.minimumWindowSize
  func updateFloatingOSCScale(scale: CGFloat) { floatingOSCScale = scale }
  lazy var sidebars = SidebarController(mainWindow: self)
  func setWindowToolbar() {}
  var videoContainerPhysicalConstraints: [NSLayoutConstraint] = []
  var videoContainerConstraints: [NSLayoutConstraint.Attribute: NSLayoutConstraint] = [:]
  let layoutSides: [NSLayoutConstraint.Attribute] = [.leading, .trailing, .top, .bottom]
  func installVideoConstraints() { setupVideoContainerConstraints() }
  func installAccessoryConstraints() {
// PRODUCTION_ACCESSORY_CONSTRAINTS
  }
// PRODUCTION_VIDEO_CONSTRAINTS
}
class SidebarViewController: NSViewController {
  struct TabType: Equatable { let name: String }
  unowned let mainWindow: MainWindowController
  var sidebarType: SidebarController.ViewType { .settings }
  var leadingPrefKey: Preference.Key { .settingsLeading }
  var isLeading: Bool { Preference.bool(for: leadingPrefKey) }
  var widthRange: ClosedRange<CGFloat> { 300...500 }
  var width: CGFloat { 300 }
  let tabHeader = NSView()
  var tabButtonsStackView: NSView? { tabHeader }
  var topConstraint: NSLayoutConstraint!
  func setTopInset(_ height: CGFloat, animated: Bool) {
    if animated { topConstraint.animator().constant = height }
    else { topConstraint.constant = height }
  }
  var currentTab = TabType(name: "main")
  init(mainWindow: MainWindowController) { self.mainWindow = mainWindow; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError() }
  override func loadView() {
    view = NSView(); view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(tabHeader); tabHeader.translatesAutoresizingMaskIntoConstraints = false
    topConstraint = tabHeader.topAnchor.constraint(equalTo: view.topAnchor)
    NSLayoutConstraint.activate([topConstraint, tabHeader.leftAnchor.constraint(equalTo: view.leftAnchor),
                                 tabHeader.rightAnchor.constraint(equalTo: view.rightAnchor),
                                 tabHeader.heightAnchor.constraint(equalToConstant: 52)])
  }
  func findTab(named name: String) -> TabType? { TabType(name: name) }
  func pleaseSwitchToTab(_ tab: TabType) { currentTab = tab }

}
class QuickSettingViewController: SidebarViewController {}
class PlaylistViewController: SidebarViewController {
  override var sidebarType: SidebarController.ViewType { .playlist }
  override var leadingPrefKey: Preference.Key { .playlistLeading }
}
class PluginViewController: SidebarViewController {
  override var sidebarType: SidebarController.ViewType { .plugins }
  override var leadingPrefKey: Preference.Key { .pluginsLeading }
}

// Required internal chrome width models the fixed icon/accessory row in the
// production titlebar. Sidebar-facing constraint priorities are injected from
// production files by the runner so this catches their minimum-window chain.
class ChromeFixture: NSView, HeaderInsets {
  let inner = NSView()
  var leadingConstraint: NSLayoutConstraint!
  var trailingConstraint: NSLayoutConstraint!
  var sidebarInsetPriority = NSLayoutConstraint.Priority.required
  var heightConstraint: NSLayoutConstraint!
  init(minimumWidth: CGFloat, titlebar: Bool) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    inner.translatesAutoresizingMaskIntoConstraints = false
    addSubview(inner)
    inner.widthAnchor.constraint(greaterThanOrEqualToConstant: minimumWidth).isActive = true
    heightConstraint = inner.heightAnchor.constraint(equalToConstant: 30)
    heightConstraint.isActive = true
    inner.topAnchor.constraint(equalTo: topAnchor).isActive = true
    inner.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
    leadingConstraint = inner.leadingAnchor.constraint(equalTo: leadingAnchor)
    trailingConstraint = trailingAnchor.constraint(equalTo: inner.trailingAnchor)
// PRODUCTION_CHROME_PRIORITIES


    leadingConstraint.isActive = true
    trailingConstraint.isActive = true
    inner.leftAnchor.constraint(greaterThanOrEqualTo: leftAnchor).isActive = true
    inner.rightAnchor.constraint(lessThanOrEqualTo: rightAnchor).isActive = true
  }
  required init?(coder: NSCoder) { fatalError() }
  func setLeadingConstraint(_ value: CGFloat, animated: Bool = true) {
    leadingConstraint.priority = value > 0 ? sidebarInsetPriority : .required
    leadingConstraint.constant = value
  }
  func setTrailingConstraint(_ value: CGFloat, animated: Bool = true) {
    trailingConstraint.priority = value > 0 ? sidebarInsetPriority : .required
    trailingConstraint.constant = value
  }
}

// The top OSC uses real NSStackView groups and the actual production Titlebar
// constraints / MainWindow visibility priorities inserted by the runner.
class TopOSCFixture: NSView {
  let oscContainer = NSView()
  let oscView = TimeLabelOverflowedStackView()
  var oscLeadingConstraint: NSLayoutConstraint!
  let oscVolumeView = NSView()
  let oscToolbarView = NSView()
  let oscPlayControlView = NSView()
  let oscSliderView = NSView()
  init(direction: NSUserInterfaceLayoutDirection) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    userInterfaceLayoutDirection = direction
    oscContainer.translatesAutoresizingMaskIntoConstraints = false
    oscContainer.userInterfaceLayoutDirection = direction
    addSubview(oscContainer)
    oscContainer.padding(.all)
    oscView.translatesAutoresizingMaskIntoConstraints = false
    oscView.userInterfaceLayoutDirection = direction
    oscView.orientation = .horizontal
    oscView.spacing = 8
    oscContainer.addSubview(oscView)
// PRODUCTION_TOP_OSC_CONSTRAINTS
    for (view, width) in [(oscVolumeView, CGFloat(110)), (oscToolbarView, CGFloat(140)),
                          (oscPlayControlView, CGFloat(120)), (oscSliderView, CGFloat(160))] {
      view.translatesAutoresizingMaskIntoConstraints = false
      view.widthAnchor.constraint(equalToConstant: width).isActive = true
      view.heightAnchor.constraint(equalToConstant: 24).isActive = true
    }
    let oscTopMainView = oscView
// PRODUCTION_TOP_OSC_GROUPS
  }
  required init?(coder: NSCoder) { fatalError() }
}

extension NSImage {
  static func sf(_ name: String, withConfiguration config: NSImage.SymbolConfiguration? = nil) -> NSImage? {
    let image = NSImage(systemSymbolName: name == "remove.blackbars" ? "rectangle" : name, accessibilityDescription: nil)
    return config.flatMap { image?.withSymbolConfiguration($0) } ?? image
  }
}
extension NSColor { static var titleBarBorder: NSColor { .separatorColor } }
extension NSFont { static func titleBarFont(ofSize size: CGFloat) -> NSFont { .systemFont(ofSize: size) } }
