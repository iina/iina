import Darwin
setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var checks = 0
var failures = 0
func check(_ result: @autoclosure () -> Bool, _ description: String) {
  checks += 1
  if result() { print("PASS: \(description)") }
  else { failures += 1; print("FAIL: \(description)") }
}
func near(_ value: Double, _ expected: Double) -> Bool { abs(value - expected) < 0.025 }
if CommandLine.arguments.contains("--verify-persistence") {
  check(near(Double(Preference.floatingOSCDefaultPosition.horizontal.value * 100), 37.25), "default horizontal persists into second isolated process")
  check(near(Double(Preference.floatingOSCDefaultPosition.vertical.value), 22.5) && Preference.floatingOSCDefaultPosition.vertical.unit == .point && Preference.floatingOSCDefaultPosition.vertical.edge == .far, "point value, unit and bottom anchor persist into second isolated process")
  check(near(Double(Preference.float(for: .controlBarPositionHorizontal)), 0.74), "current horizontal persists unchanged")
  check(near(Double(Preference.float(for: .controlBarPositionVertical)), 0.61), "current vertical persists unchanged")
  let restoredPreview = PositionPreviewContextSelector()
  restoredPreview.configure([PositionPreviewContext(title: "Standard", size: OSCPositionSettingsSheetController.standardPreviewSize,
    minimumSize: FloatingOSCMetrics.minimumWindowSize, identifier: "standard")],
    rememberSelectionUnder: OSCPositionSettingsSheetController.previewContextPersistenceKey)
  check(restoredPreview.selectedSize == NSSize(width: 900, height: 1600), "Custom preview dimensions persist into second isolated process")
  exit(failures == 0 ? 0 : 1)
}
UserDefaults.standard.removeObject(forKey: OSCPositionSettingsSheetController.previewContextPersistenceKey)
Preference.Key.allCases.forEach { Preference.defaults.removeObject(forKey: $0.rawValue) }
Preference.set(true, for: .controlBarDefaultPositionIsCustomized)
Preference.set(50, for: .controlBarDefaultPositionHorizontal)
Preference.set(10, for: .controlBarDefaultPositionVertical)
Preference.set(0.74, for: .controlBarPositionHorizontal)
Preference.set(0.61, for: .controlBarPositionVertical)
Preference.writes = []
let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 750),
                      styleMask: [.titled], backing: .buffered, defer: false)
parent.isReleasedWhenClosed = false
let sheet = OSCPositionSettingsSheetController()
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.025)) }
func field(_ axis: String) -> NSTextField {
  descendants(sheet.window!.contentView!).compactMap { $0 as? NSTextField }.first {
    $0.isEditable && ($0.accessibilityLabel() ?? "").contains(axis)
  }!
}
func button(_ suffix: String) -> NSButton {
  let title = SettingsUIHelper.sharedUI.localized("oscDefaultPosition" + suffix)
  return descendants(sheet.window!.contentView!).compactMap { $0 as? NSButton }.first { $0.title == title }!
}
func preview() -> OSCPositionPreviewView {
  descendants(sheet.window!.contentView!).compactMap { $0 as? OSCPositionPreviewView }.first!
}
func edit(_ axis: String, _ value: String) {
  let input = field(axis)
  input.stringValue = value
  sheet.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: input))
}
func editNumber(_ axis: String, _ value: Double) {
  let input = field(axis)
  let value = (input.formatter as! NumberFormatter).string(from: NSNumber(value: value))!
  edit(axis, value)
}
func cancel() { button(".cancel").performClick(nil); settle() }
func present() {
  sheet.present(on: parent)
  settle()
  guard let content = sheet.window?.contentView else {
    print("FAIL: first presentation has no window (isWindowLoaded=\(sheet.isWindowLoaded))")
    exit(1)
  }
  content.layoutSubtreeIfNeeded()
}
present()
check(parent.attachedSheet === sheet.window, "production controller loads and attaches a settings sheet")
check(near(field("Horizontal").doubleValue, 50) && near(field("Vertical").doubleValue, 10), "first opening loads persisted default percentages")
let positionGrid = descendants(sheet.window!.contentView!).compactMap { $0 as? NSGridView }.first!
check(positionGrid.column(at: 0).xPlacement == .leading, "OSC labels align to the left")
let edgeMenus = descendants(sheet.window!.contentView!).compactMap { $0 as? NSPopUpButton }.filter {
  $0.itemTitles.first == SettingsUIHelper.sharedUI.localized("oscPosition.left") ||
    $0.itemTitles.first == SettingsUIHelper.sharedUI.localized("oscPosition.top")
}
check(edgeMenus.count == 2 && edgeMenus.allSatisfy { abs($0.frame.width - 90) < 1 },
      "OSC edge menus share the window editor width")
