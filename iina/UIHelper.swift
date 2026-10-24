//
//  UIHelper.swift
//  iina
//
//  Created by Hechen Li on 2026-06-03.
//  Copyright © 2026 lhc. All rights reserved.
//


enum CircularActionButtonStyle {
  static let hitSize: CGFloat = 22
  static let circleDiameter: CGFloat = 14
  static let circleInset = (hitSize - circleDiameter) / 2
  static let alignmentInsets = NSEdgeInsets(top: 1.5, left: 0, bottom: 1.5, right: 0)

  static func circleFrame(in bounds: NSRect) -> NSRect {
    let diameter = min(circleDiameter, bounds.width, bounds.height)
    return NSRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2,
                  width: diameter, height: diameter)
  }

  static func addCursorRect(to button: NSButton) {
    guard button.isEnabled, !button.isHiddenOrHasHiddenAncestor else { return }
    var ancestor: NSView? = button
    while let view = ancestor {
      guard view.alphaValue > 0 else { return }
      ancestor = view.superview
    }
    // Unclipped NSViews can report a visibleRect larger than their own bounds.
    let rect = button.bounds.intersection(button.visibleRect)
    guard !rect.isEmpty else { return }
    button.addCursorRect(rect, cursor: .pointingHand)
  }
}

final class CircularActionButton: NSButton {
  private var hoverArea: NSTrackingArea?
  private var hovered = false
  private var glyphImage: NSImage?
  private let glyphDiameter: CGFloat

  private static let refreshGlyph = NSImage(size: NSSize(width: 24, height: 24), flipped: true) { _ in
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 21.8883, y: 13.5))
    path.curve(to: NSPoint(x: 12, y: 22), controlPoint1: NSPoint(x: 21.1645, y: 18.3113), controlPoint2: NSPoint(x: 17.013, y: 22))
    path.curve(to: NSPoint(x: 2, y: 12), controlPoint1: NSPoint(x: 6.47715, y: 22), controlPoint2: NSPoint(x: 2, y: 17.5228))
    path.curve(to: NSPoint(x: 12, y: 2), controlPoint1: NSPoint(x: 2, y: 6.47715), controlPoint2: NSPoint(x: 6.47715, y: 2))
    path.curve(to: NSPoint(x: 21.1679, y: 8), controlPoint1: NSPoint(x: 16.1006, y: 2), controlPoint2: NSPoint(x: 19.6248, y: 4.46819))
    path.move(to: NSPoint(x: 17, y: 8))
    path.line(to: NSPoint(x: 21.4, y: 8))
    path.curve(to: NSPoint(x: 22, y: 7.4), controlPoint1: NSPoint(x: 21.7314, y: 8), controlPoint2: NSPoint(x: 22, y: 7.73137))
    path.line(to: NSPoint(x: 22, y: 3))
    path.lineWidth = 1.5
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    NSColor.black.setStroke()
    path.stroke()
    return true
  }

  init(symbolName: String, target: AnyObject?, action: Selector?) {
    glyphDiameter = symbolName == "arrow.counterclockwise" ? 8.5 : 10
    super.init(frame: .zero)
    image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 10, weight: .medium))
    // Keep the native symbol's accessibility description; draw the supplied vector.
    glyphImage = symbolName == "arrow.counterclockwise" ? Self.refreshGlyph : image
    imagePosition = .imageOnly
    bezelStyle = .smallSquare
    isBordered = false
    self.target = target
    self.action = action
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize {
    NSSize(width: CircularActionButtonStyle.hitSize, height: CircularActionButtonStyle.hitSize)
  }
  override var alignmentRectInsets: NSEdgeInsets { CircularActionButtonStyle.alignmentInsets }

  private var circleFrame: NSRect {
    CircularActionButtonStyle.circleFrame(in: bounds)
  }

  override var isHidden: Bool {
    didSet {
      if isHidden { hovered = false; needsDisplay = true }
      window?.invalidateCursorRects(for: self)
    }
  }

  override var isEnabled: Bool {
    didSet { needsDisplay = true; window?.invalidateCursorRects(for: self) }
  }
  override var alphaValue: CGFloat { didSet { window?.invalidateCursorRects(for: self) } }

  override func resetCursorRects() {
    super.resetCursorRects()
    CircularActionButtonStyle.addCursorRect(to: self)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
    addTrackingArea(area)
    hoverArea = area
  }

  override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
  override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

  override func draw(_ dirtyRect: NSRect) {
    let circle = circleFrame
    NSColor.labelColor.withAlphaComponent(cell?.isHighlighted == true ? 0.3 : hovered ? 0.2 : 0.12).setFill()
    NSBezierPath(ovalIn: circle).fill()
    guard let image = glyphImage, image.size.width > 0, image.size.height > 0 else { return }
    let foreground = NSColor.labelColor.withAlphaComponent(isEnabled ? 0.85 : 0.35)
    let tinted = NSImage(size: image.size, flipped: false) { rectangle in
      image.draw(in: rectangle)
      foreground.setFill()
      rectangle.fill(using: .sourceIn)
      return true
    }
    let maximum = circle.width * glyphDiameter / 14
    let scale = min(maximum / image.size.width, maximum / image.size.height)
    let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    tinted.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                          width: size.width, height: size.height))
  }

  override var focusRingMaskBounds: NSRect { circleFrame }
  override func drawFocusRingMask() { NSBezierPath(ovalIn: circleFrame).fill() }
}

