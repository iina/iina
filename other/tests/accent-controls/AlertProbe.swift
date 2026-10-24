import Cocoa

final class SettingsWindow: NSWindow {}
enum SettingsItem {
  final class Switch {
    let nsSwitch = NSButton()
  }
}
enum AppRestart {
  static var requested = 0
  static var discarded = 0
  static func discardRestoreRequest() { discarded += 1 }
  static func restart(restoring window: SettingsWindow) throws { requested += 1 }
}

@main
enum AlertProbe {
  static func check(_ value: @autoclosure () -> Bool, _ message: String = "Assertion failed") {
    guard value() else { print("FAIL: " + message); exit(1) }
  }
  static var firstCells: [String] = []
  static func willPresent(_ alert: NSAlert) {
    firstCells.append(String(describing: type(of: alert.buttons[0].cell!)))
  }

  static func main() {
    setbuf(stdout, nil)
    let useSystem = CommandLine.arguments[1] == "system"
    let dark = CommandLine.arguments[2] == "dark"
    UserDefaults.standard.setVolatileDomain([
      "AppleHighlightColor": "0.456984 0.081313 0.184124 Other",
      "AppleAccentColor": -2,
      "useSystemAccentColor": useSystem
    ], forName: UserDefaults.argumentDomain)
    AppAccentColor.configure(useSystemAccent: useSystem)
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let window = SettingsWindow(contentRect: NSRect(x: -1800, y: 100, width: 600, height: 400),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let item = SettingsItem.Switch()
    window.contentView!.addSubview(item.nsSwitch)
    window.makeKeyAndOrderFront(nil)
    let controller = SettingsPageUI()
    var records: [[String: Any]] = []
    for iteration in 0..<6 {
      var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
      arguments["useSystemAccentColor"] = iteration % 2 == 0 ? !useSystem : useSystem
      UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
      controller.confirmAccentColorChange(in: window)
      guard let sheet = window.attachedSheet else { fatalError("Missing sheet") }
      let initialClass = String(describing: type(of: sheet.defaultButtonCell!))
      // Sample over presentation and subsequent redraws; inspect the preparation boundary separately.
      let deadline = Date(timeIntervalSinceNow: 0.12)
      while Date() < deadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005)) }
      let settledClass = String(describing: type(of: sheet.defaultButtonCell!))
      let color = AppAccentColor.color.usingColorSpace(.sRGB)!
      check(AppAccentColor.usesSystemAccent == useSystem, "Pending preference changed the running policy")
      if useSystem { check(abs(color.redComponent - 0.456984) < 0.000001) }
      else { check(color.blueComponent > 0.9 && color.redComponent < 0.2) }
      let wasRequested = AppRestart.requested
      let key = iteration % 2 == 0 ? "\u{1b}" : "\r"
      let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: sheet.windowNumber, context: nil, characters: key,
        charactersIgnoringModifiers: key, isARepeat: false, keyCode: iteration % 2 == 0 ? 53 : 36)!
      let handled = sheet.performKeyEquivalent(with: event)
      if !handled {
        func buttons(_ view: NSView) -> [NSButton] {
          (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
        }
        print("KEY FAILURE", iteration, firstCells, initialClass, settledClass,
              buttons(sheet.contentView!).map { ($0.title, $0.keyEquivalent.debugDescription, String(describing: $0.target), String(describing: $0.action)) })
      }
      check(handled, "Native key equivalent failed")
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
      check(AppRestart.requested == wasRequested + (iteration % 2), "Wrong response callback")
      check(window.attachedSheet == nil, "Sheet did not close")
      records.append(["iteration": iteration, "first": firstCells.last ?? "none",
                      "afterBegin": initialClass, "settled": settledClass, "restart": iteration % 2 == 1])
    }
    window.close()
    let data = try! JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
    check(records.allSatisfy { ($0["first"] as? String) == "AccentAlertButtonCell" },
                 "Default accent cell was not ready at the presentation boundary")
    check(records.allSatisfy { ($0["afterBegin"] as? String) == "AccentAlertButtonCell" &&
                                     ($0["settled"] as? String) == "AccentAlertButtonCell" }, "Cell reverted")
    check(AppRestart.discarded == 3 && AppRestart.requested == 3)
    print("PASS: first presentation, six pending toggles, launch color, Escape/Return and callback routing")
  }
}
