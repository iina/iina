//
//  WindowGeometrySettingsSheetController.swift
//  iina
//

import Cocoa

private let ui = SettingsUIHelper.sharedUI

class WindowGeometrySettingsSheetController: NSWindowController, NSTextFieldDelegate {
  private let preview = WindowGeometryPreviewView()
  private let previewContext = PositionPreviewContextSelector()
  private var mediaAspect: CGFloat = 16 / 9
  private var sizeGroup: NSView?
  private var positionGroup: NSView?
  private var layoutStack: NSStackView?
  private let sizeInput = PositionSettingsTextField()
  private let widthInput = PositionSettingsTextField()
  private let heightInput = PositionSettingsTextField()
  private var singleSizeFields: NSView?
  private var independentSizeFields: NSView?
  private let xInput = PositionSettingsTextField()
  private let yInput = PositionSettingsTextField()
  private lazy var sizeDimension = popup(["$Width", "$Height"])
  private lazy var sizeUnit = popup(["oscPosition.points", "oscPosition.percent"])
  private lazy var widthUnit = popup(["oscPosition.points", "oscPosition.percent"])
  private lazy var heightUnit = popup(["oscPosition.points", "oscPosition.percent"])
  private lazy var xUnit = popup(["oscPosition.points", "oscPosition.percent"])
  private lazy var yUnit = popup(["oscPosition.points", "oscPosition.percent"])
  private lazy var xAnchor = popup(["oscPosition.left", "oscPosition.right"])
  private lazy var yAnchor = popup(["oscPosition.top", "oscPosition.bottom"])
  private var draft = InitialWindowGeometry("")
  private var previewSize = NSSize(width: 1920, height: 1080)
  private var screenSize: NSSize { preview.workAreaSize(for: previewSize) }
  private var saveHandler: ((InitialWindowGeometry) -> Void)?

