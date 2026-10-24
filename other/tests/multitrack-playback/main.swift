// Pure ID/range semantics follow source order and surviving identities.
var state = TrackSelectionState()
state.synchronize([1, 2, 3, 4])
check(state.select(2, action: .solo, active: [1]) == [2] && state.anchor == nil, "plain click selects one ID without a range anchor")
check(state.select(4, action: .toggle, active: [2]) == [2,4] && state.anchor == nil, "toggle adds without showing a range anchor")
check(state.select(2, action: .toggle, active: [2,4]) == [4], "toggle removes an active track")
check(state.select(4, action: .toggle, active: [4]) == [4], "toggle cannot disable the last sounding track")
var nonemptySelectionIsPreserved = true
for mask in 1..<16 {
  let active = Set((1...4).filter { mask & (1 << ($0 - 1)) != 0 })
  for id in 1...4 {
    for action: TrackSelectionState.Action in [.solo, .toggle, .range] {
      var selection = TrackSelectionState()
      selection.synchronize([1,2,3,4])
      let first = selection.select(id,action:action,active:active)
      let second = selection.select(id,action:action,active:first)
      nonemptySelectionIsPreserved = nonemptySelectionIsPreserved && !first.isEmpty && !second.isEmpty
    }
  }
}
check(nonemptySelectionIsPreserved, "all ordinary, toggle and Shift actions preserve at least one active track unless None is explicitly selected")
check(state.select(2, action: .range, active: [1]) == [1] && state.anchor == 2, "first Shift-click only anchors its own ID without changing playback")
check(state.select(4, action: .range, active: [1]) == [1,2,3,4], "range adds all displayed IDs and retains other active tracks")
state.synchronize([1,2,3,4])
check(state.order == [1,2,3,4] && state.anchor == 2, "source refresh preserves order and the Shift anchor identity")
check(state.select(4, action: .range, active: []) == [2,3,4], "range follows the source order")
check(state.select(3, action: .solo, active: [1,2,3,4]) == [3] && state.anchor == nil, "plain click on a sounding track solos it and clears the Shift anchor")
check(state.select(1, action: .range, active: [3]) == [3] && state.anchor == 1, "first Shift-click after solo starts a new range")
check(state.select(4, action: .toggle, active: [3]) == [3,4] && state.anchor == nil, "membership toggle ends the previous Shift range")
check(state.select(0, action: .toggle, active: [1,2]).isEmpty && state.anchor == nil, "None clears playback and anchor")
state.synchronize([1,3,5]); check(state.order == [1,3,5], "removed IDs are pruned and new tracks append")
state.synchronize([5,1,3]); check(state.order == [5,1,3], "source order changes replace cached display order")
check(AudioTrackMixGraph.make([]) == nil && AudioTrackMixGraph.make([1]) == nil, "solo/None keep native audio path")
check(AudioTrackMixGraph.make([0,1]) == nil, "None can never be a filter input")
check(AudioTrackMixGraph.make([4,1])!.hasPrefix("[aid1][aid4]amix=inputs=2"), "graph is deterministic and uses real IDs")

// Actual PlayerCore graph ownership, failure recovery, solo and volume state.
let cyclingPlayer = PlayerCore()
cyclingPlayer.setAudioTracks([4]); cyclingPlayer.cycleAudioTrack()
check(cyclingPlayer.info.activeTrackIDs(.audio) == [1], "cycling past the last audio track wraps to the first instead of None")
cyclingPlayer.setAudioTracks([2,4]); cyclingPlayer.cycleAudioTrack()
check(cyclingPlayer.info.activeTrackIDs(.audio) == [1] && cyclingPlayer.mpv.getString("lavfi-complex") == "", "cycling from a mix selects a real solo track and removes the owned graph")
let player = PlayerCore()
check(player.setAudioTracks([1,2,3,4]), "production setter installs a four-track graph")
check(player.info.activeTrackIDs(.audio) == [1,2,3,4], "active state retains all mixed tracks even with aid=no")
check(!player.mainWindow.volumeSlider.isHidden, "mixed audio keeps volume controls available")
let savedGraph = player.mpv.getString("lavfi-complex")!
player.mpv.failures = 1
check(!player.setAudioTracks([2,4]) && player.mpv.getString("lavfi-complex") == savedGraph && player.info.mixedAudioTrackIDs == [1,2,3,4], "failed graph replacement restores previous mix")
check(player.setAudioTracks([3]) && player.info.activeTrackIDs(.audio) == [3] && player.mpv.getString("lavfi-complex") == "", "plain selection removes owned graph and restores native solo")
check(player.setAudioTracks([]) && player.info.activeTrackIDs(.audio).isEmpty && player.mainWindow.volumeSlider.isHidden, "None clears audio and hides volume controls")
let beforeInvalid = player.mpv.writes
check(!player.setAudioTracks([99]) && player.mpv.writes == beforeInvalid, "missing input cannot mutate mpv")
player.mpv.strings["lavfi-complex"] = "[vid1]null[vo]"
check(!player.setAudioTracks([1,2]) && player.mpv.strings["lavfi-complex"] == "[vid1]null[vo]", "custom graph is preserved on mix conflict")
player.setTrack(2, forType: .audio)
check(player.info.aid == 2 && player.mpv.strings["lavfi-complex"] == "[vid1]null[vo]", "native solo remains available with custom video graph")
player.nextFile()
check(player.mpv.strings["lavfi-complex"] == "[vid1]null[vo]", "new-file reset preserves a non-owned graph")
player.mpv.strings["lavfi-complex"] = ""
player.setAudioTracks([1,4]); player.nextFile()
check(player.info.mixedAudioTrackIDs.isEmpty && player.mpv.strings["lavfi-complex"] == "", "new media clears the owned mix")
for ids in [[1,2,4], [2,4,1], [4,1,2], [3,2,1]] {
  player.setAudioTracks([])
  for count in 1...3 { player.setAudioTracks(Set(ids.prefix(count))) }
  player.setAudioTracks([ids[0]])
  check(player.info.activeTrackIDs(.audio) == [ids[0]], "returning to the first-added track after successive mix additions selects that track, not None")
}

// If both replacement and rollback fail, retain real native tracks instead of None.
let failedRollback = PlayerCore()
failedRollback.setAudioTracks([2,4])
failedRollback.setVideoTracks([1,3], order: [3,1,2])
failedRollback.mpv.failures = 2
check(!failedRollback.setVideoTracks([1,2]), "a failed replacement and rollback report failure")
check(failedRollback.info.activeTrackIDs(.audio) == [2] &&
      failedRollback.info.activeTrackIDs(.video) == [3],
      "a rejected rollback falls back to native tracks from both previous selections")
check(failedRollback.info.mixedAudioTrackIDs.isEmpty && failedRollback.info.layeredVideoTrackIDs.isEmpty,
      "rollback failure clears stale multi-track marks")

