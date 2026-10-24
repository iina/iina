// Fixed source lists, ignored dragging and mutually exclusive subtitle roles.
let subPlayer = PlayerCore()
subPlayer.info.subTracks = (1...4).map { MPVTrack($0, .sub) }
subPlayer.info.subTracks[1].readableLanguage = "rus"
subPlayer.info.subTracks[2].readableLanguage = "rus"
subPlayer.mpv.integers["sid"] = 1
subPlayer.mpv.integers["secondary-sid"] = 2
subPlayer.getSelectedTracks()
let subHost = NSWindow(contentRect: NSRect(x: 300, y: 200, width: 800, height: 380),
                       styleMask: [.borderless], backing: .buffered, defer: false)
subHost.isReleasedWhenClosed = false
let primaryList = TrackSelector(.sub, player: subPlayer, observedKeys: [.iinaSIDChanged])
let secondaryList = TrackSelector(.secondSub, player: subPlayer, observedKeys: [.iinaSIDChanged])
for (list, y) in [(primaryList, CGFloat(220)), (secondaryList, CGFloat(40))] {
  list.translatesAutoresizingMaskIntoConstraints = true
  list.frame = NSRect(x: 20, y: y, width: 360, height: 130)
  subHost.contentView!.addSubview(list)
}
subHost.orderFrontRegardless()
subHost.contentView!.layoutSubtreeIfNeeded()
private let primaryTable = primaryList.documentView as! TrackTableView
private let secondaryTable = secondaryList.documentView as! TrackTableView
func subPoint(_ table: NSTableView, _ row: Int) -> NSPoint {
  table.convert(NSPoint(x: 100, y: table.rect(ofRow: row).midY), to: nil)
}
func subEvent(_ type: NSEvent.EventType, _ point: NSPoint, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
  NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: subHost.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
}
func subClick(_ table: NSTableView, row: Int, flags: NSEvent.ModifierFlags = []) {
  let point = subPoint(table, row)
  NSApp.postEvent(subEvent(.leftMouseUp, point, flags), atStart: true)
  subHost.sendEvent(subEvent(.leftMouseDown, point, flags))
}
func subDrag(_ table: NSTableView, row: Int, to destination: NSPoint) {
  let origin = subPoint(table, row)
  NSApp.postEvent(subEvent(.leftMouseUp, destination), atStart: true)
  NSApp.postEvent(subEvent(.leftMouseDragged, destination), atStart: true)
  subHost.sendEvent(subEvent(.leftMouseDown, origin))
}
func subCell(_ table: NSTableView, _ row: Int) -> NSTableCellView {
  table.view(atColumn: 0, row: row, makeIfNecessary: true) as! NSTableCellView
}
func subArrow(_ table: NSTableView, _ key: UInt16, flags: NSEvent.ModifierFlags = []) {
  table.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
    timestamp: 0, windowNumber: subHost.windowNumber, context: nil, characters: "",
    charactersIgnoringModifiers: "", isARepeat: false, keyCode: key)!)
}
check(primaryTable.numberOfRows == 4 && secondaryTable.numberOfRows == 4,
      "both subtitle roles retain the complete list of sources")
check(!primaryTable.allowsMultipleSelection && !secondaryTable.allowsMultipleSelection,
      "both subtitle tables explicitly disallow native multiselection")
check(subCell(primaryTable, 1).alphaValue == 0.4 && !subCell(primaryTable, 1).isAccessibilityEnabled() &&
      subCell(secondaryTable, 0).alphaValue == 0.4 && !subCell(secondaryTable, 0).isAccessibilityEnabled(),
      "source occupied by the other role is dimmed and accessibility-disabled in both directions")
check(subCell(primaryTable, 0).alphaValue == 1 && subCell(secondaryTable, 1).alphaValue == 1,
      "each role's selected source keeps its normal appearance")
check(primaryList.tableView(primaryTable, shouldSelectRow: 1) == false &&
      secondaryList.tableView(secondaryTable, shouldSelectRow: 0) == false,
      "native row selection rejects sources occupied by the other role")
for appearance in [NSAppearance.Name.aqua, .darkAqua] {
  subHost.contentView!.appearance = NSAppearance(named: appearance)
  subHost.contentView!.wantsLayer = true
  subHost.contentView!.layer?.backgroundColor = (appearance == .aqua ? NSColor.white : NSColor.windowBackgroundColor).cgColor
  if let bitmap = subHost.contentView!.bitmapImageRepForCachingDisplay(in: subHost.contentView!.bounds) {
    subHost.contentView!.cacheDisplay(in: subHost.contentView!.bounds, to: bitmap)
    if let png = bitmap.representation(using: .png, properties: [:]), CommandLine.arguments.count > 1 {
      try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent()
        .appendingPathComponent("subtitle-availability-\(appearance.rawValue).png"))
    }
  }
}
let beforeIgnoredSubtitleInput = subPlayer.mpv.writes
for flags: NSEvent.ModifierFlags in [[], .command, .shift, [.command, .shift]] {
  subClick(primaryTable, row: 1, flags: flags)
  subClick(secondaryTable, row: 0, flags: flags)
}
primaryTable.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
secondaryTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
check(subPlayer.info.sid == 1 && subPlayer.info.secondSid == 2 && subPlayer.mpv.writes == beforeIgnoredSubtitleInput,
      "ordinary, modifier and native selection cannot steal an occupied subtitle source")
