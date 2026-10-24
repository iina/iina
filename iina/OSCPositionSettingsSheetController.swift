//
//  OSCPositionSettingsSheetController.swift
//  iina
//

import Cocoa

struct FloatingOSCPreviewAppearance {
  var compact = false
  var sliderHeight: CGFloat = {
    let slider = AccentSlider()
    slider.controlSize = .small
    return slider.intrinsicContentSize.height
  }()
  var titlebarHeight: CGFloat = { if #available(macOS 26, *) { 40 } else { 36 } }()
  var transportImages: [NSImage] = ["backward.end.fill", "play.fill", "forward.end.fill"].compactMap {
    NSImage(systemSymbolName: $0, accessibilityDescription: nil)
  }
  var toolbarImages: [NSImage] = ["puzzlepiece.extension", "pip.enter", "list.bullet.rectangle", "gearshape"].compactMap {
    NSImage(systemSymbolName: $0, accessibilityDescription: nil)
  }
}

private let ui = SettingsUIHelper.sharedUI

class OSCPositionSettingsSheetController: NSWindowController, NSTextFieldDelegate {
  private let preview = OSCPositionPreviewView()
  // Fallback for a presenter that has not been placed on a screen yet.
  static var standardPreviewSize: NSSize {
    NSScreen.screens.first?.frame.size ?? FloatingOSCMetrics.minimumWindowSize
  }
  static let previewContextPersistenceKey = "oscPositionPreviewContext"
  private let previewContext = PositionPreviewContextSelector()
  private let horizontalInput = PositionSettingsTextField()
  private let verticalInput = PositionSettingsTextField()
  private lazy var horizontalUnit = popup(["oscPosition.percent", "oscPosition.points"], label: "oscPosition.horizontalUnit")
  private lazy var verticalUnit = popup(["oscPosition.percent", "oscPosition.points"], label: "oscPosition.verticalUnit")
  private lazy var horizontalEdge = popup(["oscPosition.left", "oscPosition.right"], label: "oscPosition.horizontalEdge")
  private lazy var verticalEdge = popup(["oscPosition.top", "oscPosition.bottom"], label: "oscPosition.verticalEdge")
  private lazy var horizontalFrom = ui.label("oscPosition.from")
  private lazy var verticalFrom = ui.label("oscPosition.from")
  private var position: FloatingOSCPosition = .initial

  init() { super.init(window: nil) }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func present(on parent: NSWindow, contexts: [PositionPreviewContext] = [], appearance: FloatingOSCPreviewAppearance = .init()) {
    guard parent.attachedSheet == nil else { return }
    if window == nil { loadWindow() }
    guard let window else { return }
    preview.controllerAppearance = appearance
    position = Preference.floatingOSCDefaultPosition
    let standard = PositionPreviewContext(title: ui.localized("previewContext.standard"),
      size: parent.screen?.frame.size ?? Self.standardPreviewSize,
      minimumSize: FloatingOSCMetrics.minimumWindowSize, identifier: "standard")
    var playerContexts = contexts
    if !playerContexts.isEmpty { playerContexts[0].identifier = "current-window" }
    let minimum = FloatingOSCMetrics.minimumWindowSize
    let screens = NSScreen.screens.map { $0.frame.size }
    let maximum = NSSize(width: max(minimum.width, screens.map(\.width).max() ?? standard.size.width),
                         height: max(minimum.height, screens.map(\.height).max() ?? standard.size.height))
    previewContext.customSizeLimits = (minimum, maximum)
    previewContext.configure([standard] + playerContexts, minimumSize: minimum,
      rememberSelectionUnder: Self.previewContextPersistenceKey)
    updateInputs()
    updatePreview()
    parent.beginSheet(window)
  }

