//
//  AccentColorSettingsItem.swift
//  iina
//

import Cocoa

/// Keep native button interaction and accessibility with a color-well-style bezel.
final class AccentColorSwatchButton: NSButton {
  var color: NSColor = .controlColor {
    didSet { needsDisplay = true }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    cell = AccentColorSwatchCell(textCell: "")
    setButtonType(.momentaryPushIn)
    bezelStyle = .rounded
    isBordered = true // The cell draws the capsule instead of AppKit's standard bezel.
    focusRingType = .exterior
    title = ""
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class AccentColorSwatchCell: NSButtonCell {
  private func capsule(in frame: NSRect) -> NSBezierPath {
    let height = min(16, max(0, frame.height - 2))
    let bounds = NSRect(x: frame.minX + 1, y: frame.midY - height / 2,
                        width: max(0, frame.width - 2), height: height)
    return NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
  }

  override func drawBezel(withFrame frame: NSRect, in controlView: NSView) {
    guard let button = controlView as? AccentColorSwatchButton else { return }
    let path = capsule(in: frame)
    button.color.setFill()
    path.fill()
    if isHighlighted {
      NSColor.black.withAlphaComponent(0.12).setFill()
      path.fill()
    }
    NSColor.separatorColor.setStroke()
    path.lineWidth = 1
    path.stroke()
  }

  override func drawFocusRingMask(withFrame cellFrame: NSRect, in controlView: NSView) {
    capsule(in: cellFrame).fill()
  }
}

/// Saved settings are independent of this process's launch-stable accent policy.
final class AccentColorSelectionControl: NSStackView {
  typealias CustomPicker = (NSWindow, NSColor, @escaping (NSColor?) -> Void) -> Void

  let popupButton = NSPopUpButton()
  let customColorButton = AccentColorSwatchButton()
  var didCommitChange: (() -> Void)?
  private let defaults: UserDefaults
  private let customPicker: CustomPicker
  private var isPickingColor = false
  private var popupWidth: NSLayoutConstraint!

  init(defaults: UserDefaults = .standard,
       customPicker: @escaping CustomPicker = AccentCustomColorPicker.present) {
    self.defaults = defaults
    self.customPicker = customPicker
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    orientation = .horizontal
    alignment = .centerY
    spacing = 8
    popupButton.translatesAutoresizingMaskIntoConstraints = false
    popupButton.bezelStyle = .flexiblePush
    if #available(macOS 26, *) { popupButton.showsBorderOnlyWhileMouseInside = false }
    else { popupButton.showsBorderOnlyWhileMouseInside = true }
    popupButton.target = self
    popupButton.action = #selector(sourceSelected)
    popupButton.setAccessibilityLabel(localized("label"))
    popupButton.identifier = .init("accentColorSource")
    for source in AppAccentColor.Source.allCases {
      popupButton.addItem(withTitle: localized("items.\(source.rawValue)"))
      popupButton.lastItem?.tag = source.rawValue
      popupButton.lastItem?.toolTip = localized("help.\(source.rawValue)")
    }
    customColorButton.target = self
    customColorButton.action = #selector(editCustomColor)
    customColorButton.setAccessibilityLabel(localized("custom.edit"))
    customColorButton.identifier = .init("customAccentColor")
    customColorButton.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      customColorButton.widthAnchor.constraint(equalToConstant: 32),
      customColorButton.heightAnchor.constraint(equalToConstant: 24)
    ])
    popupWidth = popupButton.widthAnchor.constraint(equalToConstant: 0)
    popupWidth.isActive = true
    addArrangedSubview(popupButton)
    addArrangedSubview(customColorButton)
    applyControlSize(.regular)
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func refresh() {
    let source = AppAccentColor.savedSource(defaults: defaults)
    popupButton.selectItem(withTag: source.rawValue)
    updatePopupWidth()
    popupButton.toolTip = localized("help.\(source.rawValue)")
    popupButton.setAccessibilityHelp(popupButton.toolTip)
    customColorButton.isHidden = source != .custom
    let color = AppAccentColor.savedCustomColor(defaults: defaults)
    let hex = AppAccentColor.hexString(for: color) ?? AppAccentColor.defaultCustomColor
    customColorButton.toolTip = String(format: localized("custom.help"), hex)
    customColorButton.setAccessibilityHelp(customColorButton.toolTip)
    customColorButton.setAccessibilityValue(hex)
    customColorButton.color = color
  }

  func applyControlSize(_ size: NSControl.ControlSize) {
    popupButton.controlSize = size
    popupButton.font = .systemFont(ofSize: NSFont.systemFontSize(for: size))
    customColorButton.controlSize = size
    updatePopupWidth()
  }

  private func updatePopupWidth() {
    // Use native metrics for the displayed choice; long menu options need not
    // reserve empty space when a shorter choice such as Custom is selected.
    let measurement = NSPopUpButton()
    measurement.bezelStyle = popupButton.bezelStyle
    measurement.controlSize = popupButton.controlSize
    measurement.font = popupButton.font
    measurement.addItem(withTitle: popupButton.title)
    popupWidth.constant = ceil(measurement.intrinsicContentSize.width)
  }

  @objc private func sourceSelected() {
    guard let source = AppAccentColor.Source(rawValue: popupButton.selectedTag()) else { refresh(); return }
    selectSource(source)
  }

  func selectSource(_ source: AppAccentColor.Source) {
    guard !isPickingColor else { return }
    if source == .custom {
      // Selecting Custom opens a transaction; the saved choice stays visible.
      refresh()
      editCustomColor()
    } else {
      commit(source: source)
    }
  }

  @objc func editCustomColor() {
    guard !isPickingColor, let window, window.attachedSheet == nil else { refresh(); return }
    isPickingColor = true
    popupButton.isEnabled = false
    customColorButton.isEnabled = false
    customPicker(window, AppAccentColor.savedCustomColor(defaults: defaults)) { [weak self] color in
      guard let self, self.isPickingColor else { return }
      self.isPickingColor = false
      self.popupButton.isEnabled = true
      self.customColorButton.isEnabled = true
      guard let color = color?.usingColorSpace(.sRGB)?.withAlphaComponent(1),
            let hex = AppAccentColor.hexString(for: color, appearance: self.effectiveAppearance) else {
        self.refresh()
        return
      }
      self.commit(source: .custom, customHex: hex)
    }
  }

  private func commit(source: AppAccentColor.Source, customHex: String? = nil) {
    let oldSource = AppAccentColor.savedSource(defaults: defaults)
    let oldCustom = AppAccentColor.hexString(for: AppAccentColor.savedCustomColor(defaults: defaults))
    let colorChanged = customHex.map { $0 != oldCustom } ?? false
    guard source != oldSource || colorChanged else { refresh(); return }
    if let customHex { defaults.set(customHex, forKey: AppAccentColor.customColorPreferenceKey) }
    defaults.set(source.rawValue, forKey: AppAccentColor.sourcePreferenceKey)
    defaults.set(source != .defaultBlue, forKey: "useSystemAccentColor")
    refresh()
    didCommitChange?()
  }

  private func localized(_ suffix: String) -> String {
    NSLocalizedString("settings.accentColorSource.\(suffix)", comment: "Accent color setting")
  }
}

private enum AccentCustomColorPicker {
  static func present(on parent: NSWindow, initialColor: NSColor, completion: @escaping (NSColor?) -> Void) {
    let panel = NSColorPanel.shared
    let previousAlpha = panel.showsAlpha
    let previousColor = panel.color
    let wasVisible = panel.isVisible
    func activeWells(in view: NSView) -> [NSColorWell] {
      let own = (view as? NSColorWell).flatMap { $0.isActive ? $0 : nil }.map { [$0] } ?? []
      return own + view.subviews.flatMap { activeWells(in: $0) }
    }
    let previousWells = NSApp.windows.filter { !($0 is NSColorPanel) }.compactMap(\.contentView)
      .flatMap { activeWells(in: $0) }
    let well = NSColorWell(frame: NSRect(x: 0, y: 0, width: 72, height: 32))
    well.color = initialColor.withAlphaComponent(1)
    if #available(macOS 14, *) { well.supportsAlpha = false }
    if #available(macOS 26, *) { well.maximumLinearExposure = 1 }
    well.setAccessibilityLabel(NSLocalizedString("settings.accentColorSource.custom.color", comment: "Color"))
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("settings.accentColorSource.custom.title", comment: "Custom accent title")
    alert.informativeText = NSLocalizedString("settings.accentColorSource.custom.message", comment: "Choose a color")
    alert.accessoryView = well
    let apply = alert.addButton(withTitle: NSLocalizedString("settings.accentColorSource.custom.apply", comment: "Apply Color"))
    alert.addButton(withTitle: NSLocalizedString("settings.accentColorSource.custom.cancel", comment: "Cancel")).keyEquivalent = "\u{1b}"
    AccentControls.styleDefaultButton(in: alert)
    alert.beginSheetModal(for: parent) { response in
      let selected = response == .alertFirstButtonReturn ? well.color : nil
      well.deactivate()
      panel.showsAlpha = previousAlpha
      // Restore the native color-well owner instead of replacing panel targets.
      if previousWells.isEmpty { panel.color = previousColor }
      previousWells.forEach { $0.activate(false) }
      if !wasVisible { panel.orderOut(nil) }
      completion(selected)
    }
    apply.keyEquivalent = "\r"
    DispatchQueue.main.async {
      guard alert.window.sheetParent != nil else { return }
      panel.showsAlpha = false
      well.activate(true)
    }
  }
}

// Settings row integration.
final class AccentColorSettingsItem: SettingsItem.General {
  let selectionControl: AccentColorSelectionControl
  var didCommitChange: (() -> Void)? {
    get { selectionControl.didCommitChange }
    set { selectionControl.didCommitChange = newValue }
  }
  var window: NSWindow? { selectionControl.window }

  init(defaults: UserDefaults = .standard) {
    selectionControl = AccentColorSelectionControl(defaults: defaults)
    super.init(title: .general("settings.accentColorSource.label"))
  }

  override func getValueViews() -> [NSView] { [selectionControl] }
  override func initBinding() {
    selectionControl.applyControlSize(controlSize)
    selectionControl.refresh()
  }

  override func registerSearchEntry(context: SettingsSearch.Context) {
    super.registerSearchEntry(context: context)
    for source in AppAccentColor.Source.allCases {
      context.add(itemID, NSLocalizedString("settings.accentColorSource.items.\(source.rawValue)", comment: "Accent source"))
    }
  }
}
