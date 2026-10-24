import Cocoa
import CoreImage
import ImageIO

enum PositionPreviewDrawing {
  static func draw(in rect: NSRect) {
    NSColor(calibratedRed: 0.43, green: 0.80, blue: 0.98, alpha: 1).setFill()
    rect.fill()
    NSColor(calibratedRed: 0.97, green: 0.86, blue: 0.20, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: rect.minX + rect.width * 0.80, y: rect.minY + rect.height * 0.72,
                              width: rect.height * 0.17, height: rect.height * 0.17)).fill()
    mountain(in: rect, points: [(0, 0), (0, 0.38), (0.31, 0.70), (0.63, 0.31), (1, 0.50), (1, 0)],
             color: NSColor(calibratedRed: 0.20, green: 0.65, blue: 0.37, alpha: 1))
    mountain(in: rect, points: [(0, 0), (0, 0.12), (0.66, 0.62), (1, 0.27), (1, 0)],
             color: NSColor(calibratedRed: 0.08, green: 0.53, blue: 0.28, alpha: 1))
  }

  private static func mountain(in rect: NSRect, points: [(CGFloat, CGFloat)], color: NSColor) {
    let path = NSBezierPath()
    for (index, point) in points.enumerated() {
      let point = NSPoint(x: rect.minX + rect.width * point.0, y: rect.minY + rect.height * point.1)
      if index == 0 { path.move(to: point) } else { path.line(to: point) }
    }
    path.close()
    color.setFill()
    path.fill()
  }
}

/// Uses the wallpaper file, never a live desktop capture.
struct DesktopPreviewBackground {
  let image: NSImage
  private let dockImage: NSImage?
  private static let imageContext = CIContext(options: [.cacheIntermediates: false])
  // The editor measures position in visibleFrame; display chrome surrounds it.
  var visibleRegion = NSRect(x: 0, y: 0, width: 1, height: 1)

  init(image: NSImage) {
    self.image = image
    // Cache the blur once; dragging the preview must not rerun the image filter.
    if let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
      let factor = min(1, 512 / CGFloat(max(bitmap.width, bitmap.height)))
      let input = CIImage(cgImage: bitmap).transformed(by: CGAffineTransform(scaleX: factor, y: factor))
      let blurred = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 12])
      dockImage = Self.imageContext.createCGImage(blurred, from: input.extent).map {
        NSImage(cgImage: $0, size: image.size)
      }
    } else {
      dockImage = nil
    }
  }

  static func load(for screen: NSScreen) -> DesktopPreviewBackground? {
    guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048
          ] as CFDictionary) else { return nil }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? Double(thumbnail.width)
    let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? Double(thumbnail.height)
    let image = NSImage(cgImage: thumbnail, size: NSSize(width: width, height: height))
    var background = DesktopPreviewBackground(image: image)
    let full = screen.frame
    let visible = screen.visibleFrame
    if full.width > 0, full.height > 0 {
      background.visibleRegion = NSRect(x: (visible.minX - full.minX) / full.width,
        y: (visible.minY - full.minY) / full.height, width: visible.width / full.width, height: visible.height / full.height)
    }
    return background
  }

  func imageFrame(in rect: NSRect) -> NSRect {
    let factor = max(rect.width / image.size.width, rect.height / image.size.height)
    let size = NSSize(width: image.size.width * factor, height: image.size.height * factor)
    return NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                  width: size.width, height: size.height)
  }

  func draw(in rect: NSRect, frosted: Bool = false) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: rect).addClip()
    (frosted ? dockImage ?? image : image).draw(in: imageFrame(in: rect), from: .zero,
      operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    NSGraphicsContext.restoreGraphicsState()
  }

}

struct DesktopPreviewDock: Equatable {
  enum Edge { case bottom, left, right }
  let edge: Edge
  let thickness: CGFloat
  // Its length is illustrative; visibleFrame only exposes the reserved thickness.
  let length: CGFloat

  static var current: DesktopPreviewDock? {
    var result: DesktopPreviewDock?
    for screen in NSScreen.screens {
      let full = screen.frame
      let visible = screen.visibleFrame
      let margins: [(Edge, CGFloat)] = [(.bottom, visible.minY - full.minY),
        (.left, visible.minX - full.minX), (.right, full.maxX - visible.maxX)]
      for (edge, thickness) in margins where thickness > 2 {
        if thickness > (result?.thickness ?? 0) {
          let extent = edge == .bottom ? full.width : visible.height
          result = DesktopPreviewDock(edge: edge, thickness: thickness, length: extent * 0.42)
        }
      }
    }
    return result
  }
}