  override func loadWindow() {
    let panel = PositionSettingsPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 550),
                        styleMask: [.titled], backing: .buffered, defer: false)
    panel.title = ui.localized("oscDefaultPosition.title")
    panel.isReleasedWhenClosed = false
    let content = NSView()
    panel.contentView = content
    window = panel
    let title = ui.label("oscDefaultPosition.title", font: .boldSystemFont(ofSize: 16))
    previewContext.onSizeChanged = { [weak self] size in
      guard let self else { return }
      self.preview.minimumSize = self.previewContext.minimumSize
      self.preview.setReferenceSize(size)
      self.updatePreview()
    }
    preview.translatesAutoresizingMaskIntoConstraints = false
    preview.size(width: 560, height: 315)
    preview.onPositionChanged = { [weak self] _, _ in
      guard let self else { return }
      self.position = self.preview.position
      self.updateInputs()
    }
    let horizontalRow = inputRow("controlBarDefaultPositionHorizontal.label", input: horizontalInput,
      unit: horizontalUnit, from: horizontalFrom, edge: horizontalEdge)
    let verticalRow = inputRow("controlBarDefaultPositionVertical.label", input: verticalInput,
      unit: verticalUnit, from: verticalFrom, edge: verticalEdge)
    let fields = NSGridView(views: [horizontalRow, verticalRow])
    fields.rowSpacing = 8
    fields.columnSpacing = 8
    fields.column(at: 0).xPlacement = .leading
    horizontalEdge.size(width: 90)
    verticalEdge.size(width: 90)
    fields.column(at: 1).width = horizontalRow[1].fittingSize.width
    fields.column(at: 2).width = max(horizontalUnit.fittingSize.width, verticalUnit.fittingSize.width)
    fields.column(at: 3).width = horizontalFrom.fittingSize.width
    fields.column(at: 4).width = 90
    fields.rowAlignment = .firstBaseline
    fields.translatesAutoresizingMaskIntoConstraints = false
    let cancel = ui.button("oscDefaultPosition.cancel", target: self, action: #selector(cancel))
    cancel.keyEquivalent = "\u{1b}"
    let save = ui.button("oscDefaultPosition.save", target: self, action: #selector(save))
    save.keyEquivalent = "\r"
    let reset = ui.button("oscDefaultPosition.reset", target: self, action: #selector(reset))
    let buttons = ui.hStack(reset, ui.flexibleSpace(), cancel, save)
    let stack = ui.vStack(spacing: 16, title, previewContext, preview, fields, buttons)
    content.addSubview(stack)
    stack.padding(.all(20))
    [title, previewContext, preview, fields, buttons].forEach { $0.padding(.horizontal, from: stack) }
    updateInputs()
    panel.setContentSize(NSSize(width: stack.fittingSize.width + 40, height: stack.fittingSize.height + 40))
  }

  private func popup(_ keys: [String], label: String) -> NSPopUpButton {
    let popup = NSPopUpButton()
    popup.translatesAutoresizingMaskIntoConstraints = false
    popup.bezelStyle = .accessoryBarAction
    popup.controlSize = .small
    for (tag, key) in keys.enumerated() {
      let item = NSMenuItem(title: ui.localized(key), action: nil, keyEquivalent: "")
      item.tag = tag
      popup.menu!.addItem(item)
    }
    popup.setAccessibilityLabel(ui.localized(label))
    popup.target = self
    popup.action = #selector(selectionChanged(_:))
    return popup
  }

  private func inputRow(_ key: String, input: NSTextField,
                        unit: NSPopUpButton, from: NSTextField, edge: NSPopUpButton) -> [NSView] {
    let label = ui.label(key)
    input.translatesAutoresizingMaskIntoConstraints = false
    input.size(width: 76)
    input.delegate = self
    (input as? PositionSettingsTextField)?.isValid = { [weak self, weak input] in
      guard let self, let input else { return false }
      return self.validValue(input) != nil
    }
    (input as? PositionSettingsTextField)?.normalizedInput = { [weak self, weak input] text in
      guard let self, let input, let formatter = input.formatter as? NumberFormatter,
            let value = PositionSettingsTextField.number(text, separator: formatter.decimalSeparator) else { return nil }
      let horizontal = input === self.horizontalInput
      let axis = horizontal ? self.position.horizontal : self.position.vertical
      let range = axis.unit == .percent ? 0.0...100.0 : self.preview.pointLimits(horizontal: horizontal)
      return formatter.string(from: NSNumber(value: min(max(value, range.lowerBound), range.upperBound)))
    }
    let formatter = PositionSettingsNumberFormatter()
    formatter.isPartialStringValidationEnabled = true
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.minimum = 0
    formatter.maximumFractionDigits = 2
    input.formatter = formatter
    input.setAccessibilityLabel(label.stringValue)
    return [label, input, unit, from, edge]
  }

  private func displayValue(_ axis: FloatingOSCPosition.Axis) -> Double {
    Double(axis.value) * (axis.unit == .percent ? 100 : 1)
  }

  private func validValue(_ input: NSTextField) -> Double? {
    let text = input.currentEditor()?.string ?? input.stringValue
    guard let formatter = input.formatter as? NumberFormatter,
          !text.isEmpty,
          text.components(separatedBy: formatter.decimalSeparator).count <= 2,
          text.allSatisfy({ $0.wholeNumberValue != nil || String($0) == formatter.decimalSeparator }),
          let number = formatter.number(from: text) else { return nil }
    let value = number.doubleValue
    let axis = input === horizontalInput ? position.horizontal : position.vertical
    let minimum = axis.unit == .point && input === horizontalInput ? 16.0 : 0
    let maximum = axis.unit == .percent ? 100.0 : 100000
    guard value.isFinite, value >= minimum, value <= maximum else { return nil }
    if input.currentEditor() != nil, axis.unit == .point,
       !preview.pointLimits(horizontal: input === horizontalInput).contains(value) { return nil }
    return value
  }

  private func apply(_ value: Double, horizontal: Bool) {
    if horizontal {
      position.horizontal.value = CGFloat(value / (position.horizontal.unit == .percent ? 100 : 1))
    } else {
      position.vertical.value = CGFloat(value / (position.vertical.unit == .percent ? 100 : 1))
    }
  }

  func controlTextDidChange(_ notification: Notification) {
    guard let input = notification.object as? NSTextField, let value = validValue(input) else { return }
    let horizontal = input === horizontalInput
    apply(value, horizontal: horizontal)
    updatePreview()
  }

  @objc private func selectionChanged(_ sender: NSPopUpButton) {
    guard window!.makeFirstResponder(nil) else { return }
    let horizontal = sender === horizontalUnit || sender === horizontalEdge
    var candidate = position
    var axis = horizontal ? candidate.horizontal : candidate.vertical
    if sender === horizontalUnit || sender === verticalUnit {
      axis.unit = FloatingOSCPosition.Unit(rawValue: sender.indexOfSelectedItem)!
      axis.value = axis.unit == .percent ? 0.5 : 16
    } else {
      let edge = FloatingOSCPosition.Edge(rawValue: sender.indexOfSelectedItem)!
      if axis.unit == .percent && axis.edge != edge { axis.value = 1 - axis.value }
      axis.edge = edge
    }
    if horizontal { candidate.horizontal = axis } else { candidate.vertical = axis }
    let converted = preview.converted(candidate)
    if horizontal { position.horizontal = converted.horizontal } else { position.vertical = converted.vertical }
    updateInputs()
    updatePreview()
  }

  private func updateInputs() {
    for (axis, input, unit, edge, horizontal) in [
      (position.horizontal, horizontalInput, horizontalUnit, horizontalEdge, true),
      (position.vertical, verticalInput, verticalUnit, verticalEdge, false)] {
      let value = displayValue(axis)
      let minimum = axis.unit == .point && horizontal ? 16.0 : 0
      let maximum = axis.unit == .percent ? 100.0 : 100000
      (input.formatter as! NumberFormatter).minimum = NSNumber(value: minimum)
      (input.formatter as! NumberFormatter).maximum = NSNumber(value: maximum)
      input.doubleValue = value
      input.rememberValue()
      unit.selectItem(at: axis.unit.rawValue)
      edge.selectItem(at: axis.edge.rawValue)
    }
  }

  private func updatePreview() {
    preview.setPosition(position)
    for (input, axis, horizontal) in [(horizontalInput, position.horizontal, true),
                                      (verticalInput, position.vertical, false)] {
      let range = axis.unit == .percent ? 0.0...100.0 : preview.pointLimits(horizontal: horizontal)
      let formatter = input.formatter as! NumberFormatter
      let lower = formatter.string(from: NSNumber(value: range.lowerBound)) ?? ""
      let upper = formatter.string(from: NSNumber(value: range.upperBound)) ?? ""
      input.toolTip = "\(lower)–\(upper) \(axis.unit == .percent ? "%" : "pt")"
    }
  }

  @objc private func reset() {
    horizontalInput.abortEditing()
    verticalInput.abortEditing()
    window?.makeFirstResponder(nil)
    position = .initial
    updateInputs()
    updatePreview()
  }

  @objc private func save() {
    guard window!.makeFirstResponder(nil), let horizontal = validValue(horizontalInput),
          let vertical = validValue(verticalInput) else { return }
    apply(horizontal, horizontal: true)
    apply(vertical, horizontal: false)
    Preference.saveFloatingOSCDefaultPosition(position)
    window?.sheetParent?.endSheet(window!, returnCode: .OK)
  }

  @objc private func cancel() { window?.sheetParent?.endSheet(window!, returnCode: .cancel) }
}

class OSCPositionPreviewView: NSView {
  var onPositionChanged: ((Double, Double) -> Void)?
  private(set) var position: FloatingOSCPosition = .initial
  private var dragOffset: NSPoint?
  private var referenceSize = NSSize(width: 1280, height: 720)
  var controllerAppearance = FloatingOSCPreviewAppearance()
  var minimumSize = FloatingOSCMetrics.minimumWindowSize

  var canvasFrame: NSRect {
    let scale = min(bounds.width / referenceSize.width, bounds.height / referenceSize.height)
    let size = NSSize(width: referenceSize.width * scale, height: referenceSize.height * scale)
    return NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
  }

  func setReferenceSize(_ size: NSSize) {
    guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
    referenceSize = NSSize(width: max(size.width, minimumSize.width),
                           height: max(size.height, minimumSize.height))
    dragOffset = nil
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
  }

  private var panelSize: NSSize {
    let size = FloatingOSCMetrics.panelSize(scale: FloatingOSCScale.factor(for: referenceSize),
                                           compact: controllerAppearance.compact, sliderHeight: controllerAppearance.sliderHeight)
    return NSSize(width: size.width * previewScale, height: size.height * previewScale)
  }

  private var previewScale: CGFloat { canvasFrame.width / referenceSize.width }
  private var panelCornerRadius: CGFloat {
    let radius: CGFloat = if #available(macOS 26, *) { 12 } else { 6 }
    return radius * previewScale
  }

  private var titlebarFrame: NSRect {
    NSRect(x: canvasFrame.minX, y: canvasFrame.maxY - controllerAppearance.titlebarHeight * previewScale,
           width: canvasFrame.width, height: min(canvasFrame.height, controllerAppearance.titlebarHeight * previewScale))
  }

  func pointLimits(horizontal: Bool) -> ClosedRange<Double> {
    guard previewScale > 0 else { return horizontal ? 16...16 : 0...0 }
    let range = horizontal
      ? FloatingOSCPlacement.horizontalRange(width: panelSize.width, windowWidth: canvasFrame.width,
          margin: FloatingOSCPlacement.defaultMargin * previewScale)
      : FloatingOSCPlacement.verticalRange(height: panelSize.height, windowHeight: canvasFrame.height,
          titlebarBottom: titlebarFrame.minY - canvasFrame.minY, margin: 0)
    return Double(range.lowerBound / previewScale)...max(Double(range.lowerBound / previewScale), floor(Double(range.upperBound / previewScale) * 100) / 100)
  }

  var panelFrame: NSRect {
    FloatingOSCPlacement.frame(position: position, size: panelSize, contentSize: canvasFrame.size,
      titlebarBottom: titlebarFrame.minY - canvasFrame.minY, pointScale: previewScale)
      .offsetBy(dx: canvasFrame.minX, dy: canvasFrame.minY)
  }

  func converted(_ candidate: FloatingOSCPosition) -> FloatingOSCPosition {
    FloatingOSCPlacement.capturing(frame: panelFrame.offsetBy(dx: -canvasFrame.minX, dy: -canvasFrame.minY), keeping: candidate,
      contentSize: canvasFrame.size, titlebarBottom: titlebarFrame.minY - canvasFrame.minY, pointScale: previewScale)
  }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.cornerRadius = 8
    layer?.masksToBounds = true
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    setAccessibilityLabel(ui.localized("oscDefaultPosition.preview"))
  }

  convenience init() {
    self.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setPosition(_ position: FloatingOSCPosition) {
    self.position = position
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
  }

  override func resetCursorRects() {
    addCursorRect(panelFrame, cursor: dragOffset == nil ? .openHand : .closedHand)
  }

  override func draw(_ dirtyRect: NSRect) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: canvasFrame, xRadius: 8, yRadius: 8).addClip()
    // Clip the composited scene so antialiased corners cannot reveal sky through the titlebar/mountains.
    let context = NSGraphicsContext.current?.cgContext
    context?.beginTransparencyLayer(auxiliaryInfo: nil)
    defer {
      context?.endTransparencyLayer()
      NSGraphicsContext.restoreGraphicsState()
    }
    PositionPreviewDrawing.draw(in: canvasFrame)

    // Shade the unreachable area once so corners and side gaps have equal opacity.
    let imageArea = NSRect(x: canvasFrame.minX, y: canvasFrame.minY, width: canvasFrame.width,
                           height: max(0, titlebarFrame.minY - canvasFrame.minY))
    let sideGap = min(imageArea.width / 2, FloatingOSCPlacement.defaultMargin * previewScale)
    let reachableArea = imageArea.insetBy(dx: sideGap, dy: 0)
    let excludedArea = NSBezierPath(rect: imageArea)
    excludedArea.append(NSBezierPath(roundedRect: reachableArea,
                                    xRadius: panelCornerRadius, yRadius: panelCornerRadius))
    excludedArea.windingRule = .evenOdd
    NSColor.black.withAlphaComponent(0.32).setFill()
    excludedArea.fill()

    let titlebar = titlebarFrame
    NSColor(calibratedWhite: 0.24, alpha: 1).setFill()
    titlebar.fill()
    let diameter = 12 * previewScale
    let colors = [NSColor(calibratedRed: 1, green: 0.37, blue: 0.34, alpha: 1),
                  NSColor(calibratedRed: 1, green: 0.74, blue: 0.18, alpha: 1),
                  NSColor(calibratedRed: 0.16, green: 0.79, blue: 0.25, alpha: 1)]
    for (index, color) in colors.enumerated() {
      color.setFill()
      NSBezierPath(ovalIn: NSRect(
        x: titlebar.minX + (12 + CGFloat(index) * 20) * previewScale,
        y: titlebar.midY - diameter / 2, width: diameter, height: diameter)).fill()
    }

    let rect = panelFrame
    NSColor(calibratedWhite: 0.12, alpha: 0.88).setFill()
    NSBezierPath(roundedRect: rect, xRadius: panelCornerRadius, yRadius: panelCornerRadius).fill()
    guard rect.width > 0, rect.height > 0 else {
      return
    }
    drawController(in: rect)
  }