check(preview().bounds.size == NSSize(width: 560, height: 315), "real production layout helpers produce the intended preview size")
check(preview().isAccessibilityElement() && preview().accessibilityRole() == .image &&
      preview().accessibilityLabel() == SettingsUIHelper.sharedUI.localized("oscDefaultPosition.preview"),
      "preview is an accessible image with its localized descriptive label")
func checkCompactFields(_ direction: NSUserInterfaceLayoutDirection, _ name: String) {
  let content = sheet.window!.contentView!
  descendants(content).forEach { $0.userInterfaceLayoutDirection = direction }
  content.layoutSubtreeIfNeeded()
  let grid = descendants(content).compactMap { $0 as? NSGridView }.first!
  let controls = grid.cell(atColumnIndex: 1, rowIndex: 0).contentView!
  let percent = grid.cell(atColumnIndex: 2, rowIndex: 0).contentView!
  let controlsFrame = grid.convert(controls.alignmentRect(forFrame: controls.frame), from: controls.superview)
  let percentFrame = grid.convert(percent.alignmentRect(forFrame: percent.frame), from: percent.superview)
  let gap = min(abs(percentFrame.minX - controlsFrame.maxX), abs(controlsFrame.minX - percentFrame.maxX))
  check(grid.column(at: 1).width > 0 && abs(controlsFrame.width - controls.fittingSize.width) < 1,
        "\(name) input column retains its preattachment fitting width")
  check(abs(gap - grid.columnSpacing) < 1 && percent.frame.width > 0,
        "\(name) percent stays adjacent to controls after full sheet layout")
}
checkCompactFields(.leftToRight, "LTR")
checkCompactFields(.rightToLeft, "RTL")
checkCompactFields(.leftToRight, "restored LTR")
check(Preference.writes.isEmpty, "opening does not write preferences")
sheet.present(on: parent)
check(parent.attachedSheet === sheet.window, "repeated open while attached leaves the existing sheet intact")
editNumber("Horizontal", 65.25)
editNumber("Vertical", 35.5)
check(Preference.writes.isEmpty, "changing fields remains a local draft")
cancel()
check(parent.attachedSheet == nil && Preference.writes.isEmpty, "Cancel dismisses without modifying either default or current position")
present()
check(near(field("Horizontal").doubleValue, 50) && near(field("Vertical").doubleValue, 10), "reopening discards the canceled draft")

func mouse(_ type: NSEvent.EventType, in view: NSView, at local: NSPoint) -> NSEvent {
  let point = view.convert(local, to: nil)
  return NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                           timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: view.window!.windowNumber, context: nil,
                           eventNumber: checks, clickCount: 1, pressure: 1)!
}
let p = preview()
let initialCenter = NSPoint(x: p.panelFrame.midX, y: p.panelFrame.midY)
let sheetScale = Double(p.canvasFrame.width / OSCPositionSettingsSheetController.standardPreviewSize.width)
let inset = 16.0 * sheetScale
let travelX = p.canvasFrame.width - p.panelFrame.width - 2 * inset
let travelY = p.canvasFrame.height - 40.0 * sheetScale - p.panelFrame.height
let targetCenter = NSPoint(x: initialCenter.x + travelX * 0.1,
                           y: initialCenter.y - travelY * 0.1)
p.mouseDown(with: mouse(.leftMouseDown, in: p, at: initialCenter))
p.mouseDragged(with: mouse(.leftMouseDragged, in: p, at: targetCenter))
p.mouseUp(with: mouse(.leftMouseUp, in: p, at: targetCenter))
check(near(field("Horizontal").doubleValue, 60) && near(field("Vertical").doubleValue, 20), "preview drag synchronizes both percentage fields")
check(Preference.writes.isEmpty, "preview dragging does not write preferences")
p.mouseDragged(with: mouse(.leftMouseDragged, in: p, at: NSPoint(x: 450, y: 220)))
check(near(field("Horizontal").doubleValue, 60) && near(field("Vertical").doubleValue, 20), "mouse-up clears preview drag state")
cancel()

let geomWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 315),
                          styleMask: [.borderless], backing: .buffered, defer: false)
geomWindow.isReleasedWhenClosed = false
let geom = OSCPositionPreviewView(frame: NSRect(x: 0, y: 0, width: 560, height: 315))
geomWindow.contentView = geom
var moved: (Double, Double)?
geom.onPositionChanged = { moved = ($0, $1) }
func drag(from start: NSPoint, to end: NSPoint) {
  moved = nil
  geom.mouseDown(with: mouse(.leftMouseDown, in: geom, at: start))
  geom.mouseDragged(with: mouse(.leftMouseDragged, in: geom, at: end))
  geom.mouseUp(with: mouse(.leftMouseUp, in: geom, at: end))
}
for direction: NSUserInterfaceLayoutDirection in [.leftToRight, .rightToLeft] {
  geom.userInterfaceLayoutDirection = direction
  geom.setPosition(.percentages(0.25, 0.40))
  let start = NSPoint(x: geom.panelFrame.midX, y: geom.panelFrame.midY)
  let fixtureScale = geom.canvasFrame.width / 1280
  let fixtureTravelX = geom.canvasFrame.width - geom.panelFrame.width - 32 * fixtureScale
  let fixtureTravelY = geom.canvasFrame.height - geom.panelFrame.height - 40 * fixtureScale
  drag(from: start, to: NSPoint(x: start.x + fixtureTravelX * 0.1, y: start.y - fixtureTravelY * 0.1))
  check(moved.map { near($0.0, 35) && near($0.1, 50) } ?? false,
        "preview drag uses physical left-to-right and top-to-bottom travel percentages in LTR and RTL")
}
geom.userInterfaceLayoutDirection = .leftToRight
geom.setPosition(.percentages(0, 0))
drag(from: NSPoint(x: geom.panelFrame.midX, y: geom.panelFrame.midY), to: NSPoint(x: -500, y: 1000))
check(moved.map { near($0.0, 0) && near($0.1, 0) } ?? false, "preview drag reports zero at the safe top-left boundary")
// Numeric extremes and outward dragging must reserve the same scaled 16pt
// gaps, including the separate 25pt sample header. Check the actual drawn rect.
for direction: NSUserInterfaceLayoutDirection in [.leftToRight, .rightToLeft] {
  geom.userInterfaceLayoutDirection = direction
  for horizontal in [0.0, 50.0, 100.0] {
    for vertical in [0.0, 50.0, 100.0] {
      geom.setPosition(.percentages(horizontal / 100, vertical / 100))
      let rect = geom.panelFrame
      let inset = 16.0 * 560 / 1280
      check(rect.minX >= inset - 0.001 && 560 - rect.maxX >= inset - 0.001 &&
            rect.minY >= -0.001 && 315 - 40.0 * 560 / 1280 - rect.maxY >= -0.001,
            "numeric default extremes retain sixteen-point side gaps and flush vertical boundaries")
      let start = NSPoint(x: rect.midX, y: rect.midY)
      drag(from: start, to: NSPoint(x: -500, y: -500))
      check(near(Double(geom.panelFrame.minX), inset) && near(Double(geom.panelFrame.minY), 0),
            "outward default drag stops at safe left/bottom boundaries")
      geom.setPosition(.percentages(horizontal / 100, vertical / 100))
      drag(from: NSPoint(x: geom.panelFrame.midX, y: geom.panelFrame.midY), to: NSPoint(x: 2000, y: 2000))
      check(near(Double(560 - geom.panelFrame.maxX), inset) &&
            near(Double(315 - 40.0 * 560 / 1280 - geom.panelFrame.maxY), 0),
            "outward default drag stops at safe right/header boundaries")
    }
  }
}
geom.userInterfaceLayoutDirection = .leftToRight
geom.setPosition(.percentages(0.5, 0.1))
drag(from: NSPoint(x: 5, y: 5), to: NSPoint(x: 100, y: 100))
check(moved == nil, "drag beginning on template background cannot move the controller")

