import Darwin
setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
defer { Preference.ud.removePersistentDomain(forName: Preference.suiteName) }
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message); checks += 1; print("PASS: \(message)")
}
func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
func button(_ title: String, in main: MainWindowController) -> NSButton {
  descendants(main.videoViewContainer).compactMap { $0 as? NSButton }.first { $0.title == title }!
}
func input(_ label: String, in main: MainWindowController) -> NSTextField {
  descendants(main.videoViewContainer).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == label }!
}
func box(in main: MainWindowController) -> CropBoxView {
  descendants(main.videoViewContainer).compactMap { $0 as? CropBoxView }.first!
}
func selector(in main: MainWindowController) -> ScrollSelectionControl {
  descendants(main.videoViewContainer).compactMap { $0 as? ScrollSelectionControl }.first!
}
func zoomControl(in main: MainWindowController) -> NSPopUpButton {
  descendants(main.videoViewContainer).compactMap { $0 as? NSPopUpButton }.first!
}
func edit(_ input: NSTextField, _ text: String, in main: MainWindowController, finish: Bool = false) {
  input.stringValue = text
  let notification = Notification(name: NSControl.textDidChangeNotification, object: input)
  if finish { main.interactiveMode.controlTextDidEndEditing(notification) }
  else { main.interactiveMode.controlTextDidChange(notification) }
}
func wheel(_ selector: ScrollSelectionControl, _ dy: CGFloat, precise: Bool = false,
           phase: NSEvent.Phase = [], momentum: NSEvent.Phase = [], time: TimeInterval = 1) {
  let event = WheelEvent(); event.dy = dy; event.precise = precise
  event.gesturePhase = phase; event.inertia = momentum; event.time = time
  selector.scrollWheel(with: event)
}

func delogoParameters(_ filter: MPVFilter?) -> [String: String]? {
  guard let graph = filter?.rawParamString, graph.hasPrefix("[delogo="), graph.hasSuffix("]") else { return nil }
  return Dictionary(uniqueKeysWithValues: graph.dropFirst(8).dropLast().split(separator: ":").map {
    let pair = $0.split(separator: "=", maxSplits: 1); return (String(pair[0]), String(pair[1]))
  })
}
check(MPVFilter.crop(w: 640, h: 360, x: nil, y: nil).stringFormat == "crop=640:360::", "existing automatic crop serialization stays unchanged")
let protectedCrop = MPVFilter.crop(w: 501, h: 301, x: 101, y: 166, exact: true)
check(protectedCrop.stringFormat.hasPrefix("lavfi=[format=pix_fmts=") &&
      protectedCrop.stringFormat.hasSuffix(",crop=501:301:101:166:exact=1]"),
      "odd exact pixel crop converts chroma before the unchanged source-pixel coordinates")
let restoredExactFilter = MPVFilter(name: "crop", label: "iina_crop", params: ["w": "501", "h": "301", "x": "230", "y": "120", "exact": "1"])
check(restoredExactFilter.stringFormat.hasPrefix("@iina_crop:lavfi=[format=pix_fmts=") &&
      restoredExactFilter.stringFormat.hasSuffix(",crop=501:301:230:120:exact=1]"),
      "old persisted exact crops gain chroma protection without losing their coordinates")
let graphStart = protectedCrop.stringFormat.index(after: protectedCrop.stringFormat.firstIndex(of: "[")!)
let protectedGraph = String(protectedCrop.stringFormat[graphStart..<protectedCrop.stringFormat.index(before: protectedCrop.stringFormat.endIndex)])
let engineCrop = MPVFilter(name: "lavfi", label: nil, params: ["graph": protectedGraph])
check(engineCrop.isEqual(protectedCrop) && engineCrop.params == protectedCrop.params,
      "mpv's lavfi readback restores the logical crop for editor selection and persistence")
check(MPVFilter(rawString: protectedCrop.stringFormat)?.isEqual(protectedCrop) == true,
      "raw protected crop round-trips through the existing filter abstraction")
check(MPVFilter.crop(w: 640, h: 360, x: 100, y: 80, exact: true).stringFormat == "crop=640:360:100:80:exact=1",
      "aligned exact crops keep the direct filter without a format conversion")
if let path = ProcessInfo.processInfo.environment["CROP_FILTER_OUTPUT"] {
  let filter = MPVFilter.crop(w: 31, h: 21, x: 5, y: 7, exact: true)
  try! JSONSerialization.data(withJSONObject: ["filter": filter.stringFormat], options: [.prettyPrinted])
    .write(to: URL(fileURLWithPath: path))
}
let ratioGeometry = CropVideoGeometry(sourceSize: NSSize(width: 1920, height: 1080),
                                     displaySize: NSSize(width: 1920, height: 1080), rotation: 0)
for (size, title) in [(NSSize(width: 900, height: 420), "15:7"),
                      (NSSize(width: 958, height: 260), "70:19"),
                      (NSSize(width: 748, height: 478), "97:62"),
                      (NSSize(width: 1919, height: 1079), "16:9"),
                      (NSSize(width: 540, height: 960), "9:16"),
                      (NSSize(width: 1, height: 1), "1:1"),
                      (NSSize(width: 10000, height: 1), "99:1")] {
  check(ratioGeometry.aspectTitle(for: NSRect(origin: .zero, size: size)) == title,
        "compact ratio for \(size) is \(title)")
  let transposed = NSRect(x: 0, y: 0, width: size.height, height: size.width)
  check(ratioGeometry.aspectTitle(for: transposed) == title.split(separator: ":").reversed().joined(separator: ":"),
        "transposing \(size) reverses the compact ratio")
}
check(ratioGeometry.aspectTitle(for: .zero) == "—", "empty selection has no ratio")
for (from, to, path, direction) in [("7", "5", ["7", "6", "5"], -1),
                                   ("9", "1", ["9", "0", "1"], 1),
                                   ("1", "9", ["1", "0", "9"], -1),
                                   ("0", "5", ["0", "1", "2", "3", "4", "5"], 1),
                                   ("5", "5", ["5"], 1)] {
  let roll = ScrollSelectionDigitRoll.path(from: from, to: to)!
  check(roll.titles == path && roll.direction == direction, "digit drum \(from) → \(to) follows the shortest cyclic path")
}
let shortestPaths = (0...9).allSatisfy { from in
  (0...9).allSatisfy { to in
    let roll = ScrollSelectionDigitRoll.path(from: String(from), to: String(to))!
    let steps = roll.titles.count - 1
    return roll.titles.first == String(from) && roll.titles.last == String(to) &&
      steps == min(abs(to - from), 10 - abs(to - from)) &&
      zip(roll.titles, roll.titles.dropFirst()).allSatisfy { (Int($0)! + roll.direction + 10) % 10 == Int($1)! }
  }
}
check(shortestPaths, "all 100 digit transitions use adjacent cyclic steps and at most five turns")
check(ScrollSelectionDigitRoll.path(from: ":", to: "1") == nil &&
      ScrollSelectionDigitRoll.glyphs(in: "—") == nil && ScrollSelectionDigitRoll.glyphs(in: "1.5:1") == nil,
      "nonnumeric titles and separators are never digit wheels")
let oldColumns = Dictionary(uniqueKeysWithValues: ScrollSelectionDigitRoll.glyphs(in: "17:9")!.map { ($0.column, $0.text) })
let newColumns = Dictionary(uniqueKeysWithValues: ScrollSelectionDigitRoll.glyphs(in: "5:10")!.map { ($0.column, $0.text) })
check(oldColumns[.digit(side: 0, place: 0)] == "7" && newColumns[.digit(side: 0, place: 0)] == "5" &&
      oldColumns[.digit(side: 1, place: 0)] == "9" && newColumns[.digit(side: 1, place: 0)] == "0" &&
      newColumns[.digit(side: 0, place: 1)] == nil && newColumns[.digit(side: 1, place: 1)] == "1",
      "changing number lengths pairs units on each side independently")
let rotatedAnamorphic = CropVideoGeometry(sourceSize: NSSize(width: 720, height: 576),
                                         displaySize: NSSize(width: 1024, height: 576), rotation: 90)
check(rotatedAnamorphic.aspectTitle(for: NSRect(origin: .zero, size: rotatedAnamorphic.selectionSize)) == "9:16",
      "compact ratio accounts for rotation and nonsquare pixels together")
// Personal presets start empty and persist exact display ratios without an input dialog.
Preference.set(nil, for: .customCropAspectPresets)
let personal = MainWindowController()
personal.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
var personalMenu = personal.interactiveMode.makeAspectMenu()
check(personalMenu.items.map { $0.title } == ["Add…"] && personalMenu.items[0].isEnabled,
      "empty personal menu contains only Add, with no built-ins or separator")
let initialPersonalRect = box(in: personal).selectedRect
wheel(selector(in: personal), -1)
wheel(selector(in: personal), 1)
check(box(in: personal).selectedRect == initialPersonalRect && selector(in: personal).label(forSegment: 0) == "16:9",
      "cycling an empty personal list keeps the current frame and ratio")
func choose(_ item: NSMenuItem) {
  NSApp.sendAction(item.action!, to: item.target, from: item)
}
box(in: personal).setSelectedRect(to: NSRect(x: 100, y: 0, width: 450, height: 540))
let personalRect = box(in: personal).selectedRect
let windowsBeforeAdd = NSApp.windows.count
choose(personalMenu.items.last!)
check(NSApp.windows.count == windowsBeforeAdd, "Add opens no input dialog or additional window")
personalMenu = personal.interactiveMode.makeAspectMenu()
check(personalMenu.items.map { $0.title } == ["5:6", "", "Add…"] && personalMenu.items[1].isSeparatorItem,
      "Add immediately saves the current ratio and creates the personal list")
check(box(in: personal).selectedRect == personalRect && personal.interactiveMode.isActive &&
      personal.player.savedCrop == nil && personalMenu.items[0].state == .on,
      "adding a preset keeps the exact frame, active editor and unapplied crop")
check(!personalMenu.items.last!.isEnabled, "Add is disabled when the current ratio is already saved")
choose(personalMenu.items.last!)
check(Preference.array(for: .customCropAspectPresets)?.count == 1,
      "duplicate Add actions do not create duplicate presets")
let exactPersonalRect = NSRect(x: 101, y: 73, width: 501, height: 301)
box(in: personal).setSelectedRect(to: exactPersonalRect)
choose(personal.interactiveMode.makeAspectMenu().items.last!)
let exactSaved = Preference.array(for: .customCropAspectPresets) as! [Double]
check(exactSaved.count == 2 && abs(exactSaved[1] - 501.0 / 301) < 1e-12 &&
      personal.interactiveMode.makeAspectMenu().items[1].title == "5:3",
      "personal presets store the exact aspect even when the short label is approximate")
let persisted = UserDefaults(suiteName: Preference.suiteName)!
check(persisted.array(forKey: Preference.Key.customCropAspectPresets.rawValue) as? [Double] == exactSaved,
      "a fresh defaults instance reads the saved personal ratios")
button("Cancel", in: personal).performClick(nil)
check(Preference.array(for: .customCropAspectPresets)?.count == 2,
      "Cancel restores the crop without discarding saved presets")
let otherPersonal = MainWindowController()
otherPersonal.player.originalVideoSize = (1920, 1080)
otherPersonal.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
let otherPersonalMenu = otherPersonal.interactiveMode.makeAspectMenu()
check(otherPersonalMenu.items.map { $0.title } == ["5:6", "5:3", "", "Add…"],
      "a new player inherits only saved personal presets")
choose(otherPersonalMenu.items[0])
check(box(in: otherPersonal).selectedRect.size == NSSize(width: 900, height: 1080),
      "a saved aspect adapts to a different video resolution")
choose(otherPersonalMenu.items[1])
check(box(in: otherPersonal).selectedRect.size == NSSize(width: 1798, height: 1080),
      "reapplying a personal preset uses its exact ratio rather than its rounded label")
let personalAnamorphic = MainWindowController()
personalAnamorphic.player.originalVideoSize = (720, 576)
personalAnamorphic.player.displaySizeOverride = NSSize(width: 1024, height: 576)
personalAnamorphic.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
choose(personalAnamorphic.interactiveMode.makeAspectMenu().items[0])
check(box(in: personalAnamorphic).selectedRect.size == NSSize(width: 338, height: 576),
      "personal presets adapt to nonsquare source pixels")
box(in: personalAnamorphic).setSelectedRect(to: NSRect(x: 0, y: 0, width: 300, height: 512))
check(!personalAnamorphic.interactiveMode.makeAspectMenu().items.last!.isEnabled,
      "the same display aspect on anamorphic video is recognized as already saved")
box(in: personalAnamorphic).setSelectedRect(to: NSRect(x: 0, y: 0, width: 400, height: 512))
choose(personalAnamorphic.interactiveMode.makeAspectMenu().items.last!)
check(abs((Preference.array(for: .customCropAspectPresets) as! [Double]).last! - 10.0 / 9) < 1e-12,
      "Add accounts for pixel aspect when saving from anamorphic video")
check(otherPersonal.interactiveMode.makeAspectMenu().items.map { $0.title } == ["5:6", "5:3", "10:9", "", "Add…"],
      "an already open editor refreshes presets saved by another player")
let stableItem = otherPersonal.interactiveMode.makeAspectMenu().items[0]
Preference.set([10.0/9, 5.0/6], for: .customCropAspectPresets)
choose(stableItem)
check(box(in: otherPersonal).selectedRect.size == NSSize(width: 900, height: 1080),
      "menu selection remains tied to its ratio if another player changes the list")
Preference.set([0, -1, "invalid", true, Double.infinity, 5.0/6, 5.0/6] as [Any], for: .customCropAspectPresets)
check(otherPersonal.interactiveMode.makeAspectMenu().items.map { $0.title } == ["5:6", "", "Add…"],
      "malformed and duplicate stored entries do not enter the menu")
box(in: otherPersonal).setSelectedRect(to: .zero)
check(!otherPersonal.interactiveMode.makeAspectMenu().items.last!.isEnabled,
      "an empty frame cannot be added as a personal preset")
let rotatedPersonal = MainWindowController()
rotatedPersonal.player.originalVideoSize = (720, 576)
rotatedPersonal.player.displaySizeOverride = NSSize(width: 1024, height: 576)
rotatedPersonal.player.rotation = 90
rotatedPersonal.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
box(in: rotatedPersonal).setSelectedRect(to: NSRect(x: 0, y: 0, width: 400, height: 300))
choose(rotatedPersonal.interactiveMode.makeAspectMenu().items.last!)
check(abs((Preference.array(for: .customCropAspectPresets) as! [Double]).last! - 15.0 / 16) < 1e-12,
      "Add stores the displayed ratio after rotation and nonsquare-pixel correction")
rotatedPersonal.interactiveMode.exit()
// Publish the latest typed geometry even while its ratio label is still settled on the previous value.
box(in: personalAnamorphic).setSelectedRect(to: NSRect(x: 0, y: 0, width: 400, height: 512))
edit(input("Width in pixels", in: personalAnamorphic), "350", in: personalAnamorphic)
let typedRatio = 350.0 / 512 * 64 / 45
choose(personalAnamorphic.interactiveMode.makeAspectMenu().items.last!)
check(abs((Preference.array(for: .customCropAspectPresets) as! [Double]).last! - typedRatio) < 1e-12,
      "Add saves the latest typed W/H rather than the previous displayed ratio")
for controller in [personal, otherPersonal, personalAnamorphic] { controller.interactiveMode.exit() }

// Deleting saved choices changes only the personal list, including stale-item handling.
Preference.set([5.0/6, 3.0/2, 5.0/4], for: .customCropAspectPresets)
let deletion = MainWindowController()
deletion.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
box(in: deletion).setSelectedRect(to: NSRect(x: 100, y: 0, width: 450, height: 540))
box(in: deletion).setZoom(2)
let beforeDeletionRect = box(in: deletion).selectedRect
let beforeDeletionPreview = box(in: deletion).previewTransform
let beforeDeletionWindow = deletion.window!.frame
let deleteOther = deletion.interactiveMode.makeAspectMenu().items[1]
deletion.interactiveMode.deleteAspectPreset(deleteOther)
check(Preference.array(for: .customCropAspectPresets) as? [Double] == [5.0/6, 5.0/4],
      "Delete removes only the requested saved ratio")
check(box(in: deletion).selectedRect == beforeDeletionRect &&
      box(in: deletion).previewTransform == beforeDeletionPreview &&
      deletion.window!.frame == beforeDeletionWindow && selector(in: deletion).label(forSegment: 0) == "5:6" &&
      deletion.player.savedCrop == nil && deletion.interactiveMode.isActive,
      "deleting another preset preserves the frame, zoom, label, window and unapplied crop")
let deletionReload = MainWindowController()
deletionReload.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
check(deletionReload.interactiveMode.makeAspectMenu().items.map { $0.title } == ["5:6", "5:4", "", "Add…"],
      "a new editor sees the persisted deletion")
deletion.interactiveMode.deleteAspectPreset(deletion.interactiveMode.makeAspectMenu().items[0])
check(box(in: deletion).selectedRect == beforeDeletionRect && selector(in: deletion).label(forSegment: 0) == "5:6" &&
      deletion.interactiveMode.makeAspectMenu().items.last!.isEnabled,
      "deleting the selected preset keeps its crop and makes Add available again")
wheel(selector(in: deletion), -1)
check(selector(in: deletion).label(forSegment: 0) == "5:4",
      "cycling after deleting the active preset uses only the remaining choices")
let deleteLast = deletion.interactiveMode.makeAspectMenu().items[0]
deletion.interactiveMode.deleteAspectPreset(deleteLast)
let afterLastDeletionRect = box(in: deletion).selectedRect
wheel(selector(in: deletion), 1)
check(deletion.interactiveMode.makeAspectMenu().items.map { $0.title } == ["Add…"] &&
      box(in: deletion).selectedRect == afterLastDeletionRect &&
      UserDefaults(suiteName: Preference.suiteName)!.array(forKey: Preference.Key.customCropAspectPresets.rawValue)?.isEmpty == true,
      "deleting the last preset persists an Add-only menu with safe empty-list cycling")
choose(deletion.interactiveMode.makeAspectMenu().items.last!)
deletion.interactiveMode.deleteAspectPreset(deleteOther)
check(Preference.array(for: .customCropAspectPresets) as? [Double] == [5.0/4],
      "a stale Delete action cannot remove a different preset")
let rowsMenu = deletion.interactiveMode.makeAspectMenu()
private let listController = CropAspectPresetListController(menu: rowsMenu)
listController.maximumHeight = 44
listController.select = { choose($0) }
private let list = (listController.view as! NSScrollView).documentView as! CropAspectPresetListView
private let row = list.rows[0]
check(list.rows.allSatisfy { $0.frame.minX >= 0 && $0.frame.maxX <= list.bounds.maxX },
      "initial list sizing keeps every row and its accessibility bounds inside the visible width")
var deletionRequested = false
row.deletePreset = { deletionRequested = true }
deletion.window!.contentView!.addSubview(listController.view)
let rowRect = box(in: deletion).selectedRect
let secondaryClick = NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 10, y: 10), modifierFlags: [],
                                       timestamp: 1, windowNumber: deletion.window!.windowNumber, context: nil,
                                       eventNumber: 1, clickCount: 1, pressure: 1)!
row.rightMouseDown(with: secondaryClick)
check(deletionRequested && box(in: deletion).selectedRect == rowRect,
      "a preset row deletes immediately on right-click without applying the preset")