  /// Preview scaling must not change panel geometry units.
  private func drawController(in rect: NSRect) {
    let adaptive = FloatingOSCScale.factor(for: referenceSize)
    let scale = previewScale
    let topInset = (controllerAppearance.compact ? FloatingOSCMetrics.compactTopInset : FloatingOSCMetrics.topInset) * adaptive
    let topY = rect.maxY - (topInset + 12 * adaptive) * scale
    func image(_ image: NSImage?, center: NSPoint, size: CGFloat) {
      let length = size * adaptive * scale
      image?.tinted(.white).draw(in: NSRect(x: center.x - length / 2, y: center.y - length / 2, width: length, height: length))
    }
    for (index, transportImage) in controllerAppearance.transportImages.enumerated() {
      image(transportImage,
        center: NSPoint(x: rect.midX + CGFloat(index - 1) * 48 * adaptive * scale, y: topY), size: 20)
    }
    image(NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil),
      center: NSPoint(x: rect.minX + 28 * adaptive * scale, y: topY), size: 14)
    let volume = NSBezierPath()
    volume.lineWidth = 3 * adaptive * scale
    NSColor.white.withAlphaComponent(0.4).setStroke()
    volume.move(to: NSPoint(x: rect.minX + 44 * adaptive * scale, y: topY))
    volume.line(to: NSPoint(x: rect.minX + 110 * adaptive * scale, y: topY))
    volume.stroke()
    NSColor.white.setFill()
    let knob = 10 * adaptive * scale
    NSBezierPath(ovalIn: NSRect(x: rect.minX + 90 * adaptive * scale, y: topY - knob / 2, width: knob, height: knob)).fill()
    for (index, toolbarImage) in controllerAppearance.toolbarImages.enumerated() {
      image(toolbarImage, center: NSPoint(x: rect.maxX - (24 + CGFloat(controllerAppearance.toolbarImages.count - 1 - index) * 24) * adaptive * scale, y: topY), size: 14)
    }
    let bottomInset = (controllerAppearance.compact ? FloatingOSCMetrics.compactBottomInset : FloatingOSCMetrics.bottomInset) * adaptive
    let timelineY = rect.minY + (bottomInset + FloatingOSCMetrics.sliderVerticalInset + controllerAppearance.sliderHeight / 2) * scale
    let font = NSFont.monospacedDigitSystemFont(ofSize: max(10, 11 * adaptive) * scale, weight: .regular)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.7)]
    let timeWidth = 46 * adaptive * scale
    let leftX = rect.minX + 10 * adaptive * scale
    let rightX = rect.maxX - (10 * adaptive * scale + timeWidth)
    for (text, x) in [("00:00", leftX), ("−00:00", rightX)] {
      (text as NSString).draw(at: NSPoint(x: x, y: timelineY - font.pointSize / 2), withAttributes: attributes)
    }
    let timeline = NSBezierPath()
    timeline.lineWidth = 2 * scale
    NSColor.white.withAlphaComponent(0.45).setStroke()
    timeline.move(to: NSPoint(x: leftX + timeWidth + 2 * adaptive * scale, y: timelineY))
    timeline.line(to: NSPoint(x: rightX - 2 * adaptive * scale, y: timelineY))
    timeline.stroke()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: leftX + timeWidth + 12 * scale, y: timelineY - 7 * scale,
                                   width: 3 * scale, height: 14 * scale), xRadius: scale, yRadius: scale).fill()
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    guard panelFrame.contains(point) else { return }
    dragOffset = NSPoint(x: point.x - panelFrame.minX, y: point.y - panelFrame.minY)
    window?.invalidateCursorRects(for: self)
    NSCursor.closedHand.set()
  }

  override func mouseDragged(with event: NSEvent) {
    guard let dragOffset, bounds.width > 0, bounds.height > 0 else { return }
    let absolute = convert(event.locationInWindow, from: nil)
    let point = NSPoint(x: absolute.x - canvasFrame.minX, y: absolute.y - canvasFrame.minY)
    let size = panelSize
    let xRange = FloatingOSCPlacement.horizontalRange(
      width: size.width, windowWidth: canvasFrame.width,
      margin: FloatingOSCPlacement.defaultMargin * previewScale)
    let yRange = FloatingOSCPlacement.verticalRange(
      height: size.height, windowHeight: canvasFrame.height,
      titlebarBottom: titlebarFrame.minY - canvasFrame.minY, margin: 0)
    let x = (point.x - dragOffset.x).clamped(to: xRange)
    let y = (point.y - dragOffset.y).clamped(to: yRange)
    position = FloatingOSCPlacement.capturing(
      frame: NSRect(origin: NSPoint(x: x, y: y), size: size), keeping: position,
      contentSize: canvasFrame.size, titlebarBottom: titlebarFrame.minY - canvasFrame.minY, pointScale: previewScale)
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
    onPositionChanged?(Double(position.horizontal.value) * (position.horizontal.unit == .percent ? 100 : 1),
                       Double(position.vertical.value) * (position.vertical.unit == .percent ? 100 : 1))
    NSCursor.closedHand.set()
  }

  override func mouseUp(with event: NSEvent) {
    guard dragOffset != nil else { return }
    dragOffset = nil
    window?.invalidateCursorRects(for: self)
    let point = convert(event.locationInWindow, from: nil)
    (panelFrame.contains(point) ? NSCursor.openHand : NSCursor.arrow).set()
  }
}