present()
editNumber("Horizontal", 37.25)
let activeVertical = field("Vertical")
check(sheet.window!.makeFirstResponder(activeVertical), "percentage field accepts first responder in the real sheet")
let activeEditor = activeVertical.currentEditor() as? NSTextView
check(activeEditor != nil, "real AppKit field editor is available for pending-edit Save")
if let activeEditor { activeEditor.string = (activeVertical.formatter as! NumberFormatter).string(from: 22.5)! }
else { editNumber("Vertical", 22.5) }
button(".save").performClick(nil)
settle()
check(parent.attachedSheet == nil, "Save dismisses sheet")
check(Preference.writes == [.controlBarDefaultPlacement], "Save writes the explicit-default flag and the two default-position preferences")
check(near(Double(Preference.floatingOSCDefaultPosition.vertical.value * 100), 22.5), "Save commits the active AppKit field editor before storing draft")
check(near(Double(Preference.float(for: .controlBarPositionHorizontal)), 0.74) && near(Double(Preference.float(for: .controlBarPositionVertical)), 0.61), "Save leaves the live player current position unchanged")
present()
check(near(field("Horizontal").doubleValue, 37.25) && near(field("Vertical").doubleValue, 22.5), "reopening loads saved draft")
check(button(".cancel").keyEquivalent == "\u{1b}" && (["\r", "\n", "\u{3}"].contains(button(".save").keyEquivalent) || sheet.window!.defaultButtonCell === button(".save").cell), "Cancel and Save have Escape and Return/default-button equivalents")
editNumber("Horizontal", 99)
let escapeInput = field("Horizontal")
check(sheet.window!.makeFirstResponder(escapeInput), "field editor accepts focus before Escape")
if let editor = escapeInput.currentEditor() as? NSTextView { editor.string = "-" }
let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                            timestamp: ProcessInfo.processInfo.systemUptime,
                            windowNumber: sheet.window!.windowNumber, context: nil,
                            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
let handledEscape = sheet.window!.performKeyEquivalent(with: escape)
settle()
check(handledEscape && parent.attachedSheet == nil, "Escape discards draft while an invalid incomplete edit is active")
check(Preference.writes.count == 1 && near(Double(Preference.floatingOSCDefaultPosition.horizontal.value * 100), 37.25), "Escape does not commit edited default")
if parent.attachedSheet != nil { cancel() }
present()
let formatter = field("Horizontal").formatter as! NumberFormatter
let originalLocale = formatter.locale
formatter.locale = Locale(identifier: "ru_RU")
edit("Horizontal", "40,75")
let localePreview = preview()
let localeStart = NSPoint(x: localePreview.panelFrame.midX, y: localePreview.panelFrame.midY)
let localeEnd = NSPoint(x: localeStart.x + travelX * 0.1, y: localeStart.y)
localePreview.mouseDown(with: mouse(.leftMouseDown, in: localePreview, at: localeStart))
localePreview.mouseDragged(with: mouse(.leftMouseDragged, in: localePreview, at: localeEnd))
localePreview.mouseUp(with: mouse(.leftMouseUp, in: localePreview, at: localeEnd))
check(near(field("Horizontal").doubleValue, 50.75), "locale decimal input updates preview and remains synchronized after drag")
formatter.locale = originalLocale
cancel()
for badValue in ["", "101", "-1", "NaN", "not a number", "10abc", "999999999999999999999999999999999"] {
  present()
  let previous = field("Horizontal").doubleValue
  let writesBefore = Preference.writes.count
  let input = field("Horizontal")
  sheet.window!.makeFirstResponder(input)
  input.currentEditor()!.string = badValue
  let expected = badValue == "101" || badValue.hasPrefix("999") ? 100.0 : (badValue == "-1" ? 0.0 : previous)
  button(".save").performClick(nil)
  settle()
  check(parent.attachedSheet == nil && Preference.writes.count == writesBefore + 1 &&
        near(Double(Preference.floatingOSCDefaultPosition.horizontal.value * 100), expected),
        "invalid input '\(badValue)' reverts before Save")
}
present()
// Find the two position unit controls by their localized menu items.
let axisUnits = descendants(sheet.window!.contentView!).compactMap { $0 as? NSPopUpButton }.filter {
  $0.itemTitles == [SettingsUIHelper.sharedUI.localized("oscPosition.percent"), SettingsUIHelper.sharedUI.localized("oscPosition.points")]
}
for (index, axis) in ["Horizontal", "Vertical"].enumerated() {
  axisUnits[index].selectItem(at: 1)
  axisUnits[index].sendAction(axisUnits[index].action!, to: axisUnits[index].target)
  let range = preview().pointLimits(horizontal: index == 0)
  for (text, expected) in [("1000000", range.upperBound), ("-50", range.lowerBound)] {
    let input = field(axis)
    sheet.window!.makeFirstResponder(input)
    input.currentEditor()!.string = text
    sheet.window!.makeFirstResponder(nil)
    check(near(input.doubleValue, expected), "point offset clamps to the safe \(axis) range")
  }
}
cancel()
present()
editNumber("Horizontal", 37.25)
button(".save").performClick(nil)
settle()
Preference.defaults.synchronize()
parent.orderOut(nil)
geomWindow.orderOut(nil)
// Fresh profile uses explicit mixed units; legacy defaults remain readable.
Preference.defaults.removeObject(forKey: Preference.Key.controlBarDefaultPlacement.rawValue)
Preference.set(false, for: .controlBarDefaultPositionIsCustomized)
Preference.writes = []
present()
check(preview().position == .initial, "fresh default is fifty percent and sixteen points from bottom")
check(near(field("Horizontal").doubleValue, 50) && near(field("Vertical").doubleValue, 16), "mixed default displays actual per-axis values")
check(near(Double(preview().panelFrame.minY), inset), "point distances scale with preview geometry")
func popup(_ suffix: String) -> NSPopUpButton {
  let label = SettingsUIHelper.sharedUI.localized("oscPosition." + suffix)
  return descendants(sheet.window!.contentView!).compactMap { $0 as? NSPopUpButton }.first {
    $0.accessibilityLabel() == label
  }!
}
func select(_ suffix: String, _ index: Int) {
  let control = popup(suffix)
  control.selectItem(at: index)
  control.sendAction(control.action!, to: control.target)
}
check(!popup("horizontalEdge").isHidden && !popup("verticalEdge").isHidden, "edge selectors remain visible in percent and point modes")
editNumber("Horizontal", 25)
let percentFrame = preview().panelFrame
select("horizontalEdge", 1)
check(near(field("Horizontal").doubleValue, 75) && preview().position.horizontal.edge == .far,
      "twenty-five percent from left converts to seventy-five from right")
