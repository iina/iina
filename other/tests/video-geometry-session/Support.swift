import Cocoa
import Darwin
struct FilterPresetInstance {
  struct Preset { let name: String }
  let preset: Preset
  let params: [String: NSNumber]
}
extension String { var mpvFixedLengthQuoted: String { "%\(utf8.count)%\(self)" } }
extension Array { subscript(at index: Int) -> Element? { indices.contains(index) ? self[index] : nil } }
enum MPVTrack { enum TrackType { case video, audio, sub, secondSub } }
enum Logger { enum Level { case warning }; static func log(_ value: String, level: Level) {} }
enum Constants {
  enum FilterName {
    static let crop = "iina_crop", flip = "iina_flip", mirror = "iina_mirror"
    static let delogo = "iina_delogo", audioEq = "iina_aeq"
  }
}
enum MPVOption {
  enum Video { static let videoAspectOverride = "video-aspect-override", videoRotate = "video-rotate" }
  enum Window { static let windowScale = "window-scale" }
}
enum MPVProperty { static let vf = "vf", af = "af" }
enum AppData {
  static let cropsInPanel = ["None", "4:3", "16:9", "16:10", "21:9", "5:4"]
  static let aspects = ["4:3", "5:4", "16:9", "16:10", "1:1", "3:2", "2.21:1", "2.35:1", "2.39:1"]
}
class MPVFixture {
  var options = ["video-aspect-override":"-1", "video-rotate":"0", "panscan":"0", "video-zoom":"0"]
  var videoFilters: [MPVFilter] = []
  var failWrites = false
  var writes: [(String, String)] = []
  func getString(_ key: String) -> String? { options[key] }
  func getDouble(_ key: String) -> Double {
    let value = options[key] ?? "0"
    let parts = value.split(separator: ":").compactMap { Double($0) }
    return parts.count == 2 ? parts[0]/parts[1] : Double(value) ?? 0
  }
  func getInt(_ key: String) -> Int { Int(options[key] ?? "0") ?? 0 }
  func getFilters(_ key: String) -> [MPVFilter] { key == "vf" ? videoFilters : [] }
  @discardableResult func setString(_ key: String, _ value: String) -> Int32 {
    guard !failWrites else { return -1 }
    writes.append((key, value))
    let name = key.replacingOccurrences(of: "file-local-options/", with: "")
    if name == "vf" {
      videoFilters = value.split(separator: ",").map { MPVFilter(rawString: String($0))! }
    } else { options[name] = value }
    return 0
  }
}
class InfoFixture {
  struct State { var loaded = true; var active = true }
  var state = State()
  var currentURL: URL?
  var justStartedFile = false, justOpenedFile = false
  var unsureAspect = "Default", unsureCrop = "None"
  var rotation = 0, cachedWindowScale = 0.5
  var cropFilter: MPVFilter?, flipFilter: MPVFilter?, mirrorFilter: MPVFilter?, delogoFilter: MPVFilter?, audioEqFilter: MPVFilter?
  var videoTrackOrder: [Int] = []
  struct Track { var id: Int }
  var videoTracks = [Track(id: 1), Track(id: 2)]
  var activeVideo: Set<Int> = [1]
  func activeTrackIDs(_ type: MPVTrack.TrackType) -> Set<Int> { activeVideo }
}
class InteractiveFixture { var isActive = false; var onExit: (() -> Void)?; func exit() { onExit?(); onExit = nil } }
class WindowFixture {
  func prepareVideoTransformWindowReference() {}
  var loaded = true
  var isCropTransitionInProgress = false
  let interactiveMode = InteractiveFixture()
  var finishCount = 0
  var videoAspectTransitionOriginalPanscan: Double?
  var scales: [Double] = []
  func finishVideoAspectTransition() { finishCount += 1 }
  func setWindowScale(_ scale: Double) { scales.append(scale) }
}
class PlayerFixture {
  let info = InfoFixture(), mpv = MPVFixture()
  var mainWindow: WindowFixture! = WindowFixture()
  var scopedTrackSettings = TrackProcessingState()
  var defaultVideoGeometry: MediaVideoGeometryState?
  var videoGeometrySession: [URL: MediaVideoGeometryState] = [:]
  var videoGeometryMediaURL: URL?
  var videoGeometryIsLoaded = false
  enum Notification { case iinaTrackSettingsChanged }
  var refreshSucceeds = true
  var refreshes: [[Int]] = []
  var warnings = 0
  var settingsUpdates = 0
  var geometryReads = 0
  var geometry = CropVideoGeometry(sourceSize: NSSize(width: 1280, height: 720), displaySize: NSSize(width: 1280, height: 720), rotation: 0)
  func log(_ text: String, level: Logger.Level) { warnings += 1 }
  func postNotification(_ notification: Notification) { settingsUpdates += 1 }
  func refreshTrackProcessing(_ type: MPVTrack.TrackType, videoOverride: [Int]) -> Bool {
    refreshes.append(videoOverride); return refreshSucceeds
  }
  func interactiveVideoGeometry(uncropped: Bool) -> CropVideoGeometry { geometryReads += 1; return geometry }
  @discardableResult func setCrop(fromFilter filter: MPVFilter) -> Bool { info.cropFilter = filter; return true }
  func addVideoFilter(_ filter: MPVFilter) -> Bool { mpv.videoFilters.append(filter); return true }
  func removeVideoFilter(_ filter: MPVFilter) -> Bool {
    mpv.videoFilters.removeAll { $0.isEqual(filter) }; return true
  }
  func removeCropFilter() { info.cropFilter = nil; info.unsureCrop = "None" }
  private func applyCropChange(_ filter: MPVFilter?, description: String, outputSize: NSSize?) {
    if let filter { if setCrop(fromFilter: filter) { info.unsureCrop = description } }
    else { removeCropFilter() }
  }
  // PRODUCTION_METHODS
  func start(_ url: URL, loaded: Bool = true) {
    info.currentURL = url
    // Mirrors the production on-load graph cleanup and file-loaded boundary.
    scopedTrackSettings = TrackProcessingState()
    prepareVideoGeometryForNewFile()
    restoreVideoGeometryForCurrentMedia()
    restoreVideoTrackGeometryForCurrentMedia()
    videoGeometryIsLoaded = loaded
  }
  func save() { saveVideoGeometryForCurrentMedia() }
  func captureDefaults() { defaultVideoGeometry = readVideoGeometry() }
}