  init() {
    super.init(window: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func present(on parent: NSWindow, geometry: InitialWindowGeometry? = nil,
               mediaAspect: CGFloat = 16 / 9,
               onSave: ((InitialWindowGeometry) -> Void)? = nil) {
    guard parent.attachedSheet == nil else { return }
    if window == nil { loadWindow() }
    guard let window else { return }
    draft = geometry ?? InitialWindowGeometry(Preference.string(for: .initialWindowSizePosition) ?? "")
    saveHandler = onSave
    previewSize = parent.screen?.visibleFrame.size ?? NSScreen.main?.visibleFrame.size ?? NSSize(width: 1920, height: 1080)
    preview.dock = DesktopPreviewDock.current
    self.mediaAspect = mediaAspect.isFinite && mediaAspect > 0 ? mediaAspect : 16 / 9
    let oscPosition: Preference.OSCPosition = Preference.enum(for: .oscPosition)
    preview.minimumSize = oscPosition == .floating ? AppData.floatingOSCWindowMinSize : AppData.mainWindowMinSize
    preview.enforceMinimumAfterScreenFit = oscPosition == .floating
    preview.compactUI = Preference.bool(for: .compactUI)
    let screens = NSScreen.screens
    let minimum = preview.minimumSize
    let maximum = NSSize(width: max(minimum.width, screens.map { $0.visibleFrame.width }.max() ?? screenSize.width),
                         height: max(minimum.height, screens.map { $0.visibleFrame.height }.max() ?? screenSize.height))
    previewContext.customSizeLimits = (minimum, maximum)
    let choices = screens.map { PositionPreviewContext(title: $0.localizedName, size: $0.visibleFrame.size,
      desktopBackground: DesktopPreviewBackground.load(for: $0)) }
    previewContext.configure(choices.isEmpty ? [PositionPreviewContext(title: ui.localized("previewContext.display"), size: screenSize)] : choices,
      selected: screens.firstIndex(where: { $0 == parent.screen }) ?? 0, minimumSize: minimum)
    if Preference.unlockWindowAspectRatio {
      draft.prepareIndependentSize(screenSize: screenSize, aspect: self.mediaAspect, minimumSize: preview.minimumSize,
                                   enforceMinimumAfterScreenFit: preview.enforceMinimumAfterScreenFit)
    }
    singleSizeFields?.isHidden = draft.independentSize
    independentSizeFields?.isHidden = !draft.independentSize
    preview.clearInteraction()
    updateControls()
    sizeGroup?.isHidden = !draft.sizeEnabled
    positionGroup?.isHidden = !draft.positionEnabled
    if let layoutStack {
      window.contentView?.layoutSubtreeIfNeeded()
      let size = layoutStack.fittingSize
      window.setContentSize(NSSize(width: size.width + 40, height: size.height + 40))
    }
    parent.beginSheet(window) { [weak self] _ in
      self?.saveHandler = nil
      self?.preview.clearInteraction()
    }
  }

  override func loadWindow() {
    let panel = PositionSettingsPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 660),
                        styleMask: [.titled], backing: .buffered, defer: false)
    panel.title = ui.localized("windowGeometry.title")
    panel.isReleasedWhenClosed = false
    let content = NSView()
    panel.contentView = content
    window = panel

    let title = ui.label("windowGeometry.title", font: .boldSystemFont(ofSize: 16))
    previewContext.onSizeChanged = { [weak self] size in
      guard let self else { return }
      self.previewSize = size
      self.preview.desktopBackground = self.previewContext.selectedDesktopBackground
      self.preview.clearInteraction()
      self.updatePreview()
    }
    preview.onWorkAreaChanged = { [weak self] in self?.updatePreview() }
    preview.translatesAutoresizingMaskIntoConstraints = false
    preview.size(width: 560, height: 315)
    preview.onGeometryChanged = { [weak self] geometry in
      guard let self else { return }
      var configured = geometry
      configured.sizeEnabled = self.draft.sizeEnabled
      configured.positionEnabled = self.draft.positionEnabled
      self.draft = configured
      self.updateControls()
    }

    configureInput(sizeInput, label: "$InitialWindowSize")
    configureInput(widthInput, label: "$Width")
    configureInput(heightInput, label: "$Height")
    configureInput(xInput, label: "controlBarDefaultPositionHorizontal.label")
    configureInput(yInput, label: "controlBarDefaultPositionVertical.label")
    let sizeFields = ui.hStack(align: .firstBaseline, sizeDimension, sizeInput, sizeUnit)
    singleSizeFields = sizeFields
    let independentFields = NSGridView(views: [
      [ui.label("$Width"), widthInput, widthUnit],
      [ui.label("$Height"), heightInput, heightUnit]
    ])
    independentFields.rowSpacing = 8
    independentFields.columnSpacing = 8
    independentFields.rowAlignment = .firstBaseline
    independentFields.column(at: 0).xPlacement = .leading
    independentFields.column(at: 1).width = widthInput.fittingSize.width
    independentFields.column(at: 2).width = max(widthUnit.fittingSize.width, heightUnit.fittingSize.width)
    independentSizeFields = independentFields
    let rows = [
      [ui.label("controlBarDefaultPositionHorizontal.label"), xInput, xUnit, ui.label("oscPosition.from"), xAnchor],
      [ui.label("controlBarDefaultPositionVertical.label"), yInput, yUnit, ui.label("oscPosition.from"), yAnchor]
    ]
    let positionGrid = NSGridView(views: rows)
    positionGrid.rowSpacing = 8
    positionGrid.columnSpacing = 8
    positionGrid.rowAlignment = .firstBaseline
    positionGrid.column(at: 0).xPlacement = .leading
    xAnchor.size(width: 90)
    yAnchor.size(width: 90)
    for column in 1...4 {
      positionGrid.column(at: column).width = rows.map { $0[column].fittingSize.width }.max()!
    }
    positionGrid.translatesAutoresizingMaskIntoConstraints = false
    let positionFields = positionGrid
    let sizeHeading = sectionHeading("$InitialWindowSize")
    let positionHeading = sectionHeading("$InitialWindowPosition")
    let sizeGroup = ui.vStack(spacing: 8, sizeHeading, sizeFields, independentFields)
    sizeGroup.detachesHiddenViews = true
    let positionGroup = ui.vStack(spacing: 8, positionHeading, positionFields)
    self.sizeGroup = sizeGroup
    self.positionGroup = positionGroup
    sizeFields.padding(.horizontal, from: sizeGroup)
    independentFields.padding(.horizontal, from: sizeGroup)
    positionFields.padding(.horizontal, from: positionGroup)

    let cancel = ui.button("oscDefaultPosition.cancel", target: self, action: #selector(cancel))
    cancel.keyEquivalent = "\u{1b}"
    let save = ui.button("oscDefaultPosition.save", target: self, action: #selector(save))
    save.keyEquivalent = "\r"
    let reset = ui.button("oscDefaultPosition.reset", target: self, action: #selector(reset))
    let buttons = ui.hStack(reset, ui.flexibleSpace(), cancel, save)
    let stack = ui.vStack(spacing: 12, title, previewContext, preview, sizeGroup, positionGroup, buttons)
    stack.detachesHiddenViews = true
    layoutStack = stack
    content.addSubview(stack)
    stack.padding(.all(20))
    [title, previewContext, preview, sizeGroup, positionGroup, buttons].forEach {
      $0.padding(.horizontal, from: stack)
    }
    let size = stack.fittingSize
    panel.setContentSize(NSSize(width: size.width + 40, height: size.height + 40))
  }

  private func sectionHeading(_ key: String) -> NSTextField {
    let label = ui.label(key, font: .boldSystemFont(ofSize: NSFont.systemFontSize))
    label.stringValue += ":"
    return label
  }

  private func popup(_ keys: [String]) -> NSPopUpButton {
    let popup = NSPopUpButton()
    popup.translatesAutoresizingMaskIntoConstraints = false
    popup.bezelStyle = .accessoryBarAction
    popup.controlSize = .small
    popup.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    for (tag, key) in keys.enumerated() {
      let item = NSMenuItem(title: ui.localized(key), action: nil, keyEquivalent: "")
      item.tag = tag
      popup.menu!.addItem(item)
    }
    popup.target = self
    popup.action = #selector(controlChanged(_:))
    return popup
  }

  private func configureInput(_ input: NSTextField, label: String) {
    input.translatesAutoresizingMaskIntoConstraints = false
    input.size(width: 72)
    input.delegate = self
    (input as? PositionSettingsTextField)?.isValid = { [weak self, weak input] in
      guard let self, let input else { return false }
      return self.validValue(input) != nil
    }
    input.setAccessibilityLabel(ui.localized(label))
    (input as? PositionSettingsTextField)?.normalizedInput = { [weak self, weak input] text in
      guard let self, let input,
            let value = PositionSettingsTextField.number(text, allowsFractions: false) else { return nil }
      let range = self.inputRange(input)
      return String(Int(min(max(value, Double(range.lowerBound)), Double(range.upperBound))))
    }
    input.formatter = WindowGeometryIntegerFormatter()
  }

  private func inputRange(_ input: NSTextField) -> ClosedRange<Int> {
    let horizontal = input === widthInput || input === xInput || (input === sizeInput && draft.sizeDimension == .width)
    let extent = max(1, horizontal ? screenSize.width : screenSize.height)
    let unit: InitialWindowGeometry.Unit
    if input === sizeInput { unit = draft.sizeUnit }
    else if input === widthInput { unit = draft.widthUnit }
    else if input === heightInput { unit = draft.heightUnit }
    else if input === xInput { unit = draft.xUnit }
    else { unit = draft.yUnit }
    if input === xInput || input === yInput {
      if unit == .percent { return 0...100 }
      let frame = draft.previewFrame(screenSize: screenSize, aspect: mediaAspect, minimumSize: preview.minimumSize,
                                     enforceMinimumAfterScreenFit: preview.enforceMinimumAfterScreenFit)
      return 0...max(0, Int(ceil(extent - (horizontal ? frame.width : frame.height))))
    }
    var lower = horizontal ? preview.minimumSize.width : preview.minimumSize.height
    var upper = extent
    if !draft.independentSize {
      let aspect = mediaAspect
      let required = horizontal ? max(lower, preview.minimumSize.height * aspect)
                                : max(lower, preview.minimumSize.width / aspect)
      upper = min(upper, horizontal ? screenSize.height * aspect : screenSize.width / aspect)
      // Extremely narrow references use the player's existing letterboxing fallback.
      upper = max(lower, upper)
      lower = min(required, upper)
    }
    if unit == .percent {
      let minimum = min(100, max(1, Int(ceil(lower / extent * 100))))
      return minimum...max(minimum, min(100, Int(floor(upper / extent * 100))))
    }
    let minimum = max(1, Int(ceil(lower)))
    return minimum...max(minimum, Int(floor(upper)))
  }

  private func validValue(_ input: NSTextField) -> Int? {
    guard let value = WindowGeometryIntegerFormatter.value(from: input.currentEditor()?.string ?? input.stringValue) else { return nil }
    let unit: InitialWindowGeometry.Unit
    if input === sizeInput { unit = draft.sizeUnit }
    else if input === widthInput { unit = draft.widthUnit }
    else if input === heightInput { unit = draft.heightUnit }
    else if input === xInput { unit = draft.xUnit }
    else { unit = draft.yUnit }
    if unit == .percent && value > 100 { return nil }
    if input.currentEditor() != nil && !inputRange(input).contains(value) { return nil }
    if (input === widthInput || input === heightInput) && value == 0 { return nil }
    return value
  }

  func controlTextDidChange(_ notification: Notification) {
    guard let input = notification.object as? NSTextField, let value = validValue(input) else { return }
    if input === sizeInput { draft.sizeValue = value }
    else if input === widthInput { draft.widthValue = value }
    else if input === heightInput { draft.heightValue = value }
    else if input === xInput { draft.xValue = value }
    else if input === yInput { draft.yValue = value }
    updatePreview()
  }

  @objc private func controlChanged(_ sender: NSControl) {
    if draft.independentSize {
      draft.widthUnit = InitialWindowGeometry.Unit(rawValue: widthUnit.selectedTag())!
      draft.heightUnit = InitialWindowGeometry.Unit(rawValue: heightUnit.selectedTag())!
    } else {
      draft.sizeDimension = InitialWindowGeometry.SizeDimension(rawValue: sizeDimension.selectedTag())!
      draft.sizeUnit = InitialWindowGeometry.Unit(rawValue: sizeUnit.selectedTag())!
    }
    draft.xUnit = InitialWindowGeometry.Unit(rawValue: xUnit.selectedTag())!
    draft.yUnit = InitialWindowGeometry.Unit(rawValue: yUnit.selectedTag())!
    draft.xAnchor = InitialWindowGeometry.HorizontalAnchor(rawValue: xAnchor.selectedTag())!
    draft.yAnchor = InitialWindowGeometry.VerticalAnchor(rawValue: yAnchor.selectedTag())!
    func bounded(_ value: Int, input: NSTextField) -> Int { value.clamped(to: inputRange(input)) }
    if sender === sizeUnit || sender === sizeDimension { draft.sizeValue = bounded(draft.sizeValue, input: sizeInput) }
    if sender === widthUnit { draft.widthValue = bounded(draft.widthValue, input: widthInput) }
    if sender === heightUnit { draft.heightValue = bounded(draft.heightValue, input: heightInput) }
    if sender === xUnit { draft.xValue = bounded(draft.xValue, input: xInput) }
    if sender === yUnit { draft.yValue = bounded(draft.yValue, input: yInput) }
    preview.clearInteraction()
    updateControls()
  }

  private func updateControls() {
    sizeDimension.selectItem(withTag: draft.sizeDimension.rawValue)
    sizeUnit.selectItem(withTag: draft.sizeUnit.rawValue)
    widthUnit.selectItem(withTag: draft.widthUnit.rawValue)
    heightUnit.selectItem(withTag: draft.heightUnit.rawValue)
    xUnit.selectItem(withTag: draft.xUnit.rawValue)
    yUnit.selectItem(withTag: draft.yUnit.rawValue)
    xAnchor.selectItem(withTag: draft.xAnchor.rawValue)
    yAnchor.selectItem(withTag: draft.yAnchor.rawValue)
    sizeInput.stringValue = String(draft.sizeValue)
    widthInput.stringValue = String(draft.widthValue)
    heightInput.stringValue = String(draft.heightValue)
    xInput.stringValue = String(draft.xValue)
    yInput.stringValue = String(draft.yValue)
    [sizeInput, widthInput, heightInput, xInput, yInput].forEach { $0.rememberValue() }
    updatePreview()
  }

  private func updatePreview() {
    preview.setGeometry(draft, screenSize: previewSize, aspect: mediaAspect)
    let frame = draft.previewFrame(screenSize: screenSize, aspect: mediaAspect, minimumSize: preview.minimumSize,
                                   enforceMinimumAfterScreenFit: preview.enforceMinimumAfterScreenFit)
    for input in [sizeInput, widthInput, heightInput, xInput, yInput] {
      let range = inputRange(input)
      input.toolTip = "\(range.lowerBound)–\(range.upperBound)"
    }
    xInput.isEnabled = frame.width < screenSize.width - 0.01
    yInput.isEnabled = frame.height < screenSize.height - 0.01
  }

  @objc private func reset() {
    sizeInput.abortEditing()
    widthInput.abortEditing()
    heightInput.abortEditing()
    xInput.abortEditing()
    yInput.abortEditing()
    let sizeEnabled = draft.sizeEnabled
    let positionEnabled = draft.positionEnabled
    let independentSize = draft.independentSize
    draft = InitialWindowGeometry("")
    draft.sizeEnabled = sizeEnabled
    draft.positionEnabled = positionEnabled
    if independentSize {
      draft.prepareIndependentSize(screenSize: screenSize, aspect: mediaAspect, minimumSize: preview.minimumSize,
                                   enforceMinimumAfterScreenFit: preview.enforceMinimumAfterScreenFit)
    }
    preview.clearInteraction()
    updateControls()
  }

  @objc private func save() {
    guard window?.makeFirstResponder(nil) == true else { return }
    if draft.sizeEnabled, draft.independentSize {
      guard let width = validValue(widthInput), let height = validValue(heightInput), width > 0, height > 0 else { return }
      draft.widthValue = width
      draft.heightValue = height
    }
    guard let window,
          let size = draft.sizeEnabled && !draft.independentSize ? validValue(sizeInput) : draft.sizeValue,
          let x = draft.positionEnabled ? validValue(xInput) : draft.xValue,
          let y = draft.positionEnabled ? validValue(yInput) : draft.yValue else { return }
    draft.sizeValue = size
    draft.xValue = x
    draft.yValue = y
    let handler = saveHandler
    saveHandler = nil
    if let handler { handler(draft) }
    else { Preference.set(draft.geometryString, for: .initialWindowSizePosition) }
    preview.clearInteraction()
    window.sheetParent?.endSheet(window, returnCode: .OK)
  }

  @objc private func cancel() {
    guard let window else { return }
    saveHandler = nil
    preview.clearInteraction()
    window.sheetParent?.endSheet(window, returnCode: .cancel)
  }
}

private class WindowGeometryIntegerFormatter: Formatter {
  override func isPartialStringValid(_ partialString: String,
                                    newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
                                    errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
    PositionSettingsNumberFormatter.acceptsInput(partialString)
  }

  static func value(from text: String) -> Int? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let digits = text.compactMap(\.wholeNumberValue)
    guard !text.isEmpty, digits.count == text.count,
          text.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) else { return nil }
    return Int(digits.map(String.init).joined())
  }

  override func string(for object: Any?) -> String? {
    if let number = object as? NSNumber { return number.stringValue }
    return object as? String
  }

  override func getObjectValue(_ object: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
                               for string: String,
                               errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
    guard let value = Self.value(from: string) else { return false }
    object?.pointee = NSNumber(value: value)
    return true
  }
}

class WindowGeometryPreviewView: NSView {
  var minimumSize = AppData.mainWindowMinSize
  var enforceMinimumAfterScreenFit = false
  var compactUI = false
  var titlebarHeight: CGFloat {
    let compactHeight: CGFloat = if #available(macOS 26, *) { 32 } else { 28 }
    return compactHeight + (compactUI ? 0 : 8)
  }
  var desktopBackground: DesktopPreviewBackground? { didSet { needsDisplay = true } }
  var dock: DesktopPreviewDock? = DesktopPreviewDock.current
  var onWorkAreaChanged: (() -> Void)?
  var onGeometryChanged: ((InitialWindowGeometry) -> Void)?
  private var geometry = InitialWindowGeometry("")
  private var availableSize = NSSize(width: 1920, height: 1080)
  private var screenSize: NSSize { desktopLayout.workAreaSize }