deletionRequested = false
let controlClick = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 10), modifierFlags: .control,
                                     timestamp: 2, windowNumber: deletion.window!.windowNumber, context: nil,
                                     eventNumber: 2, clickCount: 1, pressure: 1)!
row.mouseDown(with: controlClick)
check(deletionRequested && box(in: deletion).selectedRect == rowRect,
      "Control-click deletes immediately without applying the preset")
deletionRequested = false
_ = row.accessibilityDeletePreset()
check(deletionRequested && row.accessibilityCustomActions()?.first?.name == "Delete",
      "the accessible Delete action invokes deletion directly")
button("Reset", in: deletion).performClick(nil)
check(row.accessibilityPerformPress() && selector(in: deletion).label(forSegment: 0) == "5:4",
      "normal accessible activation still applies the saved preset")
check(listController.view.frame.height <= 44 && list.rows.last?.deletePreset == nil &&
      list.rows.last?.item.title == "Add…", "the list scrolls within its height limit and Add has no deletion action")
var selectionRequests = 0
let savedSelect = row.select
row.select = { _ in selectionRequests += 1 }
row.mouseDown(with: controlClick)
row.mouseUp(with: controlClick)
check(selectionRequests == 0, "releasing Control-click after deletion cannot select the deleted preset")
row.select = savedSelect
var listCanceled = false
list.cancel = { listCanceled = true }
func listKey(_ code: UInt16) {
  list.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
                                    windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                    isARepeat: false, keyCode: code)!)
}
listKey(125)
check(row.keyboardHighlight, "Down highlights the first enabled preset row")
button("Reset", in: deletion).performClick(nil)
listKey(36)
check(selector(in: deletion).label(forSegment: 0) == "5:4", "Return in the list applies the highlighted preset")
listKey(53)
check(listCanceled, "Escape in the list closes it without resetting the crop")
listController.view.removeFromSuperview()
button("Cancel", in: deletion).performClick(nil)
deletion.interactiveMode.deleteAspectPreset(deleteLast)
check(Preference.array(for: .customCropAspectPresets) as? [Double] == [5.0/4],
      "Delete callbacks from an editor that already closed are ignored")
deletionReload.interactiveMode.exit()

Preference.set([5.0/6, 3.0/2], for: .customCropAspectPresets)
let directDeletion = MainWindowController()
directDeletion.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
let directRect = NSRect(x: 100, y: 70, width: 501, height: 301)
box(in: directDeletion).setSelectedRect(to: directRect)
private let directListController = CropAspectPresetListController(menu: directDeletion.interactiveMode.makeAspectMenu())
directListController.deletePreset = { directDeletion.interactiveMode.deleteAspectPreset($0) }
private let directList = (directListController.view as! NSScrollView).documentView as! CropAspectPresetListView
let windowsBeforeDirectDeletion = NSApp.windows.count
directList.rows[0].rightMouseDown(with: secondaryClick)
check(Preference.array(for: .customCropAspectPresets) as? [Double] == [3.0/2] &&
      NSApp.windows.count == windowsBeforeDirectDeletion && box(in: directDeletion).selectedRect == directRect,
      "one right-click reaches persisted deletion without opening a menu or changing the current frame")
directDeletion.interactiveMode.exit()

// Option temporarily replaces Add with deletion of the checked saved ratio.
Preference.set([5.0/6, 3.0/2], for: .customCropAspectPresets)
let optionDeletion = MainWindowController()
optionDeletion.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
box(in: optionDeletion).setSelectedRect(to: NSRect(x: 100, y: 0, width: 450, height: 540))
box(in: optionDeletion).setZoom(2)
private let optionMenuController = CropAspectPresetListController(menu: optionDeletion.interactiveMode.makeAspectMenu())
var activatedOptionItem: NSMenuItem?
var deletedOptionItem: NSMenuItem?
optionMenuController.select = { activatedOptionItem = $0 }
optionMenuController.deletePreset = { deletedOptionItem = $0 }
private let optionList = (optionMenuController.view as! NSScrollView).documentView as! CropAspectPresetListView
private let optionAction = optionList.rows.last!
let optionListSize = optionMenuController.preferredContentSize
let optionRowFrames = optionList.rows.map { $0.frame }
func optionFlags(_ held: Bool) -> NSEvent {
  NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: held ? .option : [], timestamp: 1,
                   windowNumber: optionDeletion.window!.windowNumber, context: nil, characters: "",
                   charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58)!
}
check(optionAction.item.title == "Add…" && !optionAction.item.isEnabled,
      "a checked ratio starts with disabled Add")
optionList.flagsChanged(with: optionFlags(true))
check(optionAction.item.title == "Delete…" && optionAction.item.isEnabled &&
      optionAction.accessibilityLabel() == "Delete…" && optionAction.isAccessibilityEnabled(),
      "holding Option changes disabled Add to enabled Delete for the checked preset")
optionList.rows[1].keyboardHighlight = true
check(optionAction.accessibilityPerformPress() && deletedOptionItem === optionList.rows[0].item && activatedOptionItem == nil,
      "Option Delete targets the checked preset rather than another highlighted row")
check(optionMenuController.preferredContentSize == optionListSize && optionList.rows.map { $0.frame } == optionRowFrames,
      "Add/Delete modifier changes preserve popup size and all row positions")
optionList.flagsChanged(with: optionFlags(false))
check(optionAction.item.title == "Add…" && !optionAction.item.isEnabled &&
      optionAction.accessibilityLabel() == "Add…" && !optionAction.isAccessibilityEnabled(),
      "releasing Option restores Add's original label and disabled appearance")
optionMenuController.setOptionHeld(true)
activatedOptionItem = nil
_ = optionList.rows[1].accessibilityPerformPress()
check(activatedOptionItem === optionList.rows[1].item,
      "holding Option leaves ordinary preset selection unchanged")
optionMenuController.deletePreset = { optionDeletion.interactiveMode.deleteAspectPreset($0) }
let beforeOptionDelete = box(in: optionDeletion).selectedRect
let beforeOptionZoom = box(in: optionDeletion).previewTransform
_ = optionAction.accessibilityPerformPress()
check(Preference.array(for: .customCropAspectPresets) as? [Double] == [3.0/2] &&
      box(in: optionDeletion).selectedRect == beforeOptionDelete &&
      box(in: optionDeletion).previewTransform == beforeOptionZoom,
      "Option Delete persists removal of the checked ratio without changing the crop or zoom")
private let unmatchedController = CropAspectPresetListController(menu: optionDeletion.interactiveMode.makeAspectMenu())
var unmatchedActivations = 0
unmatchedController.select = { _ in unmatchedActivations += 1 }
unmatchedController.deletePreset = { _ in unmatchedActivations += 1 }
private let unmatchedList = (unmatchedController.view as! NSScrollView).documentView as! CropAspectPresetListView
private let unmatchedAction = unmatchedList.rows.last!
check(unmatchedAction.item.title == "Add…" && unmatchedAction.item.isEnabled,
      "an unsaved current ratio keeps Add available")
unmatchedList.flagsChanged(with: optionFlags(true))
check(unmatchedAction.item.title == "Delete…" && !unmatchedAction.item.isEnabled &&
      !unmatchedAction.isAccessibilityEnabled() && !unmatchedAction.accessibilityPerformPress() && unmatchedActivations == 0,
      "Option Delete is dimmed and inert when no saved preset is checked")
unmatchedList.flagsChanged(with: optionFlags(false))
check(unmatchedAction.item.title == "Add…" && unmatchedAction.item.isEnabled,
      "releasing Option restores enabled Add for an unsaved ratio")
_ = unmatchedAction.accessibilityPerformPress()
check(unmatchedActivations == 1, "the restored Add action routes to normal saving")
private let heldOnOpen = CropAspectPresetListController(menu: optionDeletion.interactiveMode.makeAspectMenu())
heldOnOpen.setOptionHeld(true)
private let heldOnOpenList = (heldOnOpen.view as! NSScrollView).documentView as! CropAspectPresetListView
check(heldOnOpenList.rows.last!.item.title == "Delete…" && !heldOnOpenList.rows.last!.item.isEnabled,
      "opening the popup with Option already held initializes its Delete state")
Preference.set([], for: .customCropAspectPresets)
private let emptyOptionController = CropAspectPresetListController(menu: optionDeletion.interactiveMode.makeAspectMenu())
private let emptyOptionList = (emptyOptionController.view as! NSScrollView).documentView as! CropAspectPresetListView
emptyOptionList.flagsChanged(with: optionFlags(true))
check(emptyOptionList.rows.count == 1 && emptyOptionList.rows[0].item.title == "Delete…" &&
      !emptyOptionList.rows[0].item.isEnabled && emptyOptionList.rows[0].deletePreset == nil,
      "an empty saved list shows only dimmed Delete while Option is held")
var emptyOptionCanceled = false
emptyOptionList.cancel = { emptyOptionCanceled = true }
emptyOptionList.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .option, timestamp: 1,
                                            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                            isARepeat: false, keyCode: 53)!)
check(emptyOptionCanceled, "Escape closes the Option popup even when its only Delete row is disabled")
emptyOptionList.flagsChanged(with: optionFlags(false))
check(emptyOptionList.rows[0].item.title == "Add…" && emptyOptionList.rows[0].item.isEnabled,
      "an empty list returns to enabled Add after releasing Option")
optionDeletion.interactiveMode.exit()

// The regression fixture uses personal presets; production starts with an empty list.
let fixtureAspects = [4.0/3, 16.0/9, 16.0/10, 21.0/9, 3.0/2, 5.0/4]
Preference.set(fixtureAspects, for: .customCropAspectPresets)
let main = MainWindowController()
main.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
main.videoViewContainer.layoutSubtreeIfNeeded()
let crop = box(in: main), width = input("Width in pixels", in: main), height = input("Height in pixels", in: main)
let picker = selector(in: main)
check(width.integerValue == 960 && height.integerValue == 540, "fields start at full source dimensions")
check(button("Save", in: main).isEnabled, "crop confirmation is Save and accepts a full frame")
check(main.preparedWindowReferences > 0, "Editor entry captures the original window reference before installing preview geometry")
check(picker.label(forSegment: 0) == "16:9", "native source starts at its actual aspect ratio")
edit(width, "640", in: main)
edit(height, "360", in: main)
check(crop.selectedRect == NSRect(x: 160, y: 90, width: 640, height: 360), "W/H resize around selection center in source pixels")
check(picker.label(forSegment: 0) == "16:9", "dimensions update matching aspect")
edit(width, "invalid", in: main)
check(crop.selectedRect.width == 640, "invalid partial input leaves the last valid selection")
edit(width, "invalid", in: main, finish: true)
check(width.integerValue == 640, "ending invalid input restores the actual width")
edit(width, "99999", in: main, finish: true)
check(width.integerValue == 960 && crop.selectedRect.minX == 0, "oversized input clamps without shrinking the requested valid width")
edit(height, "0", in: main, finish: true)
check(height.integerValue == 1 && crop.selectedRect.height == 1, "zero input resolves to one source pixel")
edit(height, "999999999999999999999999999", in: main, finish: true)
check(height.integerValue == 1, "overflowing integer input restores the last valid height")
button("Reset", in: main).performClick(nil)
for _ in 0..<2 { wheel(picker, -1) }
check(crop.selectedRect.height == 411, "21:9 preset rounds the pixel dimension once before centering")
button("Reset", in: main).performClick(nil)
check(crop.selectedRect == NSRect(x: 0, y: 0, width: 960, height: 540), "Reset restores the complete native frame")
wheel(picker, -1)
check(picker.label(forSegment: 0) == "16:10" && width.integerValue == 864 && height.integerValue == 540,
      "wheel down applies the next preset and synchronizes W/H")
wheel(picker, 1)
check(picker.label(forSegment: 0) == "16:9", "wheel up returns to the previous preset")
crop.setSelectedRect(to: NSRect(x: 120, y: 0, width: 720, height: 540))
wheel(picker, 1)
check(picker.label(forSegment: 0) == "5:4", "preset drum wraps backward")
wheel(picker, -1)
check(picker.label(forSegment: 0) == "4:3", "preset drum wraps forward without a redundant Original entry")
wheel(picker, -5, precise: true, phase: .began, time: 2)
check(picker.label(forSegment: 0) == "4:3", "small trackpad motion leaves selection unchanged")
wheel(picker, -10, precise: true, phase: .changed, time: 2.01)
wheel(picker, -100, precise: true, phase: .changed, time: 2.02)
wheel(picker, -100, precise: true, momentum: .changed, time: 2.03)
check(picker.label(forSegment: 0) == "16:9", "one trackpad gesture selects once and ignores momentum")
crop.setSelectedRect(to: NSRect(x: 101, y: 73, width: 501, height: 301))
check(width.integerValue == 501 && height.integerValue == 301 && picker.label(forSegment: 0) == "5:3",
      "free selection updates fields and the current numeric aspect ratio")
let originalPreview = main.videoView.frame
let originalControlsCenter = picker.superview!.frame.midX
let originalReset = button("Reset", in: main).frame
let originalSave = button("Save", in: main).frame
edit(width, "530", in: main)
check(crop.selectedRect.width == 530 && picker.label(forSegment: 0) == "5:3",
      "typing updates the selection immediately while holding the ratio label")
edit(width, "530", in: main, finish: true)
main.videoViewContainer.layoutSubtreeIfNeeded()
check(picker.label(forSegment: 0) == "81:46", "ending pixel input updates the numeric aspect ratio")
check(main.videoView.frame == originalPreview && picker.superview!.frame.midX == originalControlsCenter &&
      button("Reset", in: main).frame == originalReset && button("Save", in: main).frame == originalSave,
      "changing numeric ratio labels preserves the preview, centered group, and outer actions")
crop.setSelectedRect(to: NSRect(x: 101, y: 73, width: 501, height: 301))
button("Save", in: main).performClick(nil)
check(main.player.info.unsureCrop == "Custom" && main.player.publishedCropDescriptions.last == "Custom",
      "Save commits Custom before publishing crop changes to sidebar and menu observers")
check(main.player.savedCrop?.params == ["x": "101", "y": "166", "w": "501", "h": "301", "exact": "1"],
      "Save uses source pixels with the correct top-origin filter coordinate")
check(!main.interactiveMode.isActive && main.player.resumedCount == 0 && main.liveText.requests == 1,
      "Save removes editing UI and preserves paused playback")

let typing = MainWindowController()
typing.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
let typingWidth = input("Width in pixels", in: typing)
typing.interactiveMode.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: typingWidth))
for partial in ["5", "50", "501"] {
  edit(typingWidth, partial, in: typing)
  check(selector(in: typing).label(forSegment: 0) == "16:9",
        "partial dimension input \(partial) leaves the displayed ratio stable")
}
edit(typingWidth, "501", in: typing, finish: true)
check(box(in: typing).selectedRect.minX == 230, "typing digits keeps a stable center instead of accumulating pixel-rounding drift")
check(selector(in: typing).label(forSegment: 0) != "16:9", "losing focus publishes the final typed ratio")
edit(typingWidth, "400", in: typing)
NSApp.sendAction(typingWidth.action!, to: typingWidth.target, from: typingWidth)
check(selector(in: typing).label(forSegment: 0) == "20:27", "confirming a dimension publishes its final ratio")
edit(typingWidth, "401", in: typing)
button("Save", in: typing).performClick(nil)
check(typing.player.savedCrop?.params?["w"] == "401", "Save uses live pixel dimensions even before a ratio-label update")
typing.interactiveMode.exit()

let native = MainWindowController()
native.player.originalVideoSize = (720, 540)
native.player.info.state = .playing
native.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
wheel(selector(in: native), -1)
check(box(in: native).selectedRect.size == NSSize(width: 720, height: 405), "16:9 crop of a 4:3 source uses its native pixels")
button("Reset", in: native).performClick(nil)
check(box(in: native).selectedRect.size == NSSize(width: 720, height: 540), "Reset of a 4:3 source returns 4:3")
button("Save", in: native).performClick(nil)
check(native.player.removedCropCount == 0 && native.player.savedCrop == nil, "saving a complete uncropped source creates no redundant filter")
check(native.player.resumedCount == 0 && native.player.pausedCount == 0 && native.player.info.state == .playing,
      "playing video continues through crop editing without pause or resume commands")

for initiallyPaused in [true, false] {
  for changeDuringEditing in [false, true] {
    for action in ["Save", "Cancel"] {
      let fixture = MainWindowController()
      fixture.player.info.state = initiallyPaused ? .paused : .playing
      fixture.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
      check(fixture.player.info.state == (initiallyPaused ? .paused : .playing) &&
            fixture.player.pausedCount == 0 && fixture.player.resumedCount == 0,
            "Crop inherits playback state (paused: \(initiallyPaused), action: \(action))")
      if changeDuringEditing { fixture.player.info.state = initiallyPaused ? .playing : .paused }
      let expected = fixture.player.info.state
      button(action, in: fixture).performClick(nil)
      check(fixture.player.info.state == expected && fixture.player.pausedCount == 0 && fixture.player.resumedCount == 0,
            "\(action) preserves playback state chosen during Crop (changed: \(changeDuringEditing))")
    }
  }
}
let playingDelogo = MainWindowController()
playingDelogo.player.info.state = .playing
playingDelogo.interactiveMode.enter(mode: .delogo)
check(playingDelogo.player.pausedCount == 1 && playingDelogo.player.info.state == .paused,
      "Delogo retains its automatic pause")
playingDelogo.interactiveMode.exit()
check(playingDelogo.player.resumedCount == 1 && playingDelogo.player.info.state == .playing,
      "Delogo retains playback restoration")

let cancelled = MainWindowController()
cancelled.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
edit(input("Width in pixels", in: cancelled), "300", in: cancelled)
button("Cancel", in: cancelled).performClick(nil)
check(cancelled.player.savedCrop == nil && cancelled.player.removedCropCount == 0, "Cancel applies no crop")
let delogo = MainWindowController()
delogo.interactiveMode.enter(mode: .delogo)
check(!button("Done", in: delogo).isEnabled, "empty delogo selection cannot apply an invalid filter")
box(in: delogo).setSelectedRect(to: NSRect(x: 30, y: 40, width: 100, height: 50))
button("Done", in: delogo).performClick(nil)
check(delogoParameters(delogo.player.savedDelogo) == ["x": "30", "y": "450", "w": "100", "h": "50"], "shared selection still supports delogo")

let restored = MainWindowController()
let priorCrop = MPVFilter.crop(w: 720, h: 540, x: 120, y: 0)
restored.player.info.cropFilter = priorCrop
restored.player.info.unsureCrop = "4:3"
restored.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
check(box(in: restored).selectedRect == NSRect(x: 120, y: 0, width: 720, height: 540), "reopening a crop selects the prior crop over the complete source")
check(restored.player.info.cropFilter == nil, "preview temporarily removes the prior crop")
button("Reset", in: restored).performClick(nil)
button("Cancel", in: restored).performClick(nil)
check(restored.player.savedCrop === priorCrop && restored.player.info.unsureCrop == "4:3", "Cancel restores the prior filter and aspect description after Reset")
restored.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
button("Reset", in: restored).performClick(nil)
button("Save", in: restored).performClick(nil)
check(restored.player.info.unsureCrop == "None" && restored.player.publishedCropDescriptions.last == "None",
      "Reset and Save publish None after removing the crop rather than the previous description")
check(restored.player.savedCrop == nil && restored.player.info.cropFilter == nil, "saving Reset after reopening a crop keeps the full source")
restored.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
check(box(in: restored).selectedRect == NSRect(x: 0, y: 0, width: 960, height: 540), "reopening after Reset and Save selects the entire source instead of a stale crop")
button("Cancel", in: restored).performClick(nil)