check(abs(preview().panelFrame.minX - percentFrame.minX) < 0.001,
      "changing percent edge preserves the drawn position")
select("horizontalEdge", 0)
editNumber("Horizontal", 50)
let beforeConversion = preview().panelFrame
select("verticalUnit", 0)
check(preview().position.vertical.unit == .percent && preview().position.horizontal.value == 0.5,
      "unit conversion affects only the selected axis")
check(abs(preview().panelFrame.minY - beforeConversion.minY) < 0.001, "unit conversion preserves visible placement")
select("verticalUnit", 1)
select("verticalEdge", 0)
check(abs(preview().panelFrame.minY - beforeConversion.minY) < 0.001 && preview().position.vertical.edge == .near,
      "edge conversion preserves visible placement")
editNumber("Vertical", 150)
check(preview().position.vertical.value == 150, "point input accepts distances beyond one hundred")
select("verticalEdge", 1)
editNumber("Vertical", 0)
check(near(Double(preview().panelFrame.minY), 0), "zero points from bottom reaches the boundary")
let dragStart = NSPoint(x: preview().panelFrame.midX, y: preview().panelFrame.midY)
preview().mouseDown(with: mouse(.leftMouseDown, in: preview(), at: dragStart))
preview().mouseDragged(with: mouse(.leftMouseDragged, in: preview(), at: NSPoint(x: dragStart.x, y: dragStart.y + 20 * sheetScale)))
preview().mouseUp(with: mouse(.leftMouseUp, in: preview(), at: dragStart))
check(preview().position.horizontal.unit == .percent && preview().position.vertical.unit == .point &&
      near(field("Vertical").doubleValue, 20), "drag preserves mixed units and measures points at logical preview scale")