  private enum Interaction {
    case move(offset: NSPoint)
    case resize(frame: NSRect, point: NSPoint, edges: ResizeEdges)
  }
  private struct ResizeEdges: OptionSet {
    let rawValue: Int
    static let left = ResizeEdges(rawValue: 1)
    static let right = ResizeEdges(rawValue: 2)
    static let bottom = ResizeEdges(rawValue: 4)
    static let top = ResizeEdges(rawValue: 8)
  }
  private var interaction: Interaction?
  private var resizingFrame: NSRect?
  private var mediaAspect: CGFloat = 16 / 9

  private var desktopLayout: DesktopPreviewLayout {
    DesktopPreviewLayout(bounds: bounds, availableSize: availableSize,
                         visibleRegion: desktopBackground?.visibleRegion, dock: dock)
  }

  func workAreaSize(for availableSize: NSSize) -> NSSize {
    DesktopPreviewLayout(bounds: bounds, availableSize: availableSize,
                         visibleRegion: desktopBackground?.visibleRegion, dock: dock).workAreaSize
  }

  private var scale: CGFloat { desktopLayout.scale }
  private var screenFrame: NSRect { desktopLayout.workAreaFrame }

  private var windowFrame: NSRect {
    let frame = physicalWindowFrame
    return NSRect(x: screenFrame.minX + frame.minX * scale, y: screenFrame.minY + frame.minY * scale,
                  width: frame.width * scale, height: frame.height * scale)
  }

