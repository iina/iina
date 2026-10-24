// Integration doubles mirror synchronous preference observation and the real
// SettingsItem.Switch rule: programmatic setIsOn does not call user callbacks.
enum Preference {
  enum Key { case initialWindowSizePosition, initialWindowGeometryConfiguration }
  static var raw = ""
  static var configured = ""
  static var writes = 0
  static var observers: [(Key) -> Void] = []
  static func string(for key: Key) -> String? { key == .initialWindowSizePosition ? raw : configured }
  static func set(_ value: String, for key: Key) {
    if key == .initialWindowGeometryConfiguration { configured = value; return }
    raw = value
    writes += 1
    observers.forEach { $0(key) }
  }
  class Observer {
    func add(_ key: Key, block: @escaping (Key) -> Void) { Preference.observers.append(block) }
  }
}
enum SettingsItem {
  class Switch {
    enum State { case on, off }
    class NativeSwitch { var state = State.off }
    let nsSwitch = NativeSwitch()
    var stateChangeCallback: ((Switch) -> Void)?
    func setIsOn(_ isOn: Bool) { nsSwitch.state = isOn ? .on : .off }
    func userToggle(_ isOn: Bool) {
      setIsOn(isOn)
      stateChangeCallback?(self)
    }
  }
}
