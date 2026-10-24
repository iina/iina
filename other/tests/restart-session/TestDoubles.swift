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
}
enum MPVProperty {
  static let timePos = "time-pos"
  static let seekable = "seekable"
  static let seeking = "seeking"
}
enum MPVCommand { case playlistClear, seek }
extension Notification.Name {
  static let iinaPlayerStopped = Notification.Name("test.player-stopped")
  static let iinaPlayerShutdown = Notification.Name("test.player-shutdown")
  static let iinaPlaylistChanged = Notification.Name("test.playlist-changed")
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
  let mainWindow = TestMainWindow()
  let miniPlayer = TestMiniPlayer()
  let mpv = TestMPV()
  var isInMiniPlayer = false
  var disableWindowAnimation = false
  var autoLoadArgument: Bool?
  var openedURL: URL?
  var openResult: Int? = 1
  var logs: [String] = []
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