cancel()
check(Preference.writes.isEmpty, "canceling unit and anchor changes leaves defaults intact")
// Restore the saved fixture used by the second process.
Preference.saveFloatingOSCDefaultPosition(FloatingOSCPosition(horizontal: .init(value: 0.3725), vertical: .init(value: 22.5, unit: .point, edge: .far)))
Preference.defaults.synchronize()
let adaptivePreview = OSCPositionPreviewView(frame: NSRect(x: 0, y: 0, width: 560, height: 315))
adaptivePreview.setPosition(.initial)
for dimensions in [NSSize(width: 900, height: 1600), NSSize(width: 2100, height: 900), NSSize(width: 600, height: 300)] {
  adaptivePreview.setReferenceSize(dimensions)
  let canvas = adaptivePreview.canvasFrame
  let panel = adaptivePreview.panelFrame
  check(abs(canvas.width / canvas.height - dimensions.width / dimensions.height) < 0.001,
        "preview preserves reference window aspect ratio")
  check(abs(panel.midX - canvas.midX) < 0.001, "center percentage remains centered in every context")
  check(abs((panel.minY - canvas.minY) / (canvas.width / dimensions.width) - 16) < 0.001,
        "point offset keeps physical size under preview scaling")
  check(adaptivePreview.position == .initial, "changing preview dimensions leaves saved position values unchanged")
}
// Compare preview dimensions with the same nominal layout measured by the native harness.
for compact in [false, true] {
  adaptivePreview.controllerAppearance.compact = compact
  for dimensions in [NSSize(width: 400, height: 225), NSSize(width: 600, height: 300), NSSize(width: 900, height: 500), NSSize(width: 900, height: 1600)] {
    adaptivePreview.setReferenceSize(dimensions)
    let logicalScale = adaptivePreview.canvasFrame.width / dimensions.width
    let native = FloatingOSCMetrics.panelSize(scale: FloatingOSCScale.factor(for: dimensions), compact: compact,
      sliderHeight: adaptivePreview.controllerAppearance.sliderHeight)
    check(abs(adaptivePreview.panelFrame.width / logicalScale - native.width) < 0.001 &&
          abs(adaptivePreview.panelFrame.height / logicalScale - native.height) < 0.001,
          "preview matches native panel dimensions at compact, intermediate and full scales")
  }
}
adaptivePreview.setReferenceSize(NSSize(width: 10, height: 10))
check(abs(adaptivePreview.canvasFrame.width / adaptivePreview.canvasFrame.height - 400.0 / 225) < 0.001,
      "undersized custom window is clamped to the native Floating minimum")
check(adaptivePreview.panelFrame.width <= adaptivePreview.canvasFrame.width && adaptivePreview.panelFrame.height <= adaptivePreview.canvasFrame.height,
      "OSC fits at the minimum window size")
let contextSelector = PositionPreviewContextSelector()
contextSelector.configure([PositionPreviewContext(title: "Window", size: NSSize(width: 900, height: 1600), minimumSize: FloatingOSCMetrics.minimumWindowSize)])
let contextViews = descendants(contextSelector)
let menu = contextViews.compactMap { $0 as? NSPopUpButton }.first!
let dimensions = contextViews.compactMap { $0 as? NSTextField }.filter { $0.isEditable }
menu.selectItem(at: 1)
menu.sendAction(menu.action!, to: menu.target)
dimensions[0].stringValue = "10"
dimensions[1].stringValue = "20"
contextSelector.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: dimensions[0]))
check(contextSelector.selectedSize == FloatingOSCMetrics.minimumWindowSize, "Custom clamps both axes to the native window minimum")
for input in dimensions { contextSelector.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: input)) }
check(dimensions[0].integerValue == 400 && dimensions[1].integerValue == 225, "committing Custom displays the enforced minimum")
dimensions[0].stringValue = "100000"
dimensions[1].stringValue = "100000"
contextSelector.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: dimensions[0]))
check(contextSelector.selectedSize == NSSize(width: 100000, height: 100000), "Custom accepts the largest serializable point reference")
let boundedSelector = PositionPreviewContextSelector()
boundedSelector.customSizeLimits = (FloatingOSCMetrics.minimumWindowSize, NSSize(width: 2400, height: 1800))
boundedSelector.configure([PositionPreviewContext(title: "Standard", size: NSSize(width: 1800, height: 1100))], minimumSize: FloatingOSCMetrics.minimumWindowSize)
let boundedWindow = PositionSettingsPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
boundedWindow.isReleasedWhenClosed = false
boundedWindow.contentView!.addSubview(boundedSelector)
let boundedFields = descendants(boundedSelector).compactMap { $0 as? PositionSettingsTextField }
let boundedMenu = descendants(boundedSelector).compactMap { $0 as? NSPopUpButton }.first!
boundedMenu.selectItem(at: 1)
boundedMenu.sendAction(boundedMenu.action!, to: boundedMenu.target)
for (index, text, expected) in [(0, "300", 400), (1, "100", 225), (0, "99999", 2400), (1, "99999", 1800), (0, "-20", 400)] {
  let field = boundedFields[index]
  _ = boundedWindow.makeFirstResponder(field)
  field.currentEditor()!.string = text
  _ = boundedWindow.makeFirstResponder(nil)
  check(field.integerValue == expected, "Custom dimension clamps on commit: \(text) to \(expected)")
  check(Int(index == 0 ? boundedSelector.selectedSize.width : boundedSelector.selectedSize.height) == expected,
        "Custom field and preview use the same committed size")
}
let previousWidth = boundedFields[0].integerValue
_ = boundedWindow.makeFirstResponder(boundedFields[0])
boundedFields[0].currentEditor()!.string = "abc"
_ = boundedWindow.makeFirstResponder(nil)
check(boundedFields[0].integerValue == previousWidth, "malformed Custom dimension restores original input")
let stableSize = boundedSelector.selectedSize
_ = boundedWindow.makeFirstResponder(boundedFields[0])
boundedFields[0].currentEditor()!.string = "99999"
boundedSelector.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: boundedFields[0]))
check(boundedSelector.selectedSize == stableSize, "out-of-range typing does not change Custom preview before commit")
_ = boundedWindow.makeFirstResponder(nil)
let largestPlacement = FloatingOSCPlacement.capturing(frame: NSRect(x: 60000, y: 60000, width: 460, height: 80),
  keeping: FloatingOSCPosition(horizontal: .init(value: 0, unit: .point, edge: .near),
    vertical: .init(value: 0, unit: .point, edge: .far)),
  contentSize: contextSelector.selectedSize, titlebarBottom: nil)
