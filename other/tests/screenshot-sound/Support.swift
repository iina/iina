import Cocoa
import AudioToolbox

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
// Only playback is intercepted: the production helper creates a real system sound
// object and uses the native UI-sound policy. Tests do not make audible sounds.
func AudioServicesPlaySystemSoundWithCompletion(_ id: SystemSoundID, _ completion: (() -> Void)?) {
  playedSounds.append(id)
  completion?()
}

enum MPVOption { enum Screenshot { static let screenshotDir = "screenshot-directory" } }
class EngineFixture {
  var folder: String? = "/fixture"
  func getString(_ key: String) -> String? { folder }
}
enum Utility {
  static var latestURL: URL?
  static func getLatestScreenshot(from path: String) -> URL? { latestURL }
}
class TestPasteboard {
  static let shared = TestPasteboard()
  var writeSucceeds = true
  var writes = 0
  func clearContents() {}
  func writeObjects(_ images: [NSImage]) -> Bool { writes += 1; return writeSucceeds }
}
class PreviewFixture {
  let view = NSView()
  func setImage(_ image: NSImage, size: NSSize, fileURL: URL?) {}
}
extension NSSize {
  func shrink(toSize: NSSize) -> NSSize { self }
}
enum OSDMessage { case screenshot }
enum LogLevel { case verbose }
final class CallbackFixture {
  let mpv = EngineFixture()
  var osdCount = 0
  func log(_ message: String, level: LogLevel) {}
  func createImage(_ url: URL) -> NSImage? { NSImage(contentsOf: url) }
  func sendOSD(_ message: OSDMessage, forcedTimeout: Int = 0, accessoryView: NSView? = nil, context: Any? = nil) {
    osdCount += 1
  }
  // PRODUCTION_CALLBACK
}
