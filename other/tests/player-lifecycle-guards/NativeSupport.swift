import Foundation

enum Logger {
  enum Level { case debug, verbose, error }
  static func ensure(_ condition: Bool, _ message: String) { precondition(condition, message) }
}
enum IINAError: Error { case unsupportedMPVNodeFormat(UInt32) }
enum OSDFeedbackValue {
  case number(Double)
  case string(String)
  init(_ value: String) { self = .string(value) }
}
final class OSDFeedbackOrigins {
  var records = 0
  static func propertyKey(_ value: String) -> String { value }
  func record(_ key: String, value: OSDFeedbackValue?, origin: Int) -> UUID? { records += 1; return nil }
  func cancel(_ key: String, token: UUID?) {}
}
final class NativePlayer {
  var state = PlayerState.idle
  let osdFeedbackOrigins = OSDFeedbackOrigins()
  var currentOSDFeedbackOrigin = 0
}
enum MPVProperty { static let vf = "vf", af = "af" }
struct MPVFilter {
  let name: String
  let label: String?
  let params: [String: String]?
}
struct MPVHook { var rawValue: String }
struct MPVHookValue { var isJavascript = true, id = "test" }
@propertyWrapper final class NativeLocked<T> {
  var wrappedValue: T
  var projectedValue: NativeLocked<T> { self }
  init(wrappedValue: T) { self.wrappedValue = wrappedValue }
  func withLock<R>(_ body: (inout T) -> R) -> R { body(&wrappedValue) }
}
protocol MPVOptionValue { static var defaultValue: Self { get }; init?(rawValue: String) }
final class MPVOptionDefaults {
  static let shared = MPVOptionDefaults()
  func getString(_ key: String) -> String? { "default" }
  func getDouble(_ key: String) -> Double? { 0 }
  func getInt(_ key: String) -> Int { 0 }
}
final class MPVController {
  var mpv: OpaquePointer?
  let player = NativePlayer()
  let observeProperties: [String: mpv_format] = ["test": MPV_FORMAT_DOUBLE]
  @NativeLocked var hooks: [UInt64: MPVHookValue] = [:]
  var hookCounter: UInt64 = 1
  let yes_str = "yes", no_str = "no"
  func log(_ message: String, level: Logger.Level = .debug) {}
  func optionWrites() -> [Int32] {
    [setOptionFlag("test", true), setOptionFloat("test", 1), setOptionInt("test", 1), setOptionString("test", "yes")]
  }
  // PRODUCTION_NATIVE_METHODS
}
// PRODUCTION_NODE