let failedRemoval = PlayerFixture()
failedRemoval.info.cropFilter = priorCrop
failedRemoval.info.unsureCrop = "4:3"
failedRemoval.filterRemovalSucceeds = false
failedRemoval.removeCropFilter()
check(failedRemoval.info.cropFilter === priorCrop && failedRemoval.info.unsureCrop == "4:3", "failed filter removal preserves the actual crop state")
let failedEntry = MainWindowController()
failedEntry.player.info.cropFilter = priorCrop
failedEntry.player.info.unsureCrop = "4:3"
failedEntry.player.filterRemovalSucceeds = false
let failedEntryFrame = failedEntry.window!.frame
let failedEntryPreview = failedEntry.videoView.frame
failedEntry.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
check(!failedEntry.interactiveMode.isActive && failedEntry.player.info.cropFilter === priorCrop &&
      failedEntry.player.info.unsureCrop == "4:3" && failedEntry.window!.frame == failedEntryFrame &&
      failedEntry.videoView.frame == failedEntryPreview && descendants(failedEntry.videoViewContainer).allSatisfy { !($0 is CropBoxView) },
      "failed crop removal leaves the player unchanged instead of opening a mismatched editor")
failedEntry.player.filterRemovalSucceeds = true
failedEntry.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
check(failedEntry.interactiveMode.isActive && failedEntry.player.info.cropFilter == nil,
      "retrying crop entry after removal succeeds starts a normal editor session")
failedEntry.interactiveMode.exit()
check(failedEntry.player.savedCrop === priorCrop && failedEntry.player.info.unsureCrop == "4:3",
      "Cancel after a retried entry restores the original crop and description")

let anamorphic = MainWindowController()
anamorphic.player.originalVideoSize = (720, 576)
anamorphic.player.displaySizeOverride = NSSize(width: 1024, height: 576)
anamorphic.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
check(selector(in: anamorphic).label(forSegment: 0) == "16:9", "ratio display uses displayed aspect rather than raw nonsquare pixels")
wheel(selector(in: anamorphic), 1)
check(box(in: anamorphic).selectedRect.size == NSSize(width: 540, height: 576), "4:3 preset accounts for nonsquare source pixels")
button("Reset", in: anamorphic).performClick(nil)
check(box(in: anamorphic).selectedRect.size == NSSize(width: 720, height: 576), "anamorphic Reset preserves native source pixels")
anamorphic.interactiveMode.exit()

let sourceSize = NSSize(width: 960, height: 540)
let displaySelection = NSRect(x: 10, y: 20, width: 30, height: 40)
let rotatedCases: [(Int, NSRect)] = [
  (0, NSRect(x: 10, y: 480, width: 30, height: 40)),
  (90, NSRect(x: 900, y: 500, width: 40, height: 30)),
  (180, NSRect(x: 920, y: 20, width: 30, height: 40)),
  (270, NSRect(x: 20, y: 10, width: 40, height: 30))
]
for (rotation, expected) in rotatedCases {
  let geometry = CropVideoGeometry(sourceSize: sourceSize, displaySize: sourceSize, rotation: rotation)
  check(geometry.filterRect(for: displaySelection) == expected, "selection maps to source coordinates at rotation \(rotation)")
  check(geometry.selectionRect(forFilterRect: expected) == displaySelection, "existing crop maps back to display at rotation \(rotation)")
  check(geometry.filterRect(for: NSRect(origin: .zero, size: geometry.selectionSize)) == NSRect(origin: .zero, size: sourceSize), "full Reset maps to the complete source at rotation \(rotation)")
}
let rotated = MainWindowController()
rotated.player.rotation = 90
rotated.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
check(input("Width in pixels", in: rotated).integerValue == 540 && input("Height in pixels", in: rotated).integerValue == 960, "rotated W/H follow the displayed pixel axes")
box(in: rotated).setSelectedRect(to: NSRect(x: 60, y: 100, width: 120, height: 300))
check(input("Width in pixels", in: rotated).integerValue == 120 && input("Height in pixels", in: rotated).integerValue == 300, "rotated selection dimensions stay in sync with the frame")
button("Save", in: rotated).performClick(nil)
check(rotated.player.savedCrop?.params == ["x": "560", "y": "360", "w": "300", "h": "120", "exact": "1"], "rotated Save applies the exact visible selection in unrotated filter coordinates")

for (size, expected) in [
  (NSSize(width: 400, height: 225), [28.0, 12, 10, 12]),
  (NSSize(width: 640, height: 360), [28.0, 14.4, 10.8, 14.4]),
  (NSSize(width: 900, height: 507), [38.025, 20.28, 15.21, 20.28]),
  (NSSize(width: 1280, height: 720), [48.0, 24, 20, 24])
] {
  let insets = CropEditorInsets(size: size)
  check(zip([insets.top, insets.side, insets.gap, insets.bottom], expected).allSatisfy { abs($0 - $1) < 0.001 },
        "adaptive margins match the agreed small, medium, and large window examples at \(size)")
}

for size in [NSSize(width: 400, height: 225), NSSize(width: 640, height: 360), NSSize(width: 1200, height: 800), NSSize(width: 400, height: 700), NSSize(width: 900, height: 225)] {
  let fixture = MainWindowController(size: size)
  fixture.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
  fixture.videoViewContainer.layoutSubtreeIfNeeded()
  check(abs(fixture.videoView.bounds.width - fixture.videoView.bounds.height * 960 / 540.0) <= 1, "preview preserves source aspect at \(size)")
  let fields = [input("Width in pixels", in: fixture), input("Height in pixels", in: fixture)]
  let controls: [NSView] = fields + [selector(in: fixture), zoomControl(in: fixture), button("Reset", in: fixture), button("Cancel", in: fixture), button("Save", in: fixture)]
  let frames = controls.map { $0.convert($0.bounds, to: fixture.videoViewContainer) }
  check(frames.allSatisfy { fixture.videoViewContainer.bounds.contains($0) }, "controls fit window \(size): \(frames)")
  check(frames.indices.allSatisfy { i in frames.indices.allSatisfy { j in i == j || !frames[i].intersects(frames[j]) } },
        "fields, drum, and buttons do not overlap at \(size)")
  check(fixture.videoViewContainer.bounds.size == size, "crop controls do not enlarge the requested window \(size)")
  let dimensions = fields[0].superview!
  let adjustments = dimensions.superview!
  let footer = adjustments.superview!
  let reset = button("Reset", in: fixture)
  let playback = reset.superview!
  let buttons = button("Save", in: fixture).superview!
  let adjustmentFrame = adjustments.convert(adjustments.bounds, to: fixture.videoViewContainer)
  let playbackFrame = playback.convert(playback.bounds, to: fixture.videoViewContainer)
  let buttonFrame = buttons.convert(buttons.bounds, to: fixture.videoViewContainer)
  let insets = CropEditorInsets(size: size)
  check(footer.fittingSize.height < 70, "controls use at most two compact rows at \(size)")
  let preview = fixture.videoView.convert(fixture.videoView.bounds, to: fixture.videoViewContainer)
  let footerFrame = footer.convert(footer.bounds, to: fixture.videoViewContainer)
  check(abs(adjustmentFrame.midX - size.width / 2) <= 0.51,
        "dimensions and ratio stay centered at \(size)")
  if size == NSSize(width: 400, height: 225) {
    check(abs(buttonFrame.minX - playbackFrame.maxX - 8) <= 0.51 &&
          abs((playbackFrame.minX + buttonFrame.maxX) / 2 - size.width / 2) <= 0.51,
          "minimum editor packs actions centrally with an eight-point gap")
  }
  if size == NSSize(width: 1200, height: 800) {
    check(abs(playbackFrame.minX - preview.minX) <= 0.51 &&
          abs(buttonFrame.maxX - preview.maxX) <= 0.51 &&
          abs(adjustmentFrame.minY - playbackFrame.minY) <= 0.51,
          "wide editor aligns side groups to preview edges with the adjustments centered in one row")
  }
  // AppKit aligns fractional adaptive insets to backing pixels.
  check(preview.minX >= insets.side - 0.51 && preview.maxX <= size.width - insets.side + 0.51 &&
        abs(preview.maxY - (size.height - insets.top)) <= 0.51 && preview.minY >= footerFrame.maxY + insets.gap - 0.51 &&
        abs(footerFrame.minY - insets.bottom) <= 0.51,
        "preview and footer use adaptive top, side, gap, and bottom spacing at \(size): preview \(preview), footer \(footerFrame), insets \(insets)")
  let widthFrame = fields[0].convert(fields[0].bounds, to: fixture.videoViewContainer)
  let heightFrame = fields[1].convert(fields[1].bounds, to: fixture.videoViewContainer)
  check(abs(widthFrame.midY - heightFrame.midY) < 0.01 && widthFrame.maxX < heightFrame.minX,
        "W/H remain adjacent in the compact dimensions group at \(size)")
  if size == NSSize(width: 400, height: 225) {
    check(preview.height >= 115, "minimum player window keeps at least 115 points of source preview height")
  }
  check(fixture.interactiveMode.canDragWindow(at: fixture.videoViewContainer.convert(NSPoint(x: size.width / 2, y: size.height - insets.top / 2), to: nil)),
        "the middle of the top band is available for window dragging at \(size)")
  fixture.interactiveMode.exit()
}

let unlockedEditor = MainWindowController()
unlockedEditor.window!.aspectRatio = NSSize(width: 16, height: 9)
let inheritedFrame = unlockedEditor.window!.frame
let inheritedAspect = unlockedEditor.window!.aspectRatio
unlockedEditor.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
check(unlockedEditor.window!.frame == inheritedFrame, "entering crop inherits the player window frame")
check(unlockedEditor.window!.aspectRatio == inheritedAspect, "editor preserves the player aspect-ratio lock")
let stablePreview = unlockedEditor.videoView.frame
selector(in: unlockedEditor).switchSelection?(1)
check(unlockedEditor.window!.frame == inheritedFrame && unlockedEditor.videoView.frame == stablePreview,
      "changing crop aspect keeps both the window and source preview stable")
unlockedEditor.interactiveMode.exit()
check(unlockedEditor.window!.aspectRatio == inheritedAspect, "leaving crop restores the player resize policy")

let changingWindow = MainWindowController(size: NSSize(width: 525, height: 225))
changingWindow.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
changingWindow.window!.setContentSize(NSSize(width: 960, height: 540))
changingWindow.interactiveMode.resize()
check(abs(changingWindow.videoView.bounds.width - changingWindow.videoView.bounds.height * 960 / 540.0) <= 1, "preview recomputes its aspect after a programmatic window resize")
check(box(in: changingWindow).selectedRect == NSRect(x: 0, y: 0, width: 960, height: 540), "preview resize preserves source selection")
for size in [NSSize(width: 400, height: 225), NSSize(width: 900, height: 225), NSSize(width: 400, height: 700)] {
  changingWindow.window!.setContentSize(size)
  changingWindow.interactiveMode.resize()
  changingWindow.videoViewContainer.layoutSubtreeIfNeeded()
  let controls: [NSView] = [zoomControl(in: changingWindow), selector(in: changingWindow), input("Width in pixels", in: changingWindow),
                            input("Height in pixels", in: changingWindow), button("Reset", in: changingWindow),
                            button("Cancel", in: changingWindow), button("Save", in: changingWindow)]
  let frames = controls.map { $0.convert($0.bounds, to: changingWindow.videoViewContainer) }
  check(frames.allSatisfy { changingWindow.videoViewContainer.bounds.contains($0) } &&
        frames.indices.allSatisfy { i in frames.indices.allSatisfy { j in i == j || !frames[i].intersects(frames[j]) } },
        "controls reflow without clipping or overlap after resizing to \(size)")
  check(box(in: changingWindow).selectedRect == NSRect(x: 0, y: 0, width: 960, height: 540),
        "selection survives switching control row arrangement at \(size)")
}
changingWindow.interactiveMode.exit()

// Exercise native window fitting between resize notifications. A direct setContentSize
// followed by resize() misses AppKit's automatic minimum-size reconciliation.
final class CropResizeDelegate: NSObject, NSWindowDelegate {
  let controller: MainWindowController
  init(_ controller: MainWindowController) { self.controller = controller }
  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    sender.contentView?.layoutSubtreeIfNeeded()
    return frameSize
  }
  func windowDidResize(_ notification: Notification) {
    controller.interactiveMode.resize()
    controller.window?.contentView?.layoutSubtreeIfNeeded()
  }
}
for locked in [false, true] {
  let resizing = MainWindowController(size: NSSize(width: 900, height: 500))
  let window = resizing.window!
  window.styleMask.insert(.resizable)
  window.contentMinSize = NSSize(width: 400, height: 225)
  if locked { window.aspectRatio = NSSize(width: 16, height: 9) }
  resizing.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
  let delegate = CropResizeDelegate(resizing)
  window.delegate = delegate
  let sizes = [NSSize(width: 900, height: 507), NSSize(width: 560, height: 315),
               NSSize(width: 540, height: 304), NSSize(width: 400, height: 247),
               NSSize(width: 900, height: 247), NSSize(width: 400, height: 700),
               NSSize(width: 400, height: 247), NSSize(width: 900, height: 507)]
  for size in sizes {
    // Native resizing owns the anchor. Layout must not add a second frame change.
    let requested = NSRect(origin: NSPoint(x: 140, y: 160), size: size)
    window.setFrame(requested, display: false)
    window.contentView?.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    check(abs(window.frame.width - size.width) <= 1 && abs(window.frame.height - size.height) <= 1 &&
          window.frame.origin == requested.origin,
          "native crop layout preserves resize frame and anchor at \(size), aspect lock \(locked)")
    check(box(in: resizing).selectedRect == NSRect(x: 0, y: 0, width: 960, height: 540),
          "native resizing preserves crop source coordinates at \(size), aspect lock \(locked)")
  }
  window.delegate = nil
  resizing.interactiveMode.exit()
  window.contentView?.layoutSubtreeIfNeeded()
  check(resizing.videoView.frame == resizing.videoViewContainer.bounds,
        "leaving crop restores the player video edge constraints after native resizing")
}

for source in [NSSize(width: 960, height: 540), NSSize(width: 540, height: 960), NSSize(width: 2560, height: 1080)] {
  let reflow = MainWindowController(size: NSSize(width: 400, height: 225))
  reflow.player.originalVideoSize = (Int(source.width), Int(source.height))
  reflow.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
  let controls: [NSView] = [zoomControl(in: reflow), selector(in: reflow), input("Width in pixels", in: reflow),
                            input("Height in pixels", in: reflow), button("Reset", in: reflow),
                            button("Cancel", in: reflow), button("Save", in: reflow)]
  let footer = selector(in: reflow).superview!.superview!
  var continuous = true, fits = true, stable = true
  var previousPreview: NSRect?
  var previousFooter: CGFloat?
  for windowHeight: CGFloat in [225, 507, 1800] {
    previousPreview = nil
    previousFooter = nil
    for width in Array(400...900) + Array((400..<900).reversed()) {
      reflow.window!.setContentSize(NSSize(width: CGFloat(width), height: windowHeight))
      let requestedFrame = reflow.window!.frame
      reflow.interactiveMode.resize()
      reflow.window!.contentView?.layoutSubtreeIfNeeded()
      let preview = reflow.videoView.frame
      let footerHeight = footer.frame.height
      if let previousPreview, let previousFooter {
        continuous = continuous && abs(preview.width - previousPreview.width) <= 2 &&
          abs(preview.height - previousPreview.height) <= 2 && abs(footerHeight - previousFooter) <= 2
      }
      let frames = controls.map { $0.convert($0.bounds, to: reflow.videoViewContainer) }
      fits = fits && frames.allSatisfy { reflow.videoViewContainer.bounds.contains($0) } &&
        frames.indices.allSatisfy { i in frames.indices.allSatisfy { j in i == j || !frames[i].intersects(frames[j]) } }
      stable = stable && reflow.window!.frame == requestedFrame &&
        box(in: reflow).selectedRect == NSRect(origin: .zero, size: source)
      previousPreview = preview
      previousFooter = footerHeight
    }
  }
  check(continuous, "preview and footer reflow continuously in both resize directions for \(source)")
  check(fits, "controls fit without overlap throughout adaptive resizing for \(source)")
  check(stable, "adaptive resizing preserves native window geometry and source selection for \(source)")
  reflow.window!.setContentSize(NSSize(width: 400, height: 225))
  reflow.interactiveMode.resize()
  check(footer.intrinsicContentSize.height > 45, "narrow editor still has two usable control rows for \(source)")
  reflow.window!.setContentSize(NSSize(width: 900, height: 1800))
  reflow.interactiveMode.resize()
  check(footer.frame.height < 30, "wide editor returns every control to one compact row for \(source)")
  reflow.interactiveMode.exit()
}

for aspect: CGFloat in [16 / 9.0, 9 / 16.0, 21 / 9.0] {
  let diagonal = MainWindowController()
  diagonal.player.originalVideoSize = (Int(aspect * 1080), 1080)
  diagonal.window!.aspectRatio = NSSize(width: aspect, height: 1)
  diagonal.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
  let controls: [NSView] = [zoomControl(in: diagonal), selector(in: diagonal), input("Width in pixels", in: diagonal),
                            input("Height in pixels", in: diagonal), button("Reset", in: diagonal),
                            button("Cancel", in: diagonal), button("Save", in: diagonal)]
  var previousPreview: NSRect?
  var previousWindow: NSSize?
  var previousFrames: [NSRect]?
  var largestPreviewStep: CGFloat = 0
  var largestControlStep: CGFloat = 0
  var controlStepDescription = ""
  var boundedScaling = true, boundedControlMovement = true, stable = true, fits = true
  for width in Array(550...1050) + Array((550..<1050).reversed()) {
    diagonal.window!.setContentSize(NSSize(width: CGFloat(width), height: CGFloat(width) / aspect))
    let requestedFrame = diagonal.window!.frame
    diagonal.interactiveMode.resize()
    diagonal.window!.contentView?.layoutSubtreeIfNeeded()
    let preview = diagonal.videoView.frame
    let frames = controls.map { $0.convert($0.bounds, to: diagonal.videoViewContainer) }
    if let previousPreview, let previousFrames, let previousWindow {
      largestPreviewStep = max(largestPreviewStep, abs(preview.width - previousPreview.width))
      let windowStep = max(abs(requestedFrame.width - previousWindow.width),
                           abs(requestedFrame.height - previousWindow.height) * aspect)
      // A shorter row merge releases preview height faster; bound this deliberate gain and native rounding.
      boundedScaling = boundedScaling && abs(preview.width - previousPreview.width) <= windowStep * 3 + 1
      for (index, pair) in zip(frames, previousFrames).enumerated() {
        let (current, previous) = pair
        let step = max(abs(current.minX - previous.minX), abs(current.minY - previous.minY))
        boundedControlMovement = boundedControlMovement && step <= windowStep * 2 + 1
        if step > largestControlStep {
          largestControlStep = step
          controlStepDescription = "control \(index), width \(width), \(previous) -> \(current)"
        }
      }
    }
    fits = fits && frames.allSatisfy { diagonal.videoViewContainer.bounds.contains($0) } &&
      frames.indices.allSatisfy { i in frames.indices.allSatisfy { j in
        i == j || !frames[i].intersects(frames[j])
      } }
    stable = stable && diagonal.window!.frame == requestedFrame &&
      box(in: diagonal).selectedRect == NSRect(origin: .zero, size: box(in: diagonal).videoSize)
    previousPreview = preview
    previousWindow = requestedFrame.size
    previousFrames = frames
  }
  check(boundedScaling, "diagonal resize bounds preview growth while the compact row merges at aspect \(aspect), largest step \(largestPreviewStep)")
  check(boundedControlMovement, "footer controls move continuously between row changes during diagonal resize at aspect \(aspect), largest step \(largestControlStep), \(controlStepDescription)")
  check(fits && stable, "diagonal resizing preserves native frame, crop pixels, and usable controls at aspect \(aspect)")
  diagonal.interactiveMode.exit()
}

