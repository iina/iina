import Darwin
setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var checks = 0
var failures = 0
var failureGeometry: (() -> String)?
func check(_ result: @autoclosure () -> Bool, _ description: String) {
  checks += 1
  if result() { print("PASS: \(description)") }
  else {
    failures += 1
    print("FAIL: \(description)")
    if let failureGeometry { print(failureGeometry()) }
  }
}
func near(_ actual: CGFloat, _ expected: CGFloat) -> Bool { abs(actual - expected) < 0.6 }
func descendants(_ view: NSView) -> [NSView] {
  var children = view.subviews
  if let stack = view as? NSStackView {
    children += stack.arrangedSubviews.filter { item in !children.contains { $0 === item } }
  }
  return [view] + children.flatMap(descendants)
}
func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.025)) }
let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
                      styleMask: [.titled], backing: .buffered, defer: false)
parent.isReleasedWhenClosed = false
let sheet = WindowGeometrySettingsSheetController()
func controls() -> [NSView] { descendants(sheet.window!.contentView!) }
func copy(_ suffix: String) -> String {
  let key: String
  switch suffix {
  case ".reset", ".save", ".cancel": key = "oscDefaultPosition\(suffix)"
  case ".horizontal": key = "controlBarDefaultPositionHorizontal.label"
  case ".vertical": key = "controlBarDefaultPositionVertical.label"
  default: key = suffix.hasPrefix("$") ? suffix : "windowGeometry\(suffix)"
  }
  return SettingsUIHelper.sharedUI.localized(key)
}
func field(_ suffix: String) -> NSTextField {
  controls().compactMap { $0 as? NSTextField }.first {
    $0.isEditable && $0.accessibilityLabel() == copy(suffix)
  }!
}
func button(_ suffix: String) -> NSButton {
  controls().compactMap { $0 as? NSButton }.first { $0.title == copy(suffix) }!
}
func present(_ raw: String) {
  Preference.defaults.set(raw, forKey: Preference.Key.initialWindowSizePosition.rawValue)
  Preference.writes = []
  sheet.present(on: parent)
  settle()
  sheet.window!.contentView!.layoutSubtreeIfNeeded()
}
func save() { button(".save").performClick(nil); settle() }
func cancel() { button(".cancel").performClick(nil); settle() }
func edit(_ suffix: String, _ value: String) {
  let input = field(suffix)
  sheet.window!.makeFirstResponder(input)
  if let editor = input.currentEditor() as? NSTextView { editor.string = value }
  else { input.stringValue = value }
  sheet.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: input))
}

var editorHeights: [String: CGFloat] = [:]
for sizeEnabled in [false, true] {
  for positionEnabled in [false, true] {
    var configured = InitialWindowGeometry("640+100-80")
    configured.sizeEnabled = sizeEnabled
    configured.positionEnabled = positionEnabled
    var saved: InitialWindowGeometry?
    Preference.writes = []
    sheet.present(on: parent, geometry: configured) { saved = $0 }
    settle()
    check(controls().compactMap { $0 as? NSSwitch }.isEmpty, "editor has no switches")
    check(field("$InitialWindowSize").isHiddenOrHasHiddenAncestor == !sizeEnabled,
          "size fields follow the external size switch")
    check(field(".horizontal").isHiddenOrHasHiddenAncestor == !positionEnabled,
          "position fields follow the external position switch")
    let texts = controls().compactMap { $0 as? NSTextField }.map { $0.stringValue }
    let popups = controls().compactMap { $0 as? NSPopUpButton }
    check(popups.filter { $0.itemTitles == ["pt", "%"] && !$0.isHiddenOrHasHiddenAncestor }.count == (sizeEnabled ? 1 : 0) + (positionEnabled ? 2 : 0),
          "all window unit selectors share compact pt and percent labels")
    check(popups.contains { $0.itemTitles == ["Left", "Right"] } &&
          popups.contains { $0.itemTitles == ["Top", "Bottom"] },
          "edge selectors share OSC side labels")
    check(texts.filter { $0 == "from" }.count == 2, "from is independent text in both rows")
    check(button(".save").title == "Save", "Save matches OSC button copy")

    check(!texts.contains(copy(".instructions")) && !texts.contains(copy(".offsetHint")) && !texts.contains(copy(".note")),
          "editor contains no explanatory descriptions")
    editorHeights["\(sizeEnabled)-\(positionEnabled)"] = sheet.window!.contentView!.frame.height
    let preview = controls().compactMap { $0 as? WindowGeometryPreviewView }.first!
    check(preview.bounds.size == NSSize(width: 560, height: 315), "preview retains its size")
    if sizeEnabled { edit("$InitialWindowSize", "800") }
    if positionEnabled {
      edit(".horizontal", "120")
      edit(".vertical", "90")
    }
    save()
    check(saved?.sizeValue == (sizeEnabled ? 800 : 640) && saved?.xValue == (positionEnabled ? 120 : 100) && saved?.yValue == (positionEnabled ? 90 : 80),
          "Save edits enabled components and preserves disabled values")
    check(saved?.sizeEnabled == sizeEnabled && saved?.positionEnabled == positionEnabled,
          "Save preserves independent external switch states")
    check(Preference.writes.isEmpty, "Save delegates persistence to shared bindings")
    saved = nil
    sheet.present(on: parent, geometry: configured) { saved = $0 }
    settle()
    edit(".horizontal", "999")
    cancel()
    check(saved == nil && Preference.writes.isEmpty, "Cancel discards changes")
  }
}
for sizeEnabled in [false, true] {
  for positionEnabled in [false, true] {
    var configured = InitialWindowGeometry("1280+10-20")
    configured.sizeEnabled = sizeEnabled
    configured.positionEnabled = positionEnabled
    var resetDraft: InitialWindowGeometry?
    Preference.writes = []
    sheet.present(on: parent, geometry: configured) { resetDraft = $0 }
    settle()
    let sideMenus = controls().compactMap { $0 as? NSPopUpButton }.filter {
      $0.itemTitles == ["Left", "Right"] || $0.itemTitles == ["Top", "Bottom"]
    }
    if positionEnabled {
      check(sideMenus.allSatisfy { near($0.frame.width, 90) }, "side menus have identical fixed widths")
    }
    let headings = controls().compactMap { $0 as? NSTextField }.filter {
      $0.stringValue == copy("$InitialWindowSize") + ":" || $0.stringValue == copy("$InitialWindowPosition") + ":"
    }
    check(headings.count == 2 && headings.allSatisfy { $0.font!.fontDescriptor.symbolicTraits.contains(.bold) },
          "section headings are bold with a colon")
    if sizeEnabled { edit("$InitialWindowSize", "999") }
    button(".reset").performClick(nil)
    settle()
    check(field("$InitialWindowSize").stringValue == "40" && field(".horizontal").stringValue == "50" &&
          field(".vertical").stringValue == "50" && Preference.writes.isEmpty,
          "Reset replaces edits with factory values without writing preferences")
    save()
    check(resetDraft?.sizeValue == 40 && resetDraft?.sizeDimension == .width && resetDraft?.sizeUnit == .percent &&
          resetDraft?.xValue == 50 && resetDraft?.yValue == 50 && resetDraft?.xUnit == .percent &&
          resetDraft?.yUnit == .percent && resetDraft?.xAnchor == .left && resetDraft?.yAnchor == .top,
          "Reset and Save use width 40 percent and centered percentages")
    check(resetDraft?.sizeEnabled == sizeEnabled && resetDraft?.positionEnabled == positionEnabled,
          "Reset keeps external enable states")
    resetDraft = nil
    sheet.present(on: parent, geometry: configured) { resetDraft = $0 }
    settle()
    button(".reset").performClick(nil)
    cancel()
    check(resetDraft == nil && Preference.writes.isEmpty, "Cancel after Reset discards factory draft")
  }
}
check(editorHeights["false-false"]! < editorHeights["true-false"]! &&
      editorHeights["true-false"]! < editorHeights["true-true"]! &&
      editorHeights["false-true"]! < editorHeights["true-true"]!,
      "hidden groups shrink the sheet without leaving empty gaps")