struct DesktopPreviewLayout {
  let scale: CGFloat
  let displayFrame: NSRect
  let workAreaFrame: NSRect
  let workAreaSize: NSSize
  let menuBarFrame: NSRect
  private let dock: DesktopPreviewDock?

  init(bounds: NSRect, availableSize: NSSize, visibleRegion: NSRect? = nil, dock: DesktopPreviewDock? = nil) {
    self.dock = dock
    let region = visibleRegion ?? NSRect(x: 0, y: 0, width: 1,
      height: availableSize.height / (availableSize.height + 24))
    let fullSize = NSSize(width: availableSize.width / region.width,
                          height: availableSize.height / region.height)
    var workArea = NSRect(x: region.minX * fullSize.width, y: region.minY * fullSize.height,
                         width: availableSize.width, height: availableSize.height)
    let menuBarHeight = max(24, fullSize.height - workArea.maxY)
    if let dock {
      // Replace the measured Dock margin before applying the shared reference, avoiding a double inset.
      workArea = NSRect(x: 0, y: 0, width: fullSize.width,
                        height: max(1, fullSize.height - menuBarHeight))
      switch dock.edge {
      case .bottom:
        let thickness = min(dock.thickness, workArea.height - 1)
        workArea.origin.y += thickness
        workArea.size.height -= thickness
      case .left, .right:
        let thickness = min(dock.thickness, workArea.width - 1)
        if dock.edge == .left { workArea.origin.x += thickness }
        workArea.size.width -= thickness
      }
    }
    workAreaSize = workArea.size
    scale = min(max(0, bounds.width - 24) / fullSize.width,
                max(0, bounds.height - 24) / fullSize.height)
    let size = NSSize(width: fullSize.width * scale, height: fullSize.height * scale)
    displayFrame = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                          width: size.width, height: size.height)
    workAreaFrame = NSRect(x: displayFrame.minX + workArea.minX * scale,
      y: displayFrame.minY + workArea.minY * scale,
      width: workArea.width * scale, height: workArea.height * scale)
    let height = menuBarHeight * scale
    menuBarFrame = NSRect(x: displayFrame.minX, y: displayFrame.maxY - height,
                         width: displayFrame.width, height: height)
  }

  func drawMenuBar() {
    NSColor(calibratedWhite: 0.12, alpha: 0.45).setFill()
    menuBarFrame.fill()
    let font = NSFont.systemFont(ofSize: max(1, menuBarFrame.height * 0.65))
    let apple = NSAttributedString(string: "\u{f8ff}", attributes: [.font: font, .foregroundColor: NSColor.white])
    apple.draw(at: NSPoint(x: menuBarFrame.minX + 12 * scale,
                          y: menuBarFrame.midY - apple.size().height / 2))
  }

  var dockFrame: NSRect? {
    if let dock {
      let thickness = dock.thickness * scale
      let inset = min(4 * scale, thickness / 4)
      guard thickness > 0 else { return nil }
      if dock.edge == .bottom {
        let width = min(dock.length * scale, displayFrame.width * 0.8)
        let y = displayFrame.minY + inset
        return NSRect(x: displayFrame.midX - width / 2, y: y,
                      width: width, height: max(0, workAreaFrame.minY - y))
      }
      let height = min(dock.length * scale, (displayFrame.height - menuBarFrame.height) * 0.8)
      let x = dock.edge == .left ? displayFrame.minX + inset : workAreaFrame.maxX
      let width = dock.edge == .left ? workAreaFrame.minX - x : displayFrame.maxX - inset - x
      return NSRect(x: x,
                    y: workAreaFrame.midY - height / 2, width: width, height: height)
    }
    let bottom = max(0, workAreaFrame.minY - displayFrame.minY)
    let left = max(0, workAreaFrame.minX - displayFrame.minX)
    let right = max(0, displayFrame.maxX - workAreaFrame.maxX)
    let thickness = max(bottom, max(left, right))
    guard scale > 0, thickness > 2 * scale else { return nil }
    let inset = min(4 * scale, thickness / 4)
    if bottom >= max(left, right) {
      let width = displayFrame.width * 0.42
      return NSRect(x: displayFrame.midX - width / 2, y: displayFrame.minY + inset,
                    width: width, height: bottom - inset)
    }
    let height = workAreaFrame.height * 0.42
    return NSRect(x: left >= right ? displayFrame.minX + inset : workAreaFrame.maxX,
                  y: workAreaFrame.midY - height / 2, width: thickness - inset, height: height)
  }

  func drawDock(background: DesktopPreviewBackground? = nil) {
    guard let dockFrame else { return }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let radius = min(dockFrame.width, dockFrame.height) * 0.28
    let shape = NSBezierPath(roundedRect: dockFrame, xRadius: radius, yRadius: radius)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
    shadow.shadowBlurRadius = 4
    shadow.shadowOffset = NSSize(width: 0, height: -1)
    shadow.set()
    let context = NSGraphicsContext.current?.cgContext
    context?.beginTransparencyLayer(auxiliaryInfo: nil)
    defer { context?.endTransparencyLayer() }
    shape.addClip()
    background?.draw(in: displayFrame, frosted: true)
    NSColor(calibratedWhite: 0.24, alpha: 0.82).setFill()
    dockFrame.fill()
    NSGradient(starting: NSColor.white.withAlphaComponent(0.06),
               ending: NSColor.black.withAlphaComponent(0.03))?.draw(in: dockFrame, angle: -90)
  }
}