let readyRow = MainWindowController(size: NSSize(width: 842, height: 470))
readyRow.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
readyRow.window!.contentView?.layoutSubtreeIfNeeded()
let readyAdjustments = selector(in: readyRow).superview!
let readyUtilities = button("Reset", in: readyRow).superview!
let readyButtons = button("Save", in: readyRow).superview!
check(abs(readyAdjustments.frame.minY - readyUtilities.frame.minY) <= 0.51,
      "editor with available first-row space merges immediately instead of waiting for more preview growth")
check(readyAdjustments.frame.minX >= readyUtilities.frame.maxX + 7.5 &&
      readyButtons.frame.minX >= readyAdjustments.frame.maxX + 7.5,
      "early merged row retains clear gaps around the centered adjustments")
let readyPreview = readyRow.videoView.frame
selector(in: readyRow).setLabel("99:99", forSegment: 0)
readyRow.interactiveMode.resize()
readyRow.window!.contentView?.layoutSubtreeIfNeeded()
check(readyRow.videoView.frame == readyPreview &&
      !readyAdjustments.frame.intersects(readyUtilities.frame) && !readyAdjustments.frame.intersects(readyButtons.frame),
      "longest custom ratio fits the early merged row without moving the preview")
readyRow.interactiveMode.exit()

let progressiveReflow = MainWindowController(size: NSSize(width: 400, height: 225))
progressiveReflow.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
AccessibilityPreferences.disableAnimations = false
let reflowGroups = [selector(in: progressiveReflow).superview!, button("Reset", in: progressiveReflow).superview!,
                    button("Save", in: progressiveReflow).superview!]
var forwardFrames: [Int: [NSRect]] = [:]
var intermediateOffsets = Set<CGFloat>()
var reversible = true
var noDeferredMotion = true
for width in Array(400...1200) + Array((400..<1200).reversed()) {
  progressiveReflow.window!.setContentSize(NSSize(width: CGFloat(width), height: CGFloat(width) * 9 / 16))
  progressiveReflow.interactiveMode.resize()
  progressiveReflow.window!.contentView?.layoutSubtreeIfNeeded()
  let frames = reflowGroups.map { $0.convert($0.bounds, to: progressiveReflow.videoViewContainer) }
  let offset = frames[0].minY - frames[1].minY
  if offset > 0 && offset < 32 { intermediateOffsets.insert(offset) }
  if let previous = forwardFrames[width] {
    reversible = reversible && previous == frames
  } else {
    forwardFrames[width] = frames
  }
  noDeferredMotion = noDeferredMotion && reflowGroups.allSatisfy { $0.layer?.animation(forKey: "crop.reflow") == nil }
}
check(intermediateOffsets.count > 20, "center group merges through many intermediate positions as the window expands")
check(reversible, "reversing resize visits exactly the same control positions at every width")
check(noDeferredMotion, "row reflow follows geometry without a timed breakpoint animation")
progressiveReflow.window!.setContentSize(NSSize(width: 780, height: 439))
progressiveReflow.interactiveMode.resize()
progressiveReflow.window!.contentView?.layoutSubtreeIfNeeded()
let stoppedFrames = reflowGroups.map { $0.frame }
RunLoop.main.run(until: Date().addingTimeInterval(0.4))
check(reflowGroups.map { $0.frame } == stoppedFrames,
      "controls stop moving immediately when window resizing stops: \(stoppedFrames) -> \(reflowGroups.map { $0.frame })")
for width in [1000, 1200] {
  progressiveReflow.window!.setContentSize(NSSize(width: CGFloat(width), height: CGFloat(width) * 9 / 16))
  progressiveReflow.interactiveMode.resize()
  let preview = progressiveReflow.videoView.frame
  let frames = reflowGroups.map { $0.convert($0.bounds, to: progressiveReflow.videoViewContainer) }
  check(abs(frames[1].minX - preview.minX) <= 0.51 && abs(frames[2].maxX - preview.maxX) <= 0.51 &&
        abs(frames[0].midX - preview.midX) <= 0.51,
        "wide controls continue spreading with the preview edges at width \(width)")
}
progressiveReflow.interactiveMode.exit()
AccessibilityPreferences.disableAnimations = true

let portrait = MainWindowController(size: NSSize(width: 900, height: 507))
portrait.player.originalVideoSize = (540, 960)
portrait.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
portrait.videoViewContainer.layoutSubtreeIfNeeded()
check(selector(in: portrait).label(forSegment: 0) == "9:16", "portrait source displays its actual ratio after entering crop")
let portraitFooter = selector(in: portrait).superview!.superview!
check(portraitFooter.frame.width > portrait.videoView.frame.width && portraitFooter.frame.minX >= 20,
      "narrow portrait previews retain enough footer width for usable controls")
box(in: portrait).setSelectedRect(to: NSRect(x: 100, y: 100, width: 1, height: 1))
check(selector(in: portrait).label(forSegment: 0) == "1:1", "tiny free selections do not falsely match a standard preset")
wheel(selector(in: portrait), 1)
check(selector(in: portrait).label(forSegment: 0) == "5:4", "scrolling backward from a custom ratio chooses the final preset")
box(in: portrait).setSelectedRect(to: NSRect(x: 100, y: 100, width: 101, height: 333))
wheel(selector(in: portrait), -1)
check(selector(in: portrait).label(forSegment: 0) == "4:3", "scrolling forward from a custom ratio chooses the first preset")
button("Reset", in: portrait).performClick(nil)
check(box(in: portrait).selectedRect == NSRect(x: 0, y: 0, width: 540, height: 960) &&
      selector(in: portrait).label(forSegment: 0) == "9:16", "Reset alone restores the full portrait source and its numeric aspect")
portrait.interactiveMode.exit()

let resizingSelector = MainWindowController(size: NSSize(width: 640, height: 360))
resizingSelector.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
resizingSelector.videoViewContainer.layoutSubtreeIfNeeded()
let animatedPicker = selector(in: resizingSelector)
let shortWidth = animatedPicker.intrinsicContentSize.width
let stationaryPreview = resizingSelector.videoView.frame
AccessibilityPreferences.disableAnimations = false
animatedPicker.setLabel("11:99", forSegment: 0)
RunLoop.main.run(until: Date().addingTimeInterval(0.06))
check(animatedPicker.intrinsicContentSize.width > shortWidth && animatedPicker.isResizing,
      "long ratio begins expanding immediately, before the shrink delay")
for title in ["22:88", "33:77", "44:66", "88:11"] {
  animatedPicker.setLabel(title, forSegment: 0)
  RunLoop.main.run(until: Date().addingTimeInterval(0.06))
}
let expandedWidth = animatedPicker.intrinsicContentSize.width
check(!animatedPicker.isResizing && expandedWidth > shortWidth,
      "equal-width digit changes do not restart the ongoing expansion")
animatedPicker.setLabel("4:3", forSegment: 0)
RunLoop.main.run(until: Date().addingTimeInterval(0.18))
check(animatedPicker.intrinsicContentSize.width == expandedWidth,
      "shorter ratio holds the expanded width during the 250ms debounce")
animatedPicker.setLabel("3:2", forSegment: 0)
RunLoop.main.run(until: Date().addingTimeInterval(0.18))
check(animatedPicker.intrinsicContentSize.width == expandedWidth && animatedPicker.isResizing,
      "continued text changes postpone shrinking until editing settles")
RunLoop.main.run(until: Date().addingTimeInterval(0.4))
check(animatedPicker.intrinsicContentSize.width < expandedWidth && !animatedPicker.isResizing,
      "capsule smoothly shrinks to its title after text becomes stable")
resizingSelector.videoViewContainer.layoutSubtreeIfNeeded()
check(resizingSelector.videoView.frame == stationaryPreview,
      "adaptive capsule width leaves the source preview stationary")
let adjustmentGroup = animatedPicker.superview!
let playbackGroup = button("Reset", in: resizingSelector).superview!
let actionGroup = button("Save", in: resizingSelector).superview!
check(abs(adjustmentGroup.frame.midX - adjustmentGroup.superview!.bounds.midX) <= 0.51 &&
      !adjustmentGroup.frame.intersects(playbackGroup.frame) && !adjustmentGroup.frame.intersects(actionGroup.frame),
      "adaptive ratio width stays centered without overlapping the side groups")
animatedPicker.setLabel("97:62", forSegment: 0)
AccessibilityPreferences.motionReductionEnabled = true
animatedPicker.setLabel("4:3", forSegment: 0)
check(!animatedPicker.isResizing, "Reduce Motion settles adaptive width without queued work")
AccessibilityPreferences.motionReductionEnabled = false
AccessibilityPreferences.disableAnimations = true
animatedPicker.setLabel("17:9", forSegment: 0)
resizingSelector.videoViewContainer.layoutSubtreeIfNeeded()
AccessibilityPreferences.disableAnimations = false
func ratioMask() -> CALayer {
  let overlay = animatedPicker.subviews.first { $0 is ScrollSelectionOverlay }!
  return overlay.layer!.sublayers!.first { $0.masksToBounds && $0.isGeometryFlipped }!
}
func finishDigitAnimation() {
  let end = Date().addingTimeInterval(0.8)
  while Date() < end {
    CATransaction.flush()
    RunLoop.main.run(until: min(end, Date().addingTimeInterval(0.005)))
    resizingSelector.videoViewContainer.layoutSubtreeIfNeeded()
  }
}
animatedPicker.setLabel("15:9", forSegment: 0)
let drums = ratioMask().sublayers!.first!
let columns = drums.sublayers!
check(animatedPicker.isRolling && animatedPicker.label(forSegment: 0) == "15:9" && animatedPicker.accessibilityLabel() == "15:9",
      "digit animation publishes the logical and accessible target immediately")
check(columns.count == 4 && columns[0].sublayers!.first!.animationKeys() == nil &&
      columns[2].sublayers!.first!.animationKeys() == nil && columns[3].sublayers!.first!.animationKeys() == nil,
      "unchanged digits and colon stay still while the changed digit rotates")
let backwardFaces = columns[1].sublayers!.first!.sublayers!
let backwardGroup = backwardFaces[0].animation(forKey: "selectionCylinder") as! CAAnimationGroup
let backwardRotation = backwardGroup.animations![0] as! CAKeyframeAnimation
check(backwardFaces.count == 3 && (backwardRotation.values![24] as! NSValue).caTransform3DValue.m42 < 0,
      "7 → 5 renders three faces and rotates backward through 6")
finishDigitAnimation()
check(!animatedPicker.isRolling && ratioMask().sublayers!.count == 1,
      "completed digit animation removes temporary columns and restores one static title")
animatedPicker.setLabel("15:1", forSegment: 0)
let forwardFaces = ratioMask().sublayers!.first!.sublayers![3].sublayers!.first!.sublayers!
let forwardGroup = forwardFaces[0].animation(forKey: "selectionCylinder") as! CAAnimationGroup
let forwardRotation = forwardGroup.animations![0] as! CAKeyframeAnimation
check(forwardFaces.count == 3 && (forwardRotation.values![24] as! NSValue).caTransform3DValue.m42 > 0,
      "9 → 1 renders the forward wrap through 0")
animatedPicker.setLabel("5:10", forSegment: 0)
let lengthColumns = ratioMask().sublayers!.first!.sublayers!
check(lengthColumns.filter { $0.animation(forKey: "digitPresence") != nil }.count == 2 &&
      lengthColumns.contains { $0.animation(forKey: "digitPosition") != nil },
      "adding and removing tens fades those columns and slides the remaining glyphs")
animatedPicker.setLabel("21:9", forSegment: 0)
finishDigitAnimation()
check(!animatedPicker.isRolling && animatedPicker.label(forSegment: 0) == "21:9",
      "rapid changes cancel old drum completions and retain the newest target")
animatedPicker.setLabel("16:10", forSegment: 0)
AccessibilityPreferences.motionReductionEnabled = true
animatedPicker.setLabel("4:3", forSegment: 0)
check(!animatedPicker.isRolling && !animatedPicker.isResizing, "Reduce Motion cancels digit and width animations")
AccessibilityPreferences.motionReductionEnabled = false
animatedPicker.setLabel("16:9", forSegment: 0)
check(animatedPicker.isRolling, "a subsequent committed ratio can animate again")
wheel(animatedPicker, -1)
let swipeFaces = ratioMask().sublayers!.first!.sublayers!
check(swipeFaces.count == 2 && swipeFaces.allSatisfy { $0.contents != nil && $0.sublayers == nil } &&
      animatedPicker.label(forSegment: 0) == "16:10",
      "preset swipe replaces the whole title instead of rolling individual digits")
let swipeGroup = swipeFaces[0].animation(forKey: "selectionCylinder") as! CAAnimationGroup
let swipeRotation = swipeGroup.animations![0] as! CAKeyframeAnimation
check((swipeRotation.values![24] as! NSValue).caTransform3DValue.m42 > 0,
      "forward preset swipe follows the plugin selector direction")
wheel(animatedPicker, 1)
let reverseFaces = ratioMask().sublayers!.first!.sublayers!
let reverseGroup = reverseFaces[0].animation(forKey: "selectionCylinder") as! CAAnimationGroup
let reverseRotation = reverseGroup.animations![0] as! CAKeyframeAnimation
check(reverseFaces.count == 2 && (reverseRotation.values![24] as! NSValue).caTransform3DValue.m42 < 0 &&
      animatedPicker.label(forSegment: 0) == "16:9",
      "reversing a swipe interrupts the previous roll and reverses the whole title")
let presetItem = NSMenuItem(title: "4:3", action: nil, keyEquivalent: "")
presetItem.representedObject = 4.0 / 3
NSApp.sendAction(NSSelectorFromString("aspectMenuAction:"), to: resizingSelector.interactiveMode, from: presetItem)
check(!animatedPicker.isRolling && animatedPicker.label(forSegment: 0) == "4:3",
      "menu preset selection stays immediate like the plugin menu")
wheel(animatedPicker, 1)
let wrapFaces = ratioMask().sublayers!.first!.sublayers!
check(wrapFaces.count == 2 && wrapFaces.allSatisfy { $0.contents != nil && $0.sublayers == nil } &&
      animatedPicker.label(forSegment: 0) == "5:4",
      "preset wraparound also rolls the whole title")
edit(input("Width in pixels", in: resizingSelector), "501", in: resizingSelector, finish: true)
check(animatedPicker.isRolling && ratioMask().sublayers!.first!.sublayers!.count > 2,
      "committing custom dimensions after a preset swipe restores individual digit drums")
let animatedResetBox = box(in: resizingSelector)
let resetStartFrame = animatedResetBox.boxRect
let resetWindowFrame = resizingSelector.window!.frame
let resetPreviewFrame = resizingSelector.videoView.frame
button("Reset", in: resizingSelector).performClick(nil)
check(animatedPicker.isRolling && animatedPicker.label(forSegment: 0) == "16:9" &&
      ratioMask().sublayers!.first!.sublayers!.count > 2,
      "Reset restores the source ratio with individual digit drums rather than a preset swipe")
check(animatedResetBox.isAnimatingSelection && animatedResetBox.boxRect == resetStartFrame &&
      animatedResetBox.selectedRect == NSRect(origin: .zero, size: animatedResetBox.videoSize),
      "Reset publishes the full source immediately while presentation starts at the visible frame")
RunLoop.main.run(until: Date().addingTimeInterval(0.1))
let resetIntermediate = animatedResetBox.boxRect
check(resetIntermediate.width > resetStartFrame.width && resetIntermediate.width < animatedResetBox.previewRect.width &&
      animatedResetBox.isAnimatingSelection && animatedPicker.label(forSegment: 0) == "16:9",
      "Reset interpolates the frame through intermediate positions instead of teleporting")
check((resetIntermediate.width - resetStartFrame.width) / (animatedResetBox.previewRect.width - resetStartFrame.width) > 0.6,
      "the 280ms ease-out advances faster than linear motion and slows near the destination")
button("Reset", in: resizingSelector).performClick(nil)
check(animatedResetBox.boxRect == resetIntermediate && animatedResetBox.isAnimatingSelection,
      "repeated Reset neither restarts nor snaps an in-progress transition")
finishDigitAnimation()
check(!animatedResetBox.isAnimatingSelection && animatedResetBox.boxRect == animatedResetBox.previewRect &&
      !animatedPicker.isRolling && animatedPicker.label(forSegment: 0) == "16:9",
      "Reset finishes with exact full-frame edges and a settled original aspect label")
check(resizingSelector.window!.frame == resetWindowFrame && resizingSelector.videoView.frame == resetPreviewFrame,
      "animated Reset keeps the outer window and source preview stationary")