check(FloatingOSCPosition(dictionary: largestPlacement.dictionary) == largestPlacement,
      "dragged point coordinates in the largest Custom reference round-trip through saved configuration")
for oversized in ["100001", "1000000"] {
  dimensions[0].stringValue = oversized
  contextSelector.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: dimensions[0]))
  check(contextSelector.selectedSize == NSSize(width: 100000, height: 100000), "oversized Custom dimensions retain the last supported reference")
}
// Standard is independent of a tiny current window. Remember only preview context.
let previewKey = OSCPositionSettingsSheetController.previewContextPersistenceKey
let savedPlacement = Preference.floatingOSCDefaultPosition
let currentContext = PositionPreviewContext(title: "Current Window", size: NSSize(width: 400, height: 225),
  minimumSize: FloatingOSCMetrics.minimumWindowSize)
let standardSheet = OSCPositionSettingsSheetController()
standardSheet.present(on: parent, contexts: [currentContext])
settle()
func selector(in controller: OSCPositionSettingsSheetController) -> PositionPreviewContextSelector {
  descendants(controller.window!.contentView!).compactMap { $0 as? PositionPreviewContextSelector }.first!
}
let standardSelector = selector(in: standardSheet)
let standardMenu = descendants(standardSelector).compactMap { $0 as? NSPopUpButton }.first!
check(standardMenu.indexOfSelectedItem == 0 && standardSelector.selectedSize == (parent.screen?.frame.size ?? OSCPositionSettingsSheetController.standardPreviewSize),
      "first opening uses the settings window display full logical size despite a tiny current player window")
check(standardMenu.numberOfItems == 3, "Standard, current window and Custom remain available")
standardMenu.selectItem(at: 1)
standardMenu.sendAction(standardMenu.action!, to: standardMenu.target)
check(standardSelector.selectedSize == currentContext.size, "Current Window uses real current dimensions")
descendants(standardSheet.window!.contentView!).compactMap { $0 as? NSButton }.first {
  $0.title == SettingsUIHelper.sharedUI.localized("oscDefaultPosition.cancel")
}!.performClick(nil)
settle()
let rememberedSheet = OSCPositionSettingsSheetController()
let resizedContext = PositionPreviewContext(title: "Current Window", size: NSSize(width: 600, height: 300),
  minimumSize: FloatingOSCMetrics.minimumWindowSize)
