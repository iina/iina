//
//  AccentControls.swift
//  iina
//

import Cocoa

enum AccentControls {
  /// Finish AppKit's lazy layout before replacing the default cell, so the
  /// sheet's first frame already uses this launch's accent. Call before showing.
  static func styleDefaultButton(in alert: NSAlert) {
    alert.layout()
    guard let button = alert.buttons.first,
          let original = button.cell as? NSButtonCell,
          !(original is AccentAlertButtonCell) else { return }
    let target = button.target
    let action = button.action
    let tag = button.tag
    let key = button.keyEquivalent
    let modifiers = button.keyEquivalentModifierMask
    let enabled = button.isEnabled
    let state = button.state
    let cell = AccentAlertButtonCell(textCell: button.title)
    cell.setButtonType(.momentaryPushIn)
    cell.bezelStyle = original.bezelStyle
    cell.font = button.font
    cell.controlSize = button.controlSize
    cell.alignment = original.alignment
    cell.highlightsBy = original.highlightsBy
    cell.showsStateBy = original.showsStateBy
    cell.focusRingType = original.focusRingType
    button.cell = cell
    button.target = target
    button.action = action
    button.tag = tag
    button.keyEquivalent = key
    button.keyEquivalentModifierMask = modifiers
    button.isEnabled = enabled
    button.state = state
    button.isBordered = true
    button.needsDisplay = true
  }

  /// Also cover controls loaded from legacy nibs and AppKit-created alert buttons.
  /// Call when a window becomes key, not from a rendering loop.
  static func apply(to root: NSView) {
    if let slider = root as? NSSlider {
      slider.trackFillColor = AppAccentColor.color
      if #available(macOS 26.0, *) { slider.tintProminence = .primary }
    } else if let segments = root as? NSSegmentedControl {
      segments.selectedSegmentBezelColor = AppAccentColor.color
    } else if let button = root as? NSButton {
      let role = button.cell?.accessibilityRole()
      if role == .radioButton || role == .checkBox || button.keyEquivalent == "\r" {
        button.bezelColor = AppAccentColor.color
      }
    }
    root.subviews.forEach { apply(to: $0) }
  }
}

private final class AccentAlertButtonCell: NSButtonCell {
  private func bezelPath(in frame: NSRect) -> NSBezierPath {
    NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2)
  }

  override func drawBezel(withFrame frame: NSRect, in controlView: NSView) {
    let accent = AppAccentColor.color
    let fill = isHighlighted ? accent.blended(withFraction: 0.12, of: .black) ?? accent : accent
    (isEnabled ? fill : NSColor.disabledControlTextColor.withAlphaComponent(0.25)).setFill()
    bezelPath(in: frame).fill()
  }

  override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect,
                          in controlView: NSView) -> NSRect {
    let adjusted = NSMutableAttributedString(attributedString: title)
    adjusted.addAttribute(.foregroundColor,
                          value: isEnabled ? AppAccentColor.textColor : NSColor.disabledControlTextColor,
                          range: NSRange(location: 0, length: adjusted.length))
    return super.drawTitle(adjusted, withFrame: frame, in: controlView)
  }

  override func drawFocusRingMask(withFrame cellFrame: NSRect, in controlView: NSView) {
    NSColor.black.setFill()
    bezelPath(in: cellFrame).fill()
  }
}

private protocol AccentColorUpdating: AnyObject {
  func updateAccentColor()
}

/// Dynamic NSColors resolve on appearance changes. Also invalidate controls when
/// macOS changes its colors without changing the effective light/dark appearance.
private final class AccentColorObservation {
  private let token: NSObjectProtocol

  init(_ control: NSView & AccentColorUpdating) {
    token = NotificationCenter.default.addObserver(
      forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main
    ) { [weak control] _ in
      control?.updateAccentColor()
      control?.needsDisplay = true
    }
  }

  deinit { NotificationCenter.default.removeObserver(token) }
}

/// Keep the native slider's geometry, neutral value, tracking and accessibility.
class AccentSlider: NSSlider, AccentColorUpdating {
  private var accentObservation: AccentColorObservation?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    updateAccentColor()
    accentObservation = AccentColorObservation(self)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    updateAccentColor()
    accentObservation = AccentColorObservation(self)
  }

  fileprivate func updateAccentColor() {
    trackFillColor = AppAccentColor.color
    if #available(macOS 26.0, *) {
      // AppKit otherwise suppresses tint on sliders with tick marks (audio EQ).
      tintProminence = .primary
    }
  }
}