animatedResetBox.setSelectedRect(to: NSRect(x: 100, y: 60, width: 300, height: 200))
button("Reset", in: resizingSelector).performClick(nil)
RunLoop.main.run(until: Date().addingTimeInterval(0.1))
let clickDuringReset = NSPoint(x: animatedResetBox.boxRect.midX, y: animatedResetBox.boxRect.midY)
let visibleResetFrame = animatedResetBox.boxRect
let resetMouseDown = NSEvent.mouseEvent(with: .leftMouseDown,
  location: animatedResetBox.convert(clickDuringReset, to: nil), modifierFlags: [], timestamp: 1,
  windowNumber: resizingSelector.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
animatedResetBox.mouseDown(with: resetMouseDown)
check(animatedResetBox.isAnimatingSelection && !animatedResetBox.isDragging && animatedResetBox.boxRect == visibleResetFrame,
      "pointer down cannot capture or stop the resetting frame")
let resetMouseDrag = NSEvent.mouseEvent(with: .leftMouseDragged,
  location: animatedResetBox.convert(NSPoint(x: clickDuringReset.x + 40, y: clickDuringReset.y + 20), to: nil),
  modifierFlags: [.option, .shift], timestamp: 1.1, windowNumber: resizingSelector.window!.windowNumber,
  context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
animatedResetBox.mouseDragged(with: resetMouseDrag)
animatedResetBox.mouseUp(with: resetMouseDown)
check(animatedResetBox.isAnimatingSelection && !animatedResetBox.isDragging &&
      animatedResetBox.selectedRect == NSRect(origin: .zero, size: animatedResetBox.videoSize),
      "drag and release from a blocked press cannot mutate the Reset target")
let resetArrow = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1.2,
  windowNumber: resizingSelector.window!.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
  isARepeat: false, keyCode: 123)!
animatedResetBox.keyDown(with: resetArrow)
check(animatedResetBox.isAnimatingSelection && animatedResetBox.boxRect == visibleResetFrame,
      "arrow-key movement cannot stop or capture the Reset frame")
edit(input("Width in pixels", in: resizingSelector), "501", in: resizingSelector, finish: true)
check(animatedResetBox.isAnimatingSelection && animatedResetBox.selectedRect.width == 960 &&
      input("Width in pixels", in: resizingSelector).integerValue == 960,
      "dimension entry during Reset retains the full-source target and restores the displayed value")
NSApp.sendAction(NSSelectorFromString("aspectMenuAction:"), to: resizingSelector.interactiveMode, from: presetItem)
animatedResetBox.setZoom(3)
animatedResetBox.setSelectedRect(to: NSRect(x: 100, y: 60, width: 300, height: 200))
check(animatedResetBox.isAnimatingSelection && animatedResetBox.selectedRect == NSRect(origin: .zero, size: animatedResetBox.videoSize) &&
      animatedResetBox.previewTransform.zoom == 1 && animatedPicker.label(forSegment: 0) == "16:9",
      "preset, zoom and direct selection changes cannot interrupt Reset")
RunLoop.main.run(until: Date().addingTimeInterval(0.24))
check(!animatedResetBox.isAnimatingSelection && animatedResetBox.boxRect == animatedResetBox.previewRect,
      "the faster Reset reaches exact preview edges in under 350ms despite blocked input")
animatedResetBox.mouseDragged(with: resetMouseDrag)
check(!animatedResetBox.isDragging && animatedResetBox.selectedRect == NSRect(origin: .zero, size: animatedResetBox.videoSize),
      "a press ignored during Reset cannot start dragging after the transition finishes")
edit(input("Width in pixels", in: resizingSelector), "501", in: resizingSelector, finish: true)
check(animatedResetBox.selectedRect.width == 501,
      "selection editing becomes available again immediately after Reset finishes")
button("Reset", in: resizingSelector).performClick(nil)
AccessibilityPreferences.motionReductionEnabled = true
RunLoop.main.run(until: Date().addingTimeInterval(0.04))
check(!animatedResetBox.isAnimatingSelection && animatedResetBox.boxRect == animatedResetBox.previewRect,
      "enabling Reduce Motion settles an active frame transition at its exact target")
animatedResetBox.setSelectedRect(to: NSRect(x: 100, y: 60, width: 300, height: 200))
button("Reset", in: resizingSelector).performClick(nil)
check(!animatedResetBox.isAnimatingSelection && !animatedPicker.isRolling && animatedResetBox.boxRect == animatedResetBox.previewRect,
      "Reduce Motion disables both Reset frame movement and digit drums")
AccessibilityPreferences.motionReductionEnabled = false
animatedResetBox.setSelectedRect(to: NSRect(x: 100, y: 60, width: 300, height: 200))
button("Reset", in: resizingSelector).performClick(nil)
resizingSelector.interactiveMode.exit()
check(!animatedPicker.isRolling && !animatedPicker.isResizing && !animatedResetBox.isAnimatingSelection,
      "leaving crop mode cancels digit, width and frame animations")
let saveDuringReset = MainWindowController()
saveDuringReset.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
let saveResetBox = box(in: saveDuringReset)
saveResetBox.setSelectedRect(to: NSRect(x: 100, y: 60, width: 300, height: 200))
button("Reset", in: saveDuringReset).performClick(nil)
check(saveResetBox.isAnimatingSelection, "Save test starts with an active Reset transition")
button("Save", in: saveDuringReset).performClick(nil)
check(!saveDuringReset.interactiveMode.isActive && saveDuringReset.player.savedCrop == nil && !saveResetBox.isAnimatingSelection,
      "Save during Reset uses the final full source and cleans up animation")
let cancelDuringReset = MainWindowController()
let cropBeforeAnimatedReset = MPVFilter.crop(w: 501, h: 301, x: 200, y: 100, exact: true)
cancelDuringReset.player.info.cropFilter = cropBeforeAnimatedReset
cancelDuringReset.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
let cancelResetBox = box(in: cancelDuringReset)
let animatedEscape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
  windowNumber: cancelDuringReset.window!.windowNumber, context: nil, characters: "\u{1b}",
  charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
_ = cancelDuringReset.interactiveMode.handleEditorEvent(animatedEscape)
check(cancelResetBox.isAnimatingSelection && selector(in: cancelDuringReset).isRolling,
      "Escape uses the same frame and digit Reset transition as the button")
_ = cancelDuringReset.interactiveMode.handleEditorEvent(animatedEscape)
check(!cancelResetBox.isAnimatingSelection && cancelDuringReset.player.savedCrop === cropBeforeAnimatedReset,
      "Escape during Reset exits from its logical full-frame target and restores the original crop")
AccessibilityPreferences.disableAnimations = true

let edgeRouting = MainWindowController()
edgeRouting.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
edgeRouting.videoViewContainer.layoutSubtreeIfNeeded()
let routedCrop = box(in: edgeRouting)
check(!edgeRouting.videoView.mouseDownCanMoveWindow, "the actual video-view movement policy disables native dragging while cropping")
for point in [NSPoint(x: routedCrop.previewRect.minX - 3, y: routedCrop.previewRect.minY - 3), NSPoint(x: routedCrop.previewRect.maxX + 3, y: routedCrop.previewRect.minY - 3),
              NSPoint(x: routedCrop.previewRect.minX - 3, y: routedCrop.previewRect.maxY + 3), NSPoint(x: routedCrop.previewRect.maxX + 3, y: routedCrop.previewRect.maxY + 3)] {
  let parentPoint = routedCrop.convert(point, to: edgeRouting.videoViewContainer.superview)
  check(edgeRouting.videoViewContainer.hitTest(parentPoint) === routedCrop,
        "native view hit-testing routes the outer corner \(point) to crop resizing")
}
for offset: CGFloat in [8, 9] {
  let local = NSPoint(x: routedCrop.previewRect.maxX + offset, y: routedCrop.previewRect.midY)
  check(edgeRouting.videoViewContainer.hitTest(routedCrop.convert(local, to: edgeRouting.videoViewContainer.superview)) === routedCrop,
        "edge hit target includes \(offset) points outside the frame")
}
let beyondHandle = NSPoint(x: routedCrop.previewRect.maxX + 11, y: routedCrop.previewRect.midY)
check(routedCrop.hitTest(routedCrop.convert(beyondHandle, to: edgeRouting.videoViewContainer)) == nil,
      "edge hit target does not capture background beyond nine points")
check(routedCrop.boxRect == routedCrop.previewRect, "full-frame outline reaches all preview edges")
check(routedCrop.bounds.contains(routedCrop.boxRect.insetBy(dx: -3, dy: -3)), "corner handles have unclipped space outside the preview")
let backgroundPoint = NSPoint(x: 2, y: edgeRouting.videoViewContainer.bounds.midY)
check(edgeRouting.interactiveMode.canDragWindow(at: edgeRouting.videoViewContainer.convert(backgroundPoint, to: nil)),
      "background outside the preview permits window dragging")
check(!edgeRouting.interactiveMode.canDragWindow(at: routedCrop.convert(NSPoint(x: routedCrop.previewRect.midX, y: routedCrop.previewRect.midY), to: nil)),
      "preview gestures cannot drag the window")
let saveControl = button("Save", in: edgeRouting)
check(!edgeRouting.interactiveMode.canDragWindow(at: saveControl.convert(NSPoint(x: saveControl.bounds.midX, y: saveControl.bounds.midY), to: nil)),
      "action buttons cannot drag the window")
routedCrop.setSelectedRect(to: NSRect(x: 240, y: 135, width: 480, height: 270))
check(!edgeRouting.interactiveMode.canDragWindow(at: routedCrop.convert(NSPoint(x: routedCrop.previewRect.minX + 20, y: routedCrop.previewRect.minY + 20), to: nil)),
      "dimmed video outside the selection remains a selection surface")
func routedEvent(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) -> NSEvent {
  let local = NSPoint(x: routedCrop.previewRect.minX + x * routedCrop.previewRect.width / routedCrop.videoSize.width,
                      y: routedCrop.previewRect.minY + y * routedCrop.previewRect.height / routedCrop.videoSize.height)
  return NSEvent.mouseEvent(with: type, location: routedCrop.convert(local, to: nil), modifierFlags: [], timestamp: 1,
                           windowNumber: edgeRouting.window!.windowNumber, context: nil, eventNumber: 1,
                           clickCount: 1, pressure: 1)!
}
routedCrop.mouseDown(with: routedEvent(.leftMouseDown, x: 720, y: 405))
for (x, y) in [(CGFloat(700), CGFloat(395)), (640, 335)] {
  routedCrop.mouseDragged(with: routedEvent(.leftMouseDragged, x: x, y: y))
  check(selector(in: edgeRouting).label(forSegment: 0) == "16:9",
        "ratio label stays unchanged during corner resizing at \(x),\(y)")
  check(input("Width in pixels", in: edgeRouting).integerValue == Int(routedCrop.selectedRect.width) &&
        input("Height in pixels", in: edgeRouting).integerValue == Int(routedCrop.selectedRect.height),
        "W/H follow the frame during corner resizing")
}
routedCrop.mouseUp(with: routedEvent(.leftMouseUp, x: 640, y: 335))
check(selector(in: edgeRouting).label(forSegment: 0) == "2:1" && !routedCrop.isDragging,
      "releasing the frame publishes the completed ratio")
routedCrop.setSelectedRect(to: .zero)
routedCrop.mouseDown(with: routedEvent(.leftMouseDown, x: 100, y: 100))
routedCrop.mouseDragged(with: routedEvent(.leftMouseDragged, x: 400, y: 300))
check(selector(in: edgeRouting).label(forSegment: 0) == "—" && routedCrop.selectedRect.size == NSSize(width: 300, height: 200),
      "drawing a new selection also defers only its ratio label")
routedCrop.mouseUp(with: routedEvent(.leftMouseUp, x: 400, y: 300))
check(selector(in: edgeRouting).label(forSegment: 0) == "3:2", "new selection publishes its ratio on release")
edgeRouting.interactiveMode.exit()
check(edgeRouting.videoView.mouseDownCanMoveWindow, "ordinary video window movement returns after crop editing")

let canvasWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500), styleMask: [], backing: .buffered, defer: false)
canvasWindow.isReleasedWhenClosed = false
let canvas = CropBoxView(callback: nil)
canvas.translatesAutoresizingMaskIntoConstraints = true
canvas.frame = NSRect(x: 30, y: 40, width: 480, height: 400)
canvas.videoSize = NSSize(width: 960, height: 540)
canvasWindow.contentView!.addSubview(canvas)
check(!canvas.mouseDownCanMoveWindow, "crop gestures cannot initiate native window movement")
check(canvas.acceptsFirstMouse(for: nil), "the first click in an inactive crop editor can resize the selection")
canvas.setSelectedRect(to: NSRect(x: 100, y: 60, width: 300, height: 200))
func viewPoint(_ source: NSPoint) -> NSPoint {
  NSPoint(x: canvas.bounds.minX + source.x * canvas.bounds.width / canvas.videoSize.width,
          y: canvas.bounds.minY + source.y * canvas.bounds.height / canvas.videoSize.height)
}
func dragInView(_ from: NSPoint, _ to: NSPoint, modifiers: NSEvent.ModifierFlags = []) {
  func event(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: modifiers, timestamp: 1,
                      windowNumber: canvasWindow.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
  }
  canvas.mouseDown(with: event(.leftMouseDown, from))
  canvas.mouseDragged(with: event(.leftMouseDragged, to))
  canvas.mouseUp(with: event(.leftMouseUp, to))
}
func drag(_ from: NSPoint, _ to: NSPoint, modifiers: NSEvent.ModifierFlags = []) { dragInView(viewPoint(from), viewPoint(to), modifiers: modifiers) }
drag(NSPoint(x: 600, y: 300), NSPoint(x: 800, y: 450))
check(canvas.selectedRect == NSRect(x: 600, y: 300, width: 200, height: 150),
      "free drag uses separate X/Y scales and local bounds despite a nonzero frame origin")
canvas.setSelectedRect(to: NSRect(origin: .zero, size: canvas.videoSize))
check(canvas.hitTest(NSPoint(x: canvas.frame.maxX + 3, y: canvas.frame.maxY + 3)) === canvas,
      "corner hit area extends beyond the video edge")
check(canvas.hitTest(NSPoint(x: canvas.frame.maxX + 12, y: canvas.frame.maxY + 12)) == nil,
      "corner hit area leaves distant background untouched")
drag(NSPoint(x: 960, y: 540), NSPoint(x: 800, y: 450))
check(canvas.selectedRect == NSRect(x: 0, y: 0, width: 800, height: 450),
      "the exact top-right boundary of a full-frame selection can be resized")
let handleSelection = NSRect(x: 100, y: 60, width: 300, height: 200)
for left in [true, false] {
  for bottom in [true, false] {
    for offset in [NSPoint(x: 13, y: 0), NSPoint(x: 0, y: 13),
                   NSPoint(x: 16, y: -5), NSPoint(x: -5, y: 16)] {
      canvas.setSelectedRect(to: handleSelection)
      let rect = canvas.boxRect
      let point = NSPoint(x: (left ? rect.minX : rect.maxX) + (left ? offset.x : -offset.x),
                          y: (bottom ? rect.minY : rect.maxY) + (bottom ? offset.y : -offset.y))
      dragInView(point, NSPoint(x: point.x + (left ? -10 : 10), y: point.y + (bottom ? -10 : 10)))
      check(canvas.selectedRect.width > handleSelection.width && canvas.selectedRect.height > handleSelection.height,
            "both arms and nearby space resize diagonally at corner left=\(left), bottom=\(bottom), offset=\(offset)")
      check((left ? canvas.selectedRect.maxX : canvas.selectedRect.minX) == (left ? handleSelection.maxX : handleSelection.minX) &&
            (bottom ? canvas.selectedRect.maxY : canvas.selectedRect.minY) == (bottom ? handleSelection.maxY : handleSelection.minY),
            "corner arm resizing keeps the opposite corner fixed")
    }
  }
}
for horizontal in [true, false] {
  canvas.setSelectedRect(to: handleSelection)
  let rect = canvas.boxRect
  let point = horizontal ? NSPoint(x: rect.maxX, y: rect.midY) : NSPoint(x: rect.midX, y: rect.maxY)
  dragInView(point, NSPoint(x: point.x + 10, y: point.y + 10))
  check(horizontal ? canvas.selectedRect.height == handleSelection.height : canvas.selectedRect.width == handleSelection.width,
        "straight-edge resizing away from corners retains one-axis behavior")
}
// Option-resize mirrors each participating edge around a stationary center.
for left in [true, false] {
  for bottom in [true, false] {
    let start = NSPoint(x: left ? 100 : 400, y: bottom ? 60 : 260)
    for outward in [true, false] {
      canvas.setSelectedRect(to: handleSelection)
      let sign: CGFloat = outward ? 1 : -1
      drag(start, NSPoint(x: start.x + (left ? -20 : 20) * sign,
                          y: start.y + (bottom ? -10 : 10) * sign), modifiers: .option)
      let expected = outward ? NSRect(x: 80, y: 50, width: 340, height: 220) : NSRect(x: 120, y: 70, width: 260, height: 180)
      check(canvas.selectedRect == expected,
            "Option corner resizing mirrors all four edges left=\(left), bottom=\(bottom), outward=\(outward)")
    }
  }
}
for (from, to, expected) in [
  (NSPoint(x: 100, y: 160), NSPoint(x: 80, y: 190), NSRect(x: 80, y: 60, width: 340, height: 200)),
  (NSPoint(x: 400, y: 160), NSPoint(x: 420, y: 190), NSRect(x: 80, y: 60, width: 340, height: 200)),
  (NSPoint(x: 250, y: 60), NSPoint(x: 280, y: 40), NSRect(x: 100, y: 40, width: 300, height: 240)),
  (NSPoint(x: 250, y: 260), NSPoint(x: 280, y: 280), NSRect(x: 100, y: 40, width: 300, height: 240))] {
  canvas.setSelectedRect(to: handleSelection)
  drag(from, to, modifiers: .option)
  check(canvas.selectedRect == expected, "Option straight-edge resizing mirrors only its own axis from \(from)")
}
canvas.setSelectedRect(to: NSRect(x: 10, y: 20, width: 301, height: 201))
drag(NSPoint(x: 311, y: 221), NSPoint(x: 900, y: 500), modifiers: .option)
check(canvas.selectedRect == NSRect(x: 0, y: 0, width: 321, height: 241),
      "Option expansion stops at the nearer image boundary without shifting a half-pixel center")
canvas.setSelectedRect(to: NSRect(x: 10, y: 20, width: 301, height: 201))
drag(NSPoint(x: 311, y: 221), NSPoint(x: 100, y: 30), modifiers: .option)
check(canvas.selectedRect == NSRect(x: 160, y: 120, width: 1, height: 1),
      "Option shrinking odd dimensions can reach one pixel while retaining the exact center")
canvas.setSelectedRect(to: handleSelection)
drag(NSPoint(x: 400, y: 260), NSPoint(x: 100, y: 30), modifiers: .option)
check(canvas.selectedRect == NSRect(x: 249, y: 159, width: 2, height: 2),
      "Option shrinking even dimensions retains integer pixels and a stationary center without crossing")
canvas.setSelectedRect(to: NSRect(x: 0, y: 60, width: 300, height: 200))
drag(NSPoint(x: 300, y: 260), NSPoint(x: 350, y: 280), modifiers: .option)
check(canvas.selectedRect == NSRect(x: 0, y: 40, width: 300, height: 240),
      "an axis already at the image boundary stays fixed while the other axis expands symmetrically")
func centeredResizeEvent(_ type: NSEvent.EventType, _ source: NSPoint, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
  let image = canvas.imageRect
  let point = NSPoint(x: image.minX + source.x * image.width / canvas.videoSize.width,
                      y: image.minY + source.y * image.height / canvas.videoSize.height)
  return NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: modifiers, timestamp: 1,
                           windowNumber: canvasWindow.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
}
// Shift+Option scales every handle around the center with one common scale.
let uniformModifiers: NSEvent.ModifierFlags = [.option, .shift]
for left in [true, false] {
  for bottom in [true, false] {
    let start = NSPoint(x: left ? 100 : 400, y: bottom ? 60 : 260)
    for outward in [true, false] {
      canvas.setSelectedRect(to: handleSelection)
      let sign: CGFloat = outward ? 1 : -1
      drag(start, NSPoint(x: start.x + (left ? -30 : 30) * sign,
                          y: start.y + (bottom ? -20 : 20) * sign), modifiers: uniformModifiers)
      let expected = outward ? NSRect(x: 70, y: 40, width: 360, height: 240) : NSRect(x: 130, y: 80, width: 240, height: 160)
      check(canvas.selectedRect == expected,
            "Shift+Option corner scales both axes left=\(left), bottom=\(bottom), outward=\(outward)")
    }
  }
}
for (start, delta) in [
  (NSPoint(x: 100, y: 160), NSPoint(x: -30, y: 17)),
  (NSPoint(x: 400, y: 160), NSPoint(x: 30, y: 17)),
  (NSPoint(x: 250, y: 60), NSPoint(x: 17, y: -20)),
  (NSPoint(x: 250, y: 260), NSPoint(x: 17, y: 20))] {
  for outward in [true, false] {
    canvas.setSelectedRect(to: handleSelection)
    let sign: CGFloat = outward ? 1 : -1
    drag(start, NSPoint(x: start.x + delta.x * sign, y: start.y + delta.y * sign), modifiers: uniformModifiers)
    let expected = outward ? NSRect(x: 70, y: 40, width: 360, height: 240) : NSRect(x: 130, y: 80, width: 240, height: 160)
    check(canvas.selectedRect == expected, "Shift+Option straight edge scales all four sides from \(start), outward=\(outward)")
  }
}
canvas.setSelectedRect(to: NSRect(x: 10, y: 60, width: 300, height: 200))
drag(NSPoint(x: 310, y: 160), NSPoint(x: 800, y: 160), modifiers: uniformModifiers)
check(canvas.selectedRect == NSRect(x: 0, y: 53, width: 320, height: 214),
      "uniform expansion stops both axes at the first boundary with source-pixel rounding")
