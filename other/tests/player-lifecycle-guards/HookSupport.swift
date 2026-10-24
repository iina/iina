import Foundation
import JavaScriptCore

final class JavascriptAPIMpv: NSObject {}
enum Logger { enum Level { case warning } }
@propertyWrapper final class HookLocked<T> {
  var wrappedValue: T
  var projectedValue: HookLocked<T> { self }
  init(wrappedValue: T) { self.wrappedValue = wrappedValue }
  func withLock<R>(_ body: (inout T) -> R) -> R { body(&wrappedValue) }
}
// PRODUCTION_HOOK_VALUE
final class HookController {
  var mpv: OpaquePointer? = nativeTestHandle()
  @HookLocked var hooks: [UInt64: MPVHookValue] = [:]
  func log(_ message: String, level: Logger.Level) {}
  func handle(_ event: UnsafePointer<mpv_event>) {
    switch event.pointee.event_id {
    case MPV_EVENT_HOOK:
      // PRODUCTION_HOOK_EVENT
    default: break
    }
  }
}
final class WeakHookController {
  weak var value: HookController?
  init(_ value: HookController?) { self.value = value }
}