for invalid in ["", "-1", "1.5", "abc"] {
  var saved: InitialWindowGeometry?
  sheet.present(on: parent, geometry: InitialWindowGeometry("640")) { saved = $0 }
  settle()
  edit("$InitialWindowSize", invalid)
  save()
  check(parent.attachedSheet == nil && saved?.sizeValue == (invalid == "-1" ? 285 : 640), "numeric input clamps and malformed input reverts before Save")
  cancel()
}
for raw in ["0", "0x720", "640x480+0010-0020", "1280-10+20", "invalid geometry"] {
  present(raw)
  save()
  check(parent.attachedSheet == nil && Preference.writes == [raw], "no-op Save preserves raw geometry")
  if parent.attachedSheet != nil { cancel() }
}
let geomWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 315),
                          styleMask: [.borderless], backing: .buffered, defer: false)
geomWindow.isReleasedWhenClosed = false
let geom = WindowGeometryPreviewView(frame: NSRect(x: 0, y: 0, width: 560, height: 315))
geom.dock = nil
geomWindow.contentView = geom
let screen = NSSize(width: 1600, height: 900)
let scale: CGFloat = 291 / 924
let screenOrigin = NSPoint(x: (560 - 1600 * scale) / 2, y: 12)
func local(_ physical: NSPoint) -> NSPoint {
  NSPoint(x: screenOrigin.x + physical.x * scale, y: screenOrigin.y + physical.y * scale)
}
func mouse(_ type: NSEvent.EventType, _ physical: NSPoint, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
  NSEvent.mouseEvent(with: type, location: geom.convert(local(physical), to: nil), modifierFlags: modifiers,
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: geomWindow.windowNumber,
                    context: nil, eventNumber: checks, clickCount: 1, pressure: 1)!
}
var changed: InitialWindowGeometry?
geom.onGeometryChanged = { changed = $0 }
func drag(_ raw: String, from start: NSPoint, to end: NSPoint, modifiers: NSEvent.ModifierFlags = []) {
  geom.setGeometry(InitialWindowGeometry(raw), screenSize: screen)
  geom.clearInteraction()
  changed = nil
  geom.mouseDown(with: mouse(.leftMouseDown, start, modifiers: modifiers))
  geom.mouseDragged(with: mouse(.leftMouseDragged, end, modifiers: modifiers))
  geom.mouseUp(with: mouse(.leftMouseUp, end))
}
drag("640+100-100", from: NSPoint(x: 420, y: 620), to: NSPoint(x: 520, y: 480))
check(changed?.geometryString == "640+200-240", "visual move updates physical left/top integer offsets")
geom.userInterfaceLayoutDirection = .rightToLeft
drag("640+100-100", from: NSPoint(x: 420, y: 620), to: NSPoint(x: 520, y: 480))
check(changed?.geometryString == "640+200-240", "RTL does not mirror physical screen anchors")
geom.userInterfaceLayoutDirection = .leftToRight
drag("640+100-100", from: NSPoint(x: 420, y: 620), to: NSPoint(x: -5000, y: -5000))
check(changed?.geometryString == "640+0-540", "out-of-screen move stores the visible bounded position")
drag("640", from: NSPoint(x: 800, y: 450), to: NSPoint(x: 900, y: 550))
check(changed == nil, "position-disabled preview cannot move")
drag("", from: NSPoint(x: 800, y: 450), to: NSPoint(x: 1000, y: 500))
check(changed == nil, "both-disabled preview remains inert")
drag("640-100+100", from: NSPoint(x: 872, y: 448), to: NSPoint(x: 712, y: 448))
check(changed?.sizeValue == 800 && changed?.xAnchor == .right && changed?.yAnchor == .bottom &&
      changed?.xValue == 100 && changed?.yValue == 100,
      "resize uses free top-left corner for physical right/bottom anchors")