canvas.setSelectedRect(to: NSRect(x: 100, y: 20, width: 300, height: 200))
drag(NSPoint(x: 400, y: 120), NSPoint(x: 800, y: 120), modifiers: uniformModifiers)
check(canvas.selectedRect == NSRect(x: 70, y: 0, width: 360, height: 240),
      "horizontal uniform expansion also respects the vertical boundary")
canvas.setSelectedRect(to: NSRect(x: 0, y: 60, width: 300, height: 200))
drag(NSPoint(x: 300, y: 160), NSPoint(x: 350, y: 160), modifiers: uniformModifiers)
check(canvas.selectedRect == NSRect(x: 0, y: 60, width: 300, height: 200),
      "uniform expansion cannot change another axis when one axis is already bounded")
for selection in [handleSelection, NSRect(x: 10, y: 20, width: 301, height: 201)] {
  for outward in [true, false] {
    canvas.setSelectedRect(to: selection)
    drag(NSPoint(x: selection.maxX, y: selection.midY),
         NSPoint(x: outward ? 900 : 0, y: selection.midY), modifiers: uniformModifiers)
    let result = canvas.selectedRect
    check(result.midX == selection.midX && result.midY == selection.midY && result.width >= 1 && result.height >= 1 &&
          result.minX >= 0 && result.maxX <= canvas.videoSize.width && result.minY >= 0 && result.maxY <= canvas.videoSize.height,
          "uniform resize preserves the exact center, pixel bounds and minimum for \(selection), outward=\(outward)")
    check(abs(result.width - result.height * selection.width / selection.height) <= 1 + selection.width / selection.height,
          "uniform resize retains the initial proportion within symmetric pixel quantization")
  }
}
canvas.setSelectedRect(to: handleSelection)
canvas.mouseDown(with: centeredResizeEvent(.leftMouseDown, NSPoint(x: 400, y: 160), modifiers: .option))
canvas.mouseDragged(with: centeredResizeEvent(.leftMouseDragged, NSPoint(x: 430, y: 160), modifiers: .option))
let beforeShiftPress = canvas.selectedRect
canvas.mouseDragged(with: centeredResizeEvent(.leftMouseDragged, NSPoint(x: 430, y: 160), modifiers: uniformModifiers))
check(canvas.selectedRect == beforeShiftPress, "pressing Shift during an Option resize does not jump")
canvas.mouseDragged(with: centeredResizeEvent(.leftMouseDragged, NSPoint(x: 466, y: 160), modifiers: uniformModifiers))
check(canvas.selectedRect == NSRect(x: 34, y: 40, width: 432, height: 240),
      "Shift pressed mid-drag locks the currently visible proportion around its center")
let beforeShiftRelease = canvas.selectedRect
canvas.mouseDragged(with: centeredResizeEvent(.leftMouseDragged, NSPoint(x: 466, y: 160), modifiers: .option))
check(canvas.selectedRect == beforeShiftRelease, "releasing Shift during an Option resize does not jump")
canvas.mouseDragged(with: centeredResizeEvent(.leftMouseDragged, NSPoint(x: 476, y: 160), modifiers: .option))
canvas.mouseUp(with: centeredResizeEvent(.leftMouseUp, NSPoint(x: 476, y: 160), modifiers: .option))
check(canvas.selectedRect == NSRect(x: 24, y: 40, width: 452, height: 240),
      "releasing Shift returns an Option edge resize to its original single axis")
canvas.setSelectedRect(to: handleSelection)
drag(NSPoint(x: 400, y: 160), NSPoint(x: 430, y: 180), modifiers: .shift)
check(canvas.selectedRect == NSRect(x: 100, y: 60, width: 330, height: 200),
      "Shift without Option retains ordinary resize behavior")
canvas.allowsZoom = true
canvas.setZoom(3)
canvas.setSelectedRect(to: NSRect(x: 350, y: 220, width: 100, height: 60))
canvas.mouseDown(with: centeredResizeEvent(.leftMouseDown, NSPoint(x: 450, y: 250), modifiers: uniformModifiers))
canvas.mouseDragged(with: centeredResizeEvent(.leftMouseDragged, NSPoint(x: 460, y: 250), modifiers: uniformModifiers))
canvas.mouseUp(with: centeredResizeEvent(.leftMouseUp, NSPoint(x: 460, y: 250), modifiers: uniformModifiers))
check(canvas.selectedRect == NSRect(x: 340, y: 214, width: 120, height: 72) && canvas.previewTransform.zoom == 3,
      "Shift+Option proportional resizing uses source pixels under zoom without altering the preview")
canvas.resetPreview()
canvas.allowsZoom = false
canvas.setSelectedRect(to: handleSelection)
canvas.mouseDown(with: centeredResizeEvent(.leftMouseDown, NSPoint(x: 400, y: 160)))
canvas.mouseDragged(with: centeredResizeEvent(.leftMouseDragged, NSPoint(x: 420, y: 160)))
let beforeOptionPress = canvas.selectedRect
canvas.mouseDragged(with: centeredResizeEvent(.leftMouseDragged, NSPoint(x: 420, y: 160), modifiers: .option))
check(canvas.selectedRect == beforeOptionPress, "pressing Option during a resize does not jump the frame")
canvas.mouseDragged(with: centeredResizeEvent(.leftMouseDragged, NSPoint(x: 430, y: 160), modifiers: .option))
check(canvas.selectedRect == NSRect(x: 90, y: 60, width: 340, height: 200),
      "Option pressed mid-drag mirrors subsequent motion around the current center")
let beforeOptionRelease = canvas.selectedRect
canvas.mouseDragged(with: centeredResizeEvent(.leftMouseDragged, NSPoint(x: 430, y: 160)))
check(canvas.selectedRect == beforeOptionRelease, "releasing Option during a resize does not jump the frame")
canvas.mouseDragged(with: centeredResizeEvent(.leftMouseDragged, NSPoint(x: 440, y: 160)))
canvas.mouseUp(with: centeredResizeEvent(.leftMouseUp, NSPoint(x: 440, y: 160)))
check(canvas.selectedRect == NSRect(x: 90, y: 60, width: 350, height: 200),
      "releasing Option restores ordinary resizing with the opposite edge fixed")
canvas.allowsZoom = true
canvas.setZoom(3)
canvas.setSelectedRect(to: NSRect(x: 350, y: 220, width: 100, height: 60))
canvas.mouseDown(with: centeredResizeEvent(.leftMouseDown, NSPoint(x: 450, y: 280), modifiers: .option))
canvas.mouseDragged(with: centeredResizeEvent(.leftMouseDragged, NSPoint(x: 460, y: 288), modifiers: .option))
canvas.mouseUp(with: centeredResizeEvent(.leftMouseUp, NSPoint(x: 460, y: 288), modifiers: .option))
check(canvas.selectedRect == NSRect(x: 340, y: 212, width: 120, height: 76) && canvas.previewTransform.zoom == 3,
      "Option resizing under zoom mirrors exact source pixels without changing the preview transform")
canvas.resetPreview()
canvas.allowsZoom = false
canvas.setSelectedRect(to: handleSelection)
drag(NSPoint(x: 250, y: 160), NSPoint(x: 270, y: 170), modifiers: .option)
check(canvas.selectedRect == NSRect(x: 120, y: 70, width: 300, height: 200),
      "Option leaves dragging the selection interior as ordinary movement")
canvas.setSelectedRect(to: .zero)
drag(NSPoint(x: 600, y: 300), NSPoint(x: 800, y: 450), modifiers: .option)
check(canvas.selectedRect == NSRect(x: 600, y: 300, width: 200, height: 150),
      "Option leaves drawing a new selection unchanged")

canvas.setSelectedRect(to: NSRect(x: 100, y: 60, width: 300, height: 200))
drag(NSPoint(x: 250, y: 160), NSPoint(x: 900, y: 500))
check(canvas.selectedRect == NSRect(x: 660, y: 340, width: 300, height: 200), "moving a selection clamps its origin and preserves dimensions")
canvas.setSelectedRect(to: NSRect(x: 100, y: 60, width: 300, height: 200))
drag(NSPoint(x: 100, y: 60), NSPoint(x: 500, y: 350))
check(canvas.selectedRect == NSRect(x: 399, y: 259, width: 1, height: 1), "corner resize cannot cross the opposite edge or create negative dimensions")
drag(NSPoint(x: 400, y: 260), NSPoint(x: 500, y: 350))
check(canvas.selectedRect == NSRect(x: 399, y: 259, width: 101, height: 91), "a one-pixel selection can grow from its nearest opposite corner")
canvas.setSelectedRect(to: NSRect(x: 100, y: 60, width: 300, height: 200))
drag(NSPoint(x: 400, y: 260), NSPoint(x: 950, y: 530))
check(canvas.selectedRect == NSRect(x: 100, y: 60, width: 850, height: 470), "corner resize updates both pixel dimensions")
canvas.bounds.origin = NSPoint(x: 20, y: 30)
canvas.setSelectedRect(to: NSRect(x: 100, y: 60, width: 300, height: 200))
check(abs(canvas.boxRect.minX - 70) < 0.001 && abs(canvas.boxRect.minY - (30 + 60 * 400 / 540.0)) < 0.001,
      "selection mapping respects a nonzero bounds origin")

canvas.bounds.origin = .zero
canvas.setSelectedRect(to: NSRect(x: 240, y: 135, width: 480, height: 270))
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 480, pixelsHigh: 400,
  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(deviceRed: 0.9, green: 0.2, blue: 0.6, alpha: 1).setFill()
canvas.bounds.fill()
let before = bitmap.colorAt(x: 240, y: 200)!.usingColorSpace(.deviceRGB)!
canvas.draw(canvas.bounds)
let inside = bitmap.colorAt(x: 240, y: 200)!.usingColorSpace(.deviceRGB)!
let outside = bitmap.colorAt(x: 20, y: 20)!.usingColorSpace(.deviceRGB)!
let besideOutline = bitmap.colorAt(x: 118, y: 200)!.usingColorSpace(.deviceRGB)!
NSGraphicsContext.restoreGraphicsState()
check(abs(inside.redComponent - before.redComponent) < 0.005 &&
      abs(inside.greenComponent - before.greenComponent) < 0.005 &&
      abs(inside.blueComponent - before.blueComponent) < 0.005,
      "selection rendering leaves video colors untouched")
check(outside.redComponent < before.redComponent * 0.6 && outside.alphaComponent > 0.99,
      "only the area outside selection is dimmed")
check(besideOutline.redComponent < before.redComponent * 0.6,
      "shading reaches the thin outline instead of leaving a bright strip beside it")
let expandedCanvas = CropBoxView(callback: nil)
expandedCanvas.frame = NSRect(x: 0, y: 0, width: 200, height: 160)
expandedCanvas.previewInset = 8
expandedCanvas.videoSize = NSSize(width: 184, height: 144)
expandedCanvas.setSelectedRect(to: NSRect(x: 0, y: 0, width: 184, height: 144))
let expandedBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 160,
  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: expandedBitmap)
NSColor.black.setFill()
expandedCanvas.bounds.fill()
expandedCanvas.draw(expandedCanvas.bounds)
NSGraphicsContext.restoreGraphicsState()
let outerCorner = expandedBitmap.colorAt(x: 7, y: 8)!.usingColorSpace(.deviceRGB)!
check(outerCorner.redComponent > 0.8, "corner stroke renders outside the preview without clipping")
let viewport = NSRect(x: 20, y: 30, width: 480, height: 270)
let zoomAnchor = NSPoint(x: 140, y: 120)
var previewTransform = CropPreviewTransform()
check(previewTransform.imageRect(in: viewport) == viewport, "base zoom exactly fits the full preview")
previewTransform.setZoom(0.2, at: zoomAnchor, in: viewport)
check(previewTransform == CropPreviewTransform(), "pinching out cannot go below the fitted full frame")
previewTransform.pan(by: NSPoint(x: 200, y: -100), in: viewport)
check(previewTransform == CropPreviewTransform(), "panning at fit cannot displace the source frame")
previewTransform.setZoom(2, at: zoomAnchor, in: viewport)
let anchoredImage = previewTransform.imageRect(in: viewport)
check(abs((zoomAnchor.x - anchoredImage.minX) / anchoredImage.width - 0.25) < 1e-9 &&
      abs((zoomAnchor.y - anchoredImage.minY) / anchoredImage.height - 1.0 / 3) < 1e-9,
      "pinch keeps the source point under the cursor stationary")
let validTransform = previewTransform
previewTransform.setZoom(.nan, at: zoomAnchor, in: viewport)
previewTransform.pan(by: NSPoint(x: CGFloat.infinity, y: 0), in: viewport)
check(previewTransform == validTransform, "invalid gesture values do not poison the preview transform")
for delta in [NSPoint(x: 10000, y: 10000), NSPoint(x: -10000, y: -10000),
              NSPoint(x: -10000, y: 10000), NSPoint(x: 10000, y: -10000)] {
  previewTransform.pan(by: delta, in: viewport)
  let image = previewTransform.imageRect(in: viewport)
  check(image.contains(viewport), "panning to \(delta) stops at the image edges without exposing empty space")
}
previewTransform.setZoom(100, at: zoomAnchor, in: viewport)
check(previewTransform.zoom == 8, "preview zoom has a bounded maximum")
previewTransform.setZoom(1, at: zoomAnchor, in: viewport)
check(previewTransform == CropPreviewTransform(), "returning to fit removes all accumulated pan")

let zoomEditor = MainWindowController(size: NSSize(width: 640, height: 360))
let savedVideoMask = CALayer()
let savedVideoTransform = CATransform3DMakeTranslation(0, 0, 0)
zoomEditor.videoView.layer!.mask = savedVideoMask
zoomEditor.videoView.layer!.transform = savedVideoTransform
zoomEditor.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
zoomEditor.videoViewContainer.layoutSubtreeIfNeeded()
let zoomBox = box(in: zoomEditor), zoomPicker = zoomControl(in: zoomEditor)
let zoomWindowFrame = zoomEditor.window!.frame, zoomVideoBounds = zoomEditor.videoView.bounds
let videoLayerViewport = zoomEditor.videoView.layer!.convert(zoomVideoBounds, to: zoomEditor.videoView.layer!.superlayer)
zoomBox.setSelectedRect(to: NSRect(x: 300, y: 200, width: 200, height: 100))
let zoomSelection = zoomBox.selectedRect, zoomRatio = selector(in: zoomEditor).label(forSegment: 0)
let zoomCenter = NSPoint(x: zoomBox.previewRect.midX, y: zoomBox.previewRect.midY)
zoomBox.setZoom(2, at: zoomCenter)
zoomBox.resetCursorRects()
check(zoomBox.selectedRect == zoomSelection && selector(in: zoomEditor).label(forSegment: 0) == zoomRatio &&
      input("Width in pixels", in: zoomEditor).integerValue == 200 && input("Height in pixels", in: zoomEditor).integerValue == 100,
      "zoom changes neither crop pixels nor the aspect label")
check(zoomEditor.window!.frame == zoomWindowFrame && zoomEditor.videoView.bounds == zoomVideoBounds,
      "zoom leaves the window and live video render dimensions unchanged")
let zoomLayer = zoomEditor.videoView.layer!
check(zoomLayer.transform.m11 == 2 && zoomLayer.transform.m22 == 2 &&
      zoomLayer.mask !== savedVideoMask && zoomLayer.mask!.frame.size ==
        NSSize(width: zoomVideoBounds.width / 2, height: zoomVideoBounds.height / 2),
      "live video is scaled and clipped to the fixed viewport")
let visibleLayerViewport = zoomLayer.convert(zoomLayer.mask!.frame, to: zoomLayer.superlayer)
check(abs(visibleLayerViewport.minX - videoLayerViewport.minX) < 1e-6 &&
      abs(visibleLayerViewport.minY - videoLayerViewport.minY) < 1e-6 &&
      abs(visibleLayerViewport.width - videoLayerViewport.width) < 1e-6 &&
      abs(visibleLayerViewport.height - videoLayerViewport.height) < 1e-6,
      "transformed video mask stays at the original viewport despite AppKit's layer anchor")
check(zoomPicker.item(at: 0)?.title == "200%" && zoomPicker.accessibilityValue() as? String == "200%",
      "zoom indicator and accessibility publish the current scale")
let panEvent = WheelEvent()
panEvent.point = zoomBox.convert(zoomCenter, to: nil)
panEvent.precise = true
panEvent.dx = 42
panEvent.dy = -30
let imageBeforePan = zoomBox.imageRect
zoomBox.scrollWheel(with: panEvent)
check(abs(zoomBox.imageRect.minX - imageBeforePan.minX - 42) < 1e-9 &&
      abs(zoomBox.imageRect.minY - imageBeforePan.minY - 30) < 1e-9,
      "two-finger scrolling pans horizontally and vertically in viewport points")
check(abs(zoomLayer.transform.m41 + (1 - zoomLayer.transform.m11) * zoomLayer.bounds.width * zoomLayer.anchorPoint.x -
        (zoomBox.imageRect.minX - zoomBox.previewRect.minX)) < 1e-9 &&
      abs(zoomLayer.transform.m42 + (1 - zoomLayer.transform.m22) * zoomLayer.bounds.height * zoomLayer.anchorPoint.y -
        (zoomBox.imageRect.minY - zoomBox.previewRect.minY)) < 1e-9,
      "live video and selection use the same pan offset")
let pannedLayerViewport = zoomLayer.convert(zoomLayer.mask!.frame, to: zoomLayer.superlayer)
check(abs(pannedLayerViewport.minX - videoLayerViewport.minX) < 1e-6 &&
      abs(pannedLayerViewport.minY - videoLayerViewport.minY) < 1e-6,
      "panning moves the image while the transformed mask stays stationary")
let transformBeforeOutsideScroll = zoomBox.previewTransform
panEvent.point = zoomBox.convert(NSPoint(x: -20, y: -20), to: nil)
zoomBox.scrollWheel(with: panEvent)
check(zoomBox.previewTransform == transformBeforeOutsideScroll, "scrolling outside the preview does not pan")
panEvent.point = zoomBox.convert(zoomCenter, to: nil)
panEvent.inertia = .changed
panEvent.dx = 12
panEvent.dy = 0
zoomBox.scrollWheel(with: panEvent)
check(abs(zoomBox.imageRect.minX - imageBeforePan.minX - 54) < 1e-9,
      "native momentum continues the same bounded pan")
