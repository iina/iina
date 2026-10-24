import Cocoa

// Engine/window boundaries only: AppRestartSession and AppRestart compile unchanged.
// Native windows stay hidden; no media, plugins, app activation, or user preferences.
final class TestWindow: NSWindow {
  var testVisible = true
  var testMinimized = false
  override var isVisible: Bool { testVisible }
  override var isMiniaturized: Bool { testMinimized }
  override func miniaturize(_ sender: Any?) { testMinimized = true }
  init() {
    super.init(contentRect: NSRect(x: 100, y: 100, width: 640, height: 360),
               styleMask: .borderless, backing: .buffered, defer: false)
    isReleasedWhenClosed = false
  }
}
final class SettingsWindow: NSWindow {
  static let `default` = SettingsWindow()
  var frontCount = 0
  var saveCount = 0
  init() {
    super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    isReleasedWhenClosed = false
  }
  override func makeKeyAndOrderFront(_ sender: Any?) { frontCount += 1 }
  func saveNavigationLocation() { saveCount += 1 }
}
enum MPVOption {
  enum PlaybackControl { static let pause = "pause"; static let speed = "speed" }
  enum Audio { static let volume = "volume"; static let mute = "mute" }
  enum Window { static let fullscreen = "fullscreen" }
  enum TrackSelection { static let aid = "aid", vid = "vid", sid = "sid" }
  enum Subtitles { static let secondarySid = "secondary-sid" }
}
enum MPVProperty {
  static let timePos = "time-pos"
  static let seekable = "seekable"
  static let seeking = "seeking"
  static let vf = "vf", af = "af"
}
struct MPVCommand: Equatable {
  let rawValue: String
  init(_ rawValue: String) { self.rawValue = rawValue }
  static let playlistClear = MPVCommand("playlist-clear"), seek = MPVCommand("seek")
}
extension Notification.Name {
  static let iinaPlayerStopped = Notification.Name("test.player-stopped")
  static let iinaPlayerShutdown = Notification.Name("test.player-shutdown")
  static let iinaPlaylistChanged = Notification.Name("test.playlist-changed")
  static let iinaTracklistChanged = Notification.Name("test.track-list")
  static let iinaAIDChanged = Notification.Name("test.audio")
  static let iinaVIDChanged = Notification.Name("test.video")
  static let iinaSIDChanged = Notification.Name("test.subtitles")
}
final class MPVTrack {
  enum TrackType: String { case audio, video, sub, secondSub }
  var id: Int
  let type: TrackType
  var srcId: Int?
  var externalFilename: String?
  var isExternal = false
  init(_ id: Int, _ type: TrackType, sourceID: Int? = nil, file: String? = nil) {
    self.id = id; self.type = type; srcId = sourceID
    externalFilename = file; isExternal = file != nil
  }
}
enum TestPlayerState {
  case loading, loaded, playing, paused, stopping, idle, shuttingDown, shutDown
  var loaded: Bool { self == .loaded || self == .playing || self == .paused }
  var active: Bool { self == .loading || self == .loaded || self == .playing || self == .paused }
}
struct TestTime { var second: Double }
struct TestPlaylistItem {
  var filename: String
  var isCurrent: Bool
  var isPlaying: Bool { isCurrent }
}
final class TestInfo {
  var state = TestPlayerState.idle
  var trackSelectionGeneration = 0
  var volume = 50.0
  var isMuted = false
  var playSpeed = 1.0
  var currentURL: URL?
  var playlist: [TestPlaylistItem] = []
  var videoDuration: TestTime? = TestTime(second: 300)
  var audioTracks: [MPVTrack] = []
  var videoTracks: [MPVTrack] = []
  var subTracks: [MPVTrack] = []
  var audioTrackOrder: [Int] = []
  var videoTrackOrder: [Int] = []
  var mixedAudioTrackIDs: Set<Int> = []
  var layeredVideoTrackIDs: [Int] = []
  var aid: Int?, vid: Int?, sid: Int?, secondSid: Int?
  func trackList(_ type: MPVTrack.TrackType) -> [MPVTrack] {
    switch type { case .audio: return audioTracks; case .video: return videoTracks; default: return subTracks }
  }
  func activeTrackIDs(_ type: MPVTrack.TrackType) -> Set<Int> {
    if type == .audio, !mixedAudioTrackIDs.isEmpty { return mixedAudioTrackIDs }
    if type == .video, !layeredVideoTrackIDs.isEmpty { return Set(layeredVideoTrackIDs) }
    let id = type == .audio ? aid : vid
    return id.map { $0 > 0 ? [$0] : [] } ?? []
  }
}
final class TestVideoView {
  var activeCount = 0
  func displayActive() { activeCount += 1 }
}
final class TestMainWindow {
  enum PIPStatus { case notInPIP, inPIP }
  struct FSState {
    var isFullscreen = false
    var priorWindowedFrame: NSRect?
  }
  var isWindowLoaded = true
  let window: TestWindow? = TestWindow()
  var fsState = FSState()
  var pipStatus = PIPStatus.notInPIP
  let videoView = TestVideoView()
  var appliedFrames: [NSRect] = []
  final class InteractiveMode {
    var onExit: ((Bool) -> Void)?
    func exit(discardingCrop: Bool = false) { onExit?(discardingCrop) }
  }
  let interactiveMode = InteractiveMode()
  var videoAspectTransitionOriginalPanscan: Double?
  func finishVideoAspectTransition() {}
  var isCropTransitionInProgress = false
  var transitionEvents: [String] = []
  func interruptPlayerCropTransition() { transitionEvents.append("interrupt") }
  func cancelCropExitTransition() { transitionEvents.append("cancel"); isCropTransitionInProgress = false }
  func applyRestartWindowFrame(_ frame: NSRect) {
    appliedFrames.append(frame)
    window?.setFrame(frame, display: false)
  }
  func toggleWindowFullScreen() { fsState.isFullscreen.toggle() }
  func enterPIP() { pipStatus = .inPIP }
}
final class TestMiniPlayer { let window: TestWindow? = TestWindow() }
final class TestMPV {
  var time = 0.0
  var paused = true
  var volume = 50.0
  var muted = false
  var speed = 1.0
  var writes: [String] = []
  var reads = 0
  var seekable = true
  var seeking = false
  var fullscreen = false
  var seekError: Int32 = 0
  var playlist: [String] = []
  var currentIndex = 0
  var seekRequests: [(Double, String)] = []
  var strings: [String: String] = [:]
  var integers: [String: Int] = [:]
  var onTrackAdd: ((String, String) -> Void)?
  var trackAdds: [(String, String)] = []
  var savePositionOnQuit = false
  func getString(_ name: String) -> String? { strings[name] }
  @discardableResult func setString(_ name: String, _ value: String) -> Int32 {
    strings[name] = value; writes.append("\(name)=\(value)"); return 0
  }
  func setInt(_ name: String, _ value: Int) { integers[name] = value; writes.append("\(name)=\(value)") }
  func getInt(_ name: String) -> Int { integers[name] ?? 0 }
  func getDouble(_ name: String) -> Double {
    reads += 1
    switch name { case MPVOption.Audio.volume: return volume; case MPVOption.PlaybackControl.speed: return speed; default: return time }
  }
  func getFlag(_ name: String) -> Bool {
    reads += 1
    switch name {
    case MPVProperty.seekable: return seekable
    case MPVProperty.seeking: return seeking
    case MPVOption.Window.fullscreen: return fullscreen
    case MPVOption.Audio.mute: return muted
    case "save-position-on-quit": return savePositionOnQuit
    default: return paused
    }
  }
  func setFlag(_ name: String, _ value: Bool) {
    writes.append("\(name)=\(value)")
    if name == MPVOption.Window.fullscreen { fullscreen = value }
    else if name == MPVOption.Audio.mute { muted = value }
    else { paused = value }
  }
  func setDouble(_ name: String, _ value: Double) {
    writes.append("\(name)=\(value)")
    if name == MPVOption.Audio.volume { volume = value } else { speed = value }
  }
  func command(_ command: MPVCommand, args: [String?] = [], checkError: Bool = true,
               returnValueCallback: ((Int32) -> Void)? = nil) {
    if command == .playlistClear {
      playlist = playlist.indices.contains(currentIndex) ? [playlist[currentIndex]] : []
      currentIndex = 0
    } else if command == .seek {
      seekRequests.append((Double(args[0]!)!, args[1]!))
    } else if command.rawValue.hasSuffix("-add"), let filename = args.first ?? nil {
      trackAdds.append((command.rawValue, filename))
      onTrackAdd?(command.rawValue, filename)
    }
    returnValueCallback?(command == .seek ? seekError : 0)
  }
  func playlistInsert(_ path: String, index: Int) {
    playlist.insert(path, at: index)
    if index <= currentIndex { currentIndex += 1 }
  }
  func playlistAppend(_ path: String) { playlist.append(path) }
}
final class PlayerCore: NSObject {
  static var playerCores: [PlayerCore] = []
  static var onOpen: ((PlayerCore) -> Void)?
  static var playerCoreForRestart: PlayerCore {
    let player = PlayerCore()
    playerCores.append(player)
    return player
  }
  var isManagedByPlugin = false
  let info = TestInfo()
  var mainWindow: TestMainWindow! = TestMainWindow()
  let miniPlayer = TestMiniPlayer()
  let mpv = TestMPV()
  var isInMiniPlayer = false
  var disableWindowAnimation = false
  var autoLoadArgument: Bool?
  var openedURL: URL?
  var openResult: Int? = 1
  var logs: [String] = []
  var scopedTrackSettings = TrackProcessingState()
  var restartOptionDefaults: [String: String]?
  var restartSelectionDefaults: [String: String] = [:]
  var restartVideoFilterDefault: String?
  var restartAudioFilterDefault: String?
  var restoredProcessing: [TrackProcessingState] = []
  var restoredMembership: [(Set<Int>, [Int])] = []
  var aspectDescription = "Default", cropDescription = "None"
  func getTrackInfo() {}
  func getSelectedTracks() {
    info.aid = mpv.getInt("aid"); info.vid = mpv.getInt("vid")
    info.sid = mpv.getInt("sid"); info.secondSid = mpv.getInt("secondary-sid")
  }
  private func reconcileTrackGraph() {}
  private func readVideoGeometry() -> MediaVideoGeometryState {
    var result = MediaVideoGeometryState()
    result.aspectDescription = aspectDescription; result.cropDescription = cropDescription
    let active = info.activeTrackIDs(.video)
    result.activeVideo = info.videoTrackOrder.filter { active.contains($0) }
    result.activeVideo.append(contentsOf: active.sorted().filter { !result.activeVideo.contains($0) })
    return result
  }
  private func syncVideoGeometryInfo(aspect: String, crop: String) {
    aspectDescription = aspect; cropDescription = crop
  }
  private func applyTrackSelection(audio: Set<Int>, video: [Int], changedType: MPVTrack.TrackType,
                                   soloID: Int, forceRebuild: Bool) -> Bool {
    restoredProcessing.append(scopedTrackSettings)
    restoredMembership.append((audio, video))
    info.mixedAudioTrackIDs = audio; info.layeredVideoTrackIDs = video
    return true
  }
  // PRODUCTION_RESTART_BRIDGES
  var currentWindow: NSWindow? { isInMiniPlayer ? miniPlayer.window : mainWindow.window }
  func openURLs(_ urls: [URL], shouldAutoLoad: Bool) -> Int? {
    autoLoadArgument = shouldAutoLoad
    openedURL = urls.first
    info.currentURL = urls.first
    info.state = .loading
    mpv.playlist = [urls[0].isFileURL ? urls[0].path : urls[0].absoluteString]
    PlayerCore.onOpen?(self)
    return openResult
  }
  func getPlaylist() {
    info.playlist = mpv.playlist.enumerated().map {
      TestPlaylistItem(filename: $0.element, isCurrent: $0.offset == mpv.currentIndex)
    }
  }
  func postNotification(_ name: Notification.Name) {
    NotificationCenter.default.post(name: name, object: self)
  }
  func switchToMiniPlayer(showMiniPlayer: Bool) { isInMiniPlayer = true }
  func switchBackFromMiniPlayer(showMainWindow: Bool) { isInMiniPlayer = false }
  func log(_ message: String) { logs.append(message) }
  func refreshSyncUITimer() {}
  enum SyncUIOption { case time, playButton }
  func syncUI(_ options: [SyncUIOption]) {}
}

// The coordinator suite does not present Settings alerts; native presenter
// behavior is covered independently by settings-restart-presenter/run.py.
enum AccentControls {
  static func styleDefaultButton(in alert: NSAlert) {}
}
