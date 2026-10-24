import Cocoa

struct SettingsLocalization {
  struct Key { static func general(_ value: String) -> Self { .init() } }
}
struct SettingsSearch {
  final class Context { func add(_ itemID: Int, _ title: String?) {} }
}
struct SettingsItem {
  class General: NSObject {
    let itemID = 0
    var controlSize: NSControl.ControlSize = .regular
    init(title: SettingsLocalization.Key?) { super.init() }
    func getValueViews() -> [NSView] { [] }
    func initBinding() {}
    func registerSearchEntry(context: SettingsSearch.Context) {}
  }
}

private final class PickerDefaults: UserDefaults {
  var values: [String: Any] = ["useSystemAccentColor": true, "accentColorSource": 2,
    "customAccentColor": "#13579B", "AppleHighlightColor": "0.456984 0.081313 0.184124 Other"]
  var writes = 0
  override func object(forKey key: String) -> Any? { values[key] }
  override func string(forKey key: String) -> String? { values[key] as? String }
  override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
  override func set(_ value: Any?, forKey key: String) { values[key] = value; writes += 1 }
}

private final class PickerDelegate: NSObject, NSApplicationDelegate {
  let defaults = PickerDefaults()
  let window = NSWindow(contentRect: NSRect(x: 300, y: 180, width: 650, height: 260),
    styleMask: [.titled, .closable], backing: .buffered, defer: false)
  var control: AccentColorSelectionControl!
  let previousWell = NSColorWell(frame: NSRect(x: 30, y: 55, width: 70, height: 30))
  var commits = 0
  var previousWellActions = 0
  let panel = NSColorPanel.shared
  func applicationDidFinishLaunching(_ notification: Notification) {
    AppAccentColor.configure(source: .textHighlight, defaults: defaults)
    window.title = "Accent Color Settings Probe"
    window.appearance = NSAppearance(named: .darkAqua)
    let label = NSTextField(labelWithString: "Accent Color")
    label.frame = NSRect(x: 30, y: 190, width: 180, height: 24)
    window.contentView!.addSubview(label)
    control = AccentColorSelectionControl(defaults: defaults)
    control.frame = NSRect(x: 330, y: 187, width: 280, height: 30)
    window.contentView!.addSubview(control)
    control.didCommitChange = { self.commits += 1 }
    previousWell.color = NSColor(srgbRed: 0.2, green: 0.6, blue: 0.4, alpha: 1)
    previousWell.target = self
    previousWell.action = #selector(previousWellChanged)
    window.contentView!.addSubview(previousWell)
    panel.showsAlpha = true
    panel.color = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    later {
      if ProcessInfo.processInfo.environment["ACCENT_PICKER_VISUAL"] == "1" {
        self.control.selectSource(.custom)
      } else {
        self.cancelCase()
      }
    }
  }
  @objc func previousWellChanged() { previousWellActions += 1 }
  func later(_ block: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: block)
  }
  func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
    (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, of: type) }
  }
  var sheet: NSWindow { window.attachedSheet! }
  var well: NSColorWell { descendants(sheet.contentView!, of: NSColorWell.self).first! }
  func respond(apply: Bool) {
    let key = apply ? "\r" : "\u{1b}"
    descendants(sheet.contentView!, of: NSButton.self).first { $0.keyEquivalent == key }!.performClick(nil)
  }
  func checkRestored() {
    precondition(window.attachedSheet == nil && control.popupButton.isEnabled)
    precondition(panel.showsAlpha && !panel.isVisible)
    precondition(AppAccentColor.hexString(for: panel.color) == "#0000FF")
  }
  func cancelCase() {
    control.selectSource(.custom)
    later {
      precondition(self.panel.isVisible && !self.panel.showsAlpha && self.well.isActive)
      self.well.color = NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 0.2)
      precondition(self.defaults.writes == 0 && self.commits == 0)
      self.respond(apply: false)
      self.later {
        self.checkRestored()
        precondition(self.defaults.writes == 0 && self.commits == 0)
        precondition(self.control.popupButton.selectedTag() == 2)
        print("PASS native Cancel: no writes/callback; popup/color unchanged; panel alpha/color/visibility restored")
        self.applyCase()
      }
    }
  }
  func applyCase() {
    control.selectSource(.custom)
    later {
      self.well.color = NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 0.2)
      self.respond(apply: true)
      self.later {
        self.checkRestored()
        precondition(self.commits == 1 && self.defaults.string(forKey: "customAccentColor") == "#FF8000")
        precondition(self.control.popupButton.selectedTag() == 3 && !self.control.customColorButton.isHidden)
        print("PASS native Apply: one opaque sRGB commit/callback; panel state restored")
        self.previousOwnerCase()
      }
    }
  }
  func previousOwnerCase() {
    previousWell.activate(true)
    later {
      precondition(self.previousWell.isActive && self.panel.isVisible)
      let original = AppAccentColor.hexString(for: self.previousWell.color)
      self.control.customColorButton.performClick(nil)
      self.later {
        precondition(!self.previousWell.isActive && self.well.isActive)
        self.well.color = .red
        self.respond(apply: false)
        self.later {
          precondition(self.previousWell.isActive && self.panel.isVisible && self.panel.showsAlpha)
          precondition(AppAccentColor.hexString(for: self.previousWell.color) == original)
          precondition(AppAccentColor.hexString(for: self.panel.color) == original)
          precondition(self.previousWellActions == 0 && self.commits == 1)
          print("PASS previous active well restored with unchanged color/actions and visible panel")
          self.previousWell.deactivate()
          self.panel.orderOut(nil)
          self.closedPanelCase()
        }
      }
    }
  }
  func closedPanelCase() {
    control.customColorButton.performClick(nil)
    later {
      self.panel.performClose(nil)
      precondition(self.window.attachedSheet != nil)
      self.respond(apply: false)
      self.later {
        precondition(self.window.attachedSheet == nil && self.commits == 1)
        precondition(self.control.popupButton.selectedTag() == 3 && self.control.popupButton.isEnabled)
        print("PASS closing native color panel keeps confirmation available; Cancel leaves saved custom unchanged")
        NSApp.terminate(nil)
      }
    }
  }
}

@main
enum NativePickerProbe {
  static func main() {
    setbuf(stdout, nil)
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = PickerDelegate()
    app.delegate = delegate
    app.run()
  }
}