// Both outputs share one owned graph and return to native selection independently.
let av = PlayerCore()
check(av.setVideoTracks([1,2,3],order:[1,2,3]) && av.info.activeTrackIDs(.video) == [1,2,3], "video setter enables real layered inputs")
check(av.mainWindow.videoView.active == 1 && av.mainWindow.videoView.idle == 1, "paused video reconfiguration wakes the render display link and schedules idle afterward")
check(av.setAudioTracks([1,4]) && av.mpv.getString("lavfi-complex")!.contains("[ao]") && av.mpv.getString("lavfi-complex")!.contains("[vo]"), "audio mixing preserves the video output in one graph")
check(av.setVideoTracks([1,2,3],order:[2,1,3]) && av.info.layeredVideoTrackIDs == [2,1,3] && av.info.mixedAudioTrackIDs == [1,4], "video order changes preserve sounding audio IDs")
let combined = av.mpv.getString("lavfi-complex")!
let finishedBeforeFailure = av.mainWindow.finishedTransitions
av.mpv.failures = 1
check(!av.setVideoTracks([1,3]) && av.mpv.getString("lavfi-complex") == combined && av.info.layeredVideoTrackIDs == [2,1,3], "failed video change restores both outputs and previous layer order")
check(av.mainWindow.finishedTransitions == finishedBeforeFailure + 1, "failed layer reconfiguration releases its temporary aspect fill")
check(av.setVideoTracks([1]) && av.info.activeTrackIDs(.video) == [1] && av.info.mixedAudioTrackIDs == [1,4] && !av.mpv.getString("lavfi-complex")!.contains("[vo]"), "video solo restores native output while audio continues mixing")
av.setVideoTracks([1,2]); av.setAudioTracks([4])
check(av.info.activeTrackIDs(.audio) == [4] && av.info.activeTrackIDs(.video) == [1,2], "audio solo leaves video layers enabled")
av.setVideoTracks([])
check(av.info.activeTrackIDs(.video).isEmpty && av.info.activeTrackIDs(.audio) == [4], "explicit video None preserves audio playback")
av.setVideoTracks([3]); av.cycleVideoTrack()
check(av.info.activeTrackIDs(.video) == [1], "video cycling wraps to the first source track without None")
av.setVideoTracks([1,2]); av.cycleVideoTrack()
check(av.info.activeTrackIDs(.video) == [1], "video cycling leaves a stack for the first source solo track")
av.setVideoTracks([1,2]); av.nextFile()
check(av.info.layeredVideoTrackIDs.isEmpty && av.info.videoTrackOrder.isEmpty && av.mpv.getString("lavfi-complex") == "", "new media clears both owned outputs and video order")
// Persistent mixing keeps its topology through solo, explicit None and gestures.
let outdatedMixer = PlayerCore()
outdatedMixer.mpv.supportsPersistentMixer = true
outdatedMixer.mpv.supportsAudioRefresh = false
outdatedMixer.prepareMixer()
check(outdatedMixer.mpv.writes == 0, "an engine without audio-buffer refresh retains the legacy path")
let persistent = PlayerCore()
persistent.mpv.supportsPersistentMixer = true
persistent.prepareMixer()
check(persistent.mpv.graphWrites == 1 && persistent.info.activeTrackIDs(.audio) == [1] && persistent.info.aid == 1,
      "preparing all audio inputs preserves the native initial solo and logical aid")
let initialPersistentGraph = persistent.mpv.getString("lavfi-complex")!
check(initialPersistentGraph.contains("[aid1][aid2][aid3][aid4]") && initialPersistentGraph.contains("weights='1 0 0 0'"),
      "persistent mixer connects inactive inputs at zero gain")
for ids: Set<Int> in [[1,2], [1,2,3], [1,2,3,4], [1], [2,4], [], [3], [4]] {
  check(persistent.setAudioTracks(ids) && persistent.info.activeTrackIDs(.audio) == ids,
        "gain command retains the exact logical audio selection \(ids.sorted())")
}
check(persistent.mpv.graphWrites == 1 && persistent.mpv.getString("lavfi-complex") == initialPersistentGraph,
      "audio additions, removals, solo and None never replace the running mixer")
check(persistent.info.aid == 4 && !persistent.mainWindow.volumeSlider.isHidden,
      "persistent solo exposes its logical aid and keeps native volume controls")
persistent.cycleAudioTrack()
check(persistent.info.activeTrackIDs(.audio) == [1], "persistent solo cycles past the final real track without None")
persistent.cycleAudioTrack()
check(persistent.info.activeTrackIDs(.audio) == [2], "persistent solo cycling advances instead of returning to the first input")
persistent.setAudioTracks([])
check(persistent.info.activeTrackIDs(.audio).isEmpty && persistent.mainWindow.volumeSlider.isHidden,
      "explicit None silences persistent inputs and hides volume controls")
persistent.setAudioTracks([1,3])
persistent.mpv.commandFailures = 1
check(!persistent.setAudioTracks([2,4]) && persistent.info.activeTrackIDs(.audio) == [1,3] && persistent.mpv.graphWrites == 1,
      "a rejected gain command preserves the previous selection without rebuilding")
persistent.setVideoTracks([1,2])
check(persistent.mpv.getString("lavfi-complex")!.contains("weights='1 0 1 0'") && persistent.info.activeTrackIDs(.video) == [1,2],
      "adding video layers rebuilds with the current audio weights")
persistent.setAudioTracks([2,4])
persistent.mpv.failures = 1
check(!persistent.setVideoTracks([1,3]) && persistent.info.activeTrackIDs(.audio) == [2,4] &&
      persistent.mpv.getString("lavfi-complex")!.contains("weights='0 1 0 1'"),
      "video rollback restores audible weights instead of stale initialization weights")
let graphWritesBeforeNone = persistent.mpv.graphWrites
persistent.setAudioTracks([])
check(persistent.mpv.graphWrites == graphWritesBeforeNone && persistent.info.activeTrackIDs(.video) == [1,2],
      "audio None preserves video layers and their running graph")
persistent.setAudioTracks([4])
persistent.info.audioTracks.append(MPVTrack(5))
persistent.setAudioTracks([4,5])
let graphWritesAfterAddition = persistent.mpv.graphWrites
check(persistent.mpv.getString("lavfi-complex")!.contains("[aid5]") && persistent.info.activeTrackIDs(.audio) == [4,5],
      "selecting a newly attached audio stream extends the connected input topology")
persistent.setAudioTracks([5])
check(persistent.mpv.graphWrites == graphWritesAfterAddition && persistent.info.aid == 5,
      "later selections on an attached stream use gains again")
persistent.mpv.strings["lavfi-complex"] = "[vid1]null[vo]"
persistent.mpv.integers["aid"] = 2
persistent.aidChanged()
check(persistent.info.activeTrackIDs(.audio) == [2] && persistent.info.mixedAudioTrackIDs.isEmpty,
      "foreign graph replacement clears persistent ownership and refreshes the real native aid")
