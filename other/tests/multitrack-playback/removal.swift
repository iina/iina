// Removing an attachment must not turn explicit playback into None or retain
// graph inputs that mpv cannot detach. Exercise the production removal method.
for type: MPVTrack.TrackType in [.audio, .video] {
  let p = PlayerCore()
  let tracks = p.info.trackList(type)
  let id = tracks[1].id
  tracks[1].isExternal = true
  let order = tracks.reversed().map(\.id)
  func select(_ ids: Set<Int>) {
    if type == .audio { check(p.setAudioTracks(ids), "prepare audio removal selection") }
    else { check(p.setVideoTracks(ids, order: order), "prepare video removal selection") }
  }
  select([id])
  p.scopedTrackSettings.setTarget(id, for: type == .audio ? .audioDelay : .videoColor)
  check(p.removeExternalTrack(id, type: type, order: order), "external solo track can be removed")
  check(p.info.activeTrackIDs(type) == [1], "removed solo selects its next visible neighbour")
  check(!p.info.trackList(type).contains { $0.id == id }, "removed attachment disappears from list")
  check(p.scopedTrackSettings.target(type == .audio ? .audioDelay : .videoColor) == 0, "removed editing target returns to Master/Output")
  check(!p.removeExternalTrack(1, type: type, order: order), "embedded tracks cannot be removed")

  let mix = PlayerCore()
  mix.info.trackList(type)[1].isExternal = true
  if type == .audio { mix.mpv.supportsPersistentMixer = true; mix.prepareMixer(); mix.setAudioTracks([1,2,3]) }
  else { mix.setVideoTracks([1,2,3], order: [3,2,1]) }
  check(mix.removeExternalTrack(2, type: type, order: [3,2,1,4]), "attachment in a mix/layers can be removed")
  check(mix.info.activeTrackIDs(type) == [1,3], "removal preserves every other active track")
  let graph = mix.mpv.strings["lavfi-complex"] ?? ""
  check(!graph.contains(type == .audio ? "[aid2]" : "[vid2]"), "removed track is disconnected from owned graph")

  let off = PlayerCore()
  off.info.trackList(type)[1].isExternal = true
  if type == .audio { off.setAudioTracks([]) } else { off.setVideoTracks([]) }
  check(off.removeExternalTrack(2, type: type, order: [1,2,3,4]) && off.info.activeTrackIDs(type).isEmpty,
        "removing inactive attachment preserves explicitly selected No state")

  for noOp in [false, true] {
    let failed = PlayerCore()
    failed.info.trackList(type)[1].isExternal = true
    if type == .audio { failed.mpv.supportsPersistentMixer = true; failed.prepareMixer(); failed.setAudioTracks([1,2,3]) }
    else { failed.setVideoTracks([1,2,3]) }
    failed.mpv.removalFails = !noOp; failed.mpv.removalNoOp = noOp
    check(!failed.removeExternalTrack(2, type: type, order: [1,2,3,4]), "failed or silently rejected mpv removal reports failure")
    check(failed.info.activeTrackIDs(type) == [1,2,3], "rejected removal restores original active membership")
  }
}
let onlyAttachment = PlayerCore()
onlyAttachment.info.audioTracks = [MPVTrack(5)]
onlyAttachment.info.audioTracks[0].isExternal = true
onlyAttachment.setAudioTracks([5])
check(onlyAttachment.removeExternalTrack(5, type: .audio, order: [5]) && onlyAttachment.info.activeTrackIDs(.audio).isEmpty,
      "removing the last available attachment permits No audio")
let inactiveInput = PlayerCore()
inactiveInput.info.audioTracks[1].isExternal = true
inactiveInput.mpv.supportsPersistentMixer = true
inactiveInput.prepareMixer()
check(inactiveInput.removeExternalTrack(2, type: .audio, order: [1,2,3,4]) &&
      inactiveInput.info.activeTrackIDs(.audio) == [1] &&
      !(inactiveInput.mpv.strings["lavfi-complex"] ?? "").contains("[aid2]"),
      "inactive persistent mixer input is disconnected without changing playback")
print("External track removal checks complete")

for type: MPVTrack.TrackType in [.audio, .video] {
  let rejected = PlayerCore()
  rejected.info.trackList(type)[1].isExternal = true
  if type == .audio { rejected.setAudioTracks([1,2,3]) } else { rejected.setVideoTracks([1,2,3]) }
  rejected.mpv.failures = 1
  check(!rejected.removeExternalTrack(2, type: type, order: [1,2,3,4]) &&
        rejected.info.trackList(type).contains { $0.id == 2 } && rejected.info.activeTrackIDs(type) == [1,2,3],
        "graph disconnect failure retains attachment and previous playback")
}
let loneVideo = PlayerCore()
loneVideo.info.videoTracks = [MPVTrack(8, .video)]
loneVideo.info.videoTracks[0].isExternal = true
loneVideo.setVideoTracks([8])
check(loneVideo.removeExternalTrack(8, type: .video, order: [8]) && loneVideo.info.activeTrackIDs(.video).isEmpty,
      "last external video removal permits No video and preserves audio")
check(loneVideo.info.activeTrackIDs(.audio) == [1], "video removal retains independent audio playback")