drag("40%+50%+50%", from: NSPoint(x: 1108, y: 282), to: NSPoint(x: 1188, y: 282))
check(changed?.sizeValue == 45 && changed?.sizeUnit == .percent && changed?.xUnit == .percent && changed?.xValue == 53,
      "ordinary proportional corner resize holds the opposite corner with percent positioning")
drag("40%+50%+50%", from: NSPoint(x: 1108, y: 282), to: NSPoint(x: 1188, y: 282), modifiers: .option)
check(changed?.sizeValue == 50 && changed?.xValue == 50 && changed?.yValue == 50,
      "Option proportional resize doubles the corner delta and keeps the center with percent units")
drag("640", from: NSPoint(x: 1108, y: 282), to: NSPoint(x: 1188, y: 282))
check(changed?.sizeValue == 800 && changed?.positionEnabled == false,
      "position-disabled centered preview retains resize interaction")
drag("640+100-100", from: NSPoint(x: 728, y: 452), to: NSPoint(x: -5000, y: 452))
check(changed?.sizeValue == 285, "visual resize clamps to production minimum")
drag("640+100-100", from: NSPoint(x: 728, y: 452), to: NSPoint(x: 9000, y: 452))
check(changed?.sizeValue == 1422, "ordinary proportional resize clamps at screen bounds while holding the opposite corner")
let previous = changed?.geometryString
geom.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 100, y: 100)))
check(changed?.geometryString == previous, "mouse-up clears resize interaction")

var disabledDraft = InitialWindowGeometry("640+100-100")
disabledDraft.sizeEnabled = false
disabledDraft.positionEnabled = false
var configuredDrag: InitialWindowGeometry?
sheet.present(on: parent, geometry: disabledDraft) { configuredDrag = $0 }
settle()
let editorPreview = controls().compactMap { $0 as? WindowGeometryPreviewView }.first!
// A deterministic screen makes the real preview's hit-testing reproducible.
var visibleDraft = disabledDraft
visibleDraft.sizeEnabled = false
visibleDraft.positionEnabled = false
editorPreview.setGeometry(visibleDraft, screenSize: screen)
func editorMouse(_ type: NSEvent.EventType, _ physical: NSPoint) -> NSEvent {
  NSEvent.mouseEvent(with: type, location: editorPreview.convert(local(physical), to: nil), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: sheet.window!.windowNumber,
                    context: nil, eventNumber: checks, clickCount: 1, pressure: 1)!
}
editorPreview.mouseDown(with: editorMouse(.leftMouseDown, NSPoint(x: 420, y: 620)))
editorPreview.mouseDragged(with: editorMouse(.leftMouseDragged, NSPoint(x: 520, y: 480)))
editorPreview.mouseUp(with: editorMouse(.leftMouseUp, NSPoint(x: 520, y: 480)))
save()
check(configuredDrag?.xValue == 100 && configuredDrag?.yValue == 100,
      "disabled preview cannot move")
check(configuredDrag?.sizeEnabled == false && configuredDrag?.positionEnabled == false,
      "preview drag does not enable disabled features")

var afterContextChange: InitialWindowGeometry?
sheet.present(on: parent, geometry: InitialWindowGeometry("800+160-90")) { afterContextChange = $0 }
settle()
let sheetSelector = controls().compactMap { $0 as? PositionPreviewContextSelector }.first!
let sheetSelectorMenu = descendants(sheetSelector).compactMap { $0 as? NSPopUpButton }.first!
sheetSelectorMenu.selectItem(at: sheetSelectorMenu.numberOfItems - 1)
sheetSelectorMenu.sendAction(sheetSelectorMenu.action!, to: sheetSelectorMenu.target)
let sheetDimensions = descendants(sheetSelector).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
sheetDimensions[0].stringValue = "900"
sheetDimensions[1].stringValue = "1600"
sheetSelector.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: sheetDimensions[0]))
check(field("$InitialWindowSize").stringValue == "800" && field(".horizontal").stringValue == "160" && field(".vertical").stringValue == "90",
      "context changes leave window configuration fields unchanged")
save()
check(afterContextChange?.geometryString == "800+160-90", "Save after custom context keeps the same geometry")

Preference.unlockWindowAspectRatio = true
Preference.oscPosition = .floating
var freeSaved: InitialWindowGeometry?
sheet.present(on: parent, geometry: InitialWindowGeometry("640x480+50%-50%")) { freeSaved = $0 }
settle()
check(field("$InitialWindowSize").isHiddenOrHasHiddenAncestor && !field("$Width").isHiddenOrHasHiddenAncestor &&
      !field("$Height").isHiddenOrHasHiddenAncestor, "unlocked editor replaces the single size selector with simultaneous Width and Height")
edit("$Width", "500")
edit("$Height", "700")
save()
check(freeSaved?.geometryString == "500x700+50%-50%", "free editor saves a portrait window independently of media aspect")
freeSaved = nil
sheet.present(on: parent, geometry: InitialWindowGeometry("640x480")) { freeSaved = $0 }
settle()
edit("$Height", "0")
save()
check(parent.attachedSheet == nil && freeSaved?.geometryString == "640x225", "zero free dimension clamps to its native minimum before Save")
cancel()
sheet.present(on: parent, geometry: InitialWindowGeometry("640x480")) { freeSaved = $0 }
settle()
button(".reset").performClick(nil)
save()
check(freeSaved?.widthValue == 40 && freeSaved?.widthUnit == .percent && freeSaved?.independentSize == true &&
      freeSaved!.heightValue > 0, "free Reset derives both dimensions from centered factory width 40 percent")
Preference.unlockWindowAspectRatio = false
Preference.oscPosition = .bottom
present("640x480")
check(field("$InitialWindowSize").isHiddenOrHasHiddenAncestor && !field("$Width").isHiddenOrHasHiddenAncestor &&
      !field("$Height").isHiddenOrHasHiddenAncestor,
      "explicit startup dimensions remain visible after locking the live window aspect ratio")
cancel()