for (url, spdif, foreign) in [(URL(string:"https://example.test/video.mkv")!, "", ""),
                             (URL(fileURLWithPath:"/fixture.mkv"), "ac3,dts", ""),
                             (URL(fileURLWithPath:"/fixture.mkv"), "", "[vid1]null[vo]")] {
  let excluded = PlayerCore(); excluded.mpv.supportsPersistentMixer = true
  excluded.info.currentURL = url; excluded.mpv.strings["audio-spdif"] = spdif
  excluded.mpv.strings["lavfi-complex"] = foreign; excluded.prepareMixer()
  check(excluded.mpv.writes == 0, "preparation preserves network playback, passthrough and custom graphs")
}
let cleanup = PlayerCore(); cleanup.mpv.supportsPersistentMixer = true; cleanup.prepareMixer()
cleanup.setAudioTracks([2,4]); cleanup.nextFile(); cleanup.setAudioTracks([3])
check(cleanup.info.activeTrackIDs(.audio) == [3] && cleanup.mpv.getString("lavfi-complex") == "",
      "new-file cleanup drops old persistent inputs and restores ordinary selection")
let surround = PlayerCore(); surround.mpv.supportsPersistentMixer = true
surround.info.audioTracks[1].demuxChannelCount = 6
surround.info.audioTracks[1].demuxChannels = "5.1"
surround.prepareMixer()
check(surround.mpv.writes == 0, "different channel counts retain native playback instead of downmixing to an inactive input's layout")
for track in surround.info.audioTracks { track.demuxChannelCount = 6; track.demuxChannels = "5.1" }
surround.prepareMixer()
check(surround.mpv.graphWrites == 1, "matching known surround layouts can share a persistent mixer")
let addedSurround = PlayerCore(); addedSurround.mpv.supportsPersistentMixer = true; addedSurround.prepareMixer()
let sixChannels = MPVTrack(5); sixChannels.demuxChannelCount = 6; sixChannels.demuxChannels = "5.1"
addedSurround.info.audioTracks.append(sixChannels); addedSurround.setAudioTracks([5])
check(addedSurround.mpv.getString("lavfi-complex") == "" && addedSurround.info.activeTrackIDs(.audio) == [5],
      "selecting an attached incompatible layout restores its native channels instead of packing it into the old pool")

let graphs = [[1,2,3],[2,1,3],[3,2,1]].map { ids -> [String:Any] in
  ["order":ids, "h264":VideoTrackLayerGraph.make([1,2],width:960,height:720)!, "h264Reverse":VideoTrackLayerGraph.make([2,1],width:1280,height:720)!, "video":VideoTrackLayerGraph.make(ids,width:320,height:180)!,
   "combined":AudioTrackMixGraph.make([1,2])! + ";" + VideoTrackLayerGraph.make(ids,width:320,height:180)!]
}
if CommandLine.arguments.count > 1 {
  try! JSONSerialization.data(withJSONObject:graphs,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
  let connected: Set<Int> = [1,2,3,4]
  let persistentGraphs: [String:Any] = ["graph":AudioTrackMixGraph.make([1],inputs:connected)!,
                                       "target":AudioTrackMixGraph.target,
                                       "weights":["solo":"1 0 0 0", "subset":AudioTrackMixGraph.weights([2,4],inputs:connected)]]
  let url = URL(fileURLWithPath:CommandLine.arguments[1]).deletingLastPathComponent().appendingPathComponent("persistent-graphs.json")
  try! JSONSerialization.data(withJSONObject:persistentGraphs,options:[.prettyPrinted,.sortedKeys]).write(to:url)
}

// Full production TrackSelector and table event handling against actual AppKit.
player.mpv.supportsPersistentMixer = true
player.prepareMixer()
class FocusScrollingWindow: NSWindow {
  var onFirstResponder: (() -> Void)?
  override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
    let callback = onFirstResponder
    onFirstResponder = nil
    let result = super.makeFirstResponder(responder)
    callback?()
    return result
  }
}
let window = FocusScrollingWindow(contentRect: NSRect(x:100,y:100,width:420,height:234), styleMask:[.borderless], backing:.buffered, defer:false)
window.isReleasedWhenClosed = false
player.mainWindow.window = window
let selector = TrackSelector(.audio, player: player, observedKeys: [.iinaAIDChanged])
window.contentView!.addSubview(selector)
selector.frame = NSRect(x:20,y:60,width:380,height:130)
selector.translatesAutoresizingMaskIntoConstraints = true
window.orderFrontRegardless(); window.contentView!.layoutSubtreeIfNeeded()
private let table = selector.documentView as! TrackTableView
private let offButton = table.headerView!.subviews.compactMap { $0 as? NSButton }.first!
func pump() { RunLoop.main.run(until:Date().addingTimeInterval(0.03)); window.contentView!.layoutSubtreeIfNeeded() }
pump()
func point(_ row: Int) -> NSPoint { table.convert(NSPoint(x:50,y:table.rect(ofRow:row-1).midY),to:nil) }
func event(_ type: NSEvent.EventType, _ p: NSPoint, flags: NSEvent.ModifierFlags = []) -> NSEvent {
  NSEvent.mouseEvent(with:type, location:p, modifierFlags:flags,timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:checks+1,clickCount:1,pressure:1)!
}
func click(_ row: Int, flags: NSEvent.ModifierFlags = [], right: Bool = false) {
  if row == 0 { offButton.performClick(nil); pump(); return }
  table.scrollRowToVisible(row-1); pump()
  let p = point(row)
  if right {
    window.sendEvent(event(.rightMouseDown,p)); window.sendEvent(event(.rightMouseUp,p))
  } else {
    NSApp.postEvent(event(.leftMouseUp,p,flags:flags),atStart:true)
    window.sendEvent(event(.leftMouseDown,p,flags:flags))
  }
  pump()
}
func label(_ row: Int) -> String { (table.view(atColumn:0,row:row-1,makeIfNecessary:true) as! NSTableCellView).textField!.stringValue }
click(1)
check(player.info.activeTrackIDs(.audio) == [1], "native left click plays only its track")
check(!(table.rowView(atRow:0,makeIfNecessary:true) as! TrackRangeRowView).isHighlighted, "ordinary click has no gray range anchor")
let beforeLastTrackToggle = player.mpv.writes
click(1,right:true)
check(player.info.activeTrackIDs(.audio) == [1] && player.mpv.writes == beforeLastTrackToggle, "right click on the last track leaves audio playing without rewriting mpv")
click(1,flags:.command)
check(player.info.activeTrackIDs(.audio) == [1] && player.mpv.writes == beforeLastTrackToggle, "Command-click also protects the last active track")
click(0)
check(player.info.activeTrackIDs(.audio).isEmpty, "explicit No audio still disables the last active track")
check(offButton.state == .on && table.numberOfRows == 4 && table.trackID?(0) == 1,
      "No audio is selected outside the table, whose first row is the first real track")
let writesWhileOff = player.mpv.writes
click(0)
check(offButton.state == .on && player.info.activeTrackIDs(.audio).isEmpty && player.mpv.writes == writesWhileOff,
      "clicking selected No audio keeps playback disabled without restoring tracks or rewriting mpv")
