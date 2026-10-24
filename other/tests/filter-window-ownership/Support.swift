import AppKit
enum MPVProperty { static let vf = "vf", af = "af" }
struct MPVTrack {
  enum TrackType { case video, audio, sub, secondSub }
  let id: Int
  let type: TrackType
}
struct MPVFilter: Equatable {
  let stringFormat: String
  init?(rawString: String) { guard !rawString.isEmpty else { return nil }; stringFormat = rawString }
}
final class SavedFilter {
  let name = "Crop"
  var filterString = "crop=900:500"
  var isEnabled = false
}
enum Logger {
  enum Level { case warning }
  static func log(_ message: String, level: Level) {}
}
enum Utility { static func showAlert(_ message: String, sheetWindow: NSWindow?) {} }
extension Array { subscript(at index: Int) -> Element? { indices.contains(index) ? self[index] : nil } }
extension NSUserInterfaceItemIdentifier { static let value = Self("value") }
final class Engine {
  var mpv: OpaquePointer? = OpaquePointer(bitPattern: 1)
  var mutations: [String] = []
  var lists: [String: [MPVFilter]] = [:]
  func getFilters(_ type: String) -> [MPVFilter] { lists[type] ?? [] }
  func setFilters(_ type: String, filters: [MPVFilter]) { mutations.append("set:" + type); lists[type] = filters }
}
final class Info {
  var state = PlayerState.paused
  var trackSelectionGeneration = 1
  var delogoFilter: MPVFilter?
  var currentURL: URL?
  var isNetworkResource = false
}
final class PlayerCore {
  private static var activeStorage: PlayerCore?
  static var lastActive: PlayerCore {
    get { activeStorage! }
    set { activeStorage = newValue }
  }
  let info = Info(), mpv = Engine()
  weak var mainWindow: MainWindowController!
  var isInMiniPlayer = false, musicRequests = 0
  enum OSD { case addFilter(String), removeFilter }
  var osds = 0
  func sendOSD(_ value: OSD) { osds += 1 }
  func switchToMiniPlayer() { musicRequests += 1 }
  func add(_ filter: MPVFilter, _ type: String) -> Bool {
    mpv.mutations.append("add:" + type); mpv.lists[type, default: []].append(filter); return true
  }
  func remove(_ filter: MPVFilter, _ type: String) -> Bool {
    mpv.mutations.append("remove:" + type); mpv.lists[type]?.removeAll { $0 == filter }; return true
  }
  func addVideoFilter(_ filter: MPVFilter) -> Bool { add(filter, MPVProperty.vf) }
  func addAudioFilter(_ filter: MPVFilter) -> Bool { add(filter, MPVProperty.af) }
  func addVideoFilter(_ text: String) -> Bool { add(MPVFilter(rawString: text)!, MPVProperty.vf) }
  func addAudioFilter(_ text: String) -> Bool { add(MPVFilter(rawString: text)!, MPVProperty.af) }
  func removeVideoFilter(_ filter: MPVFilter, _ index: Int) -> Bool { remove(filter, MPVProperty.vf) }
  func removeAudioFilter(_ filter: MPVFilter, _ index: Int) -> Bool { remove(filter, MPVProperty.af) }
  func removeVideoFilter(_ filter: MPVFilter) -> Bool { remove(filter, MPVProperty.vf) }
  func removeVideoFilter(_ text: String, _ index: Int) -> Bool { remove(MPVFilter(rawString: text)!, MPVProperty.vf) }
  func removeAudioFilter(_ text: String, _ index: Int) -> Bool { remove(MPVFilter(rawString: text)!, MPVProperty.af) }
  func removeVideoFilter(_ text: String) -> Bool { remove(MPVFilter(rawString: text)!, MPVProperty.vf) }
  func removeAudioFilter(_ text: String) -> Bool { remove(MPVFilter(rawString: text)!, MPVProperty.af) }
}
final class TestWindow: NSWindow {
  var sheetStarts = 0, sheetEnds = 0
  override func beginSheet(_ sheetWindow: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) { sheetStarts += 1 }
  override func endSheet(_ sheetWindow: NSWindow, returnCode: NSApplication.ModalResponse) { sheetEnds += 1 }
}
final class RowTable: NSTableView {
  var fixtureRow = 0, reloads = 0
  override var selectedRow: Int { fixtureRow }
  override func row(for view: NSView) -> Int { fixtureRow }
  override func reloadData() { reloads += 1 }
  override func deselectAll(_ sender: Any?) { fixtureRow = -1 }
}
final class InteractiveModeController {
  enum Mode { case delogo }
  weak var mainWindow: MainWindowController!
  var isActive = false
  // PRODUCTION_CAN_ENTER
  func enter(mode: Mode) { if canEnter { isActive = true } }
}
final class Sidebar {
  var deferred = false
  var pending: (() -> Void)?
  func hideAllSideBars(_ completion: @escaping () -> Void) { if deferred { pending = completion } else { completion() } }
}
final class MainWindowController: NSWindowController, NSMenuItemValidation {
  enum PIPStatus { case notInPIP, inPIP }
  let player = PlayerCore(), sidebars = Sidebar()
  let videoViewContainer = NSView(), videoView = NSView()
  var loaded = true, isCropTransitionInProgress = false, isFullscreenTransitionInProgress = false
  var pipStatus = PIPStatus.notInPIP
  lazy var interactiveMode: InteractiveModeController = {
    let value = InteractiveModeController(); value.mainWindow = self; return value
  }()
  init() {
    let window = TestWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 360), styleMask: .borderless, backing: .buffered, defer: false)
    super.init(window: window); window.isReleasedWhenClosed = false
    window.contentView!.addSubview(videoViewContainer); videoViewContainer.addSubview(videoView)
    player.mainWindow = self
  }
  required init?(coder: NSCoder) { fatalError() }
  // PRODUCTION_WINDOW_MENU
}
final class MainMenuActionHandler: NSResponder, NSMenuItemValidation {
  let player: PlayerCore
  init(_ player: PlayerCore) { self.player = player; super.init() }
  required init?(coder: NSCoder) { fatalError() }
  @objc func menuDeleteCurrentFile(_ sender: NSMenuItem) {}
  @objc func menuShowCurrentFileInFinder(_ sender: NSMenuItem) {}
  @objc func menuChangeCrop(_ sender: NSMenuItem) {}
  @objc func menuChangeAspect(_ sender: NSMenuItem) {}
  @objc func menuChangeRotation(_ sender: NSMenuItem) {}
  @objc func menuToggleFlip(_ sender: NSMenuItem) {}
  @objc func menuToggleMirror(_ sender: NSMenuItem) {}
  @objc func menuToggleVideoFilterString(_ sender: NSMenuItem) {}
  @objc func menuCycleTrack(_ sender: NSMenuItem) {}
  @objc func menuChangeTrack(_ sender: NSMenuItem) {}
  // PRODUCTION_MAIN_MENU
}
final class FilterWindowController: NSWindowController {
  var filterType: String!
  var filters: [MPVFilter] = [], savedFilters = [SavedFilter()]
  private var filterIsSaved: [Bool] = []
  private weak var newFilterPlayer: PlayerCore?
  private var newFilterGeneration: Int?
  let currentFiltersTableView = RowTable(), savedFiltersTableView = RowTable()
  let saveFilterNameTextField = NSTextField(), keyRecordViewLabel = NSTextField(), removeButton = NSButton()
  let newFilterSheet = TestWindow()
  init(_ type: String) {
    filterType = type
    super.init(window: TestWindow()); window!.isReleasedWhenClosed = false; newFilterSheet.isReleasedWhenClosed = false
  }
  required init?(coder: NSCoder) { fatalError() }
  func updateButtons() { updateButtonStatus() }
  // PRODUCTION_FILTER
}
enum FilterParameterType { case text, int, float, choose }
struct FilterParameter { let type: FilterParameterType; var choices: [String] = [] }
struct FilterParameterValue {
  init(string: String) {}; init(int: Int) {}; init(float: Float) {}
}
final class FilterPresetInstance {
  var params: [String: FilterParameterValue] = [:]
  init(from: FilterPreset) {}
}
struct FilterPreset {
  let localizedName = "Crop"
  var params: [String: FilterParameter] = [:]
  func transformer(_ instance: FilterPresetInstance) -> MPVFilter { MPVFilter(rawString: "crop=900:500")! }
}
final class NewFilterSheetViewController: NSObject {
  let filterWindow: FilterWindowController
  var currentPreset: FilterPreset? = FilterPreset()
  var currentBindings: [String: NSControl] = [:]
  init(_ filterWindow: FilterWindowController) { self.filterWindow = filterWindow }
  // PRODUCTION_SHEET
}