func reshape(from start: NSPoint, to end: NSPoint, modifiers: NSEvent.ModifierFlags = []) {
  var free = InitialWindowGeometry("640x360+100-100")
  free.prepareIndependentSize(screenSize: screen, aspect: 16 / 9)
  geom.setGeometry(free, screenSize: screen)
  changed = nil
  geom.mouseDown(with: mouse(.leftMouseDown, start, modifiers: modifiers))
  geom.mouseDragged(with: mouse(.leftMouseDragged, end, modifiers: modifiers))
  geom.mouseUp(with: mouse(.leftMouseUp, end))
}
reshape(from: NSPoint(x: 740, y: 620), to: NSPoint(x: 900, y: 620))
check(changed?.widthValue == 800 && changed?.heightValue == 360 && changed?.xValue == 100 && changed?.yValue == 100,
      "right-edge drag changes only width and retains the opposite edge")
reshape(from: NSPoint(x: 420, y: 440), to: NSPoint(x: 420, y: 300))
check(changed?.widthValue == 640 && changed?.heightValue == 500 && changed?.yValue == 100,
      "bottom-edge drag changes only height and retains the top edge")
reshape(from: NSPoint(x: 100, y: 800), to: NSPoint(x: 50, y: 850))
check(changed?.widthValue == 690 && changed?.heightValue == 410 && changed?.xValue == 50 && changed?.yValue == 50,
      "top-left corner changes both axes and stores the new position")
// The whole visible grip must behave like its corner, including pixels well
// inside the narrow edge hit regions that previously took the old resize path.
reshape(from: NSPoint(x: 716, y: 464), to: NSPoint(x: 796, y: 404))
check(changed?.widthValue == 720 && changed?.heightValue == 420 && changed?.xValue == 100 && changed?.yValue == 100,
      "ordinary inner-grip drag changes both axes from that corner, holding the opposite corner")
reshape(from: NSPoint(x: 716, y: 464), to: NSPoint(x: 796, y: 404), modifiers: .option)
check(changed?.widthValue == 800 && changed?.heightValue == 480 && changed?.xValue == 20 && changed?.yValue == 40,
      "Option inner-grip drag grows both sides around the original center")
for (start, end) in [(NSPoint(x: 100, y: 800), NSPoint(x: 80, y: 820)),
                     (NSPoint(x: 740, y: 800), NSPoint(x: 760, y: 820)),
                     (NSPoint(x: 100, y: 440), NSPoint(x: 80, y: 420)),
                     (NSPoint(x: 740, y: 440), NSPoint(x: 760, y: 420))] {
  reshape(from: start, to: end, modifiers: .option)
  let frame = changed!.previewFrame(screenSize: screen)
  check(changed?.widthValue == 680 && changed?.heightValue == 400 && near(frame.midX, 420) && near(frame.midY, 620),
        "Option uses the same center for each corner orientation")
}
reshape(from: NSPoint(x: 740, y: 620), to: NSPoint(x: 2000, y: 620), modifiers: .option)
var frameAfterOption = changed!.previewFrame(screenSize: screen)
check(changed?.widthValue == 840 && changed?.heightValue == 360 && near(frameAfterOption.midX, 420),
      "Option edge growth stops at the closest screen boundary without moving the center")
var optionDraft = InitialWindowGeometry("640x360+100-100")
optionDraft.prepareIndependentSize(screenSize: screen, aspect: 16 / 9)
geom.setGeometry(optionDraft, screenSize: screen)
geom.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 716, y: 464)))
geom.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 736, y: 444), modifiers: .option))
frameAfterOption = changed!.previewFrame(screenSize: screen)
check(near(frameAfterOption.midX, 420) && near(frameAfterOption.midY, 620), "Option can be pressed during an existing corner drag")
geom.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 736, y: 444)))
check(changed?.widthValue == 660 && changed?.heightValue == 380 && changed?.xValue == 100 && changed?.yValue == 100,
      "releasing Option restores ordinary corner anchoring from the captured start frame")
geom.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 736, y: 444)))

class CursorRecordingPreview: WindowGeometryPreviewView {
  var registeredCursors: [(NSRect, NSCursor)] = []
  override func addCursorRect(_ rect: NSRect, cursor: NSCursor) { registeredCursors.append((rect, cursor)) }
}
let cursorPreview = CursorRecordingPreview(frame: geom.bounds)
cursorPreview.dock = nil
cursorPreview.setGeometry(optionDraft, screenSize: screen)
cursorPreview.resetCursorRects()
let diagonalCursors = cursorPreview.registeredCursors.filter { $0.0.width <= 16 && $0.0.height <= 16 }.map { $0.1 }
check(diagonalCursors.count == 5 && diagonalCursors.allSatisfy { $0 !== NSCursor.crosshair && $0 !== NSCursor.resizeUpDown && $0 !== NSCursor.resizeLeftRight },
      "all four corners and the full grip receive diagonal cursors instead of crosshair or axis cursors")
cursorPreview.registeredCursors = []
cursorPreview.setGeometry(InitialWindowGeometry("640+100-100"), screenSize: screen)
cursorPreview.resetCursorRects()
check(cursorPreview.registeredCursors.last?.1 === diagonalCursors.last,
      "locked grip uses the same native diagonal cursor as the free grip")