click(3,right:true); click(1,right:true); click(4,right:true)
click(3)
check(player.info.activeTrackIDs(.audio) == [3], "three right-click additions followed by a plain click on the first-added track keep only that track")
click(1)
click(3,right:true)
check(player.info.activeTrackIDs(.audio) == [1,3], "native right click adds audio without replacing it")
click(2,flags:.command)
check(player.info.activeTrackIDs(.audio) == [1,2,3], "native Command-click adds audio")
click(3,right:true)
check(player.info.activeTrackIDs(.audio) == [1,2], "native right click removes playing audio")
let beforeAnchor = player.mpv.writes
click(1,flags:.shift)
check(player.info.activeTrackIDs(.audio) == [1,2] && player.mpv.writes == beforeAnchor, "first native Shift-click only marks the range start without touching mpv")
click(4,flags:.shift)
check(player.info.activeTrackIDs(.audio) == [1,2,3,4], "native Shift-click includes the anchored displayed range")
for row in 1...4 {
  let cell = table.view(atColumn:0,row:row-1,makeIfNecessary:true) as! NSTableCellView
  check(!cell.subviews.compactMap { $0 as? ColoredView }.first!.isHidden, "every sounding track has its native blue indicator")
}
private let rowView = table.rowView(atRow:0,makeIfNecessary:true) as! TrackRangeRowView
check(rowView.isHighlighted && rowView.rangeOpacity == 0, "completed range hides its neutral anchor without changing the range identity when animations are disabled")
click(2)
check(player.info.activeTrackIDs(.audio) == [2], "ordinary click on an active track exits multitrack playback in one action")
check(!(table.rowView(atRow:0,makeIfNecessary:true) as! TrackRangeRowView).isHighlighted, "solo removes the previous gray Shift anchor")
for target in 1...4 {
  click(1,flags:.shift); click(4,flags:.shift)
  click(target)
  check(player.info.activeTrackIDs(.audio) == [target], "plain click on each active ID returns from four-track mix to that solo")
}
// Becoming first responder can scroll a table. The press still belongs to the
// track under the pointer before focus, even if a different row moves there.
player.info.audioTracks.append(MPVTrack(5))
player.postNotification(.iinaTracklistChanged)
player.setAudioTracks([1,2,3,4]); pump()
selector.contentView.scroll(to:NSPoint(x:0,y:table.rect(ofRow:1).minY))
selector.reflectScrolledClipView(selector.contentView); pump()
window.onFirstResponder = {
  selector.contentView.scroll(to:NSPoint(x:0,y:-26))
  selector.reflectScrolledClipView(selector.contentView)
}
click(2)
check(player.info.activeTrackIDs(.audio) == [2], "focus-induced scrolling preserves the identity of the pressed active track")
player.info.audioTracks.removeLast()
player.postNotification(.iinaTracklistChanged)
click(2)

// Attempted row dragging is consumed without reordering or selecting.
click(1,flags:.shift)
table.scrollRowToVisible(0); pump()
let from = point(1), to = point(3)
let beforeDrag = player.mpv.writes
private let originalRowView = table.rowView(atRow:0,makeIfNecessary:true) as! TrackRangeRowView
NSCursor.crosshair.push()
NSApp.postEvent(event(.leftMouseUp,to),atStart:true)
NSApp.postEvent(event(.leftMouseDragged,NSPoint(x:to.x-40,y:to.y)),atStart:true)
NSApp.postEvent(event(.leftMouseDragged,NSPoint(x:from.x+60,y:point(2).y)),atStart:true)
window.sendEvent(event(.leftMouseDown,from)); pump()
check(player.mpv.writes == beforeDrag && player.info.activeTrackIDs(.audio) == [2], "audio drag never selects or changes playback")
check((1...table.numberOfRows).map(label) == player.info.audioTracks.map { "Track \($0.id)" }, "audio drag preserves source order")
check(table.rowView(atRow:0,makeIfNecessary:true) === originalRowView && NSCursor.current == NSCursor.crosshair,
      "audio drag keeps the row in place without a hand cursor")
NSCursor.pop()
player.postNotification(.iinaTracklistChanged);pump()
check(label(1) == "Track 1", "metadata refresh retains the fixed source order")
click(3)
check(player.info.activeTrackIDs(.audio) == [3], "click after an ignored drag addresses the original source")
let beforeRightDrag = player.mpv.writes
let rightOrigin = point(2)
window.sendEvent(event(.rightMouseDown,rightOrigin))
window.sendEvent(event(.rightMouseDragged,NSPoint(x:rightOrigin.x+20,y:rightOrigin.y)))
window.sendEvent(event(.rightMouseUp,rightOrigin))
check(player.mpv.writes == beforeRightDrag, "right drag cannot become an audio toggle even after returning to origin")
click(0)
check(player.info.activeTrackIDs(.audio).isEmpty, "native None disables the whole mix")
player.nextFile();pump()
check(label(1) == "Track 1" && label(2) == "Track 2", "new media resets displayed row order")
// Video uses exactly the same native gesture and anchor semantics.
selector.removeFromSuperview()
let videoSelector = TrackSelector(.video,player:player,observedKeys:[.iinaVIDChanged])
window.contentView!.addSubview(videoSelector)
videoSelector.translatesAutoresizingMaskIntoConstraints = true
videoSelector.frame = NSRect(x:20,y:60,width:380,height:130)
private let videoTable = videoSelector.documentView as! TrackTableView
private let videoOffButton = videoTable.headerView!.subviews.compactMap { $0 as? NSButton }.first!
pump()
func videoPoint(_ row:Int) -> NSPoint { videoTable.convert(NSPoint(x:50,y:videoTable.rect(ofRow:row-1).midY),to:nil) }
func videoClick(_ row:Int, flags:NSEvent.ModifierFlags = [], right:Bool = false) {
  if row == 0 { videoOffButton.performClick(nil); pump(); return }
  videoTable.scrollRowToVisible(row-1); pump()
  let p = videoPoint(row)
  if right { window.sendEvent(event(.rightMouseDown,p));window.sendEvent(event(.rightMouseUp,p)) }
  else { NSApp.postEvent(event(.leftMouseUp,p,flags:flags),atStart:true);window.sendEvent(event(.leftMouseDown,p,flags:flags)) }
  pump()
}
videoClick(1)
let beforeVideoLastToggle = player.mpv.writes
videoClick(1,right:true);videoClick(1,flags:.command)
check(player.info.activeTrackIDs(.video) == [1] && player.mpv.writes == beforeVideoLastToggle, "video right/Command clicks protect the final active track without graph writes")
videoClick(2,right:true);videoClick(3,flags:.command)
check(player.info.activeTrackIDs(.video) == [1,2,3], "video right and Command clicks enable multiple layers")
videoClick(1)
check(player.info.activeTrackIDs(.video) == [1], "left click on the first-added video solos it instead of None")
let beforeVideoAnchor = player.mpv.writes
videoClick(2,flags:.shift)
check(player.info.activeTrackIDs(.video) == [1] && player.mpv.writes == beforeVideoAnchor && (videoTable.rowView(atRow:1,makeIfNecessary:true) as! TrackRangeRowView).isHighlighted, "first video Shift-click only sets the neutral anchor")
videoClick(3,flags:.shift)
check(player.info.activeTrackIDs(.video) == [1,2,3], "second video Shift-click adds its inclusive displayed range")
let videoOrigin = videoPoint(1), videoTarget = videoPoint(2)
private let movingVideoRow = videoTable.rowView(atRow:0,makeIfNecessary:true)!
NSApp.postEvent(event(.leftMouseUp,videoTarget),atStart:true)
NSApp.postEvent(event(.leftMouseDragged,videoTarget),atStart:true)
window.sendEvent(event(.leftMouseDown,videoOrigin));pump()
check(player.info.layeredVideoTrackIDs == [1,2,3], "video drag preserves source compositor order")
check(videoTable.rowView(atRow:0,makeIfNecessary:true) === movingVideoRow && movingVideoRow.alphaValue == 1,
      "video drag keeps the original row at its original position")