subPlayer.setTrack(2, forType: .sub)
subPlayer.setTrack(1, forType: .secondSub)
check(subPlayer.info.sid == 1 && subPlayer.info.secondSid == 2 && subPlayer.mpv.writes == beforeIgnoredSubtitleInput,
      "core assignment rejects duplicates without clearing or rewriting either role")
NSCursor.crosshair.push()
for (source, row, destination) in [
  (primaryTable, 0, subPoint(primaryTable, 3)),
  (secondaryTable, 1, subPoint(secondaryTable, 3)),
  (primaryTable, 0, subPoint(secondaryTable, 1)),
  (secondaryTable, 1, subPoint(primaryTable, 0)),
  (primaryTable, 0, secondaryTable.headerView!.convert(NSPoint(x: 100, y: 13), to: nil)),
  (primaryTable, 0, NSPoint(x: 700, y: 180))
] {
  subDrag(source, row: row, to: destination)
}
check(subPlayer.mpv.writes == beforeIgnoredSubtitleInput && subPlayer.info.sid == 1 && subPlayer.info.secondSid == 2,
      "within-list, cross-list, header and outside subtitle drags change neither role")
check((0..<4).compactMap { primaryTable.trackID?($0) } == [1,2,3,4] &&
      (0..<4).compactMap { secondaryTable.trackID?($0) } == [1,2,3,4] && NSCursor.current == NSCursor.crosshair,
      "all subtitle drags preserve source order and the normal cursor")
NSCursor.pop()
for flags: NSEvent.ModifierFlags in [.command, .shift, [.command, .shift], []] {
  subClick(primaryTable, row: 2, flags: flags)
  check(subPlayer.info.activeTrackIDs(.sub) == [3] && subPlayer.info.activeTrackIDs(.secondSub) == [2],
        "subtitle modifiers always select one source while another same-language source can play in the other role")
  subClick(primaryTable, row: 0)
}
primaryTable.keyboardTrackID = 1
subArrow(primaryTable, 125, flags: .shift)
check(subPlayer.info.sid == 3 && subPlayer.info.secondSid == 2,
      "subtitle keyboard navigation skips the disabled source and Shift remains single-select")
subArrow(primaryTable, 126)
check(subPlayer.info.sid == 1 && subPlayer.info.secondSid == 2,
      "reverse keyboard navigation also skips the occupied source")
secondaryTable.keyboardTrackID = nil
subPlayer.setTrack(0, forType: .secondSub)
check(subCell(primaryTable, 1).alphaValue == 1 && subCell(primaryTable, 1).isAccessibilityEnabled(),
      "No subtitles immediately re-enables the freed source in the opposite list")
subClick(primaryTable, row: 1)
check(subPlayer.info.sid == 2 && subPlayer.info.secondSid == 0 && subCell(secondaryTable, 1).alphaValue == 0.4,
      "freed source can be selected and becomes unavailable in the opposite role")
subPlayer.setTrack(0, forType: .sub)
check(subCell(secondaryTable, 1).alphaValue == 1 && subCell(secondaryTable, 1).isAccessibilityEnabled(),
      "reused subtitle cells restore both opacity and accessibility after release")
subClick(secondaryTable, row: 1, flags: .command)
check(subPlayer.info.sid == 0 && subPlayer.info.secondSid == 2 && subCell(primaryTable, 1).alphaValue == 0.4,
      "secondary selection immediately updates availability in Primary")
subPlayer.setTrack(4, forType: .secondSub)
check(subCell(primaryTable, 1).alphaValue == 1 && subCell(primaryTable, 3).alphaValue == 0.4,
      "switching roles updates both old and new occupied source rows")
let subtitleTarget = SubtitleRoleSelector()
var changedRole: Bool?
subtitleTarget.onChange = { changedRole = $0 }
subtitleTarget.selectedSegment = 1
_ = subtitleTarget.sendAction(subtitleTarget.action!, to: subtitleTarget.target)
check(changedRole == false && subtitleTarget.selectedSegment == 1, "role selector reports Secondary")
subtitleTarget.selectedSegment = 0
_ = subtitleTarget.sendAction(subtitleTarget.action!, to: subtitleTarget.target)
check(changedRole == true && subtitleTarget.selectedSegment == 0, "role selector switches back to Primary")
subHost.close()
print("Subtitle availability checks complete: \(checks) total checks.")