// Exercise the displayed frame as well as the integer settings during a continuous gesture.
let trackingWindow = NSWindow(contentRect: geom.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
trackingWindow.isReleasedWhenClosed = false
trackingWindow.contentView = cursorPreview
func trackingMouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
  NSEvent.mouseEvent(with: type, location: cursorPreview.convert(local(point), to: nil), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: trackingWindow.windowNumber,
                    context: nil, eventNumber: checks, clickCount: 1, pressure: 1)!
}
func displayedFrame() -> NSRect {
  cursorPreview.registeredCursors = []
  cursorPreview.resetCursorRects()
  return cursorPreview.registeredCursors.first { $0.1 === NSCursor.openHand }!.0
}
for raw in ["640+50%+50%", "40%+50%+50%", "640x360+50%+50%"] {
  var tracked = InitialWindowGeometry(raw)
  if raw.contains("x") { tracked.prepareIndependentSize(screenSize: screen, aspect: 16 / 9) }
  cursorPreview.setGeometry(tracked, screenSize: screen)
  cursorPreview.clearInteraction()
  // Mirror the sheet's synchronous updateControls -> setGeometry feedback.
  cursorPreview.onGeometryChanged = { cursorPreview.setGeometry($0, screenSize: screen) }
  let originalFrame = displayedFrame()
  let start = NSPoint(x: 1108, y: 282)
  cursorPreview.mouseDown(with: trackingMouse(.leftMouseDown, start))
  var stableCorner = true
  var smoothWidth = true
  for step in Array(1...80) + Array((0..<80).reversed()) {
    let point = NSPoint(x: start.x + CGFloat(step), y: start.y - CGFloat(step % 7))
    cursorPreview.mouseDragged(with: trackingMouse(.leftMouseDragged, point))
    let frame = displayedFrame()
    stableCorner = stableCorner && abs(frame.minX - originalFrame.minX) < 0.001
      && abs(frame.maxY - originalFrame.maxY) < 0.001
    smoothWidth = smoothWidth && abs(frame.width - originalFrame.width - CGFloat(step) * scale) < 0.001
  }
  check(stableCorner, "continuous non-diagonal resize keeps the opposite corner fixed: \(raw)")
  check(smoothWidth, "continuous resize does not inherit whole-percent steps from fields: \(raw)")
  cursorPreview.mouseUp(with: trackingMouse(.leftMouseUp, start))
}
cursorPreview.onGeometryChanged = nil

var centeredFree = InitialWindowGeometry("640x360")
centeredFree.prepareIndependentSize(screenSize: screen, aspect: 16 / 9)
geom.setGeometry(centeredFree, screenSize: screen)
geom.minimumSize = AppData.floatingOSCWindowMinSize
geom.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 1120, y: 450)))
geom.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 1200, y: 450)))
geom.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 1200, y: 450)))
check(changed?.widthValue == 800 && changed?.heightValue == 360 && changed?.positionEnabled == false,
      "free resize with position disabled keeps the window centered and leaves height unchanged")
geom.setGeometry(centeredFree, screenSize: screen)
geom.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 800, y: 270)))
geom.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 800, y: 449)))
geom.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 800, y: 449)))
check(changed?.widthValue == 640 && changed?.heightValue == 225,
      "free edge resize uses the actual floating-player minimum on the affected axis")
let contextSelector = PositionPreviewContextSelector()
let contextWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 40),
                             styleMask: [.borderless], backing: .buffered, defer: false)
contextWindow.isReleasedWhenClosed = false
contextWindow.contentView = contextSelector
var contextSize: NSSize?
contextSelector.onSizeChanged = { contextSize = $0 }
contextSelector.configure([PositionPreviewContext(title: "Wide", size: NSSize(width: 2100, height: 900)),
                           PositionPreviewContext(title: "Portrait", size: NSSize(width: 900, height: 1600))])
settle()
let selectorViews = descendants(contextSelector)
let contextMenu = selectorViews.compactMap { $0 as? NSPopUpButton }.first!
let dimensionFields = selectorViews.compactMap { $0 as? NSTextField }.filter { $0.isEditable }
check(contextSize == NSSize(width: 2100, height: 900) && dimensionFields.allSatisfy { $0.isHiddenOrHasHiddenAncestor },
      "real preview context hides custom dimensions")
contextMenu.selectItem(at: 1)
contextMenu.sendAction(contextMenu.action!, to: contextMenu.target)
check(contextSize == NSSize(width: 900, height: 1600), "context selection supplies portrait screen dimensions")
contextMenu.selectItem(at: 2)
contextMenu.sendAction(contextMenu.action!, to: contextMenu.target)
settle()
check(dimensionFields.allSatisfy { !$0.isHiddenOrHasHiddenAncestor } &&
      near(dimensionFields[0].frame.midY, dimensionFields[1].frame.midY),
      "Custom reveals width and height in the same row")
dimensionFields[0].stringValue = "1000"
dimensionFields[1].stringValue = "1800"
contextSelector.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: dimensionFields[0]))
check(contextSize == NSSize(width: 1000, height: 1800), "Custom dimensions update only preview context")
for invalid in ["0", "-5", "1.5", "100001", "1000001", "abc"] {
  dimensionFields[0].stringValue = invalid
  contextSelector.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: dimensionFields[0]))
  check(contextSize == NSSize(width: 1000, height: 1800), "invalid preview dimensions retain the last valid context")
}
// Wallpaper fitting and context retention use fixtures rather than desktop-specific files.
let wallpaperImage = NSImage(size: NSSize(width: 200, height: 100))
wallpaperImage.lockFocus()
NSColor.systemBlue.setFill()
NSRect(x: 0, y: 0, width: 200, height: 100).fill()
wallpaperImage.unlockFocus()
var background = DesktopPreviewBackground(image: wallpaperImage)
let target = NSRect(x: 10, y: 20, width: 100, height: 100)
let wallpaperFrame = background.imageFrame(in: target)
check(near(wallpaperFrame.width, 200) && near(wallpaperFrame.height, 100) && near(wallpaperFrame.midX, target.midX),
      "wallpaper fills a different display aspect without stretching or bands")
for size in [NSSize(width: 1800, height: 1169), NSSize(width: 900, height: 1600), NSSize(width: 2400, height: 900)] {
  let display = NSRect(origin: .zero, size: size)
  let imageFrame = background.imageFrame(in: display)
  check(imageFrame.contains(display), "wallpaper covers landscape, portrait and wide displays")
}
let desktopLayout = DesktopPreviewLayout(bounds: NSRect(x: 0, y: 0, width: 560, height: 315),
  availableSize: NSSize(width: 1800, height: 1050),
  visibleRegion: NSRect(x: 0, y: 80.0 / 1169.0, width: 1, height: 1050.0 / 1169.0))