zoomBox.resetPreview()
zoomBox.setZoom(2)
func zoomViewPoint(_ source: NSPoint) -> NSPoint {
  NSPoint(x: zoomBox.imageRect.minX + source.x * zoomBox.imageRect.width / zoomBox.videoSize.width,
          y: zoomBox.imageRect.minY + source.y * zoomBox.imageRect.height / zoomBox.videoSize.height)
}
func zoomMouse(_ type: NSEvent.EventType, source: NSPoint) -> NSEvent {
  NSEvent.mouseEvent(with: type, location: zoomBox.convert(zoomViewPoint(source), to: nil), modifierFlags: [], timestamp: 1,
                    windowNumber: zoomEditor.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
}
zoomBox.mouseDown(with: zoomMouse(.leftMouseDown, source: NSPoint(x: 500, y: 300)))
zoomBox.scrollWheel(with: panEvent)
zoomBox.setZoom(4)
check(zoomBox.previewTransform.zoom == 2 && zoomBox.previewTransform.center == NSPoint(x: 0.5, y: 0.5),
      "pinch and pan cannot move the image during a crop-handle drag")
zoomBox.mouseDragged(with: zoomMouse(.leftMouseDragged, source: NSPoint(x: 520, y: 310)))
zoomBox.mouseUp(with: zoomMouse(.leftMouseUp, source: NSPoint(x: 520, y: 310)))
check(zoomBox.selectedRect == NSRect(x: 300, y: 200, width: 220, height: 110),
      "resizing a zoomed corner maps back to exact source pixels")
let selectionAfterZoomDrag = zoomBox.selectedRect
let fitItem = zoomPicker.itemArray.first { $0.tag == 100 }!
NSApp.sendAction(fitItem.action!, to: fitItem.target, from: fitItem)
check(zoomBox.previewTransform == CropPreviewTransform() && zoomPicker.item(at: 0)?.title == "100%" &&
      zoomLayer.mask === savedVideoMask && zoomBox.selectedRect == selectionAfterZoomDrag,
      "Fit restores the original viewport and mask while keeping the crop")
let fourHundred = zoomPicker.itemArray.first { $0.tag == 400 }!
NSApp.sendAction(fourHundred.action!, to: fourHundred.target, from: fourHundred)
check(zoomBox.previewTransform.zoom == 4 && fourHundred.state == .on && zoomPicker.item(at: 0)?.title == "400%",
      "zoom menu can set a scale and marks the active value")
zoomEditor.window!.setContentSize(NSSize(width: 400, height: 225))
zoomEditor.interactiveMode.resize()
check(zoomBox.previewTransform.zoom == 4 && zoomBox.imageRect.contains(zoomBox.previewRect) &&
      zoomBox.selectedRect == selectionAfterZoomDrag,
      "window resize preserves zoom and source crop without revealing empty space")
button("Reset", in: zoomEditor).performClick(nil)
zoomBox.resetCursorRects()
check(zoomBox.previewTransform.zoom == 4 && zoomBox.selectedRect.size == zoomBox.videoSize,
      "Reset changes the crop without resetting preview navigation")
zoomBox.setSelectedRect(to: selectionAfterZoomDrag)
button("Save", in: zoomEditor).performClick(nil)
check(zoomEditor.player.savedCrop?.params == ["x": "300", "y": "230", "w": "220", "h": "110", "exact": "1"],
      "Save from a zoomed view keeps exact source filter coordinates")
check(CATransform3DEqualToTransform(zoomLayer.transform, savedVideoTransform) && zoomLayer.mask === savedVideoMask,
      "leaving crop restores the live video layer transform and mask")
zoomEditor.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
check(zoomBox.previewTransform == CropPreviewTransform() && zoomPicker.item(at: 0)?.title == "100%",
      "a new editing session starts with the full frame fitted")
zoomEditor.interactiveMode.exit()

final class CropPinchRecognizer: NSMagnificationGestureRecognizer {
  var point = NSPoint.zero
  private var simulatedState = NSGestureRecognizer.State.possible
  override var state: NSGestureRecognizer.State {
    get { simulatedState }
    set { simulatedState = newValue }
  }
  override func location(in view: NSView?) -> NSPoint { point }
}
let pinchEditor = MainWindowController()
pinchEditor.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
pinchEditor.videoViewContainer.layoutSubtreeIfNeeded()
let pinchBox = box(in: pinchEditor)
let recognizer = CropPinchRecognizer()
pinchBox.addGestureRecognizer(recognizer)
recognizer.point = NSPoint(x: pinchBox.previewRect.midX, y: pinchBox.previewRect.midY)
recognizer.magnification = 0
recognizer.state = .began
pinchEditor.interactiveMode.handleMagnifyGesture(recognizer)
recognizer.magnification = 0.5
recognizer.state = .changed
pinchEditor.interactiveMode.handleMagnifyGesture(recognizer)
recognizer.magnification = 1
pinchEditor.interactiveMode.handleMagnifyGesture(recognizer)
check(pinchBox.previewTransform.zoom == 2, "pinch uses cumulative magnification without compounding previous events")
recognizer.state = .ended
pinchEditor.interactiveMode.handleMagnifyGesture(recognizer)
recognizer.state = .began
recognizer.magnification = -0.9
pinchEditor.interactiveMode.handleMagnifyGesture(recognizer)
check(pinchBox.previewTransform.zoom == 1, "reverse pinch stops at the fitted minimum")
recognizer.state = .ended
pinchEditor.interactiveMode.handleMagnifyGesture(recognizer)
recognizer.point = NSPoint(x: -10, y: -10)
recognizer.state = .began
recognizer.magnification = 1
pinchEditor.interactiveMode.handleMagnifyGesture(recognizer)
recognizer.point = NSPoint(x: pinchBox.previewRect.midX, y: pinchBox.previewRect.midY)
recognizer.state = .changed
pinchEditor.interactiveMode.handleMagnifyGesture(recognizer)
check(pinchBox.previewTransform.zoom == 1, "a pinch begun outside the preview cannot acquire it midway")
pinchEditor.interactiveMode.exit()
// Mouse wheel modifiers share the preview transform with trackpad gestures.
let mouseEditor = MainWindowController(size: NSSize(width: 900, height: 507))
mouseEditor.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
mouseEditor.videoViewContainer.layoutSubtreeIfNeeded()
let mouseBox = box(in: mouseEditor)
let mouseWheel = WheelEvent()
let mouseAnchor = NSPoint(x: mouseBox.previewRect.midX + 30, y: mouseBox.previewRect.midY - 20)
mouseWheel.point = mouseBox.convert(mouseAnchor, to: nil)
mouseWheel.modifiers = .option
mouseWheel.dy = 1
let anchorBefore = NSPoint(x: (mouseAnchor.x - mouseBox.imageRect.minX) / mouseBox.imageRect.width,
                           y: (mouseAnchor.y - mouseBox.imageRect.minY) / mouseBox.imageRect.height)
mouseBox.scrollWheel(with: mouseWheel)
let anchorAfter = NSPoint(x: (mouseAnchor.x - mouseBox.imageRect.minX) / mouseBox.imageRect.width,
                          y: (mouseAnchor.y - mouseBox.imageRect.minY) / mouseBox.imageRect.height)
check(mouseBox.previewTransform.zoom > 1 && abs(anchorBefore.x - anchorAfter.x) < 1e-9 &&
      abs(anchorBefore.y - anchorAfter.y) < 1e-9,
      "Option+mouse wheel zooms around the pointer without shifting its source point")
check(zoomControl(in: mouseEditor).item(at: 0)?.title != "100%",
      "mouse wheel zoom updates the scale indicator")
mouseWheel.dy = -1000
mouseBox.scrollWheel(with: mouseWheel)
check(mouseBox.previewTransform.zoom == 1, "Option+wheel cannot zoom out beyond the fitted frame")
mouseWheel.dy = 1000
mouseBox.scrollWheel(with: mouseWheel)
check(mouseBox.previewTransform.zoom == 8, "large wheel deltas clamp to the maximum zoom")
mouseBox.resetPreview()
mouseBox.setZoom(2)
mouseWheel.modifiers = []
mouseWheel.dx = 2
mouseWheel.dy = -2
let beforeVerticalWheel = mouseBox.imageRect
mouseBox.scrollWheel(with: mouseWheel)
check(abs(mouseBox.imageRect.minX - beforeVerticalWheel.minX) < 1e-9 &&
      abs(mouseBox.imageRect.minY - beforeVerticalWheel.minY - 20) < 1e-9,
      "ordinary mouse wheel pans vertically with mouse-sized steps")
mouseWheel.modifiers = .shift
mouseWheel.dx = 0
let beforeShiftWheel = mouseBox.imageRect
mouseBox.scrollWheel(with: mouseWheel)
check(abs(mouseBox.imageRect.minX - beforeShiftWheel.minX + 20) < 1e-9 &&
      abs(mouseBox.imageRect.minY - beforeShiftWheel.minY) < 1e-9,
      "Shift+mouse wheel converts vertical wheel movement into horizontal pan")
mouseWheel.dx = -2
mouseWheel.dy = 0
let beforeRemappedWheel = mouseBox.imageRect
mouseBox.scrollWheel(with: mouseWheel)
check(abs(mouseBox.imageRect.minX - beforeRemappedWheel.minX + 20) < 1e-9 &&
      abs(mouseBox.imageRect.minY - beforeRemappedWheel.minY) < 1e-9,
      "Shift+wheel accepts macOS-remapped horizontal deltas without doubling or reversing them")
mouseWheel.modifiers = [.option, .shift]
mouseWheel.dx = 1
let beforeCombinedWheel = mouseBox.previewTransform.zoom
mouseBox.scrollWheel(with: mouseWheel)
check(mouseBox.previewTransform.zoom > beforeCombinedWheel,
      "Option zoom takes precedence over Shift and accepts remapped wheel deltas")
let beforeOutsideWheel = mouseBox.previewTransform
mouseWheel.point = mouseBox.convert(NSPoint(x: -20, y: -20), to: nil)
mouseBox.scrollWheel(with: mouseWheel)
check(mouseBox.previewTransform == beforeOutsideWheel, "Option+wheel outside the preview leaves zoom unchanged")
check(mouseBox.selectedRect == NSRect(origin: .zero, size: mouseBox.videoSize),
      "mouse navigation never changes source crop pixels")
mouseEditor.interactiveMode.exit()

func editorKey(_ key: UInt16, in editor: MainWindowController, time: TimeInterval,
               modifiers: NSEvent.ModifierFlags = [], repeated: Bool = false) -> NSEvent {
  NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: time,
                  windowNumber: editor.window!.windowNumber, context: nil, characters: key == 53 ? "\u{1b}" : "\r",
                  charactersIgnoringModifiers: key == 53 ? "\u{1b}" : "\r", isARepeat: repeated, keyCode: key)!
}
let keyboardEditor = MainWindowController()
let priorKeyboardCrop = MPVFilter.crop(w: 501, h: 301, x: 200, y: 100, exact: true)
keyboardEditor.player.info.cropFilter = priorKeyboardCrop
keyboardEditor.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
let keyboardBox = box(in: keyboardEditor)
check(keyboardEditor.interactiveMode.handleEditorEvent(editorKey(53, in: keyboardEditor, time: 10)) == nil &&
      keyboardEditor.interactiveMode.isActive && keyboardBox.selectedRect == NSRect(origin: .zero, size: keyboardBox.videoSize),
      "first Escape resets the crop and keeps the editor open")
_ = keyboardEditor.interactiveMode.handleEditorEvent(editorKey(53, in: keyboardEditor, time: 10.05, repeated: true))
check(keyboardEditor.interactiveMode.isActive, "holding Escape cannot trigger Cancel through key repeat")
let unrelatedKey = editorKey(49, in: keyboardEditor, time: 10.1)
check(keyboardEditor.interactiveMode.handleEditorEvent(unrelatedKey) === unrelatedKey,
      "playback and other shortcuts pass through the editor event handler")
let escapeTime: TimeInterval = 1000
_ = keyboardEditor.interactiveMode.handleEditorEvent(editorKey(53, in: keyboardEditor, time: escapeTime))
check(!keyboardEditor.interactiveMode.isActive && keyboardEditor.player.savedCrop === priorKeyboardCrop,
      "Escape on the reset frame cancels after any delay and intervening playback input")
let inactiveEscape = editorKey(53, in: keyboardEditor, time: escapeTime + 0.05)
check(keyboardEditor.interactiveMode.handleEditorEvent(inactiveEscape) === inactiveEscape,
      "editor shortcuts stop intercepting events after exit")
keyboardEditor.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
keyboardBox.setSelectedRect(to: NSRect(x: 240, y: 135, width: 480, height: 270))
_ = keyboardEditor.interactiveMode.handleEditorEvent(editorKey(53, in: keyboardEditor, time: escapeTime + 0.1))
check(keyboardEditor.interactiveMode.isActive && keyboardBox.selectedRect == NSRect(origin: .zero, size: keyboardBox.videoSize),
      "a smaller crop with the original aspect still resets based on its frame rather than the ratio label")
keyboardBox.setSelectedRect(to: NSRect(x: 100, y: 60, width: 300, height: 200))
_ = keyboardEditor.interactiveMode.handleEditorEvent(editorKey(53, in: keyboardEditor, time: escapeTime + 0.11))
check(keyboardEditor.interactiveMode.isActive && keyboardBox.selectedRect == NSRect(origin: .zero, size: keyboardBox.videoSize),
      "editing again after Reset makes the next Escape reset even when the presses are close together")
_ = keyboardEditor.interactiveMode.handleEditorEvent(editorKey(53, in: keyboardEditor, time: escapeTime + 0.12))
check(!keyboardEditor.interactiveMode.isActive && keyboardEditor.player.savedCrop === priorKeyboardCrop,
      "Escape on the full frame cancels without requiring a double-click sequence")
let freshEscape = MainWindowController()
freshEscape.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
_ = freshEscape.interactiveMode.handleEditorEvent(editorKey(53, in: freshEscape, time: 1))
check(!freshEscape.interactiveMode.isActive && freshEscape.player.savedCrop == nil,
      "one Escape closes an untouched full-source editor")
freshEscape.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
let pendingEscapeWidth = input("Width in pixels", in: freshEscape)
pendingEscapeWidth.selectText(nil)
pendingEscapeWidth.currentEditor()!.string = "501"
_ = freshEscape.interactiveMode.handleEditorEvent(editorKey(53, in: freshEscape, time: 2))
check(freshEscape.interactiveMode.isActive && box(in: freshEscape).selectedRect.width == 960 &&
      pendingEscapeWidth.currentEditor() == nil,
      "Escape commits pending dimension text before deciding to reset instead of cancel")
_ = freshEscape.interactiveMode.handleEditorEvent(editorKey(53, in: freshEscape, time: 2000))
check(!freshEscape.interactiveMode.isActive, "Escape after a dimension Reset cancels regardless of elapsed time")
let emptyEscape = MainWindowController()
emptyEscape.interactiveMode.enter(mode: .crop)
_ = emptyEscape.interactiveMode.handleEditorEvent(editorKey(53, in: emptyEscape, time: 1))
check(emptyEscape.interactiveMode.isActive && box(in: emptyEscape).selectedRect == NSRect(origin: .zero, size: box(in: emptyEscape).videoSize),
      "Escape resets an empty selection to the full source before exit")
emptyEscape.interactiveMode.exit()
keyboardEditor.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
_ = keyboardEditor.interactiveMode.handleEditorEvent(editorKey(53, in: keyboardEditor, time: escapeTime + 0.13))
check(keyboardEditor.interactiveMode.isActive, "reopening a saved crop starts from its actual selection without key history")
let outsideKeyboardEditor = MainWindowController()
let otherWindowEscape = editorKey(53, in: outsideKeyboardEditor, time: escapeTime + 0.15)
check(keyboardEditor.interactiveMode.handleEditorEvent(otherWindowEscape) === otherWindowEscape,
      "crop shortcuts do not consume events belonging to another window")
keyboardEditor.isCropTransitionInProgress = true
check(keyboardEditor.interactiveMode.handleEditorEvent(otherWindowEscape) === otherWindowEscape,
      "pending crop exit leaves another player's keyboard events untouched")
keyboardEditor.isCropTransitionInProgress = false
let modifiedReturn = editorKey(36, in: keyboardEditor, time: 12, modifiers: .command)
check(keyboardEditor.interactiveMode.handleEditorEvent(modifiedReturn) === modifiedReturn && keyboardEditor.interactiveMode.isActive,
      "modified Return remains available to existing application bindings")
private let keyboardZoom = zoomControl(in: keyboardEditor) as! CropZoomPopUpButton
keyboardZoom.menuTrackingChanged?(true)
let menuReturn = editorKey(36, in: keyboardEditor, time: 12.1)
let menuEscape = editorKey(53, in: keyboardEditor, time: 12.2)
check(keyboardEditor.interactiveMode.handleEditorEvent(menuReturn) === menuReturn &&
      keyboardEditor.interactiveMode.handleEditorEvent(menuEscape) === menuEscape && keyboardEditor.interactiveMode.isActive,
      "open editor menus retain Return/Escape navigation instead of triggering Save/Reset")
keyboardEditor.interactiveMode.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: NSPopover()))
check(keyboardEditor.interactiveMode.handleEditorEvent(menuReturn) === menuReturn && keyboardEditor.interactiveMode.isActive,
      "a stale popover close cannot release another menu's keyboard routing or trigger Save")
keyboardZoom.menuTrackingChanged?(false)
let nativeMenuEditor = MainWindowController()
nativeMenuEditor.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
let nativeMenuBox = box(in: nativeMenuEditor)
nativeMenuBox.setSelectedRect(to: NSRect(x: 100, y: 60, width: 300, height: 200))
let nativeSelection = nativeMenuBox.selectedRect
let parentNativeMenu = NSMenu(title: "Video")
let nestedNativeMenu = NSMenu(title: "Crop")
let unrelatedNativeMenu = NSMenu(title: "Unrelated")
let nativeEscape = editorKey(53, in: nativeMenuEditor, time: 12.3)
let nativeReturn = editorKey(36, in: nativeMenuEditor, time: 12.4)
let menuNotifications = NotificationCenter.default
menuNotifications.post(name: NSMenu.didBeginTrackingNotification, object: parentNativeMenu)
menuNotifications.post(name: NSMenu.didBeginTrackingNotification, object: parentNativeMenu)
check(nativeMenuEditor.interactiveMode.handleEditorEvent(nativeEscape) === nativeEscape &&
      nativeMenuEditor.interactiveMode.handleEditorEvent(nativeReturn) === nativeReturn &&
      nativeMenuEditor.interactiveMode.isActive && nativeMenuBox.selectedRect == nativeSelection,
      "native menus receive Escape/Return before Crop Reset, Cancel or Save")
nativeMenuEditor.isCropTransitionInProgress = true
check(nativeMenuEditor.interactiveMode.handleEditorEvent(nativeEscape) === nativeEscape &&
      nativeMenuEditor.isCropTransitionInProgress,
      "native menu Escape cannot cancel an editor transition behind the menu")
nativeMenuEditor.isCropTransitionInProgress = false
menuNotifications.post(name: NSMenu.didBeginTrackingNotification, object: nestedNativeMenu)
menuNotifications.post(name: NSMenu.didEndTrackingNotification, object: parentNativeMenu)
menuNotifications.post(name: NSMenu.didEndTrackingNotification, object: unrelatedNativeMenu)
check(nativeMenuEditor.interactiveMode.handleEditorEvent(nativeEscape) === nativeEscape &&
      nativeMenuBox.selectedRect == nativeSelection,
      "closing a parent or unrelated native menu cannot release another tracking menu")
menuNotifications.post(name: NSMenu.didEndTrackingNotification, object: nestedNativeMenu)
check(nativeMenuEditor.interactiveMode.handleEditorEvent(nativeEscape) == nil &&
      nativeMenuEditor.interactiveMode.isActive &&
      nativeMenuBox.selectedRect == NSRect(origin: .zero, size: nativeMenuBox.videoSize),
      "one end per native menu releases duplicate begin notifications and restores Crop Reset")
