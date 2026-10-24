import Foundation
@propertyWrapper final class Locked<T> {
  var wrappedValue: T
  var projectedValue: Locked<T> { self }
  init(wrappedValue: T) { self.wrappedValue = wrappedValue }
  func withLock<R>(_ body: (inout T) -> R) -> R { body(&wrappedValue) }
}
enum SleepPreventer { static func updateSleepPrevention() {} }
final class NowPlayingInfoManager { static let shared = NowPlayingInfoManager(); func updateInfo() {} }
enum MPVOption {
  enum PlaybackControl { static let pause = "pause", speed = "speed" }
  enum TrackSelection { static let sid = "sid" }
  enum Subtitles { static let secondarySid = "secondary-sid", subDelay = "sub-delay", secondarySubDelay = "secondary-sub-delay" }
  enum Audio { static let audioDelay = "audio-delay", mute = "mute", volume = "volume" }
}
enum MPVProperty {
  static let eofReached = "eof-reached", chapterListCount = "chapter-list/count"
  static func chapterListNTitle(_ index: Int) -> String { "chapter/title" }
  static func chapterListNTime(_ index: Int) -> String { "chapter/time" }
}
enum Command { case stop, seek, subReload, subAdd }
enum Preference {
  enum SeekOption { case relative, exact, auto }
  enum Key { case useExactSeek, maxVolume, softVolume }
  static var writes = 0
  static func bool(for key: Key) -> Bool { false }
  static func integer(for key: Key) -> Int { 100 }
  static func set(_ value: Double, for key: Key) { writes += 1 }
}
enum AppData { static let mpvMinPlaybackSpeed = 0.01 }
extension Double { func clamped(to range: Range<Double>) -> Double { min(max(self, range.lowerBound), range.upperBound.nextDown) } }
extension Double { func clamped(to range: ClosedRange<Double>) -> Double { min(max(self, range.lowerBound), range.upperBound) } }
extension URL { var mpvStr: String { path } }
struct MPVTrack {
  enum TrackType { case audio, video, sub, secondSub }
  var id: Int
  var externalFilename: String?
}
struct MPVChapter {
  struct Time { var second: Double }
  let time: Time
  init(title: String?, startTime: Double, index: Int) { time = Time(second: startTime) }
}
enum OSDMessage { case volume(Double) }
enum Level { case verbose, error }
extension Notification.Name {
  static let iinaPlayerStopped = Self("test-stopped"), iinaSIDChanged = Self("test-sid"), iinaChapterListChanged = Self("test-chapters")
}
enum Utility { static func showAlert(_ key: String) {} }
final class AppDelegate {
  static let shared = AppDelegate()
  final class OpenURLWindow {
    let window: FakeWindow? = FakeWindow()
    func failedToLoadURL() {}
  }
  let openURLWindow = OpenURLWindow()
}
final class FakeMPV {
  var calls: [String] = []
  var recordedSeekTimeListener: ((Double) -> Void)?
  var needRecordSeekTime = false
  func getFlag(_ name: String) -> Bool { calls.append("read:" + name); return false }
  func getInt(_ name: String) -> Int { calls.append("read:" + name); return 0 }
  func getString(_ name: String) -> String? { calls.append("read:" + name); return nil }
  func getDouble(_ name: String) -> Double { calls.append("read:" + name); return 0 }
  func setInt(_ name: String, _ value: Int) { calls.append("write:" + name) }
  func setDouble(_ name: String, _ value: Double, level: Level = .verbose) { calls.append("write:" + name) }
  func setFlag(_ name: String, _ value: Bool, level: Level = .verbose) { calls.append("write:" + name) }
  func command(_ command: Command, args: [String] = [], checkError: Bool = true, level: Level = .verbose, returnValueCallback: ((Int32) -> Void)? = nil) {
    calls.append("command:\(command)")
    returnValueCallback?(0)
  }
  func mpvQuit() { calls.append("quit") }
}
final class FakeVideo {
  var activations = 0
  func displayActive() { activations += 1 }
  func stopDisplayLink() {}
}
final class FakeWindow {
  enum PIP { case inPIP, notInPIP }
  final class Bubble { var playing = false }
  let videoView = FakeVideo(), pip = Bubble()
  var isVisible = false
  func close() {}
  var pipStatus = PIP.notInPIP
}
final class Info {
  unowned let player: PlayerCore
  init(_ player: PlayerCore) { self.player = player }
  @Locked var matchedSubs: [String] = []
  @Locked var subTracks: [MPVTrack] = []
  var chapters: [MPVChapter] = []
  var volume = 50.0
  struct Duration { var second: Double }
  var videoDuration: Duration? = Duration(second: 20)
  var currentURL: URL?
  var isNetworkResource = false
  // PRODUCTION_STATE

}
final class PlayerCore: NSObject {
  static weak var lastActive: PlayerCore?
  lazy var info = Info(self)
  let mpv = FakeMPV(), mainWindow = FakeWindow()
  // PRODUCTION_SHUTDOWN_FLAGS
  var receivedEndFileWhileLoading = false
  var pendingUrl: URL?
  var pendingAutoLoad = false
  var openedURLs: [URL] = []
  var stoppedNotifications = 0
  var onStopped: (() -> Void)?
  var screenshotCancellations = 0
  var backgroundStopRequests = 0
  var pausedCropRefresh: Int?
  var backgroundTaskInUse = false
  var triedUsingExactSeekForCurrentFile = false, useExactSeekForCurrentFile = false
  var seekRequests = 0, trackRequests = 0
  var uiTimeSyncs = 0, osds = 0
  override init() { super.init(); Self.lastActive = self }
  func log(_ message: String, level: Level = .verbose) {}
  func cancelVideoGeometryOSDRefresh() {}
  func cancelScreenshotRequests() { screenshotCancellations += 1 }
  func savePlayerState() {}
  func savePlaybackPosition() {}
  func stopBackgroundTask() { backgroundStopRequests += 1 }
  func refreshSyncUITimer() {}
  func userInitiatedSeek() { seekRequests += 1 }
  func setAudioTracks(_ ids: Set<Int>) { trackRequests += 1 }
  func setVideoTracks(_ ids: Set<Int>) { trackRequests += 1 }
  func getSelectedTracks() {}
  func syncUITime() { uiTimeSyncs += 1 }
  func sendOSD(_ message: OSDMessage) { osds += 1 }
  var currentController: FakeWindow { mainWindow }
  var currentWindow: FakeWindow? { mainWindow }
  func open(_ url: URL, shouldAutoLoad: Bool) { openedURLs.append(url); info.state = .loading }
  func postNotification(_ name: Notification.Name) {
    if name == .iinaPlayerStopped { stoppedNotifications += 1; onStopped?() }
  }
  // PRODUCTION_METHODS
}
