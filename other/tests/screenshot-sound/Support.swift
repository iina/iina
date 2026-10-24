import Cocoa
import AudioToolbox
import ImageIO

struct Preference {
  struct Key {
    let rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }
    // PRODUCTION_KEYS
  }
  static let domain = "org.lyzmin41.screenshot-sound-test.\(ProcessInfo.processInfo.processIdentifier)"
  static let defaults = UserDefaults(suiteName: domain)!
  static func register() {
    defaults.register(defaults: [
      // PRODUCTION_DEFAULTS
    ])
  }
  static func bool(for key: Key) -> Bool { defaults.bool(forKey: key.rawValue) }
  static func set(_ value: Bool, for key: Key) { defaults.set(value, forKey: key.rawValue) }
}

var playedSounds: [SystemSoundID] = []
func AudioServicesPlaySystemSoundWithCompletion(_ id: SystemSoundID, _ completion: (() -> Void)?) {
  precondition(Thread.isMainThread, "screenshot sound must publish on main")
  playedSounds.append(id)
  completion?()
}
enum Logger {
  enum Level { case debug, verbose, warning, error }
  static func log(_ message: String) {}
  static func fatal(_ message: String) -> Never { fatalError(message) }
}
// PRODUCTION_OSD_ROUTING
enum IINAError: Error { case unsupportedMPVNodeFormat(UInt32) }
class MPVNode { // PRODUCTION_PARSE
}
struct MPVCommand {
  let rawValue: String
  static let screenshot = MPVCommand(rawValue: "screenshot")
}
struct KeyMapping { let action: [String]; let rawAction: String }
enum TrackType { case video }
final class InfoFixture {
  var state = PlayerState.loaded
  var hasVideo = true
  var currentURL: URL? = URL(fileURLWithPath: "/fixture/video.mkv")
  var trackSelectionGeneration = 1
  func activeTrackIDs(_ type: TrackType) -> [Int] { hasVideo ? [1] : [] }
}
final class WindowFixture {
  var active: Set<UUID> = []
  var begun: [UUID] = []
  var ended: [UUID] = []
  func beginOperationFeedback() -> UUID {
    precondition(Thread.isMainThread)
    let id = UUID(); active.insert(id); begun.append(id); return id
  }
  func endOperationFeedback(_ id: UUID) {
    precondition(Thread.isMainThread)
    active.remove(id); ended.append(id)
  }
}
final class MPVController {
  // PRODUCTION_USERDATA
  var mpv: OpaquePointer! = screenshotTestCreateHandle()
  weak var player: CallbackFixture!
  var observeProperties: [String: mpv_format] = [:]
  var rawCommands: [String] = []
  func command(rawString: String) -> Int32 { rawCommands.append(rawString); return 0 }
  func log(_ message: String, level: Logger.Level) {}
  func chkErr(_ value: Int32) {}
  // PRODUCTION_ASYNC
  func handleScreenshotReply(_ event: UnsafePointer<mpv_event>) {
    // PRODUCTION_REPLY
  }
}
enum Utility {
  static var screenshotCacheURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  static var alerts: [String] = []
  static func showAlert(_ message: String) { precondition(Thread.isMainThread); alerts.append(message) }
}
final class TestPasteboard {
  static let shared = TestPasteboard()
  var writeSucceeds = true
  var writes: [NSImage] = []
  func clearContents() { precondition(Thread.isMainThread) }
  func writeObjects(_ images: [NSImage]) -> Bool {
    precondition(Thread.isMainThread)
    writes += images; return writeSucceeds
  }
}
final class PreviewFixture {
  static var urls: [URL?] = []
  let view = NSView()
  func setImage(_ image: NSImage, size: NSSize, fileURL: URL?) {
    precondition(Thread.isMainThread); Self.urls.append(fileURL)
  }
}
extension NSSize { func shrink(toSize: NSSize) -> NSSize { self } }
enum OSDMessage { case screenshot }
final class DecodeObserver {
  static let shared = DecodeObserver()
  private let lock = NSLock()
  private var count = 0
  private var main = false
  var blockNext: DispatchSemaphore?
  let started = DispatchSemaphore(value: 0)
  func begin() {
    lock.lock()
    count += 1; main = main || Thread.isMainThread
    let block = blockNext; blockNext = nil
    lock.unlock()
    if let block { started.signal(); precondition(block.wait(timeout: .now() + 3) == .success) }
  }
  var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
  var usedMain: Bool { lock.lock(); defer { lock.unlock() }; return main }
}
enum FFmpegController {
  static var fallbackCalls = 0
  static func createNSImage(withContentsOf url: URL) -> NSImage? { fallbackCalls += 1; return nil }
}
// PRODUCTION_DECODER
final class CallbackFixture {
  let info = InfoFixture()
  let mpv = MPVController()
  var mainWindow: WindowFixture! = WindowFixture()
  var osdCount = 0
  let osdFeedbackOrigins = OSDFeedbackOrigins()
  var currentOSDFeedbackOrigin = OSDFeedbackOrigin.command
  init() { mpv.player = self }
  func log(_ message: String, level: Logger.Level = .debug) {}
  func sendOSD(_ message: OSDMessage, forcedTimeout: Int = 0, accessoryView: NSView? = nil, context: Any? = nil) {
    precondition(Thread.isMainThread); osdCount += 1
  }
  // PRODUCTION_SCREENSHOT
}