/// Native segmented controls support arbitrary selected-bezel colors directly.
class AccentSegmentedControl: NSSegmentedControl, AccentColorUpdating {
  private var accentObservation: AccentColorObservation?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    updateAccentColor()
    accentObservation = AccentColorObservation(self)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    updateAccentColor()
    accentObservation = AccentColorObservation(self)
  }

  fileprivate func updateAccentColor() {
    selectedSegmentBezelColor = AppAccentColor.color
  }
}

/// Bezel tint also colors native radio/checkbox indicators, leaving their titles,
/// focus rings, Cocoa bindings, keyboard behavior and accessibility intact.
class AccentButton: NSButton, AccentColorUpdating {
  private var accentObservation: AccentColorObservation?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    updateAccentColor()
    accentObservation = AccentColorObservation(self)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    updateAccentColor()
    accentObservation = AccentColorObservation(self)
  }

  fileprivate func updateAccentColor() {
    bezelColor = AppAccentColor.color
  }
}

/// Settings navigation uses the chosen accent even while focus is in the page.
/// NSTableRowView has no public arbitrary selection-color property.
class AccentTableRowView: NSTableRowView, AccentColorUpdating {
  var accentSelectionInset: NSSize { NSSize(width: 10, height: 0) }
  var accentSelectionRadius: CGFloat { 8 }
  private var accentObservation: AccentColorObservation?
  private struct SavedForeground {
    weak var view: NSView?
    let color: NSColor?
  }
  private var savedForegrounds: [SavedForeground] = []

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    super.selectionHighlightStyle = .none
    accentObservation = AccentColorObservation(self)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    super.selectionHighlightStyle = .none
    accentObservation = AccentColorObservation(self)
  }

  override var selectionHighlightStyle: NSTableView.SelectionHighlightStyle {
    get { .none }
    set {
      // Source-list selection is drawn by AppKit outside drawSelection(in:).
      // Draw the custom background while retaining native row selection state.
      super.selectionHighlightStyle = .none
    }
  }

  override var interiorBackgroundStyle: NSView.BackgroundStyle {
    guard isSelected else { return .normal }
    let text = AppAccentColor.textColor.usingColorSpace(.sRGB)
    return (text?.redComponent ?? 1) > 0.5 ? .emphasized : .normal
  }

  override var isSelected: Bool {
    didSet {
      updateAccentColor()
    }
  }

  override func didAddSubview(_ subview: NSView) {
    super.didAddSubview(subview)
    if isSelected { tintForeground(in: subview) }
  }

  override func prepareForReuse() {
    restoreForegrounds()
    super.prepareForReuse()
  }

  override func drawBackground(in dirtyRect: NSRect) {
    super.drawBackground(in: dirtyRect)
    guard isSelected else { return }
    AppAccentColor.color.setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: accentSelectionInset.width, dy: accentSelectionInset.height),
                 xRadius: accentSelectionRadius, yRadius: accentSelectionRadius).fill()
  }

  fileprivate func updateAccentColor() {
    if isSelected {
      subviews.forEach { tintForeground(in: $0) }
    } else {
      restoreForegrounds()
    }
    needsDisplay = true
  }

  private func tintForeground(in view: NSView) {
    if let label = view as? NSTextField {
      if !savedForegrounds.contains(where: { $0.view === label }) {
        savedForegrounds.append(SavedForeground(view: label, color: label.textColor))
      }
      label.textColor = AppAccentColor.textColor
    } else if let image = view as? NSImageView {
      if !savedForegrounds.contains(where: { $0.view === image }) {
        savedForegrounds.append(SavedForeground(view: image, color: image.contentTintColor))
      }
      image.contentTintColor = AppAccentColor.textColor
    } else if let button = view as? NSButton, !button.isBordered {
      if !savedForegrounds.contains(where: { $0.view === button }) {
        savedForegrounds.append(SavedForeground(view: button, color: button.contentTintColor))
      }
      button.contentTintColor = AppAccentColor.textColor
    }
    view.subviews.forEach { tintForeground(in: $0) }
  }

  private func restoreForegrounds() {
    for saved in savedForegrounds {
      if let label = saved.view as? NSTextField {
        label.textColor = saved.color
      } else if let image = saved.view as? NSImageView {
        image.contentTintColor = saved.color
      } else if let button = saved.view as? NSButton {
        button.contentTintColor = saved.color
      }
    }
    savedForegrounds.removeAll()
  }
}