  private var physicalWindowFrame: NSRect {
    resizingFrame ?? resolvedWindowFrame
  }

  private var resolvedWindowFrame: NSRect {
    geometry.previewFrame(screenSize: screenSize, aspect: mediaAspect, minimumSize: minimumSize,
                          enforceMinimumAfterScreenFit: enforceMinimumAfterScreenFit)
  }

  private func resizeEdges(at point: NSPoint) -> ResizeEdges {
    let frame = windowFrame
    guard frame.insetBy(dx: -4, dy: -4).contains(point) else { return [] }
    var edges: ResizeEdges = []
    if abs(point.x - frame.minX) <= 6 { edges.insert(.left) }
    else if abs(point.x - frame.maxX) <= 6 { edges.insert(.right) }
    if abs(point.y - frame.minY) <= 6 { edges.insert(.bottom) }
    else if abs(point.y - frame.maxY) <= 6 { edges.insert(.top) }
    return edges
  }

  private var resizeHandle: NSRect {
    NSRect(x: resizesFromLeft ? windowFrame.minX : windowFrame.maxX - 16,
           y: resizesFromTop ? windowFrame.maxY - 16 : windowFrame.minY, width: 16, height: 16)
  }

  private var resizesFromLeft: Bool {
    geometry.positionEnabled && geometry.xUnit == .points && geometry.xAnchor == .right
  }

