import Cocoa
import Darwin
setbuf(stdout, nil)
typealias AccentSegmentedControl = NSSegmentedControl
enum AppAccentColor { static let color = NSColor.controlAccentColor }
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message); checks += 1; print("PASS: \(message)")
}
extension Array { subscript(at index: Int) -> Element? { indices.contains(index) ? self[index] : nil } }
struct LayoutValue {
 let value: CGFloat
 init(_ value: CGFloat) { self.value = value }
 func get() -> CGFloat { value }
 func use(_ block: @escaping (CGFloat) -> Void, applyNow: Bool = true) { if applyNow { block(value) } }
}
struct AccessibilityPreferences {
  static var motionReductionEnabled = false
  static var animationsDisabled = true
  static func adjustedDuration(_ duration:TimeInterval) -> TimeInterval { animationsDisabled ? 0 : duration }
}
// PRODUCTION_SIDEBAR_SCROLL
extension NSColor {
  static var sidebarContainerBorder: NSColor {
    NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08)
        : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.15)
    }
  }
}
struct Constants { struct String { static let trackNone = "<None>" } }
extension NSUserInterfaceItemIdentifier { static let trackName = NSUserInterfaceItemIdentifier("trackName") }
extension Notification.Name {
  static let iinaTracklistChanged = Self("tracks")
  static let iinaAIDChanged = Self("aid")
  static let iinaVIDChanged = Self("vid")
  static let iinaSIDChanged = Self("sid")
}
class MPVTrack: NSObject {
  enum TrackType: String { case video, audio, sub, secondSub }
  let id: Int
  let type: TrackType
  var isExternal = false
  var demuxW: Int? = 320, demuxH: Int? = 180
  var demuxSamplerate: Int? = 48000
  var demuxPixelAspect: Double? = 1
  var title: String?
  var idString: String { "#\(id)" }
  var demuxChannelCount: Int? = 2
  var demuxChannels: String? = "stereo"
  init(_ id: Int, _ type: TrackType = .audio) { self.id = id; self.type = type }
  func readableString(includingLanguage: Bool = true) -> String { "Track \(id)" }
  var readableLanguage: String?
  static let noneAudioTrack = MPVTrack(0)
  static let noneVideoTrack = MPVTrack(0, .video)
}
enum MPVOption {
  enum Video { static let videoAspectOverride = "video-aspect-override", videoRotate = "video-rotate" }
  enum PlaybackControl { static let pause = "pause" }
  enum Miscellaneous { static let lavfiComplex = "lavfi-complex" }
  enum TrackSelection { static let aid = "aid", vid = "vid", sid = "sid" }
  enum Subtitles { static let secondarySid = "secondary-sid" }
}
struct MPVCommand {
  static let audioAdd = MPVCommand("audio-add")
  static let audioRemove = MPVCommand("audio-remove"), videoRemove = MPVCommand("video-remove")
  let rawValue: String; init(_ value: String) { rawValue = value } }