rememberedSheet.present(on: parent, contexts: [resizedContext])
settle()
let rememberedSelector = selector(in: rememberedSheet)
check(rememberedSelector.selectedSize == resizedContext.size, "reopening remembers Current Window and reads its new size")
let rememberedMenu = descendants(rememberedSelector).compactMap { $0 as? NSPopUpButton }.first!
rememberedMenu.selectItem(at: 2)
rememberedMenu.sendAction(rememberedMenu.action!, to: rememberedMenu.target)
rememberedSelector.customSizeLimits = (FloatingOSCMetrics.minimumWindowSize, NSSize(width: 2000, height: 1800))
let rememberedInputs = descendants(rememberedSelector).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
rememberedInputs[0].stringValue = "900"
rememberedInputs[1].stringValue = "1600"
rememberedSelector.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: rememberedInputs[0]))
descendants(rememberedSheet.window!.contentView!).compactMap { $0 as? NSButton }.first {
  $0.title == SettingsUIHelper.sharedUI.localized("oscDefaultPosition.cancel")
}!.performClick(nil)
settle()
let restoredSelector = PositionPreviewContextSelector()
restoredSelector.configure([PositionPreviewContext(title: "Standard", size: OSCPositionSettingsSheetController.standardPreviewSize,
  minimumSize: FloatingOSCMetrics.minimumWindowSize, identifier: "standard")], rememberSelectionUnder: previewKey)
check(restoredSelector.selectedSize == NSSize(width: 900, height: 1600), "Custom retains dimensions when player context disappears")
check(Preference.floatingOSCDefaultPosition == savedPlacement && near(Double(Preference.float(for: .controlBarPositionHorizontal)), 0.74),
      "remembering preview context leaves default and live OSC positions untouched")
let recoveryKey = "oscPreviewRecoveryTest"
UserDefaults.standard.set(["context": "missing-window", "width": 0, "height": -1], forKey: recoveryKey)
let recoverySelector = PositionPreviewContextSelector()
recoverySelector.configure([PositionPreviewContext(title: "Standard", size: OSCPositionSettingsSheetController.standardPreviewSize,
  identifier: "standard")], rememberSelectionUnder: recoveryKey)
check(recoverySelector.selectedSize == OSCPositionSettingsSheetController.standardPreviewSize,
      "unavailable saved context and invalid dimensions recover to Standard")
UserDefaults.standard.removeObject(forKey: recoveryKey)
UserDefaults.standard.set(["context": "custom", "width": 1000000, "height": 1000000], forKey: recoveryKey)
let oversizedRecovery = PositionPreviewContextSelector()
oversizedRecovery.configure([PositionPreviewContext(title: "Standard", size: OSCPositionSettingsSheetController.standardPreviewSize,
  identifier: "standard")], rememberSelectionUnder: recoveryKey)
check(oversizedRecovery.selectedSize == OSCPositionSettingsSheetController.standardPreviewSize,
      "remembered oversized Custom reference recovers to supported standard dimensions")
UserDefaults.standard.removeObject(forKey: recoveryKey)
// A settings window on another display must not inherit the primary display's size.
class DisplayReferenceWindow: NSWindow {
  var referenceScreen: NSScreen?
  override var screen: NSScreen? { referenceScreen }
}
let rememberedPreviewContext = UserDefaults.standard.object(forKey: previewKey)
for screen in NSScreen.screens {
  let displayParent = DisplayReferenceWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 750),
    styleMask: [.titled], backing: .buffered, defer: false)
  displayParent.isReleasedWhenClosed = false
  displayParent.referenceScreen = screen
  UserDefaults.standard.set(["context": "standard"], forKey: previewKey)
  let displaySheet = OSCPositionSettingsSheetController()
  displaySheet.present(on: displayParent, contexts: [currentContext])
  settle()
  check(selector(in: displaySheet).selectedSize == screen.frame.size,
        "Standard uses the settings display full logical frame: \(screen.localizedName)")
  displayParent.endSheet(displaySheet.window!, returnCode: .cancel)
  settle()
}
if let rememberedPreviewContext { UserDefaults.standard.set(rememberedPreviewContext, forKey: previewKey) }
else { UserDefaults.standard.removeObject(forKey: previewKey) }
UserDefaults.standard.synchronize()
print("Completed \(checks) focused checks, \(failures) failures. Production sheet and preview with isolated preferences.")
exit(failures == 0 ? 0 : 1)