let removalPlayer = PlayerCore()
removalPlayer.info.audioTracks[1].isExternal = true
removalPlayer.setAudioTracks([1,2,3])
let removalWindow = NSWindow(contentRect: NSRect(x:0,y:0,width:420,height:234), styleMask:[.borderless], backing:.buffered, defer:false)
removalWindow.isReleasedWhenClosed = false
let removalList = TrackSelector(.audio, player: removalPlayer, observedKeys:[.iinaAIDChanged])
removalWindow.contentView!.addSubview(removalList)
removalList.translatesAutoresizingMaskIntoConstraints = true
removalList.frame = NSRect(x:20,y:60,width:380,height:130)
removalWindow.contentView!.layoutSubtreeIfNeeded()
let removalTable = removalList.documentView as! NSTableView
let attachmentCell = removalTable.view(atColumn:0,row:1,makeIfNecessary:true) as! NSTableCellView
let closeTrackButton = attachmentCell.subviews.compactMap { $0 as? NSButton }.first!
let hover = NSEvent.mouseEvent(with:.mouseMoved, location:.zero, modifierFlags:[], timestamp:0,
 windowNumber:removalWindow.windowNumber, context:nil, eventNumber:0, clickCount:0, pressure:0)!
let unhoveredTitleFrame = attachmentCell.textField!.frame
let unhoveredContentFrame = attachmentCell.textField!.superview!.frame
attachmentCell.mouseEntered(with:hover)
check(attachmentCell.textField!.frame == unhoveredTitleFrame && attachmentCell.textField!.superview!.frame == unhoveredContentFrame,
      "hover overlays removal without changing text width, position or truncation")
let textMask = attachmentCell.textField!.superview!.layer!.mask as! CAGradientLayer
check((textMask.colors as! [CGColor]).last!.alpha == 0, "hover masks text and language beneath the trailing remove control")
check(!closeTrackButton.isHidden, "external row reveals its remove control on hover")
attachmentCell.mouseExited(with:hover)
check(closeTrackButton.isHidden, "external row hides remove control when hover ends")
check((textMask.colors as! [CGColor]).allSatisfy { $0.alpha == 1 }, "leaving hover restores full text opacity")
let embeddedTextFrame = (removalTable.view(atColumn:0,row:0,makeIfNecessary:true) as! NSTableCellView).textField!.superview!.frame
check(embeddedTextFrame.width == unhoveredContentFrame.width, "external and embedded rows have the same full title width")
attachmentCell.mouseEntered(with:hover)
let hit = attachmentCell.hitTest(attachmentCell.convert(NSPoint(x:closeTrackButton.bounds.midX,y:closeTrackButton.bounds.midY), from:closeTrackButton))
check(hit === closeTrackButton || hit?.isDescendant(of:closeTrackButton) == true,
      "remove control receives hit testing independently of table gestures")
let embeddedCell = removalTable.view(atColumn:0,row:0,makeIfNecessary:true) as! NSTableCellView
embeddedCell.mouseEntered(with:hover)
check(embeddedCell.subviews.compactMap { $0 as? NSButton }.allSatisfy(\.isHidden), "embedded row never reveals remove control")
closeTrackButton.performClick(nil)
check(removalTable.numberOfRows == 3 && removalPlayer.info.activeTrackIDs(.audio) == [1,3],
      "native remove button removes its stable track identity without soloing or toggling neighbours")
print("Removal and existing integration complete: \(checks) total checks.")

// Hidden language badges must release their spacing, including on reused cells.
class ReusedTrackCellTable: NSTableView {
  var reusedCell: NSView?
  override func makeView(withIdentifier identifier: NSUserInterfaceItemIdentifier, owner: Any?) -> NSView? { reusedCell }
}
for type: MPVTrack.TrackType in [.audio, .video, .sub, .secondSub] {
  let p = PlayerCore()
  let list = TrackSelector(type, player: p, observedKeys: [])
  let table = ReusedTrackCellTable()
  let column = NSTableColumn(identifier: .trackName)
  let cell = list.tableView(table, viewFor: column, row: 0) as! NSTableCellView
  table.reusedCell = cell
  removalWindow.contentView!.addSubview(cell)
  cell.frame = NSRect(x: 0, y: 0, width: 360, height: 26)
  let title = cell.textField!.superview!
  let badge = title.subviews.first { $0 is ColoredView }!
  for language: String? in [nil, "English", nil, ""] {
    p.info.trackList(type)[0].readableLanguage = language
    check(list.tableView(table, viewFor: column, row: 0) === cell, "language changes configure the same reused cell")
    cell.textField!.stringValue = String(repeating: "Long track title ", count: 10)
    cell.layoutSubtreeIfNeeded()
    let textRight = cell.textField!.alignmentRect(forFrame: cell.textField!.frame).maxX
    if let language, !language.isEmpty {
      check(!badge.isHidden && abs(badge.frame.minX - textRight - 4) < 0.01,
            "visible language badge keeps its 4 pt title gap")
    } else {
      check(badge.isHidden && abs(title.bounds.maxX - textRight) < 0.01,
            "title without language reaches the shared trailing inset without phantom badge space")
    }
  }
  cell.removeFromSuperview()
}