final class TrackAddButton: NSButton {
  private var hoverArea: NSTrackingArea?
  private var hovered = false

  init(title: String, target: AnyObject?, action: Selector?) {
    super.init(frame: .zero)
    cell = TrackAddButtonCell(textCell: title)
    self.title = title
    self.target = target
    self.action = action
    setButtonType(.momentaryPushIn)
    isBordered = false
    alignment = .left
    font = .systemFont(ofSize: NSFont.systemFontSize)
    image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
    imagePosition = .imageLeading
    imageHugsTitle = true
    translatesAutoresizingMaskIntoConstraints = false
    heightAnchor.constraint(equalToConstant: 28).isActive = true
    (cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
  override var intrinsicContentSize: NSSize { NSSize(width: super.intrinsicContentSize.width + 20, height: 28) }

  override var isEnabled: Bool {
    didSet { if !isEnabled { hovered = false }; needsDisplay = true; window?.invalidateCursorRects(for: self) }
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self)
    addTrackingArea(area)
    hoverArea = area
  }

  override func cursorUpdate(with event: NSEvent) {
    (isEnabled ? NSCursor.pointingHand : NSCursor.arrow).set()
  }

  override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
  override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
  override func resetCursorRects() {
    super.resetCursorRects()
    CircularActionButtonStyle.addCursorRect(to: self)
  }

  override func draw(_ dirtyRect: NSRect) {
    if isEnabled && (hovered || cell?.isHighlighted == true) {
      NSColor.labelColor.withAlphaComponent(cell?.isHighlighted == true ? 0.14 : 0.08).setFill()
      NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }
    super.draw(dirtyRect)
  }

  override var focusRingMaskBounds: NSRect { bounds }
  override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill() }
}

private final class TrackAddButtonCell: NSButtonCell {
  override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
    super.drawInterior(withFrame: cellFrame.insetBy(dx: 10, dy: 0), in: controlView)
  }
}

class UIHelper {
  static let shared = UIHelper()
  private static let developmentLanguageBundle: Bundle? = {
    guard let language = Bundle.main.developmentLocalization,
          let path = Bundle.main.path(forResource: language, ofType: "lproj") else { return nil }
    return Bundle(path: path)
  }()

  var table: String?
  var scope: String?

  init(table: String? = nil, scope: String? = nil) {
    self.table = table
    self.scope = scope
  }