/// Preview-only dimensions. Changing these never edits a saved position.
struct PositionPreviewContext {
  let title: String
  let size: NSSize
  var minimumSize: NSSize = .zero
  var desktopBackground: DesktopPreviewBackground? = nil
  var identifier: String? = nil
}

final class PositionPreviewContextSelector: NSView, NSTextFieldDelegate {
  private let helper = SettingsUIHelper.sharedUI
  private let choice = NSPopUpButton()
  private let widthInput = PositionSettingsTextField()
  private let heightInput = PositionSettingsTextField()
  private var customFields: NSStackView!
  private var contexts: [PositionPreviewContext] = []
  private var customSize = NSSize(width: 1280, height: 720)
  var onSizeChanged: ((NSSize) -> Void)?
  var customSizeLimits: (minimum: NSSize, maximum: NSSize)?
  private(set) var selectedDesktopBackground: DesktopPreviewBackground?
  private(set) var selectedSize = NSSize(width: 1280, height: 720)
  private(set) var minimumSize: NSSize = .zero
  private var baseMinimumSize: NSSize = .zero
  private var selectionPersistenceKey: String?
  private var isConfiguring = false
  // Match the saved OSC point-offset limit so dragged positions remain decodable.
  private static let maximumCustomDimension = 100_000.0