videoClick(1)
let beforeSoloVideoDrag = player.mpv.writes
NSApp.postEvent(event(.leftMouseUp,videoPoint(3)),atStart:true)
NSApp.postEvent(event(.leftMouseDragged,videoPoint(3)),atStart:true)
window.sendEvent(event(.leftMouseDown,videoPoint(1)));pump()
check(player.info.activeTrackIDs(.video) == [1] && player.mpv.writes == beforeSoloVideoDrag,
      "dragging a solo video row changes neither selection nor playback")
videoClick(0)
check(player.info.activeTrackIDs(.video).isEmpty, "explicit video None disables the whole stack")
window.close()
// Real constraints and native bottom-edge hit testing for all four lists.
let resizeWindow = NSWindow(contentRect: NSRect(x:100,y:100,width:420,height:700),
                            styleMask:[.borderless],backing:.buffered,defer:false)
resizeWindow.isReleasedWhenClosed = false
player.mainWindow.window = resizeWindow
let resizeRoot = resizeWindow.contentView!
let types: [MPVTrack.TrackType] = [.video, .audio, .sub, .secondSub]
let resizableLists = types.map { type -> TrackSelector in
  let list = TrackSelector(type,player:player,observedKeys:[.iinaTracklistChanged])
  resizeRoot.addSubview(list)
  list.leadingAnchor.constraint(equalTo:resizeRoot.leadingAnchor,constant:20).isActive = true
  list.topAnchor.constraint(equalTo:resizeRoot.topAnchor,constant:20).isActive = true
  list.widthAnchor.constraint(equalToConstant:380).isActive = true
  list.isHidden = true
  return list
}
resizeWindow.orderFrontRegardless()
func resizePump() { resizeRoot.layoutSubtreeIfNeeded(); RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
func dragBottom(_ list: TrackSelector, by delta: CGFloat) {
  list.isHidden = false
  resizePump()
  let handle = list.subviews.compactMap { $0 as? TrackListResizeHandle }.first!
  let start = handle.convert(NSPoint(x:handle.bounds.midX,y:handle.bounds.midY),to:nil)
  let end = NSPoint(x:start.x,y:start.y-delta)
  check(resizeRoot.hitTest(resizeRoot.convert(start,from:nil)) === handle,
        "the visible bottom edge hits the resize control rather than a row")
  func resizeEvent(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
    NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,
                      windowNumber:resizeWindow.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
  }
  NSApp.postEvent(resizeEvent(.leftMouseUp,end),atStart:true)
  NSApp.postEvent(resizeEvent(.leftMouseDragged,end),atStart:true)
  resizeWindow.sendEvent(resizeEvent(.leftMouseDown,start))
  resizePump()
}
let writesBeforeResize = player.mpv.writes
for (index,list) in resizableLists.enumerated() {
  list.isHidden = false; resizePump()
  check(abs(list.frame.height-130)<0.1,"a new \(types[index]) list starts with four complete rows")
  let nativeTable = list.documentView as! NSTableView
  let outline = list.subviews.compactMap { $0 as? TrackListOutlineView }.first!
  check(outline.frame == list.bounds && list.subviews.last === outline && outline.gridColor == nativeTable.gridColor,
        "\(types[index]) draws its full-list outline and header divider above the pinned header with the native grid color")
  check(nativeTable.rowHeight == 26 && nativeTable.intercellSpacing.height == 0 && list.contentSize.height - 26 == 104,
        "\(types[index]) uses the same complete row pitch for real rows and empty grid lines")
  let top = list.frame.maxY
  dragBottom(list,by:80)
  check(abs(list.frame.height-208)<0.1 && abs(list.frame.maxY-top)<0.1,
        "\(types[index]) grows downwards without moving its top edge")
  list.isHidden = true; resizePump(); list.isHidden = false; resizePump()
  check(abs(list.frame.height-208)<0.1,"hiding/reopening \(types[index]) preserves its session height")
  dragBottom(list,by:-500)
  check(abs(list.frame.height-130)<0.1,"\(types[index]) cannot shrink below the original four-row height")
  dragBottom(list,by:10000)
  check(abs(list.frame.height-650)<0.1,"\(types[index]) keeps its bottom resize edge inside the player")
  dragBottom(list,by:-500)
  list.isHidden = true
}
resizableLists[0].isHidden = false; resizePump()
dragBottom(resizableLists[0],by:40)
let retainedHeight = resizableLists[0].frame.height
player.nextFile(); resizePump()
check(abs(resizableLists[0].frame.height-retainedHeight)<0.1,"opening another file in the same player preserves the chosen list height")
check(player.mpv.writes == writesBeforeResize,"resizing all four lists never writes playback or track selection")
check(resizableLists.dropFirst().allSatisfy { abs($0.frame.height-156)<0.1 },"list heights are independent of tab changes and other list resizing")
let freshList = TrackSelector(.video,player:player,observedKeys:[])
check(freshList.constraints.contains { $0.firstAttribute == .height && $0.constant == 130 },
      "a fresh player list starts at the default height without any saved preference")
let unrelatedWindow = NSWindow(contentRect:NSRect(x:0,y:0,width:100,height:100),styleMask:[.borderless],backing:.buffered,defer:false)
unrelatedWindow.isReleasedWhenClosed = false
unrelatedWindow.orderFrontRegardless(); unrelatedWindow.close(); resizePump()
check(abs(resizableLists[0].frame.height-retainedHeight)<0.1,"closing another window leaves this player's list height intact")
resizableLists[1].removeFromSuperview()
check(resizableLists[1].window == nil,"inactive-tab fixture detaches its retained list from the window")
resizeWindow.close()
check(resizableLists.allSatisfy { list in list.constraints.contains { $0.firstAttribute == .height && $0.constant == 130 } },
      "closing the owning player resets retained active and detached inactive lists")
resizeRoot.addSubview(resizableLists[1])
resizableLists[1].leadingAnchor.constraint(equalTo:resizeRoot.leadingAnchor,constant:20).isActive = true
resizableLists[1].topAnchor.constraint(equalTo:resizeRoot.topAnchor,constant:20).isActive = true
resizeWindow.orderFrontRegardless(); resizePump()
check(resizableLists.allSatisfy { abs($0.frame.height-130)<0.1 },"reopening a reused player window starts a new default-height session")
resizeWindow.close()
// Quantized targets with real frame/clip animation, including held mouse tracking.
let animatedPlayer = PlayerCore()
animatedPlayer.info.audioTracks = (1...30).map { MPVTrack($0) }
let animatedWindow = NSWindow(contentRect:NSRect(x:100,y:100,width:420,height:700),
                             styleMask:[.borderless],backing:.buffered,defer:false)
animatedWindow.isReleasedWhenClosed = false
animatedPlayer.mainWindow.window = animatedWindow
let animatedRoot = animatedWindow.contentView!
let animatedList = TrackSelector(.audio,player:animatedPlayer,observedKeys:[.iinaAIDChanged])
animatedRoot.addSubview(animatedList)
animatedList.leadingAnchor.constraint(equalTo:animatedRoot.leadingAnchor,constant:20).isActive = true
animatedList.topAnchor.constraint(equalTo:animatedRoot.topAnchor,constant:20).isActive = true
animatedList.widthAnchor.constraint(equalToConstant:380).isActive = true
animatedWindow.orderFrontRegardless(); animatedRoot.layoutSubtreeIfNeeded()
private let animatedHandle = animatedList.subviews.compactMap { $0 as? TrackListResizeHandle }.first!
func animatePump(_ interval:TimeInterval = 0.02) {
  RunLoop.main.run(until:Date().addingTimeInterval(interval)); animatedRoot.layoutSubtreeIfNeeded()
}
animatedHandle.onResize?(142)
check(animatedList.frame.height == 130,"a sub-half-row drag does not create a partial row")
animatedHandle.onResize?(144)
check(animatedList.frame.height == 156,"crossing the half-row threshold selects the next full row")
animatedHandle.onResize?(10000)
check(animatedList.frame.height == 650 && (animatedList.contentSize.height - 26).truncatingRemainder(dividingBy:26) == 0,
      "the maximum size rounds down to a complete row inside the viewport")
animatedHandle.onResize?(130)
AccessibilityPreferences.animationsDisabled = false
animatedHandle.onResize?(182)
animatedHandle.onResize?(130)
animatePump(0.2)
check(animatedList.frame.height == 130,"returning to the displayed row boundary before the first tick cancels the old target")
AccessibilityPreferences.animationsDisabled = true
animatedList.contentView.scroll(to:NSPoint(x:0,y:13-26))
animatedList.reflectScrolledClipView(animatedList.contentView)
AccessibilityPreferences.animationsDisabled = false
animatedHandle.onResize?(182)
check(animatedList.frame.height == 130,"an animated step starts from the displayed frame without an instant size jump")
animatePump(0.035)
check(animatedList.frame.height > 130 && animatedList.frame.height < 182,
      "real AppKit layout exposes intermediate heights during expansion")
check(animatedList.contentView.bounds.minY > 13-26 && animatedList.contentView.bounds.minY < 26-26,
      "a partially scrolled row aligns smoothly rather than jumping at release")
let displayedHeight = animatedList.frame.height
animatedHandle.onResize?(234)
check(abs(animatedList.frame.height-displayedHeight)<0.1,"retargeting a larger row step preserves the displayed position")
let trackingDeadline = Date().addingTimeInterval(0.025)
while Date() < trackingDeadline { RunLoop.main.run(mode:.eventTracking,before:trackingDeadline) }
check(animatedList.frame.height > displayedHeight && animatedList.frame.height < 234,
      "height animation advances in AppKit event-tracking mode")
let beforeReverse = animatedList.frame.height
animatedHandle.onResize?(156)
check(abs(animatedList.frame.height-beforeReverse)<0.1,"reversing the drag keeps frame continuity")
animatePump(0.2)
check(animatedList.frame.height == 156 && animatedList.contentSize.height - 26 == 130,
      "the resize finishes at the exact complete-row boundary")
check((animatedList.contentView.bounds.minY + 26).truncatingRemainder(dividingBy:26) == 0,
      "resizing a partially scrolled list finishes with no clipped top or bottom row")

AccessibilityPreferences.animationsDisabled = true
animatedHandle.onResize?(130)
AccessibilityPreferences.animationsDisabled = false
let heldStart = animatedHandle.convert(NSPoint(x:animatedHandle.bounds.midX,y:animatedHandle.bounds.midY),to:nil)
let heldEnd = NSPoint(x:heldStart.x,y:heldStart.y-26)
func heldEvent(_ type:NSEvent.EventType,_ point:NSPoint) -> NSEvent {
  NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,
                    windowNumber:animatedWindow.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
}
var heldSample:CGFloat = -1
var beforeRelease:CGFloat = -1
let sampleTimer = Timer(timeInterval:0.04,repeats:false) { _ in heldSample = animatedList.frame.height }
let releaseTimer = Timer(timeInterval:0.2,repeats:false) { _ in
  beforeRelease = animatedList.frame.height
  NSApp.postEvent(heldEvent(.leftMouseUp,heldEnd),atStart:true)
}
for timer in [sampleTimer,releaseTimer] {
  RunLoop.main.add(timer,forMode:.common); RunLoop.main.add(timer,forMode:.eventTracking)
}
NSApp.postEvent(heldEvent(.leftMouseDragged,heldEnd),atStart:true)
animatedWindow.sendEvent(heldEvent(.leftMouseDown,heldStart))
sampleTimer.invalidate();releaseTimer.invalidate()
print("Held resize samples: intermediate=\(heldSample), beforeRelease=\(beforeRelease)")
check(heldSample > 130 && heldSample < 156 && beforeRelease == 156,
      "native mouse tracking animates each row step while the resize button is still held")
AccessibilityPreferences.motionReductionEnabled = true
animatedHandle.onResize?(208)
check(animatedList.frame.height == 208,"Reduce Motion applies whole-row steps immediately")
AccessibilityPreferences.motionReductionEnabled = false
AccessibilityPreferences.animationsDisabled = true
animatedHandle.onResize?(182)
check(animatedList.frame.height == 182,"the app's Disable animations setting also keeps exact row steps")
AccessibilityPreferences.animationsDisabled = false
animatedList.contentView.scroll(to:NSPoint(x:0,y:13-26))
animatedHandle.onResize?(234)
animatedWindow.close(); animatePump(0.2)
check(animatedList.frame.height == 130 && animatedList.contentView.bounds.minY == -26,
      "closing mid-animation resets four full rows from the top and cancels pending frame updates")
animatedWindow.orderFrontRegardless();animatePump()
animatedHandle.onResize?(208)
animatedList.removeFromSuperview()
check(animatedList.constraints.contains { $0.firstAttribute == .height && $0.constant == 208 },
      "detaching an animating tab settles its chosen complete-row height")
animatePump(0.2)
animatedWindow.close()
check(animatedList.constraints.contains { $0.firstAttribute == .height && $0.constant == 130 },
      "closing the owner resets a detached tab without a late animation restoring its old height")
// Pinned state buttons share the existing explicit-off selection path.
let offPlayer = PlayerCore()
let offWindow = NSWindow(contentRect:NSRect(x:100,y:100,width:420,height:234),
                         styleMask:[.borderless],backing:.buffered,defer:false)
offWindow.isReleasedWhenClosed = false
offPlayer.mainWindow.window = offWindow
let offRoot = offWindow.contentView!
offRoot.appearance = NSAppearance(named:.darkAqua)
offRoot.wantsLayer = true
offRoot.layer?.backgroundColor = NSColor(calibratedWhite:0.16,alpha:1).cgColor
func saveOffPreview(_ list:TrackSelector,_ name:String) {
  guard CommandLine.arguments.count > 1,
        let bitmap = offRoot.bitmapImageRepForCachingDisplay(in:offRoot.bounds) else { return }
  offRoot.cacheDisplay(in:offRoot.bounds,to:bitmap)
  if let png = bitmap.representation(using:.png,properties:[:]) {
    try! png.write(to:URL(fileURLWithPath:CommandLine.arguments[1]).deletingLastPathComponent().appendingPathComponent(name+".png"))
  }
}
for (type,title) in [(MPVTrack.TrackType.video,"No video"),(.audio,"No audio"),(.sub,"No subtitles"),(.secondSub,"No subtitles")] {
  let list = TrackSelector(type,player:offPlayer,observedKeys:[.iinaTracklistChanged])
  offRoot.addSubview(list)
  list.leadingAnchor.constraint(equalTo:offRoot.leadingAnchor,constant:20).isActive = true
  list.topAnchor.constraint(equalTo:offRoot.topAnchor,constant:20).isActive = true
  list.widthAnchor.constraint(equalToConstant:380).isActive = true
  offWindow.orderFrontRegardless();offRoot.layoutSubtreeIfNeeded()
  let nativeTable = list.documentView as! NSTableView
  let button = nativeTable.headerView!.subviews.compactMap { $0 as? NSButton }.first!
  let material = nativeTable.headerView!.subviews.compactMap { $0 as? NSVisualEffectView }.first!
  check(material.material == .popover && material.blendingMode == .withinWindow && material.frame == nativeTable.headerView!.bounds,
        "\(type) pinned No… row uses a native matte background within the existing list outline")
  check(button.title == title && button.state == .off && button.isEnabled && button.toolTip == nil,
        "\(type) has an accessible, enabled state button without a tooltip")
  check((nativeTable.accessibilityChildren()?.first as? NSView) === nativeTable.headerView &&
        (nativeTable.headerView?.accessibilityChildren()?.first as? NSButton) === button,
        "\(type) exposes the pinned state button in the accessibility hierarchy")
  let otherType:MPVTrack.TrackType = type == .audio ? .video : .audio
  let otherIDs = offPlayer.info.activeTrackIDs(otherType)
  saveOffPreview(list,"\(type)-playing")
  button.performClick(nil)
  check(offPlayer.info.activeTrackIDs(type).isEmpty && button.state == .on && offPlayer.info.activeTrackIDs(otherType) == otherIDs,
        "\(type) explicit off updates its button and leaves the other media type playing")
  if type == .sub { check(offPlayer.info.secondSid == 2,"primary subtitles off does not disable secondary subtitles") }
  let writes = offPlayer.mpv.writes
  button.performClick(nil)
  check(button.state == .on && offPlayer.info.activeTrackIDs(type).isEmpty,
        "\(type) selected state never restores a previous track on repeat click")
  if type == .audio || type == .video { check(offPlayer.mpv.writes == writes,"\(type) repeat off avoids unnecessary graph writes") }
  saveOffPreview(list,"\(type)-off")
  if type == .audio { offPlayer.info.audioTracks = [] }
  else if type == .video { offPlayer.info.videoTracks = [] }
  else { offPlayer.info.subTracks = [] }
  offPlayer.postNotification(.iinaTracklistChanged)
  check(nativeTable.numberOfRows == 0 && button.state == .on && button.isEnabled,
        "\(type) missing tracks retain the selected, pinned off state above an empty table")
  if type == .sub { offPlayer.info.subTracks = [MPVTrack(1,.sub),MPVTrack(2,.sub)] }
  list.removeFromSuperview()
}
offWindow.close()
// Scrolling may move the document, but never the off button or its clickable area.
animatedRoot.addSubview(animatedList)
animatedList.leadingAnchor.constraint(equalTo:animatedRoot.leadingAnchor,constant:20).isActive = true
animatedList.topAnchor.constraint(equalTo:animatedRoot.topAnchor,constant:20).isActive = true
animatedList.widthAnchor.constraint(equalToConstant:380).isActive = true
animatedWindow.orderFrontRegardless();animatePump()
private let pinnedButton = (animatedList.documentView as! NSTableView).headerView!.subviews.compactMap { $0 as? NSButton }.first!
let pinnedBefore = pinnedButton.convert(pinnedButton.bounds,to:nil)
animatedList.contentView.scroll(to:NSPoint(x:0,y:260-26))
animatedList.reflectScrolledClipView(animatedList.contentView);animatePump()
let pinnedAfter = pinnedButton.convert(pinnedButton.bounds,to:nil)
let pinnedCenter = pinnedButton.convert(NSPoint(x:pinnedButton.bounds.midX,y:pinnedButton.bounds.midY),to:nil)
check(pinnedBefore == pinnedAfter && animatedRoot.hitTest(animatedRoot.convert(pinnedCenter,from:nil)) === pinnedButton,
      "scrolling a long track list keeps its off button pinned and directly clickable")
pinnedButton.performClick(nil)
check(animatedPlayer.info.activeTrackIDs(.audio).isEmpty && pinnedButton.state == .on,
      "the pinned control still disables playback when the original first row is scrolled away")
animatedPlayer.setAudioTracks([7]);animatePump()
check(pinnedButton.state == .off,"external track selection clears the off state through the existing notification")
animatedWindow.close()
AccessibilityPreferences.animationsDisabled = true

// Range completion fades only the neutral background, retaining playback and anchor identity.
let fadePlayer = PlayerCore()
let fadeWindow = NSWindow(contentRect:NSRect(x:0,y:0,width:420,height:234),styleMask:[.borderless],backing:.buffered,defer:false)
fadeWindow.isReleasedWhenClosed = false
fadeWindow.contentView!.wantsLayer = true
fadeWindow.contentView!.layer?.backgroundColor = NSColor(calibratedWhite:0.16,alpha:1).cgColor
fadePlayer.mainWindow.window = fadeWindow
let fadeList = TrackSelector(.audio,player:fadePlayer,observedKeys:[.iinaAIDChanged])
fadeWindow.contentView!.addSubview(fadeList)
fadeList.frame = NSRect(x:20,y:20,width:380,height:130)
fadeList.translatesAutoresizingMaskIntoConstraints = true
fadeWindow.orderFrontRegardless();fadeWindow.contentView!.layoutSubtreeIfNeeded()
private let fadeTable = fadeList.documentView as! TrackTableView
func fadeClick(_ row:Int, shift:Bool = true) {
  let p = fadeTable.convert(NSPoint(x:50,y:fadeTable.rect(ofRow:row).midY),to:nil)
  let flags:NSEvent.ModifierFlags = shift ? .shift : []
  func e(_ type:NSEvent.EventType)->NSEvent {
    NSEvent.mouseEvent(with:type,location:p,modifierFlags:flags,timestamp:ProcessInfo.processInfo.systemUptime,
      windowNumber:fadeWindow.windowNumber,context:nil,eventNumber:checks+1,clickCount:1,pressure:1)!
  }
  NSApp.postEvent(e(.leftMouseUp),atStart:true);fadeWindow.sendEvent(e(.leftMouseDown))
}
func fadeOpacity(_ row:Int)->CGFloat { (fadeTable.rowView(atRow:row,makeIfNecessary:true) as! TrackRangeRowView).rangeOpacity }
func highlightedRows()->Set<Int> {
  Set((0..<fadeTable.numberOfRows).filter {
    let row = fadeTable.rowView(atRow:$0,makeIfNecessary:true) as! TrackRangeRowView
    return row.isHighlighted && row.rangeOpacity > 0
  })
}
@discardableResult func saveFadePreview(_ name:String)->CGFloat {
  let root = fadeWindow.contentView!
  root.appearance = NSAppearance(named:.darkAqua)
  guard let bitmap = root.bitmapImageRepForCachingDisplay(in:root.bounds) else { return 0 }
  root.cacheDisplay(in:root.bounds,to:bitmap)
  if CommandLine.arguments.count > 1 {
    try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]).deletingLastPathComponent().appendingPathComponent(name+".png"))
  }
  let point = root.convert(NSPoint(x:350,y:fadeTable.rect(ofRow:0).midY),from:fadeTable)
  let scale = CGFloat(bitmap.pixelsWide) / root.bounds.width
  return bitmap.colorAt(x:Int(point.x*scale),y:Int((root.bounds.height-point.y)*scale))!.usingColorSpace(.deviceRGB)!.redComponent
}
AccessibilityPreferences.animationsDisabled = false
fadeClick(0)
RunLoop.main.run(until:Date().addingTimeInterval(0.35))
check(fadeOpacity(0) == 1 && highlightedRows() == [0] && fadePlayer.info.activeTrackIDs(.audio) == [1], "first Shift anchor stays visible only on its row while waiting for the endpoint")
let pendingBrightness = saveFadePreview("fade-pending")
fadeClick(2)
check(highlightedRows() == [0,1,2], "second Shift-click highlights both endpoints and every row between them")
saveFadePreview("fade-whole-range")
RunLoop.main.run(until:Date().addingTimeInterval(0.1))
check(fadeOpacity(0) > 0 && fadeOpacity(0) < 1 && fadeOpacity(1) == fadeOpacity(0) && fadeOpacity(2) == fadeOpacity(0) && fadePlayer.info.activeTrackIDs(.audio) == [1,2,3], "completed Shift range fades all of its highlighted rows together")
let fadeWrites = fadePlayer.mpv.writes
RunLoop.main.run(until:Date().addingTimeInterval(0.3))
check(highlightedRows().isEmpty && fadeOpacity(0) == 0 && fadePlayer.mpv.writes == fadeWrites, "whole-range fade completes without playback writes")
check(saveFadePreview("fade-complete") < pendingBrightness - 0.03, "rendered anchor background loses its highlight after the fade")
fadeClick(3)
check(fadePlayer.info.activeTrackIDs(.audio) == [1,2,3,4] && highlightedRows() == [0,1,2,3] && fadeOpacity(0) == 1, "subsequent Shift clicks retain the logical anchor and show their new range before fading")
RunLoop.main.run(until:Date().addingTimeInterval(0.06))
fadeClick(1)
check(highlightedRows() == [0,1] && fadeOpacity(0) == 1, "a new endpoint replaces an in-progress flash instead of leaving old rows highlighted")
fadeClick(3,shift:false);fadeClick(2);fadeClick(0)
check(highlightedRows() == [0,1,2] && fadePlayer.info.activeTrackIDs(.audio) == [1,2,3,4], "reverse range highlights only its interval while retaining already active tracks outside it")
fadeClick(3,shift:false);fadeClick(1);fadeClick(1)
check(highlightedRows() == [1] && fadePlayer.info.activeTrackIDs(.audio) == [2,4], "coincident endpoints flash one row and retain other active tracks")
fadeClick(0,shift:false);fadeClick(1);fadeClick(3)
RunLoop.main.run(until:Date().addingTimeInterval(0.06))
fadeClick(0,shift:false);fadeClick(2)
RunLoop.main.run(until:Date().addingTimeInterval(0.35))
check(fadeOpacity(2) == 1 && highlightedRows() == [2], "a new pending anchor cancels the old fade without a late reset")
fadeClick(0,shift:false);fadeClick(1)
fadePlayer.mpv.failures = 1
fadeClick(3)
RunLoop.main.run(until:Date().addingTimeInterval(0.35))
check(fadeOpacity(1) == 1 && highlightedRows() == [1] && fadePlayer.info.activeTrackIDs(.audio) == [1], "failed range application retains only its pending highlight for retry")
fadeClick(3)
fadeList.removeFromSuperview()
check(fadeOpacity(1) == 0, "detaching a tab settles and cancels its active fade")
fadeWindow.close()
AccessibilityPreferences.animationsDisabled = true
print("Completed \(checks) multitrack state/core/native interaction checks.")