  func button(_ key: String, target: NSObject? = nil, action: Selector? = nil) -> NSButton {
    let btn = NSButton(title: localized(key), target: nil, action: nil)
    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.target = target
    btn.action = action
    return btn
  }

  func input(bindTo key: Preference.Key, fixedAlignmentRect: Bool = true, isFixedSize: Bool = true,
             range: ClosedRange<Double>? = nil, allowsFloats: Bool = false) -> NSTextField {
    let input = fixedAlignmentRect ? TextFieldWithFixedAlignmentRect() : NSTextField()
    input.translatesAutoresizingMaskIntoConstraints = false
    input.bezelStyle = .roundedBezel
    input.bind(.value, to: UserDefaults.standard, withKeyPath: key.rawValue)
    if isFixedSize {
      input.size(width: 48, height: 25)
    }
    if let range {
      let formatter = NumberFormatter()
      formatter.allowsFloats = allowsFloats
      formatter.usesGroupingSeparator = false
      formatter.minimum = NSNumber(value: range.lowerBound)
      formatter.maximum = NSNumber(value: range.upperBound)
      formatter.numberStyle = .decimal
      input.formatter = formatter
    }
    return input
  }

  func textInput(value: String = "", width: CGFloat = 64) -> NSTextField {
    let textField = NSTextField()
    textField.stringValue = value
    textField.controlSize = .small
    textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    textField.size(width: width)
    return textField
  }

  func label(_ key: String, wrapping: Bool = false, font: NSFont? = nil, isSmall: Bool = false, isSecondary: Bool = false, canCompress: Bool = true) -> NSTextField {
    let textField = if wrapping {
      NSTextField(wrappingLabelWithString: localized(key))
    } else {
      NSTextField(labelWithString: localized(key))
    }
    textField.translatesAutoresizingMaskIntoConstraints = false
    if isSmall {
      textField.controlSize = .small
      textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    }
    if isSecondary {
      textField.textColor = .secondaryLabelColor
    }
    if let font {
      textField.font = font
    }
    if canCompress {
      textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      textField.allowsDefaultTighteningForTruncation = true
      textField.lineBreakMode = .byTruncatingTail
    }
    return textField
  }

  func toggleButton(bindTo key: Preference.Key, size: NSControl.ControlSize = .regular, inverted: Bool = false) -> AccentSwitch {
    let btn = AccentSwitch()
    btn.controlSize = size
    let opt: [NSBindingOption : Any] = inverted ? [
      .valueTransformerName: NSValueTransformerName(rawValue: "NSNegateBoolean")
    ] : [:]
    btn.bind(.value, to: UserDefaults.standard, withKeyPath: key.rawValue, options: opt)
    return btn
  }