check(near(desktopLayout.displayFrame.width / desktopLayout.displayFrame.height, 1800.0 / 1169.0),
      "desktop preview preserves the full physical display aspect")
check(near(desktopLayout.workAreaFrame.height / desktopLayout.scale, 1050) &&
      near(desktopLayout.menuBarFrame.minY, desktopLayout.workAreaFrame.maxY),
      "menu bar sits above the measured work area without altering available geometry")
for edge in [DesktopPreviewDock.Edge.bottom, .left, .right] {
  let dock = DesktopPreviewDock(edge: edge, thickness: 80, length: 600)
  for size in [NSSize(width: 1800, height: 1130), NSSize(width: 2560, height: 1440), NSSize(width: 900, height: 1600)] {
    let layout = DesktopPreviewLayout(bounds: NSRect(x: 0, y: 0, width: 560, height: 315),
      availableSize: size, dock: dock)
    let frame = layout.dockFrame!
    check(layout.displayFrame.contains(frame), "shared Dock stays inside real-display and Custom previews")
    check(near((edge == .bottom ? frame.height : frame.width) / layout.scale, 76),
          "all previews use the same system Dock thickness")
    check(near((edge == .bottom ? frame.width : frame.height) / layout.scale, 600),
          "all previews use the same illustrative Dock length in logical points")
    check(edge == .bottom ? frame.maxY <= layout.displayFrame.minY + 80 * layout.scale + 0.000001 :
          (edge == .left ? frame.maxX <= layout.displayFrame.minX + 80 * layout.scale + 0.000001 :
            frame.minX >= layout.displayFrame.maxX - 80 * layout.scale - 0.000001),
          "shared Dock follows its system edge even when the selected display has no Dock margin")
    check(!layout.workAreaFrame.intersects(frame.insetBy(dx: 0.000001, dy: 0.000001)),
          "shared Dock is excluded from the work area on displays without a real Dock and Custom")
    let gap = edge == .bottom ? layout.workAreaFrame.minY - frame.maxY :
      (edge == .left ? layout.workAreaFrame.minX - frame.maxX : frame.minX - layout.workAreaFrame.maxX)
    check(abs(gap) < 0.001, "Dock contact edge coincides exactly with the movement boundary")
    check(near(layout.workAreaSize.width, size.width - (edge == .bottom ? 0 : 80)) &&
          near(layout.workAreaSize.height, size.height - (edge == .bottom ? 80 : 0)),
          "geometry units reserve the shared Dock exactly once")
  }
}
let measuredDockLayout = DesktopPreviewLayout(bounds: geom.bounds,
  availableSize: NSSize(width: 1800, height: 1050),
  visibleRegion: NSRect(x: 0, y: 80.0 / 1169.0, width: 1, height: 1050.0 / 1169.0),
  dock: DesktopPreviewDock(edge: .bottom, thickness: 80, length: 600))
check(near(measuredDockLayout.workAreaSize.height, 1050),
      "the display hosting the real Dock does not lose its reserved space twice")

let dockWindow = NSWindow(contentRect: geom.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
dockWindow.isReleasedWhenClosed = false
let dockPreview = CursorRecordingPreview(frame: geom.bounds)
dockWindow.contentView = dockPreview
func dockWindowFrame() -> NSRect {
  dockPreview.registeredCursors = []
  dockPreview.resetCursorRects()
  return dockPreview.registeredCursors.first { $0.1 === NSCursor.openHand }!.0
}
func dockMouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
  NSEvent.mouseEvent(with: type, location: dockPreview.convert(point, to: nil), modifierFlags: [],
    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: dockWindow.windowNumber,
    context: nil, eventNumber: checks, clickCount: 1, pressure: 1)!
}
for edge in [DesktopPreviewDock.Edge.bottom, .left, .right] {
  dockPreview.dock = DesktopPreviewDock(edge: edge, thickness: 80, length: 600)
  for size in [NSSize(width: 1800, height: 1130), NSSize(width: 900, height: 1600), NSSize(width: 1000, height: 1000)] {
    let layout = DesktopPreviewLayout(bounds: geom.bounds, availableSize: size, dock: dockPreview.dock)
    dockPreview.onGeometryChanged = { dockPreview.setGeometry($0, screenSize: size) }
    func checkDockBoundary(_ message: String) {
      let frame = dockWindowFrame()
      check(layout.workAreaFrame.insetBy(dx: -0.001, dy: -0.001).contains(frame) &&
            !frame.intersects(layout.dockFrame!.insetBy(dx: 0.000001, dy: 0.000001)), message)
    }
    for raw in ["640+0-0", "640-0+0", "100%+100%+100%", "100%x100%+100%+100%"] {
      var geometry = InitialWindowGeometry(raw)
      if raw.contains("x") { geometry.prepareIndependentSize(screenSize: layout.workAreaSize, aspect: 16 / 9) }
      dockPreview.setGeometry(geometry, screenSize: size)
      checkDockBoundary("numeric position and size remain outside the shared Dock")
    }
    dockPreview.setGeometry(InitialWindowGeometry("640+50%+50%"), screenSize: size)
    var frame = dockWindowFrame()
    let start = NSPoint(x: frame.midX, y: frame.midY)
    // Drag beyond each edge, including the reserved Dock margin.
    for destination in [NSPoint(x: -2000, y: -2000), NSPoint(x: 2000, y: 2000)] {
      dockPreview.mouseDown(with: dockMouse(.leftMouseDown, NSPoint(x: frame.midX, y: frame.midY)))
      dockPreview.mouseDragged(with: dockMouse(.leftMouseDragged, destination))
      dockPreview.mouseUp(with: dockMouse(.leftMouseUp, destination))
      checkDockBoundary("released dragging remains outside the shared Dock")
      frame = dockWindowFrame()
      if edge == .bottom && destination.y < 0 || edge == .left && destination.x < 0 || edge == .right && destination.x > 0 {
        let dock = layout.dockFrame!
        let gap = edge == .bottom ? frame.minY - dock.maxY :
          (edge == .left ? frame.minX - dock.maxX : dock.minX - frame.maxX)
        check(abs(gap) < 0.001, "released percentage drag stays flush with the Dock in real-display and Custom previews")
      }
    }
    dockPreview.setGeometry(InitialWindowGeometry("640+50%+50%"), screenSize: size)
    frame = dockWindowFrame()
    dockPreview.mouseDown(with: dockMouse(.leftMouseDown, NSPoint(x: frame.maxX - 2, y: frame.minY + 2)))
    dockPreview.mouseDragged(with: dockMouse(.leftMouseDragged, NSPoint(x: 2000, y: -2000)))
    checkDockBoundary("continuous locked resizing cannot enter the shared Dock")
    dockPreview.mouseUp(with: dockMouse(.leftMouseUp, start))
    checkDockBoundary("released locked resizing remains outside the shared Dock")
  }
}
contextSelector.configure([PositionPreviewContext(title: "Wallpaper", size: target.size, desktopBackground: background),
                           PositionPreviewContext(title: "Unavailable", size: target.size)])