  private var resizesFromTop: Bool {
    geometry.positionEnabled && geometry.yUnit == .points && geometry.yAnchor == .bottom
  }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.cornerRadius = 8
    layer?.masksToBounds = true
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    setAccessibilityLabel(ui.localized("windowGeometry.preview"))
    NotificationCenter.default.addObserver(self, selector: #selector(refreshDockPreview),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
  }

  convenience init() {
    self.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func refreshDockPreview() {
    dock = DesktopPreviewDock.current
    clearInteraction()
    onWorkAreaChanged?()
    needsDisplay = true
  }

  func setGeometry(_ geometry: InitialWindowGeometry, screenSize: NSSize, aspect: CGFloat = 16 / 9) {
    mediaAspect = aspect.isFinite && aspect > 0 ? aspect : 16 / 9
    self.geometry = geometry
    availableSize = NSSize(width: max(1, screenSize.width), height: max(1, screenSize.height))
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
  }

  func clearInteraction() {
    if case .move? = interaction { NSCursor.arrow.set() }
    interaction = nil
    resizingFrame = nil
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
  }

  private var handleEdges: ResizeEdges {
    [resizesFromLeft ? .left : .right, resizesFromTop ? .top : .bottom]
  }

  private func cornerCursor(_ edges: ResizeEdges) -> NSCursor {
    let rising = edges.contains(.left) == edges.contains(.bottom)
    return rising ? ResizeCursor.rising : ResizeCursor.falling
  }

  override func resetCursorRects() {
    if case .move? = interaction {
      addCursorRect(bounds, cursor: .closedHand)
      return
    }
    if geometry.positionEnabled { addCursorRect(windowFrame, cursor: .openHand) }
    if geometry.sizeEnabled {
      if geometry.independentSize {
        let frame = windowFrame
        for x in [frame.minX - 4, frame.maxX - 6] {
          addCursorRect(NSRect(x: x, y: frame.minY, width: 10, height: frame.height), cursor: ResizeCursor.horizontal)
        }
        for y in [frame.minY - 4, frame.maxY - 6] {
          addCursorRect(NSRect(x: frame.minX, y: y, width: frame.width, height: 10), cursor: ResizeCursor.vertical)
        }
        for left in [true, false] {
          for top in [true, false] {
            let edges: ResizeEdges = [left ? .left : .right, top ? .top : .bottom]
            addCursorRect(NSRect(x: left ? frame.minX - 4 : frame.maxX - 6,
                                 y: top ? frame.maxY - 6 : frame.minY - 4, width: 10, height: 10),
                          cursor: cornerCursor(edges))
          }
        }
      }
      addCursorRect(resizeHandle, cursor: cornerCursor(handleEdges))
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    NSGraphicsContext.saveGraphicsState()
    let desktop = desktopLayout
    NSBezierPath(roundedRect: desktop.displayFrame, xRadius: 6, yRadius: 6).addClip()
    if let desktopBackground {
      desktopBackground.draw(in: desktop.displayFrame)
    } else {
      NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
      desktop.displayFrame.fill()
    }
    desktop.drawMenuBar()
    NSGraphicsContext.restoreGraphicsState()
    let frame = windowFrame
    NSGraphicsContext.saveGraphicsState()
    let cornerRadius: CGFloat = if #available(macOS 26, *) { 12 } else { 6 }
    NSBezierPath(roundedRect: frame, xRadius: cornerRadius * scale, yRadius: cornerRadius * scale).addClip()
    NSColor.black.setFill()
    frame.fill()
    let barHeight = min(frame.height, titlebarHeight * scale)
    let bar = NSRect(x: frame.minX, y: frame.maxY - barHeight, width: frame.width, height: barHeight)
    // Match the edge-to-edge player: the titlebar overlays the fitted video.
    let content = frame
    let videoWidth = min(content.width, content.height * mediaAspect)
    let video = NSRect(x: content.midX - videoWidth / 2, y: content.midY - videoWidth / mediaAspect / 2,
                       width: videoWidth, height: videoWidth / mediaAspect)
    PositionPreviewDrawing.draw(in: video)
    NSColor(calibratedWhite: 0.18, alpha: 0.9).setFill()
    bar.fill()
    for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
      color.setFill()
      let diameter = 12 * scale
      NSBezierPath(ovalIn: NSRect(x: frame.minX + (12 + CGFloat(index) * 20) * scale,
                                y: bar.midY - diameter / 2, width: diameter, height: diameter)).fill()
    }
    if geometry.sizeEnabled {
      NSColor.white.setStroke()
      let handle = NSBezierPath()
      handle.lineWidth = 1.5
      let corner = NSPoint(x: resizesFromLeft ? frame.minX : frame.maxX,
                           y: resizesFromTop ? frame.maxY : frame.minY)
      let dx: CGFloat = resizesFromLeft ? 1 : -1
      let dy: CGFloat = resizesFromTop ? -1 : 1
      for length in [CGFloat(7), CGFloat(11)] {
        handle.move(to: NSPoint(x: corner.x + dx * length, y: corner.y + dy * 4))
        handle.line(to: NSPoint(x: corner.x + dx * 4, y: corner.y + dy * length))
      }
      handle.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: desktop.displayFrame, xRadius: 6, yRadius: 6).addClip()
    desktop.drawDock(background: desktopBackground)
    NSGraphicsContext.restoreGraphicsState()
  }

  override func mouseDown(with event: NSEvent) {
    clearInteraction()
    let point = convert(event.locationInWindow, from: nil)
    guard scale > 0 else { return }
    let edges = resizeHandle.contains(point) ? handleEdges : resizeEdges(at: point)
    if geometry.sizeEnabled, !edges.isEmpty, geometry.independentSize || resizeHandle.contains(point) {
      interaction = .resize(frame: physicalWindowFrame, point: screenPoint(point), edges: edges)
    } else if geometry.positionEnabled {
      guard windowFrame.contains(point) else { return }
      interaction = .move(offset: NSPoint(x: point.x - windowFrame.minX, y: point.y - windowFrame.minY))
      window?.invalidateCursorRects(for: self)
      NSCursor.closedHand.set()
    }
  }

  private func screenPoint(_ point: NSPoint) -> NSPoint {
    NSPoint(x: (point.x - screenFrame.minX) / scale, y: (point.y - screenFrame.minY) / scale)
  }

  override func mouseDragged(with event: NSEvent) {
    guard let interaction, scale > 0 else { return }
    let point = convert(event.locationInWindow, from: nil)
    switch interaction {
    case .move(let offset):
      guard geometry.positionEnabled else { return }
      let frame = physicalWindowFrame
      var origin = screenPoint(NSPoint(x: point.x - offset.x, y: point.y - offset.y))
      origin.x = origin.x.clamped(to: 0...max(0, screenSize.width - frame.width))
      origin.y = origin.y.clamped(to: 0...max(0, screenSize.height - frame.height))
      geometry.movePreview(to: origin, screenSize: screenSize,
                           windowSize: frame.size)
    case .resize(let frame, let start, let edges):
      guard geometry.sizeEnabled else { return }
      let current = screenPoint(point)
      let horizontal = !edges.intersection([.left, .right]).isEmpty
      let vertical = !edges.intersection([.bottom, .top]).isEmpty
      let centered = event.modifierFlags.contains(.option) || !geometry.positionEnabled
      let multiplier: CGFloat = centered ? 2 : 1
      let maxWidth = centered ? 2 * min(frame.midX, screenSize.width - frame.midX)
        : (edges.contains(.left) ? frame.maxX : screenSize.width - frame.minX)
      let maxHeight = centered ? 2 * min(frame.midY, screenSize.height - frame.midY)
        : (edges.contains(.bottom) ? frame.maxY : screenSize.height - frame.minY)
      var size = frame.size
      if horizontal {
        size.width += (current.x - start.x) * (edges.contains(.left) ? -1 : 1) * multiplier
      }
      if vertical {
        size.height += (current.y - start.y) * (edges.contains(.bottom) ? -1 : 1) * multiplier
      }
      if geometry.independentSize {
        size.width = size.width.clamped(to: min(minimumSize.width, maxWidth)...maxWidth)
        size.height = size.height.clamped(to: min(minimumSize.height, maxHeight)...maxHeight)
      } else {
        let maxLockedWidth = min(maxWidth, maxHeight * mediaAspect)
        let minLockedWidth = min(maxLockedWidth, max(minimumSize.width, minimumSize.height * mediaAspect))
        let width = geometry.sizeDimension == .width ? size.width : size.height * mediaAspect
        size.width = width.clamped(to: minLockedWidth...maxLockedWidth)
        size.height = size.width / mediaAspect
      }
      let oldWidth = geometry.widthValue
      let oldHeight = geometry.heightValue
      geometry.resizePreview(to: size, screenSize: screenSize)
      if geometry.independentSize {
        if !horizontal { geometry.widthValue = oldWidth }
        if !vertical { geometry.heightValue = oldHeight }
      }
      func anchoredFrame(size: NSSize) -> NSRect {
        var origin = frame.origin
        if centered {
          origin = NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
        } else {
          if edges.contains(.left) { origin.x = frame.maxX - size.width }
          if edges.contains(.bottom) { origin.y = frame.maxY - size.height }
        }
        return NSRect(origin: origin, size: size)
      }
      // Keep integer percentage rounding out of the active drag's drawing coordinates.
      resizingFrame = anchoredFrame(size: size)
      let resolvedFrame = anchoredFrame(size: resolvedWindowFrame.size)
      if geometry.positionEnabled {
        geometry.movePreview(to: resolvedFrame.origin, screenSize: screenSize, windowSize: resolvedFrame.size)
      }
    }
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
    onGeometryChanged?(geometry)
    if case .move? = self.interaction { NSCursor.closedHand.set() }
  }

  override func mouseUp(with event: NSEvent) {
    let wasMoving: Bool
    if case .move? = interaction { wasMoving = true } else { wasMoving = false }
    clearInteraction()
    if wasMoving {
      let point = convert(event.locationInWindow, from: nil)
      (geometry.positionEnabled && windowFrame.contains(point) ? NSCursor.openHand : NSCursor.arrow).set()
    }
  }
}
