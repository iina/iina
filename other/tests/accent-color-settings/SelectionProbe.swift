import Cocoa

// Only the settings row's layout/search host is stubbed. The selector, native
// controls, transaction code, shared color policy and accent adapters are real.
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

private final class MemoryDefaults: UserDefaults {
  var values: [String: Any] = ["useSystemAccentColor": true, "accentColorSource": 2,
    "customAccentColor": "#007AFF", "AppleHighlightColor": "0.456984 0.081313 0.184124 Other"]
  var writes = 0
  override func object(forKey key: String) -> Any? { values[key] }
  override func string(forKey key: String) -> String? { values[key] as? String }
  override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
  override func set(_ value: Any?, forKey key: String) { values[key] = value; writes += 1 }
}

@main
enum SelectionProbe {
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let panelExisted = NSColorPanel.sharedColorPanelExists
    let defaults = MemoryDefaults()
    AppAccentColor.configure(source: .textHighlight, defaults: defaults)
    let launchColor = AppAccentColor.hexString(for: AppAccentColor.color)!
    var pickerCalls = 0
    var completePicker: ((NSColor?) -> Void)?
    var pickerInitial: NSColor?
    let control = AccentColorSelectionControl(defaults: defaults) { _, initial, completion in
      pickerCalls += 1
      pickerInitial = initial
      completePicker = completion
    }
    let window = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 500, height: 100),
                          styleMask: .titled, backing: .buffered, defer: false)
    window.contentView!.addSubview(control)
    var commits = 0
    control.didCommitChange = { commits += 1 }
    func choose(_ source: AppAccentColor.Source) {
      control.popupButton.selectItem(withTag: source.rawValue)
      precondition(control.popupButton.sendAction(control.popupButton.action, to: control.popupButton.target))
    }
    precondition(control.popupButton.itemArray.map(\.tag) == [0, 1, 2, 3])
    precondition(control.popupButton.itemArray.map(\.title) == ["Default", "System Accent", "System Highlight", "Custom…"])
    precondition(control.popupButton.selectedTag() == 2 && control.customColorButton.isHidden)
    precondition(control.popupButton.itemArray.allSatisfy { $0.toolTip?.isEmpty == false })
    choose(.textHighlight)
    precondition(defaults.writes == 0 && commits == 0)

    choose(.systemAccent)
    precondition(AppAccentColor.savedSource(defaults: defaults) == .systemAccent && commits == 1)
    precondition(defaults.bool(forKey: "useSystemAccentColor"))
    let writesBeforePicker = defaults.writes
    choose(.custom)
    precondition(pickerCalls == 1 && control.popupButton.selectedTag() == 1)
    precondition(defaults.writes == writesBeforePicker && commits == 1)
    precondition(!control.popupButton.isEnabled)
    completePicker!(nil)
    completePicker!(NSColor.red) // A duplicate completion must not commit.
    precondition(control.popupButton.selectedTag() == 1 && control.popupButton.isEnabled)
    precondition(defaults.writes == writesBeforePicker && commits == 1)
    precondition(defaults.string(forKey: "customAccentColor") == "#007AFF")

    choose(.custom)
    completePicker!(NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 0.25))
    precondition(commits == 2 && defaults.string(forKey: "customAccentColor") == "#FF8000")
    precondition(AppAccentColor.savedSource(defaults: defaults) == .custom)
    precondition(AppAccentColor.savedCustomColor(defaults: defaults).alphaComponent == 1)
    precondition(control.popupButton.selectedTag() == 3 && !control.customColorButton.isHidden)
    precondition(control.customColorButton.cell?.accessibilityRole() == .button)
    precondition(control.customColorButton.accessibilityValue() as? String == "#FF8000")
    precondition(control.customColorButton.focusRingType == .exterior)
    precondition(control.customColorButton.image == nil && control.customColorButton.title.isEmpty)
    precondition(AppAccentColor.hexString(for: control.customColorButton.color) == "#FF8000")
    checkNativeMetrics(control)
    checkPillRendering(control.customColorButton)
    let writesBeforeSameColor = defaults.writes
    control.customColorButton.performClick(nil)
    precondition(pickerCalls == 3 && AppAccentColor.hexString(for: pickerInitial!) == "#FF8000")
    completePicker!(pickerInitial)
    precondition(defaults.writes == writesBeforeSameColor && commits == 2)

    control.customColorButton.performClick(nil)
    completePicker!(NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
    precondition(commits == 3 && defaults.string(forKey: "customAccentColor") == "#0000FF")
    choose(.defaultBlue)
    precondition(commits == 4 && AppAccentColor.savedSource(defaults: defaults) == .defaultBlue)
    precondition(!defaults.bool(forKey: "useSystemAccentColor") && control.customColorButton.isHidden)
    precondition(defaults.string(forKey: "customAccentColor") == "#0000FF")
    choose(.textHighlight)
    precondition(commits == 5 && defaults.bool(forKey: "useSystemAccentColor"))
    precondition(AppAccentColor.source == .textHighlight)
    precondition(AppAccentColor.hexString(for: AppAccentColor.color) == launchColor)
    precondition(NSColorPanel.sharedColorPanelExists == panelExisted)
    print("PASS four-option native selector, no-op selection, cancel without writes, duplicate callback, opaque custom commit, accessible capsule swatch, swatch reopen/edit, no-op custom, legacy compatibility, launch-stable policy; commits=\(commits), pickerCalls=\(pickerCalls)")
    withExtendedLifetime((window, control)) {}
  }

  static func checkPillRendering(_ button: AccentColorSwatchButton) {
    let originalAppearance = button.appearance
    defer { button.appearance = originalAppearance }
    for (name, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
      button.appearance = NSAppearance(named: appearanceName)
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 48,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
      bitmap.size = NSSize(width: 32, height: 24)
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
      button.effectiveAppearance.performAsCurrentDrawingAppearance {
        button.cell!.draw(withFrame: NSRect(x: 0, y: 0, width: 32, height: 24), in: button)
      }
      NSGraphicsContext.restoreGraphicsState()
      let center = bitmap.colorAt(x: 32, y: 24)!.usingColorSpace(.sRGB)!
      precondition(abs(center.redComponent - 1) < 0.01 && abs(center.greenComponent - 0.5) < 0.01)
      precondition(center.blueComponent < 0.01 && center.alphaComponent == 1)
      precondition(bitmap.colorAt(x: 2, y: 2)!.alphaComponent == 0)
      precondition(bitmap.colorAt(x: 2, y: 24)!.alphaComponent > 0)
      precondition(bitmap.colorAt(x: 32, y: 4)!.alphaComponent == 0)
      // No native square bezel or permanent blue outline around the saved color.
      for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
          let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
          precondition(!(color.alphaComponent > 0.1 && color.blueComponent > color.redComponent + 0.1))
        }
      }
      if let output = ProcessInfo.processInfo.environment["ACCENT_SELECTOR_OUTPUT"] {
        let url = URL(fileURLWithPath: output).appendingPathComponent("custom-pill-\(name).png")
        try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
      }
      print("PASS \(name) capsule: opaque saved-color center, rounded transparent corners, neutral keyline without blue outline")
    }
  }

  static func checkNativeMetrics(_ control: AccentColorSelectionControl) {
    let neighbor = NSPopUpButton()
    neighbor.bezelStyle = .flexiblePush
    neighbor.controlSize = .regular // SettingsItem.PopupButton.initBinding.
    neighbor.addItem(withTitle: control.popupButton.title)
    control.layoutSubtreeIfNeeded()
    precondition(control.popupButton.controlSize == neighbor.controlSize)
    precondition(control.popupButton.font == neighbor.font)
    precondition(control.popupButton.font?.pointSize == neighbor.font?.pointSize)
    precondition(control.popupButton.intrinsicContentSize.height == neighbor.intrinsicContentSize.height)
    precondition(control.popupButton.constraints.contains {
      $0.firstAttribute == .width && $0.constant == ceil(neighbor.intrinsicContentSize.width)
    })
    precondition(control.customColorButton.constraints.contains { $0.firstAttribute == .width && $0.constant == 32 })
    precondition(control.customColorButton.constraints.contains { $0.firstAttribute == .height && $0.constant == 24 })
    print("PASS popup metrics match Settings: controlSize=\(neighbor.controlSize.rawValue), font=\(neighbor.font!.pointSize), height=\(neighbor.intrinsicContentSize.height), selected-title width=\(ceil(neighbor.intrinsicContentSize.width)); capsule=30×16 within32×24 button")
  }
}