check(contextSelector.selectedDesktopBackground?.image === wallpaperImage, "selected display supplies its wallpaper")
contextMenu.selectItem(at: 2)
contextMenu.sendAction(contextMenu.action!, to: contextMenu.target)
check(contextSelector.selectedDesktopBackground?.image === wallpaperImage, "Custom retains the last selected display wallpaper")
contextMenu.selectItem(at: 1)
contextMenu.sendAction(contextMenu.action!, to: contextMenu.target)
check(contextSelector.selectedDesktopBackground == nil, "unavailable wallpaper clears the previous display background")
let backgroundCanvas = NSImage(size: target.size)
backgroundCanvas.lockFocus()
background.visibleRegion = NSRect(x: 0, y: 0, width: 1, height: 1)
background.draw(in: NSRect(origin: .zero, size: target.size))
backgroundCanvas.unlockFocus()
let bitmap = NSBitmapImageRep(data: backgroundCanvas.tiffRepresentation!)!
let centerColor = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
check(centerColor.blueComponent > centerColor.redComponent, "desktop preview draws the supplied wallpaper image")
for y in [1, bitmap.pixelsHigh - 2] {
  let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: y)!.usingColorSpace(.deviceRGB)!
  check(color.blueComponent > color.redComponent, "wallpaper also covers the top and bottom display edges")
}
// A small window on a portrait display must scale its chrome with the desktop,
// rather than letting a fixed-height mock titlebar cover the video.
let portraitSize = NSSize(width: 900, height: 1600)
let portraitGeometry = InitialWindowGeometry("400+50%-50%")
geom.desktopBackground = nil
geom.minimumSize = AppData.floatingOSCWindowMinSize
geom.enforceMinimumAfterScreenFit = true
geom.setGeometry(portraitGeometry, screenSize: portraitSize)
let portraitLayout = DesktopPreviewLayout(bounds: geom.bounds, availableSize: portraitSize)
let physicalPortrait = portraitGeometry.previewFrame(screenSize: portraitSize,
  minimumSize: AppData.floatingOSCWindowMinSize, enforceMinimumAfterScreenFit: true)
let portraitTop = portraitLayout.workAreaFrame.minY + physicalPortrait.maxY * portraitLayout.scale
let portraitCenter = portraitLayout.workAreaFrame.minX + physicalPortrait.midX * portraitLayout.scale
for compact in [false, true] {
  geom.compactUI = compact
  let canvas = NSImage(size: geom.bounds.size)
  canvas.lockFocus()
  geom.draw(geom.bounds)
  canvas.unlockFocus()
  let rendered = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
  func portraitColor(depth: CGFloat) -> NSColor {
    let x = Int(portraitCenter / geom.bounds.width * CGFloat(rendered.pixelsWide))
    let y = Int((geom.bounds.height - portraitTop + depth * portraitLayout.scale) / geom.bounds.height * CGFloat(rendered.pixelsHigh))
    return rendered.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
  }
  let header = portraitColor(depth: geom.titlebarHeight / 2)
  let video = portraitColor(depth: geom.titlebarHeight + 8)
  check(abs(header.blueComponent - header.redComponent) < 0.15,
        "\(compact ? "compact" : "normal") portrait mock draws the native scaled header")
  check(video.blueComponent - video.redComponent > 0.2,
        "\(compact ? "compact" : "normal") portrait mock leaves video visible immediately below the native header")
}
geom.compactUI = false
Preference.oscPosition = .floating
sheet.present(on: parent, geometry: portraitGeometry)
settle()
let presentedPreview = descendants(sheet.window!.contentView!).compactMap { $0 as? WindowGeometryPreviewView }.first!
check(presentedPreview.enforceMinimumAfterScreenFit && presentedPreview.minimumSize == AppData.floatingOSCWindowMinSize,
      "floating sheet explicitly enables post-fit native minima")
cancel()
Preference.oscPosition = .bottom
sheet.present(on: parent, geometry: portraitGeometry)
settle()
check(!presentedPreview.enforceMinimumAfterScreenFit && presentedPreview.minimumSize == AppData.mainWindowMinSize,
      "reusing the sheet for docked mode restores proportional screen fitting")
cancel()