let keyboardPlayer = PlayerCore()
keyboardPlayer.info.audioTrackOrder = [4, 1, 3, 2]
_ = keyboardPlayer.setAudioTracks([1])
let keyboardList = TrackSelector(.audio, player: keyboardPlayer, observedKeys: [.iinaAIDChanged])
private let keyboardTable = keyboardList.documentView as! TrackTableView
func arrow(_ keyCode: UInt16) {
  let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
    windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode)!
  keyboardTable.keyDown(with: event)
}
arrow(125)
check(keyboardPlayer.info.activeTrackIDs(.audio) == [2], "Down navigates from the active row in source order")
arrow(125); arrow(125)
check(keyboardPlayer.info.activeTrackIDs(.audio) == [4], "Down stops at the final source")
arrow(126); arrow(126); arrow(126); arrow(126)
check(keyboardPlayer.info.activeTrackIDs(.audio) == [1], "Up stops at the first source")
arrow(123); arrow(124)
check(keyboardPlayer.info.activeTrackIDs(.audio) == [1], "horizontal arrows stay inside the one-column track table")
keyboardPlayer.info.audioTrackOrder = [2, 4, 1, 3]
keyboardPlayer.postNotification(.iinaTracklistChanged)
arrow(125)
check(keyboardPlayer.info.activeTrackIDs(.audio) == [2], "obsolete cached order never changes keyboard navigation")
print("Track keyboard regressions complete: \(checks) total checks.")