enum MPVProperty { static let vf = "vf" }
struct MPVFilter { let label: String? }
enum OSD { case custom(String), track(MPVTrack, position: Int? = nil) }
extension URL { var mpvStr: String { isFileURL ? path : absoluteString } }
struct Utility {
  static var alerts = 0
  static func showAlert(_ key: String, sheetWindow: NSWindow? = nil) { alerts += 1 }
}
class Info {
  struct State { var active = true }
  var state = State()
  var currentURL: URL? = URL(fileURLWithPath: "/fixture.mkv")
  var mixedAudioTrackIDs: Set<Int> = []
  var layeredVideoTrackIDs: [Int] = []
  var videoTrackOrder: [Int] = []
  var audioTrackOrder: [Int] = []
  var trackSelectionGeneration = 0
  var cropFilter: MPVFilter?
  var unsureCrop = "None"
  var audioTracks = [MPVTrack(1), MPVTrack(2), MPVTrack(3), MPVTrack(4)]
  var videoTracks = [MPVTrack(1, .video), MPVTrack(2, .video), MPVTrack(3, .video)]
  var subTracks = [MPVTrack(1, .sub), MPVTrack(2, .sub)]
  var aid: Int? = 1, vid: Int? = 1, sid: Int? = 1, secondSid: Int? = 2
  func trackList(_ type: MPVTrack.TrackType) -> [MPVTrack] {
    switch type { case .audio: return audioTracks; case .video: return videoTracks; case .sub, .secondSub: return subTracks }
  }
  func trackId(_ type: MPVTrack.TrackType) -> Int? {
    switch type { case .audio: return aid; case .video: return vid; case .sub: return sid; case .secondSub: return secondSid }
  }
  func currentTrack(_ type: MPVTrack.TrackType) -> MPVTrack? { trackList(type).first { $0.id == trackId(type) } }
// PRODUCTION_ACTIVE_IDS
// PRODUCTION_ORDERED_TRACKS
}
class VideoFixture { var active = 0, idle = 0; func displayActive() { active += 1 }; func displayIdle() { idle += 1 } }
class EditorFixture { var discards = 0; var isActive = false; func exit(discardingCrop: Bool) { if discardingCrop { discards += 1 }; isActive = false } }
class MainFixture {
  let interactiveMode = EditorFixture()
  let videoView = VideoFixture()
  var loaded = true
  var aspectTransitions = 0, finishedTransitions = 0
  func prepareVideoTransformWindowReference() {}
  func beginVideoAspectTransition() -> Bool { aspectTransitions += 1; return true }
  func finishVideoAspectTransition(restore: Bool = true) { finishedTransitions += 1 }
  var window: NSWindow?
  let muteButton = NSButton(), volumeSlider = NSSlider()
}
class MPVFixture {
  var addition: (() -> Void)?
  var additionFails = false
  var removal: ((String, Int) -> Void)?
  var removalFails = false
  var removalNoOp = false
  var filters: [MPVFilter] = []
  func getFilters(_ property: String) -> [MPVFilter] { filters }
  var strings: [String: String] = [:]
  var integers = ["aid": 1, "vid": 1, "sid": 1, "secondary-sid": 2]
  var writes = 0
  var graphWrites = 0
  var supportsPersistentMixer = false
  var supportsAudioRefresh = true
  var commandFailures = 0
  var weights: [String] = []
  var equalizerGains: [String: String] = [:]
  var graphFailures = 0
  var failures = 0
  var nativeAudioChoice = 1
  var audioMixWasReconfigured = false
  func getString(_ key: String) -> String? { strings[key] }
  func getNode(_ key: String) -> Any? {
    key == "command-list" ? (supportsPersistentMixer ? [["name": "lavfi-complex-command",
      "args": supportsAudioRefresh ? [["name": "refresh-audio"]] : []]] : []) : nil
  }
  func command(_ command: MPVCommand, args: [String?], checkError: Bool,
               returnValueCallback: ((Int32) -> Void)? = nil) {
    if command.rawValue == "audio-add" {
      precondition(args.count == 2 && args[1] == "auto")
      if additionFails { returnValueCallback?(-12); return }
      addition?(); returnValueCallback?(0); return
    }
    if command.rawValue == "audio-remove" || command.rawValue == "video-remove" {
      if removalFails { returnValueCallback?(-12); return }
      if !removalNoOp { removal?(command.rawValue, Int(args[0]!)!) }
      returnValueCallback?(0)
      return
    }
    precondition(command.rawValue == "lavfi-complex-command" && args.count == 4)
    writes += 1
    guard supportsPersistentMixer && supportsAudioRefresh else { returnValueCallback?(-12); return }
    if commandFailures > 0 { commandFailures -= 1; returnValueCallback?(-12); return }
    if args[1] == "gain" { equalizerGains[args[0]!] = args[2]! }
    else { precondition(args[0] == AudioTrackMixGraph.target && args[1] == "weights"); weights.append(args[2]!) }
    returnValueCallback?(0)
  }
  func getFlag(_ key: String) -> Bool { key == "pause" }
  func getInt(_ key: String) -> Int { integers[key] ?? 0 }
  @discardableResult func setString(_ key: String, _ value: String) -> Int32 {
    writes += 1
    if key == "lavfi-complex" { graphWrites += 1 }
    if key == "lavfi-complex", graphFailures > 0 { graphFailures -= 1; strings[key] = ""; return -4 }
    if failures > 0 { failures -= 1; strings[key] = ""; return -4 }
    if key == "lavfi-complex", !(strings[key] ?? "").isEmpty, !value.isEmpty,
       strings[key] != value { audioMixWasReconfigured = true }
    strings[key] = value
    if value.contains("[ao]") { integers["aid"] = 0 }
    if value.contains("[vo]") { integers["vid"] = 0 }
    return 0
  }
  func setInt(_ key: String, _ value: Int) {
    writes += 1
    // Observed with bundled libmpv: after replacing a live complex graph,
    // reselecting the cached native aid can be ignored despite aid=no.
    if key == "aid" {
      if audioMixWasReconfigured && value == nativeAudioChoice { return }
      nativeAudioChoice = value
      audioMixWasReconfigured = false
    }
    if value > 0, (key == "sid" && integers["secondary-sid"] == value || key == "secondary-sid" && integers["sid"] == value) { return }
    integers[key] = value
  }
}
class PlayerCore {
  enum OSDFeedbackOrigin { case command, sidebar }
  var currentOSDFeedbackOrigin: OSDFeedbackOrigin { .command }
  @discardableResult func performSidebarChange<T>(_ action: () -> T) -> T { action() }
  let info = Info(), mpv = MPVFixture()
  init() {
    mpv.addition = { [weak self] in
      guard let self else { return }
      let track = MPVTrack((self.info.audioTracks.map(\.id).max() ?? 0) + 1)
      track.isExternal = true
      self.info.audioTracks.append(track)
    }
    mpv.removal = { [weak self] command, id in
      guard let self else { return }
      if command == "audio-remove" { self.info.audioTracks.removeAll { $0.id == id } }
      else { self.info.videoTracks.removeAll { $0.id == id } }
    }
  }
  func getTrackInfo() {}
  func trackListChanged() { getSelectedTracks(); postNotification(.iinaTracklistChanged) }
  var mainWindow: MainFixture! = MainFixture()
  var isInMiniPlayer = false
  let miniPlayer = MiniFixture()
  private var observers: [Notification.Name: [() -> Void]] = [:]
  func observe(_ name: Notification.Name, _ block: @escaping (Notification) -> Void) {
    observers[name, default: []].append { block(Notification(name: name)) }
  }
  func postNotification(_ name: Notification.Name) { observers[name, default: []].forEach { $0() } }
  func getSelectedTracks() {
    info.aid = info.mixedAudioTrackIDs.count == 1 ? info.mixedAudioTrackIDs.first : mpv.getInt("aid")
    info.vid = mpv.getInt("vid")
    info.sid = mpv.getInt("sid"); info.secondSid = mpv.getInt("secondary-sid")
  }
  var osdMessages: [OSD] = []
  func sendOSD(_ message: OSD) { osdMessages.append(message) }
  enum LogLevel { case error }
  func log(_ text: String, level: LogLevel) {}
  var scopedTrackSettings = TrackProcessingState()
  var videoGeometryMediaURL: URL?
  var videoGeometrySession: [URL: MediaVideoGeometryState] = [:]
  var defaultVideoGeometry: MediaVideoGeometryState?
  func restoreVideoSession() { restoreVideoTrackGeometryForCurrentMedia() }
  struct CropPreview {
    var id: Int
    var activeVideo: [Int] = [1]
    var order: [Int] = [1,2,3]
    var originalTrack = VideoTrackProcessing()
    var masterVF = ""
    var masterAspect = "-1"
    var masterRotation = "0"
    var masterCrop: MPVFilter?
    var masterCropDescription = "None"
    var masterColors: [(VideoEqualizerType, Int)] = []
  }
  var scopedCropPreview: CropPreview?
// PRODUCTION_SCOPE_CROP
  enum VideoEqualizerType { case brightness, contrast, saturation, gamma, hue }
  var masterDelay = 0.0
  var masterEQ = Array(repeating: 0.0, count: 10)
  func setAudioDelay(_ value: Double) { masterDelay = value }
  func setAudioEq(fromGains values: [Double]) { masterEQ = values }
  func setVideoAspect(_ value: String) {}
  func removeCropFilter() {}
  func setVideoRotate(_ value: Int) {}
  func setVideoEqualizer(forOption: VideoEqualizerType, value: Int) {}
  func removeVideoFilter(_ filter: String) -> Bool {
    mpv.filters.removeAll { "@" + ($0.label ?? "") == filter }
    return true
  }
// PRODUCTION_SCOPE_RESET
  private var ownedTrackGraph: String?
  private var persistentAudioInputs: Set<Int>?
// PRODUCTION_CORE
  func nextFile() {
    clearTrackGraphForNewFile(); info.trackSelectionGeneration += 1
    mpv.integers["aid"] = 1; mpv.nativeAudioChoice = 1
    mpv.audioMixWasReconfigured = false; mpv.integers["vid"] = 1; getSelectedTracks()
    postNotification(.iinaTracklistChanged)
  }
  func prepareMixer() { prepareAudioMixer() }
}

class MiniFixture { func refreshArtworkVisibility() {}
 func handleVideoSizeChange() {} }