  func colorWell(bindTo key: Preference.Key) -> NSColorWell {
    let colorWell = NSColorWell()
    colorWell.translatesAutoresizingMaskIntoConstraints = false
    if #available(macOS 13.0, *) {
      colorWell.colorWellStyle = .expanded
    } else {
      colorWell.size(width: 30)
    }
    colorWell.size(height: 24)
    colorWell.bind(.value, to: UserDefaults.standard,
                   withKeyPath: key.rawValue,
                   options: [.valueTransformer: MPVColorStringTransformer()])
    return colorWell
  }

  func hStack(align: NSLayoutConstraint.Attribute = .centerY, spacing: CGFloat = 8, _ views: NSView...) -> NSStackView {
    return hStack(align: align, spacing: LayoutValue(spacing), views)
  }

  func hStack(align: NSLayoutConstraint.Attribute = .centerY, spacing: CGFloat = 8, _ views: [NSView]) -> NSStackView {
    return hStack(align: align, spacing: LayoutValue(spacing), views)
  }

  func hStack(align: NSLayoutConstraint.Attribute = .centerY, spacing: LayoutValue, _ views: NSView...) -> NSStackView {
    return hStack(align: align, spacing: spacing, views)
  }

  func hStack(align: NSLayoutConstraint.Attribute = .centerY, spacing: LayoutValue, _ views: [NSView]) -> NSStackView {
    let stackView = NSStackView(views: views)
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .horizontal
    stackView.alignment = align
    spacing.use { [weak stackView] in
      stackView?.spacing = $0
    }
    return stackView
  }

  func vStack(align: NSLayoutConstraint.Attribute = .leading, spacing: CGFloat = 8, wantsToGrow: Bool = false, _ views: NSView...) -> NSStackView {
    return vStack(align: align, spacing: LayoutValue(spacing), wantsToGrow: wantsToGrow, views)
  }

  func vStack(align: NSLayoutConstraint.Attribute = .leading, spacing: CGFloat = 8, wantsToGrow: Bool = false, _ views: [NSView]) -> NSStackView {
    return vStack(align: align, spacing: LayoutValue(spacing), wantsToGrow: wantsToGrow, views)
  }

  func vStack(align: NSLayoutConstraint.Attribute = .leading, spacing: LayoutValue, wantsToGrow: Bool = false, _ views: NSView...) -> NSStackView {
    return vStack(align: align, spacing: spacing, wantsToGrow: wantsToGrow, views)
  }

  func vStack(align: NSLayoutConstraint.Attribute = .leading, spacing: LayoutValue, wantsToGrow: Bool = false, _ views: [NSView]) -> NSStackView {
    let stackView = NSStackView(views: views)
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .vertical
    stackView.alignment = align
    spacing.use { [weak stackView] in
      stackView?.spacing = $0
    }
    if wantsToGrow {
      stackView.setHuggingPriority(.init(100), for: .horizontal)
    }
    return stackView
  }

  func space(width: CGFloat = 0, height: CGFloat = 0) -> NSView {
    let view = NSView()
    view.size(width: width, height: height)
    return view
  }

  func flexibleSpace(_ minWidth: CGFloat = 8) -> NSView {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.size(height: 0)
    view.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth).isActive = true
    view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return view
  }

  func separator() -> NSBox {
    let box = NSBox(frame: .zero)
    box.translatesAutoresizingMaskIntoConstraints = false
    box.boxType = .separator
    return box
  }

  func image(_ symbol: String..., size: CGFloat = 16, width: CGFloat? = nil, height: CGFloat? = nil,
             config: NSImage.SymbolConfiguration? = nil, scaleUp: Bool = false) -> NSImageView {
    image(
      .sf(symbol, withConfiguration: config) ?? NSImage(named: .init(symbol[0])),
      size: size, width: width, height: height, scaleUp: scaleUp
    )
  }

  func image(_ image: NSImage?, size: CGFloat = 16, width: CGFloat? = nil, height: CGFloat? = nil, scaleUp: Bool = true) -> NSImageView {
    let imageView = NSImageView(image: image ?? .sf("square.split.diagonal.2x2")!)
    imageView.imageScaling = scaleUp ? .scaleProportionallyUpOrDown : .scaleProportionallyDown
    imageView.size(width: width ?? size, height: height ?? size)
    return imageView
  }

  func localized(_ key: String) -> String {
    let key = if let scope { "\(scope).\(key)" } else { key }
    let val = NSLocalizedString(key, tableName: table, comment: key)
    if val == key {
      let verbatimVal = NSLocalizedString(key, tableName: "VerbatimStrings", comment: key)
      if verbatimVal != key {
        return verbatimVal
      }
      // Bundle lookup needs an explicit per-key development-language fallback.
      if let bundle = Self.developmentLanguageBundle {
        let fallback = bundle.localizedString(forKey: key, value: nil, table: table)
        if fallback != key { return fallback }
      }
    }
    return val
  }

  class TextFieldWithFixedAlignmentRect: NSTextField {
    override func frame(forAlignmentRect alignmentRect: NSRect) -> NSRect {
      return alignmentRect
    }
  }
}
