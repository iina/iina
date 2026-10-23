import Cocoa

final class TrackSettingsGroupView: NSView {
  var menuAnchor: NSView?
}

enum PlayerState: Int {
  case loaded, idle, shuttingDown
  var loaded: Bool { self == .loaded }
  var active: Bool { self == .loaded }
}
enum MPVProperty { static let vf = "vf" }
struct MPVFilter {
  let label: String?
  var params: [String: String]?
  init(name: String = "lavfi", label: String?, paramString: String) {
    self.label = label
    let value = paramString.dropFirst("graph=%".count)
    let split = value.firstIndex(of: "%")!
    let graph = String(value[value.index(after: split)...])
    precondition(Int(value[..<split]) == graph.utf8.count, "mpv graph quoting must use UTF-8 bytes")
    params = ["graph": graph]
  }
}
final class LUTMPVFixture {
  var filters: [MPVFilter] = []
  var reads = 0
  func getFilters(_ name: String) -> [MPVFilter] { reads += 1; return filters }
  func getString(_ name: String) -> String? {
    reads += 1
    return String(data: try! JSONSerialization.data(withJSONObject: filters.map { ["label": $0.label ?? "", "graph": $0.params?["graph"] ?? ""] }, options: [.sortedKeys]), encoding: .utf8)
  }
  func setString(_ name: String, _ value: String) {
    let previous = try! JSONSerialization.jsonObject(with: Data(value.utf8)) as! [[String: String]]
    filters = previous.map { row in
      let graph = row["graph"]!
      return MPVFilter(label: row["label"], paramString: "graph=%\(graph.utf8.count)%\(graph)")
    }
  }
}
final class LUTWindowFixture {
  struct Editor { var isActive = false }
  var interactiveMode = Editor()
  var feedbackRequests = Set<UUID>()
  func beginOperationFeedback() -> UUID { let id = UUID(); feedbackRequests.insert(id); return id }
  func endOperationFeedback(_ id: UUID) { feedbackRequests.remove(id) }
}
final class PlayerCore {
  @discardableResult func performSidebarChange<T>(_ action: () -> T) -> T { action() }
  static var playerCores: [PlayerCore] = []
  struct Preview { var originalTrack = VideoTrackProcessing(); var masterVF = "" }
  var scopedCropPreview: Preview?
  init() { Self.playerCores.append(self) }
  struct Info {
    var state = PlayerState.loaded
    var currentURL: URL? = URL(fileURLWithPath: "/fixture.mkv")
    var trackSelectionGeneration = 0
  }
  var info = Info()
  let mainWindow: LUTWindowFixture! = LUTWindowFixture()
  var mpv: LUTMPVFixture! = LUTMPVFixture()
  var scopedTrackSettings = TrackProcessingState()
  var videoGeometrySession: [URL: MediaVideoGeometryState] = [:]
  var defaultVideoGeometry: MediaVideoGeometryState?
  // PRODUCTION_SAVED_LUT
  var failNextFilter = false
  var failNextRefresh = false
  var failRemoval = false
  var onRefresh: (() -> Void)?
  private var observers: [Notification.Name: [(Notification) -> Void]] = [:]
  func postNotification(_ name: Notification.Name) {
    for callback in observers[name] ?? [] { callback(Notification(name: name, object: self)) }
  }
  func refreshTrackProcessing(_ type: MPVTrack.TrackType) -> Bool {
    if failNextRefresh { failNextRefresh = false; return false }
    let callback = onRefresh; onRefresh = nil; callback?()
    return true
  }
  func observe(_ name: Notification.Name, block: @escaping (Notification) -> Void) {
    observers[name, default: []].append(block)
  }
  func updateScopedVideo(_ group: TrackSettingsGroup, change: (inout VideoTrackProcessing) -> Void) -> Bool {
    let id = scopedTrackSettings.target(group)
    var value = scopedTrackSettings.video[id] ?? VideoTrackProcessing()
    change(&value)
    scopedTrackSettings.video[id] = value
    return true
  }
  func addVideoFilter(_ filter: MPVFilter) -> Bool {
    if failNextFilter { failNextFilter = false; mpv.filters = []; return false }
    mpv.filters.removeAll { $0.label == filter.label }
    mpv.filters.append(filter)
    return true
  }
  func removeVideoFilter(_ name: String) -> Bool {
    if failRemoval { return false }
    mpv.filters.removeAll { "@" + ($0.label ?? "") == name }
    return true
  }
}
enum MPVTrack { enum TrackType { case video } }
enum Utility {
  static var confirmation: NSApplication.ModalResponse = .alertSecondButtonReturn
  static func quickAskPanel(_ key: String, titleArgs: [CVarArg]?, sheetWindow: NSWindow?, callback: ((NSApplication.ModalResponse) -> Void)?) {
    precondition(key == "lut_remove" && titleArgs?.count == 1)
    callback?(confirmation)
  }
  static var appSupportDirUrl: URL = URL(fileURLWithPath: CommandLine.arguments[1])
  static var nextFile: URL?
  static var alerts: [String] = []
  static func showAlert(_ key: String, arguments: [CVarArg]? = nil, sheetWindow: NSWindow?) { alerts.append(key) }
  static func quickOpenPanel(title: String, chooseDir: Bool, sheetWindow: NSWindow?, allowedFileTypes: [String]?, callback: @escaping (URL) -> Void) {
    precondition(allowedFileTypes == ["cube"] && !chooseDir)
    if let nextFile { callback(nextFile) }
  }
}
extension Notification.Name { static let iinaVFChanged = Self("vf") }
