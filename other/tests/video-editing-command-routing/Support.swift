import JavaScriptCore
import Darwin

struct MPVCommand {
  let rawValue: String
  init(_ value: String) { rawValue = value }
  static let abLoop = Self("ab-loop"), quit = Self("quit"), screenshot = Self("screenshot"), showProgress = Self("show-progress")
}
struct KeyMapping {
  let rawAction: String
  var isIINACommand = false
  var action: [String] { rawAction.components(separatedBy: .whitespaces).filter { !$0.isEmpty } }
}
extension MPVProperty { static let playlistPos = "playlist-pos", vf = "vf", af = "af" }

final class EngineBoundary {
  typealias Create = @convention(c) () -> OpaquePointer?
  typealias Initialize = @convention(c) (OpaquePointer?) -> Int32
  typealias Set = @convention(c) (OpaquePointer?, UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32
  typealias Command = @convention(c) (OpaquePointer?, UnsafePointer<CChar>) -> Int32
  typealias Get = @convention(c) (OpaquePointer?, UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
  typealias Free = @convention(c) (UnsafeMutableRawPointer?) -> Void
  typealias Destroy = @convention(c) (OpaquePointer?) -> Void
  var library: UnsafeMutableRawPointer?, core: OpaquePointer?
  var command: Command?, get: Get?, set: Set?, free: Free?, destroy: Destroy?
  var available = true
  var calls: [String] = [], commands: [String] = []
  var values: [String: String] = ["playlist-pos": "0", "volume": "42", "video-rotate": "0"]
  init() {
    guard CommandLine.arguments.count > 1, !CommandLine.arguments[1].isEmpty else { return }
    guard let library = dlopen(CommandLine.arguments[1], RTLD_NOW) else { fatalError(String(cString: dlerror())) }
    self.library = library
    let create = unsafeBitCast(dlsym(library, "mpv_create"), to: Create.self)
    let initialize = unsafeBitCast(dlsym(library, "mpv_initialize"), to: Initialize.self)
    set = unsafeBitCast(dlsym(library, "mpv_set_option_string"), to: Set.self)
    command = unsafeBitCast(dlsym(library, "mpv_command_string"), to: Command.self)
    get = unsafeBitCast(dlsym(library, "mpv_get_property_string"), to: Get.self)
    free = unsafeBitCast(dlsym(library, "mpv_free"), to: Free.self)
    destroy = unsafeBitCast(dlsym(library, "mpv_terminate_destroy"), to: Destroy.self)
    core = create()!
    for (name, value) in ["config": "no", "load-scripts": "no", "vo": "null", "ao": "null",
                          "pause": "yes", "idle": "yes", "keep-open": "yes", "terminal": "no"] {
      precondition(set!(core, name, value) >= 0)
    }
    precondition(initialize(core) >= 0)
    set = unsafeBitCast(dlsym(library, "mpv_set_property_string"), to: Set.self)
  }
  func run(_ text: String) -> Int32 {
    calls.append("command:" + text); commands.append(text)
    return command?(core, text) ?? 0
  }
  func property(_ name: String) -> String? {
    calls.append("get:" + name)
    guard let get else { return values[name] }
    guard let value = get(core, name) else { return nil }
    defer { free?(value) }
    return String(cString: value.assumingMemoryBound(to: CChar.self))
  }
  func write(_ name: String, _ value: String) {
    calls.append("set:" + name); values[name] = value
    _ = set?(core, name, value)
  }
  deinit { destroy?(core); if let library { dlclose(library) } }
}
let engine = EngineBoundary()
extension PlayerFixture.Engine {
  var mpv: OpaquePointer? { engine.available ? (engine.core ?? OpaquePointer(bitPattern: 1)) : nil }
  func command(rawString: String) -> Int32 { engine.run(rawString) }
  func command(_ name: MPVCommand, args: [String], checkError: Bool) { _ = engine.run(([name.rawValue] + args).joined(separator: " ")) }
  func getFlag(_ name: String) -> Bool { engine.property(name) == "yes" }
  func getDouble(_ name: String) -> Double { Double(engine.property(name) ?? "") ?? 0 }
  func getString(_ name: String) -> String? { engine.property(name) }
  func getNode(_ name: String) -> Any? { _ = engine.property(name); return ["probe": true] }
  func setDouble(_ name: String, _ value: Double) { engine.write(name, String(value)) }
  func setString(_ name: String, _ value: String) { engine.write(name, value) }
  func setFlag(_ name: String, _ value: Bool) { engine.write(name, value ? "yes" : "no") }
  func setNode(_ name: String, _ value: Any) { engine.write(name, "node") }
  func addHook(_ hook: MPVHook, priority: Int32, hook value: MPVHookValue) { engine.calls.append("hook") }
  func getFilters(_ name: String) -> [MPVFilter] { engine.calls.append("filters:" + name); return [] }
}
extension PlayerFixture {
  func screenshot(fromKeyBinding: KeyMapping) -> Bool { true }
  func removeVideoFilter(_ filter: MPVFilter, _ index: Int) -> Bool { removeVideoFilter(filter) }
  func addAudioFilter(_ filter: MPVFilter) -> Bool { engine.calls.append("audioFilter"); return true }
  func removeAudioFilter(_ filter: MPVFilter, _ index: Int) -> Bool { true }
}
class DispatchBase: NSObject {
  var player: PlayerFixture { fatalError() }
  func handleIINACommand(_ command: IINACommand) {}
  func handleInterfaceCommand(_ command: IINACommand, arguments: [String]) -> Bool { false }
  func abLoop() {}
  func log(_ text: String, level: Logger.Level) {}
  // PRODUCTION_DISPATCH
}
enum Permission { case accessFileSystem }
enum AppData {
  static let safeMPVOptions: Set<String> = []
  static let safeMPVCommands: Set<String> = []
}
struct MPVHook { init(_ name: String) {} }
struct MPVHookValue { init(withIdentifier: String, jsContext: JSContext, jsBlock: JSValue, owner: AnyObject) {} }
class JavascriptAPIMpv: NSObject {
  var player: PlayerFixture?
  let context = JSContext()!
  let identifier = "routing-test"
  var errors: [String] = []
  init(_ player: PlayerFixture?) { self.player = player }
  func permitted(to permission: Permission) -> Bool { true }
  func throwError(withMessage message: String) { errors.append(message) }
  // PRODUCTION_JS
}
final class AppDelegate {
  final class FilterWindow { var loaded = false; func reloadTable() {} }
  static let shared = AppDelegate()
  let vfWindow = FilterWindow()
}
final class MainMenuActionHandler: NSObject {
  let player: PlayerFixture
  init(_ player: PlayerFixture) { self.player = player }
  @objc func menuDeleteCurrentFile(_ sender: NSMenuItem) {}
  @objc func menuShowCurrentFileInFinder(_ sender: NSMenuItem) {}
  @objc func menuChangeCrop(_ sender: NSMenuItem) {}
  @objc func menuChangeAspect(_ sender: NSMenuItem) {}
  @objc func menuChangeRotation(_ sender: NSMenuItem) {}
  @objc func menuToggleFlip(_ sender: NSMenuItem) {}
  @objc func menuToggleMirror(_ sender: NSMenuItem) {}
  @objc func menuToggleVideoFilterString(_ sender: NSMenuItem) {}
  @objc func menuCycleTrack(_ sender: NSMenuItem) {}
  @objc func audioAction(_ sender: NSMenuItem) {}
  func toggleFilter(_ type: String) { menuToggleFilterString("crop=900:500:0:0", forType: type) }
  // PRODUCTION_MENU
}