  init() {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    choice.bezelStyle = .accessoryBarAction
    choice.controlSize = .small
    choice.size(width: 200)
    choice.setAccessibilityLabel(helper.localized("previewContext.label"))
    choice.target = self
    choice.action = #selector(selectionChanged)
    for (input, key) in [(widthInput, "$Width"), (heightInput, "$Height")] {
      input.translatesAutoresizingMaskIntoConstraints = false
      input.size(width: 55)
      input.delegate = self
      input.isValid = { [weak self, weak input] in
        guard let self, let input else { return false }
        return self.value(input) != nil
      }
      input.normalizedInput = { [weak self, weak input] text in
        guard let self, let input, let limits = self.customSizeLimits else { return nil }
        guard let value = PositionSettingsTextField.number(text, allowsFractions: false) else { return nil }
        let width = input === self.widthInput
        let lower = width ? limits.minimum.width : limits.minimum.height
        let upper = width ? limits.maximum.width : limits.maximum.height
        return String(Int(min(max(value, Double(lower)), Double(upper))))
      }
      input.setAccessibilityLabel(helper.localized("previewContext.label") + " " + helper.localized(key))
      let formatter = PositionSettingsNumberFormatter()
      formatter.numberStyle = .none
      formatter.allowsFloats = false
      formatter.minimum = 1
      formatter.maximum = NSNumber(value: Self.maximumCustomDimension)
      input.formatter = formatter
    }
    customFields = helper.hStack(spacing: 6, helper.label("$Width"), widthInput,
      helper.label("$Height"), heightInput, helper.label("oscPosition.points"))
    let label = helper.label("previewContext.label")
    label.stringValue += ":"
    let row = helper.hStack(spacing: 8, label, choice, customFields, helper.flexibleSpace())
    row.detachesHiddenViews = true
    addSubview(row)
    row.padding(.all(0))
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(_ contexts: [PositionPreviewContext], selected: Int = 0, minimumSize: NSSize = .zero,
                 rememberSelectionUnder key: String? = nil) {
    isConfiguring = true
    defer { isConfiguring = false }
    selectionPersistenceKey = key
    for input in [widthInput, heightInput] {
      (input.formatter as? PositionSettingsNumberFormatter)?.isPartialStringValidationEnabled = customSizeLimits != nil
    }
    if customSizeLimits == nil {
      widthInput.normalizedInput = nil
      heightInput.normalizedInput = nil
    }
    baseMinimumSize = minimumSize
    self.minimumSize = minimumSize
    self.contexts = contexts.isEmpty ? [PositionPreviewContext(title: helper.localized("previewContext.window"), size: NSSize(width: 1280, height: 720))] : contexts
    let contexts = self.contexts
    choice.removeAllItems()
    contexts.forEach { choice.menu?.addItem(NSMenuItem(title: $0.title, action: nil, keyEquivalent: "")) }
    choice.addItem(withTitle: helper.localized("previewContext.custom"))
    var index = min(max(0, selected), max(0, contexts.count - 1))
    let remembered = key.flatMap { UserDefaults.standard.dictionary(forKey: $0) }
    if let identifier = remembered?["context"] as? String {
      index = identifier == "custom" ? contexts.count :
        (contexts.firstIndex { ($0.identifier ?? $0.title) == identifier } ?? index)
    }
    choice.selectItem(at: index)
    let initialContext = contexts[min(index, contexts.count - 1)]
    self.minimumSize = NSSize(width: max(minimumSize.width, initialContext.minimumSize.width),
                              height: max(minimumSize.height, initialContext.minimumSize.height))
    customSize = constrained(initialContext.size)
    if let width = remembered?["width"] as? NSNumber, let height = remembered?["height"] as? NSNumber,
       width.doubleValue.isFinite, height.doubleValue.isFinite,
       (1...Self.maximumCustomDimension).contains(width.doubleValue),
       (1...Self.maximumCustomDimension).contains(height.doubleValue) {
      customSize = constrained(NSSize(width: width.doubleValue, height: height.doubleValue))
    }
    widthInput.integerValue = Int(customSize.width.rounded())
    heightInput.integerValue = Int(customSize.height.rounded())
    widthInput.rememberValue()
    heightInput.rememberValue()
    if let limits = customSizeLimits {
      widthInput.toolTip = "\(Int(limits.minimum.width))–\(Int(limits.maximum.width)) pt"
      heightInput.toolTip = "\(Int(limits.minimum.height))–\(Int(limits.maximum.height)) pt"
    }
    selectionChanged()
  }

  @objc private func selectionChanged() {
    let custom = choice.indexOfSelectedItem == contexts.count
    customFields.isHidden = !custom
    selectedSize = custom ? customSize : contexts[choice.indexOfSelectedItem].size
    if !custom {
      selectedDesktopBackground = contexts[choice.indexOfSelectedItem].desktopBackground
      let contextMinimum = contexts[choice.indexOfSelectedItem].minimumSize
      minimumSize = NSSize(width: max(baseMinimumSize.width, contextMinimum.width), height: max(baseMinimumSize.height, contextMinimum.height))
    }
    if custom { selectedSize = constrained(customSize); customSize = selectedSize }
    onSizeChanged?(selectedSize)
    rememberSelection()
  }

  func controlTextDidChange(_ notification: Notification) {
    guard let width = value(widthInput), let height = value(heightInput) else { return }
    if let limits = customSizeLimits,
       (width < limits.minimum.width || width > limits.maximum.width ||
        height < limits.minimum.height || height > limits.maximum.height) { return }
    customSize = constrained(NSSize(width: width, height: height))
    selectedSize = customSize
    onSizeChanged?(selectedSize)
    rememberSelection()
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    guard let input = notification.object as? NSTextField else { return }
    input.integerValue = Int((input === widthInput ? customSize.width : customSize.height).rounded(.up))
  }

  private func rememberSelection() {
    guard !isConfiguring, let key = selectionPersistenceKey else { return }
    let index = choice.indexOfSelectedItem
    let identifier = index == contexts.count ? "custom" : (contexts[index].identifier ?? contexts[index].title)
    UserDefaults.standard.set(["context": identifier, "width": Double(customSize.width),
                              "height": Double(customSize.height)], forKey: key)
  }

  private func constrained(_ size: NSSize) -> NSSize {
    let minimum = NSSize(width: max(minimumSize.width, customSizeLimits?.minimum.width ?? 0),
                         height: max(minimumSize.height, customSizeLimits?.minimum.height ?? 0))
    return NSSize(width: min(max(size.width, minimum.width), customSizeLimits?.maximum.width ?? .greatestFiniteMagnitude),
                  height: min(max(size.height, minimum.height), customSizeLimits?.maximum.height ?? .greatestFiniteMagnitude))
  }

  private func value(_ input: NSTextField) -> CGFloat? {
    let text = input.currentEditor()?.string ?? input.stringValue
    guard !text.isEmpty, text.allSatisfy({ $0.wholeNumberValue != nil }),
          let value = Double(text),
          value.isFinite, value >= 1, value <= Self.maximumCustomDimension,
          value.rounded() == value else { return nil }
    return CGFloat(value)
  }
}

final class PositionSettingsPanel: NSPanel {
  private var editingField: PositionSettingsTextField? {
    guard let editor = firstResponder as? NSTextView, editor.isFieldEditor else { return nil }
    func find(in view: NSView) -> PositionSettingsTextField? {
      if let field = view as? PositionSettingsTextField, field.currentEditor() === editor { return field }
      return view.subviews.lazy.compactMap { find(in: $0) }.first
    }
    return contentView.flatMap { find(in: $0) }
  }

