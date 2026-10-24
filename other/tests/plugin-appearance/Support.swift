import Cocoa
import JavaScriptCore

// Minimal owning-app contracts; the tested policy, JSExport API and WebKit bridge
// are compiled from their actual production files.
enum Utility {
  static func executeOnMainThread<T>(block: () -> T) -> T {
    Thread.isMainThread ? block() : DispatchQueue.main.sync(execute: block)
  }
}
enum Preference {
  enum Theme: Int { case dark = 0, light = 2, system = 4 }
  enum Key { case themeMaterial }
  static var selectedTheme = Theme.system
  static func `enum`<T>(for key: Key) -> T { selectedTheme as! T }
  static var observerCount: Int { observers.count }
  private static var observers: [UUID: (Key) -> Void] = [:]
  static func setTheme(_ theme: Theme) {
    selectedTheme = theme
    Array(observers.values).forEach { $0(.themeMaterial) }
  }
  final class Observer {
    private let id = UUID()
    func add(_ key: Key, block: @escaping (Key) -> Void) { observers[id] = block }
    deinit { observers.removeValue(forKey: id) }
  }
}
extension NSAppearance {
  convenience init?(iinaTheme theme: Preference.Theme) {
    switch theme {
    case .dark: self.init(named: .darkAqua)
    case .light: self.init(named: .aqua)
    case .system: return nil
    }
  }
}
final class JavascriptPluginInstance { }
class JavascriptAPI: NSObject {
  weak var context: JSContext!
  init(context: JSContext, pluginInstance: JavascriptPluginInstance) { self.context = context }
  func extraSetup() { }
  func cleanUp(_ instance: JavascriptPluginInstance) { }
  func throwError(withMessage message: String) {
    context.exception = JSValue(newErrorFromMessage: message, in: context)
  }
}