Preference.oscPosition = .floating
for unlocked in [false, true] {
  Preference.unlockWindowAspectRatio = unlocked
  sheet.present(on: parent, geometry: InitialWindowGeometry(unlocked ? "640x480+50%-50%" : "640+50%-50%"))
  settle()
  let selector = descendants(sheet.window!.contentView!).compactMap { $0 as? PositionPreviewContextSelector }.first!
  selector.customSizeLimits = (AppData.floatingOSCWindowMinSize, NSSize(width: 3200, height: 1800))
  // This fixture describes an already available work area. Dock reservation is
  // exercised separately, without depending on the machine running the suite.
  presentedPreview.dock = nil
  selector.configure([PositionPreviewContext(title: "Fixture", size: NSSize(width: 1600, height: 900))], minimumSize: AppData.floatingOSCWindowMinSize)
  let inputs = unlocked ? [("$Width", 400, 1600), ("$Height", 225, 900)] : [("$InitialWindowSize", 400, 1600)]
  for (label, lower, upper) in inputs {
    edit(label, "-1")
    sheet.window!.makeFirstResponder(nil)
    check(field(label).integerValue == lower, "\(unlocked ? "free" : "locked") \(label) clamps to native minimum")
    edit(label, "99999")
    sheet.window!.makeFirstResponder(nil)
    check(field(label).integerValue == upper, "\(label) clamps to available desktop")
    edit(label, "abc")
    sheet.window!.makeFirstResponder(nil)
    check(field(label).integerValue == upper, "\(label) restores malformed input")
  }
  check(!field(".horizontal").isEnabled && !field(".vertical").isEnabled,
        "full-size window disables both position inputs")
  check(field(".horizontal").integerValue == 50 && field(".vertical").integerValue == 50,
        "disabled position fields preserve requested placement")
  let limitedField = field(unlocked ? "$Width" : "$InitialWindowSize")
  sheet.window!.makeFirstResponder(limitedField)
  let editor = limitedField.currentEditor() as! NSTextView
  let before = editor.string
  editor.insertText("123456", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
  check(editor.string == before, "window size rejects six-digit replacement")
  sheet.window!.makeFirstResponder(nil)
  cancel()
}
Preference.unlockWindowAspectRatio = false
for (raw, minimum, maximum) in [("40%", 25, 100), ("x40%", 25, 100), ("x360", 225, 900)] {
  sheet.present(on: parent, geometry: InitialWindowGeometry(raw))
  settle()
  let selector = descendants(sheet.window!.contentView!).compactMap { $0 as? PositionPreviewContextSelector }.first!
  presentedPreview.dock = nil
  selector.configure([PositionPreviewContext(title: "Fixture", size: NSSize(width: 1600, height: 900))])
  edit("$InitialWindowSize", "-5")
  sheet.window!.makeFirstResponder(nil)
  check(field("$InitialWindowSize").integerValue == minimum, "\(raw) uses dimension and unit-specific minimum")
  edit("$InitialWindowSize", "99999")
  sheet.window!.makeFirstResponder(nil)
  check(field("$InitialWindowSize").integerValue == maximum, "\(raw) uses dimension and unit-specific maximum")
  cancel()
}
Preference.unlockWindowAspectRatio = true
sheet.present(on: parent, geometry: InitialWindowGeometry("640x480+10-20"))
settle()
let boundedSelector = descendants(sheet.window!.contentView!).compactMap { $0 as? PositionPreviewContextSelector }.first!
boundedSelector.customSizeLimits = (AppData.floatingOSCWindowMinSize, NSSize(width: 2400, height: 1600))
presentedPreview.dock = nil
boundedSelector.configure([PositionPreviewContext(title: "Fixture", size: NSSize(width: 1600, height: 900))], minimumSize: AppData.floatingOSCWindowMinSize)
for (axis, maximum) in [(".horizontal", 960), (".vertical", 420)] {
  edit(axis, "99999")
  sheet.window!.makeFirstResponder(nil)
  check(field(axis).integerValue == maximum, "point position stops at available travel")
  edit(axis, "-20")
  sheet.window!.makeFirstResponder(nil)
  check(field(axis).integerValue == 0, "point position clamps to zero")
}
let customMenu = descendants(boundedSelector).compactMap { $0 as? NSPopUpButton }.first!
customMenu.selectItem(at: customMenu.numberOfItems - 1)
customMenu.sendAction(customMenu.action!, to: customMenu.target)
let customFields = descendants(boundedSelector).compactMap { $0 as? PositionSettingsTextField }
for (index, text, expected) in [(0, "1", 400), (1, "1", 225), (0, "99999", 2400), (1, "99999", 1600)] {
  let input = customFields[index]
  sheet.window!.makeFirstResponder(input)
  input.currentEditor()!.string = text
  sheet.window!.makeFirstResponder(nil)
  check(input.integerValue == expected, "virtual desktop dimension clamps to native minimum or connected maximum")
}
cancel()
for raw in ["40%x50%", "640x50%", "40%x480"] {
  var committed: InitialWindowGeometry?
  sheet.present(on: parent, geometry: InitialWindowGeometry(raw)) { committed = $0 }
  settle()
  let selector = descendants(sheet.window!.contentView!).compactMap { $0 as? PositionPreviewContextSelector }.first!
  presentedPreview.dock = nil
  selector.configure([PositionPreviewContext(title: "Fixture", size: NSSize(width: 1600, height: 900))])
  edit("$Width", "-1")
  sheet.window!.makeFirstResponder(nil)
  edit("$Height", "99999")
  sheet.window!.makeFirstResponder(nil)
  save()
  check(committed?.widthValue == (raw.hasPrefix("40%") ? 25 : 400), "independent width honors its own unit")
  check(committed?.heightValue == (raw.contains("50%") ? 100 : 900), "independent height honors its own unit")
}
let rememberedContextKey = "prepublish-preview-limits"
UserDefaults.standard.set(["context": "custom", "width": 100000, "height": 100000], forKey: rememberedContextKey)
let rememberedSelector = PositionPreviewContextSelector()
rememberedSelector.customSizeLimits = (AppData.floatingOSCWindowMinSize, NSSize(width: 2400, height: 1600))
rememberedSelector.configure([PositionPreviewContext(title: "Fixture", size: NSSize(width: 1600, height: 900))],
                             minimumSize: AppData.floatingOSCWindowMinSize,
                             rememberSelectionUnder: rememberedContextKey)
check(rememberedSelector.selectedSize == NSSize(width: 2400, height: 1600),
      "remembered custom preview is bounded by currently connected displays")
UserDefaults.standard.removeObject(forKey: rememberedContextKey)
print("Completed \(checks) editor checks with \(failures) failures.")
exit(failures == 0 ? 0 : 1)