  override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
    if let field = editingField, responder !== field, responder !== firstResponder {
      field.finishInput()
    }
    return super.makeFirstResponder(responder)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if editingField != nil, event.keyCode == 36 || event.keyCode == 76 {
      _ = makeFirstResponder(nil)
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  override func sendEvent(_ event: NSEvent) {
    if let field = editingField {
      if event.type == .keyDown && (event.keyCode == 36 || event.keyCode == 76) {
        _ = makeFirstResponder(nil)
        return
      }
      if event.type == .leftMouseDown,
         let contentView,
         !field.bounds.contains(field.convert(event.locationInWindow, from: nil)),
         contentView.bounds.contains(contentView.convert(event.locationInWindow, from: nil)) {
        _ = makeFirstResponder(nil)
      }
    }
    super.sendEvent(event)
  }
}

final class PositionSettingsTextField: NSTextField {
  var isValid: (() -> Bool)?
  var normalizedInput: ((String) -> String?)?

  static func number(_ text: String, separator: String = ".", allowsFractions: Bool = true) -> Double? {
    var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let negative = text.first == "-"
    if text.first == "-" || text.first == "+" { text.removeFirst() }
    let parts = text.components(separatedBy: separator)
    guard !text.isEmpty, parts.count <= (allowsFractions ? 2 : 1),
          parts.contains(where: { !$0.isEmpty }),
          parts.allSatisfy({ $0.allSatisfy { $0.wholeNumberValue != nil } }) else { return nil }
    let canonical = parts.map { $0.compactMap(\.wholeNumberValue).map(String.init).joined() }.joined(separator: ".")
    guard let value = Double(canonical) else { return nil }
    return negative ? -value : value
  }
  private var originalValue = ""

  override func becomeFirstResponder() -> Bool {
    if currentEditor() == nil { originalValue = stringValue }
    return super.becomeFirstResponder()
  }

  func rememberValue() { originalValue = stringValue }

  func finishInput() {
    let text = currentEditor()?.string ?? stringValue
    guard text != originalValue else { return }
    if let normalizedInput {
      let value = normalizedInput(currentEditor()?.string ?? stringValue) ?? originalValue
      currentEditor()?.string = value
      stringValue = value
    } else if isValid?() == false {
      currentEditor()?.string = originalValue
      stringValue = originalValue
    }
    delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: self))
  }
}

final class PositionSettingsNumberFormatter: NumberFormatter, @unchecked Sendable {
  static func acceptsInput(_ text: String) -> Bool {
    var digits = 0
    var signs = 0
    for character in text {
      if character.wholeNumberValue != nil { digits += 1 }
      else if "+-.,".contains(character) { signs += 1 }
      else { return false }
      if digits > 5 || signs > 1 { return false }
    }
    return true
  }

  override func isPartialStringValid(_ partialString: String,
                                    newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
                                    errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
    Self.acceptsInput(partialString)
  }
}