_ = nativeMenuEditor.interactiveMode.handleEditorEvent(nativeEscape)
check(!nativeMenuEditor.interactiveMode.isActive, "Crop Cancel resumes after native menu tracking ends")
nativeMenuEditor.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
menuNotifications.post(name: NSMenu.didBeginTrackingNotification, object: parentNativeMenu)
nativeMenuEditor.interactiveMode.exit()
menuNotifications.post(name: NSMenu.didBeginTrackingNotification, object: nestedNativeMenu)
nativeMenuEditor.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
_ = nativeMenuEditor.interactiveMode.handleEditorEvent(nativeEscape)
check(!nativeMenuEditor.interactiveMode.isActive,
      "editor exit clears native tracking and removes observers before a later session")
menuNotifications.post(name: NSMenu.didEndTrackingNotification, object: parentNativeMenu)
menuNotifications.post(name: NSMenu.didEndTrackingNotification, object: nestedNativeMenu)
let keyboardWidth = input("Width in pixels", in: keyboardEditor)
keyboardWidth.selectText(nil)
check(keyboardWidth.currentEditor() != nil, "dimension test uses the native field editor")
let dimensionResponder = keyboardEditor.window!.firstResponder
keyboardEditor.interactiveMode.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: NSPopover()))
check(keyboardEditor.window!.firstResponder === dimensionResponder && keyboardWidth.currentEditor() != nil,
      "a stale popover close cannot steal focus or commit an in-progress dimension edit")
keyboardWidth.currentEditor()!.string = "640"
_ = keyboardEditor.interactiveMode.handleEditorEvent(editorKey(36, in: keyboardEditor, time: 13))
check(keyboardEditor.interactiveMode.isActive && keyboardBox.selectedRect.width == 640 &&
      keyboardWidth.currentEditor() == nil && keyboardEditor.window!.firstResponder === keyboardBox,
      "Return commits the actual field-editor text and leaves crop open with preview focus")
_ = keyboardEditor.interactiveMode.handleEditorEvent(editorKey(36, in: keyboardEditor, time: 13.05, repeated: true))
check(keyboardEditor.interactiveMode.isActive, "holding Return after number confirmation does not save accidentally")
let keyboardHeight = input("Height in pixels", in: keyboardEditor)
keyboardHeight.selectText(nil)
keyboardHeight.currentEditor()!.string = "360"
_ = keyboardEditor.interactiveMode.handleEditorEvent(editorKey(76, in: keyboardEditor, time: 14))
check(keyboardEditor.interactiveMode.isActive && keyboardBox.selectedRect.height == 360,
      "keypad Enter also confirms a dimension without saving")
_ = keyboardEditor.interactiveMode.handleEditorEvent(editorKey(36, in: keyboardEditor, time: 15))
check(!keyboardEditor.interactiveMode.isActive && keyboardEditor.player.savedCrop?.params?["w"] == "640" &&
      keyboardEditor.player.savedCrop?.params?["h"] == "360",
      "Return outside number fields saves the confirmed crop")
let delogoKeyboard = MainWindowController()
delogoKeyboard.interactiveMode.enter(mode: .delogo, selectWholeVideoByDefault: true)
let delogoEscape = editorKey(53, in: delogoKeyboard, time: 20)
check(delogoKeyboard.interactiveMode.handleEditorEvent(delogoEscape) === delogoEscape,
      "new crop shortcuts preserve delogo keyboard behavior")
delogoKeyboard.interactiveMode.exit()

let sizingEditor = MainWindowController(size: NSSize(width: 500, height: 281.25))
let sizingFrame = sizingEditor.window!.frame
sizingEditor.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
check(sizingEditor.window!.frame == sizingFrame, "crop entry retains the current window frame")
sizingEditor.interactiveMode.exit()
check(sizingEditor.cropGeometryRefreshes == 1 && sizingEditor.window!.frame == sizingFrame,
      "uncropped Cancel refreshes geometry when no further reconfiguration is expected")
sizingEditor.player.filterAdditionSucceeds = false
sizingEditor.player.setCrop(fromFilter: MPVFilter.crop(w: 960, h: 100, x: 0, y: 0))
check(sizingEditor.player.info.cropFilter == nil,
      "failed crop application leaves no active crop")
sizingEditor.player.filterAdditionSucceeds = true
sizingEditor.player.setCrop(fromFilter: MPVFilter.crop(w: 960, h: 100, x: 0, y: 0))
check(sizingEditor.player.info.cropFilter != nil,
      "successful crop records the applied filter")
sizingEditor.player.removeCropFilter()
check(sizingEditor.player.info.cropFilter == nil,
      "removing a crop clears the applied filter")

let pendingCropEditor = MainWindowController(size: NSSize(width: 500, height: 300))
pendingCropEditor.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
box(in: pendingCropEditor).setSelectedRect(to: NSRect(x: 0, y: 0, width: 640, height: 300))
button("Save", in: pendingCropEditor).performClick(nil)
check(pendingCropEditor.player.info.cropFilter != nil && pendingCropEditor.cropGeometryRefreshes == 0,
      "Save waits for cropped output instead of resizing first to the uncropped preview")
let rejectedSave = MainWindowController(size: NSSize(width: 500, height: 300))
rejectedSave.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
box(in: rejectedSave).setSelectedRect(to: NSRect(x: 20, y: 30, width: 640, height: 300))
rejectedSave.player.filterAdditionSucceeds = false
button("Save", in: rejectedSave).performClick(nil)
check(rejectedSave.interactiveMode.isActive && rejectedSave.player.info.cropFilter == nil &&
      box(in: rejectedSave).selectedRect == NSRect(x: 20, y: 30, width: 640, height: 300),
      "a rejected crop Save retains the editor and selected pixels for retry")
check(rejectedSave.player.info.unsureCrop == "None", "A failed crop cannot publish a phantom Custom selection")
rejectedSave.player.filterAdditionSucceeds = true
button("Save", in: rejectedSave).performClick(nil)
check(!rejectedSave.interactiveMode.isActive && rejectedSave.player.info.cropFilter != nil,
      "retrying a previously rejected crop saves the preserved selection")
let cancelledCropEditor = MainWindowController(size: NSSize(width: 500, height: 300))
cancelledCropEditor.player.info.cropFilter = MPVFilter.crop(w: 640, h: 300, x: 0, y: 0)
cancelledCropEditor.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
cancelledCropEditor.interactiveMode.exit()
check(cancelledCropEditor.player.info.cropFilter != nil && cancelledCropEditor.cropGeometryRefreshes == 0,
      "Cancel restoring a crop waits for restored output geometry")


let trackCropEditor = MainWindowController(size: NSSize(width: 600, height: 400))
trackCropEditor.player.scopedCropPreview = ScopedCropFixture()
trackCropEditor.player.info.videoTracks = [CropTrackFixture(id: 1), CropTrackFixture(id: 2), CropTrackFixture(id: 3)]
trackCropEditor.player.info.videoTrackOrder = [3, 2, 1]
trackCropEditor.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
check(descendants(trackCropEditor.videoViewContainer).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "#3 Camera" },
      "source Crop heading uses the same reordered position as Configure")
box(in: trackCropEditor).setSelectedRect(to: NSRect(x: 30, y: 40, width: 400, height: 200))
trackCropEditor.player.scopedCropApplySucceeds = false
button("Save", in: trackCropEditor).performClick(nil)
check(trackCropEditor.interactiveMode.isActive && trackCropEditor.player.scopedCropPreview != nil
      && box(in: trackCropEditor).selectedRect == NSRect(x: 30, y: 40, width: 400, height: 200),
      "a rejected source Crop Save retains the editor and selected pixels")
trackCropEditor.player.scopedCropApplySucceeds = true
button("Save", in: trackCropEditor).performClick(nil)
check(trackCropEditor.player.scopedCropSaves == 1 && trackCropEditor.player.savedScopedCrop == TrackVideoCrop(x: 30, y: 300, width: 400, height: 200), "scoped Crop Save routes source pixels to the selected track")
check(trackCropEditor.player.savedCrop == nil && trackCropEditor.player.info.cropFilter == nil, "scoped Crop Save never installs a Master crop")
let trackCropCancel = MainWindowController(size: NSSize(width: 600, height: 400))
var trackPreview = ScopedCropFixture()
trackPreview.originalTrack.crop = TrackVideoCrop(x: 20, y: 10, width: 500, height: 250)
trackCropCancel.player.scopedCropPreview = trackPreview
trackCropCancel.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
trackCropCancel.interactiveMode.exit()
check(trackCropCancel.player.scopedCropCancels == 1 && trackCropCancel.player.savedCrop == nil, "scoped Crop Cancel restores preview through the scoped boundary without leaking into Master")
let staleTrackCrop = MainWindowController(size: NSSize(width: 600, height: 400))
staleTrackCrop.player.scopedCropPreview = trackPreview
staleTrackCrop.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
staleTrackCrop.interactiveMode.exit(discardingCrop: true)
check(!staleTrackCrop.interactiveMode.isActive && staleTrackCrop.player.savedCrop == nil && staleTrackCrop.player.scopedCropCancels == 0, "media replacement discards the editor without restoring stale source filters or selection")

let preparingEditor = MainWindowController(size: NSSize(width: 1056, height: 300))
preparingEditor.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
let preparingBox = box(in: preparingEditor)
preparingBox.setSelectedRect(to: NSRect(x: 20, y: 30, width: 640, height: 300))
preparingBox.setZoom(2)
let previewBeforeSave = preparingBox.previewTransform
let frameBeforeSave = preparingEditor.videoView.frame
let selectionBeforeSave = preparingBox.selectedRect
preparingEditor.exitPreparationObserver = { image, clip, selection, controls, snapshot in
  let container = preparingEditor.videoViewContainer
  check(image == container.convert(preparingBox.imageRect, from: preparingBox),
        "Save captures the zoomed/panned source position without returning through Fit")
  check(clip == container.convert(preparingBox.previewRect, from: preparingBox),
        "Save preserves the visible preview aperture before output preparation")
  check(preparingBox.previewTransform == previewBeforeSave && preparingEditor.videoView.frame == frameBeforeSave,
        "preparation leaves editor image geometry unchanged")
  check(selection == selectionBeforeSave && !controls.isEmpty && snapshot != nil,
        "the selection and native controls are captured together before leaving the editor")
}
button("Save", in: preparingEditor).performClick(nil)
check(!preparingEditor.interactiveMode.isActive, "the prepared editor commits and releases its controls")

let committingEditor = MainWindowController(size: NSSize(width: 900, height: 400))
committingEditor.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
let committingBox = box(in: committingEditor)
committingBox.setSelectedRect(to: NSRect(x: 40, y: 30, width: 500, height: 350))
committingBox.setZoom(2)
var committedTransform = CATransform3DIdentity
var committedAperture: CALayer?
committingEditor.exitPreparationObserver = { image, clip, _, _, _ in
  let overlay = CropTransitionOverlay(frame: committingEditor.videoViewContainer.bounds)
  overlay.useNativeVideo(committingEditor.videoView, in: committingEditor.videoViewContainer,
                         pixelSize: NSSize(width: 960, height: 540))
  overlay.nativeVideo!.present(frame: image, clip: clip)
  overlay.nativeVideo!.present(frame: NSRect(x: image.minX - 20, y: image.minY - 10,
                                            width: image.width * 1.5, height: image.height * 1.5), clip: clip)
  committedTransform = committingEditor.videoView.layer!.transform
  committedAperture = committingEditor.videoView.layer!.mask
  committingEditor.cropExitOverlay = overlay
}
button("Save", in: committingEditor).performClick(nil)
check(!committingEditor.interactiveMode.isActive && committedAperture != nil
      && committingEditor.videoView.layer!.mask === committedAperture
      && CATransform3DEqualToTransform(committingEditor.videoView.layer!.transform, committedTransform),
      "Save teardown cannot reset the live crop transform or aperture while canonical output is still pending")
committingEditor.cropExitOverlay!.releaseNativeVideo()
check(CATransform3DIsIdentity(committingEditor.videoView.layer!.transform) && committingEditor.videoView.layer!.mask == nil,
      "the ready canonical handoff restores player geometry rather than the obsolete zoomed editor")
committingEditor.cropExitOverlay = nil

func pumpEntry(_ predicate: () -> Bool) {
  let deadline = Date().addingTimeInterval(3)
  while !predicate() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.001)) }
  precondition(predicate(), "native entry geometry did not complete")
}
func croppedEntryFixture() -> MainWindowController {
  let editor = MainWindowController(size: NSSize(width: 1056, height: 300))
  editor.entryDuration = 0.035
  _ = editor.player.setCrop(fromFilter: MPVFilter.crop(w: 400, h: 220, x: 20, y: 30))
  editor.player.mpv.size = NSSize(width: 400, height: 220)
  return editor
}
let entering = croppedEntryFixture()
let entryWindow = entering.window!.frame
let nativeLayer = entering.videoView.layer!
entering.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
check(entering.interactiveMode.isEntering && entering.interactiveMode.isActive && entering.player.info.cropFilter == nil,
      "entry prepares full output while keeping the existing native video layer live")
check(entering.videoView.layer === nativeLayer && !entering.videoView.isHidden,
      "native video is neither replaced nor hidden while output is prepared")
let enteringOverlays = entering.videoViewContainer.subviews.compactMap { $0 as? CropTransitionOverlay }
entering.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
check(entering.videoViewContainer.subviews.compactMap { $0 as? CropTransitionOverlay }.count == enteringOverlays.count,
      "duplicate entry cannot install another motion owner")
entering.interactiveMode.finishEntryTransition()
check(entering.interactiveMode.isEntering && !enteringOverlays[0].isFinishing,
      "entry waits for actual full-source output rather than beginning on an early size event")
check(entering.window!.frame == entryWindow, "editor preparation retains the established window frame")
var entryPublishedEditorUI: [Bool] = []
entering.videoView.videoLayer.didPublishHandoff = {
  guard entering.interactiveMode.isActive, !entering.interactiveMode.isEntering else { return }
  entryPublishedEditorUI.append(!box(in: entering).isHiddenOrHasHiddenAncestor &&
    !button("Save", in: entering).isHiddenOrHasHiddenAncestor)
}
entering.player.mpv.size = NSSize(width: 960, height: 540)
entering.interactiveMode.finishEntryTransition(outputIsReady: true)
pumpEntry { !entering.interactiveMode.isEntering }
check(entryPublishedEditorUI == [true],
      "completed entry publishes the real outline and controls in the same native handoff that retires the overlay")
entering.videoView.videoLayer.didPublishHandoff = nil
check(entering.videoView.layer === nativeLayer && entering.interactiveMode.isActive
      && box(in: entering).selectedRect == NSRect(x: 20, y: 290, width: 400, height: 220),
      "entry finishes on the same video layer with the saved crop selection")
check(!box(in: entering).isHidden && entering.player.pausedCount == 0 && entering.player.resumedCount == 0,
      "entry reveals native controls without changing playback state")
button("Cancel", in: entering).performClick(nil)
check(!entering.interactiveMode.isActive && entering.player.info.cropFilter != nil,
      "Cancel after native entry restores the original crop")

let playingEntry = MainWindowController()
playingEntry.entryDuration = 0.05
playingEntry.player.info.state = .playing
let playingLayer = playingEntry.videoView.layer!
playingEntry.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
let liveContent = NSImage(size: NSSize(width: 2, height: 2)).cgImage(forProposedRect: nil, context: nil, hints: nil)
playingLayer.contents = liveContent
pumpEntry { !playingEntry.interactiveMode.isEntering }
check(playingEntry.videoView.layer === playingLayer && playingEntry.player.info.state == .playing
      && playingEntry.player.pausedCount == 0 && playingEntry.player.resumedCount == 0,
      "playing editor entry keeps native layer identity and never pauses playback")
playingEntry.interactiveMode.exit()

let failedNativeEntry = croppedEntryFixture()
failedNativeEntry.player.filterRemovalSucceeds = false
failedNativeEntry.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
check(!failedNativeEntry.interactiveMode.isActive && !failedNativeEntry.interactiveMode.isEntering
      && failedNativeEntry.player.info.cropFilter != nil,
      "failed filter removal leaves no input-blocking transition or partial editor")

let cancelledNativeEntry = croppedEntryFixture()
cancelledNativeEntry.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
cancelledNativeEntry.interactiveMode.cancelEntryTransition()
check(!cancelledNativeEntry.interactiveMode.isEntering && cancelledNativeEntry.interactiveMode.isActive
      && !box(in: cancelledNativeEntry).isHidden && !cancelledNativeEntry.videoView.videoLayer.isAnimatingWindowResize,
      "cancelling preparation restores native editor geometry and controls")
cancelledNativeEntry.interactiveMode.exit(discardingCrop: true)

for failure in ["generation", "stopped"] {
  let editor = croppedEntryFixture()
  editor.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
  if failure == "generation" { editor.player.info.trackSelectionGeneration += 1 }
  else { editor.player.info.state = .stopped }
  editor.interactiveMode.finishEntryTransition(outputIsReady: true)
  check(!editor.interactiveMode.isEntering && !editor.videoView.videoLayer.isAnimatingWindowResize,
        "\(failure) cannot complete stale native entry motion")
  editor.interactiveMode.exit(discardingCrop: true)
}
// Menu/plugin entry must obey the same ownership rules as the shortcut route.
for blockedMode in ["loading", "stopped", "unloaded-window", "music", "pip-preparing", "pip-return",
                    "fullscreen-animation", "crop-transition", "foreign-host", "detached-video"] {
  let blocked = MainWindowController()
  var foreignHost: NSWindow?
  switch blockedMode {
  case "loading": blocked.player.info.state = .loading
  case "stopped": blocked.player.info.state = .stopped
  case "unloaded-window": blocked.loaded = false
  case "music": blocked.player.isInMiniPlayer = true
  case "pip-preparing": blocked.pipStatus = .inPIP
  case "pip-return": blocked.pipStatus = .intermediate
  case "fullscreen-animation": blocked.isFullscreenTransitionInProgress = true
  case "crop-transition": blocked.isCropTransitionInProgress = true
  case "foreign-host":
    let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
                        styleMask: .borderless, backing: .buffered, defer: false)
    host.isReleasedWhenClosed = false
    foreignHost = host
    blocked.videoView.removeFromSuperview()
    host.contentView!.addSubview(blocked.videoView)
  default: blocked.videoView.removeFromSuperview()
  }
  for mode in [InteractiveModeController.Mode.crop, .delogo] {
    check(!blocked.interactiveMode.canEnter, "\(blockedMode) rejects editor ownership")
    blocked.interactiveMode.enter(mode: mode, selectWholeVideoByDefault: true)
    check(!blocked.interactiveMode.isActive && blocked.preparedWindowReferences == 0 &&
          blocked.player.removedCropCount == 0 && blocked.player.pausedCount == 0,
          "\(blockedMode) rejects \(mode) before layout, filtering or pause side effects")
  }
  withExtendedLifetime(foreignHost) {}
}
let releasedOwner = MainWindowController()
check(releasedOwner.interactiveMode.canEnter, "an ordinary loaded window accepts editor ownership")
releasedOwner.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
let entryReferences = releasedOwner.preparedWindowReferences
releasedOwner.interactiveMode.enter(mode: .delogo)
check(releasedOwner.interactiveMode.currentMode == .crop && releasedOwner.preparedWindowReferences == entryReferences,
      "reentrant menu entry cannot replace the active editor or repeat setup")
releasedOwner.interactiveMode.exit()
check(releasedOwner.interactiveMode.canEnter, "editor release permits a later deliberate entry")
print("Completed \(checks) custom crop checks using production controller, selection view, and scrolling selector.")
