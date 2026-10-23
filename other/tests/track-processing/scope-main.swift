
let scopePlayer = PlayerCore()
scopePlayer.mpv.supportsPersistentMixer = true
scopePlayer.prepareMixer()
let originalAudio = scopePlayer.info.activeTrackIDs(.audio)
let originalVideo = scopePlayer.info.activeTrackIDs(.video)
scopePlayer.scopedTrackSettings.setTarget(3, for: .audioDelay)
scopePlayer.scopedTrackSettings.setTarget(2, for: .audioEQ)
check(scopePlayer.info.activeTrackIDs(.audio) == originalAudio && scopePlayer.info.activeTrackIDs(.video) == originalVideo, "editing targets never change playback membership")
var scopedAudio = AudioTrackProcessing(); scopedAudio.delay = -0.5; scopedAudio.gains[4] = 6
scopePlayer.scopedTrackSettings.audio[3] = scopedAudio
check(scopePlayer.refreshTrackProcessing(.audio), "individual audio processing enters the owned mixer")
check(scopePlayer.mpv.strings["lavfi-complex"]!.contains("equalizer@iina_audio_eq_3_4") && scopePlayer.mpv.strings["lavfi-complex"]!.contains("atrim=start_sample=24000"), "signed delay and EQ reach the actual requested input")
let graphCount = scopePlayer.mpv.graphWrites
let priorGains = scopedAudio.gains
scopedAudio.gains[4] = -3
scopePlayer.scopedTrackSettings.audio[3] = scopedAudio
check(scopePlayer.refreshTrackAudioEQ(id: 3, previous: priorGains, gains: scopedAudio.gains, audioRollback: [3: AudioTrackProcessing(delay: -0.5, gains: priorGains)]), "EQ uses the named runtime setter")
check(scopePlayer.mpv.graphWrites == graphCount && scopePlayer.mpv.equalizerGains[ProcessedAudioGraph.equalizerTarget(trackID: 3, band: 4)] == "-3.0", "EQ updates do not replace or restart the mixer graph")
check(scopePlayer.setAudioTracks([1, 2]), "playback membership remains independently adjustable")
check(scopePlayer.scopedTrackSettings.audio[3]?.gains[4] == -3, "inactive track settings survive disable")
check(scopePlayer.setAudioTracks([3]), "configured inactive track can be enabled again")
var scopedVideo = VideoTrackProcessing(); scopedVideo.rotation = 90; scopedVideo.brightness = 25
scopePlayer.scopedTrackSettings.video[1] = scopedVideo
check(scopePlayer.refreshTrackProcessing(.video), "a single video track can use individual processing")
check(scopePlayer.mpv.strings["lavfi-complex"]!.contains("transpose=clock"), "video geometry reaches the selected input")
var isolated = scopePlayer.scopedTrackSettings
isolated.reset(.audioEQ)
check(isolated.audio[3]?.delay == -0.5 && isolated.audio[3]?.gains.allSatisfy({ $0 == 0 }) == true, "Reset all EQ preserves every track delay")
check(isolated.video[1]?.rotation == 90 && isolated.video[1]?.brightness == 25, "Reset all audio preserves video settings")
isolated.reset(.videoGeometry)
check(isolated.video[1]?.rotation == 0 && isolated.video[1]?.brightness == 25, "Reset all geometry preserves color")
check(isolated.target(.videoGeometry) == 0 && isolated.target(.audioDelay) == 2, "reset preserves the shared editing context")
scopePlayer.nextFile()
check(scopePlayer.scopedTrackSettings.audio.isEmpty && scopePlayer.scopedTrackSettings.video.isEmpty && scopePlayer.scopedTrackSettings.audioTarget == 0 && scopePlayer.scopedTrackSettings.videoTarget == 0, "new media clears individual profiles and editing targets")
print("Scoped processing integration complete: \(checks) total checks.")

// Restore through the actual graph owner, not a mock of refreshTrackProcessing.
let mediaSessionPlayer = PlayerCore()
let sessionURL = URL(fileURLWithPath:"/session-A.mkv")
mediaSessionPlayer.videoGeometryMediaURL = sessionURL
var sessionSnapshot = MediaVideoGeometryState()
sessionSnapshot.video[2] = VideoTrackProcessing(aspect:"4:3",crop:TrackVideoCrop(x:10,y:10,width:200,height:150),rotation:90)
sessionSnapshot.videoTarget = 2
sessionSnapshot.videoOrder = [2,3,1]
sessionSnapshot.activeVideo = [2]
mediaSessionPlayer.videoGeometrySession[sessionURL] = sessionSnapshot
let audioBeforeRestore = mediaSessionPlayer.info.activeTrackIDs(.audio)
mediaSessionPlayer.restoreVideoSession()
let restoredGraph = mediaSessionPlayer.mpv.strings["lavfi-complex"] ?? ""
check(restoredGraph.contains("[vid2]") && restoredGraph.contains("transpose=clock") && restoredGraph.contains("crop=w="),
      "returning media rebuilds its actual crop/rotation graph on the saved video source")
check(mediaSessionPlayer.info.activeTrackIDs(.video) == [2] && mediaSessionPlayer.scopedTrackSettings.target(.videoGeometry) == 2,
      "session graph restoration retains source membership and editing target")
check(mediaSessionPlayer.info.activeTrackIDs(.audio) == audioBeforeRestore,
      "restoring video session settings preserves native audio selection")
check(mediaSessionPlayer.setVideoTracks([3]) && mediaSessionPlayer.scopedTrackSettings.video[2]?.rotation == 90,
      "switching to another source does not erase the restored source profile")
check(mediaSessionPlayer.setVideoTracks([2]) && (mediaSessionPlayer.mpv.strings["lavfi-complex"] ?? "").contains("transpose=clock"),
      "switching back applies restored geometry through the actual track graph")
mediaSessionPlayer.nextFile()
mediaSessionPlayer.videoGeometryMediaURL = URL(fileURLWithPath:"/session-B.mkv")
mediaSessionPlayer.restoreVideoSession()
check(mediaSessionPlayer.scopedTrackSettings.video.isEmpty,
      "an unvisited item starts without a previous item's source settings")
mediaSessionPlayer.videoGeometryMediaURL = sessionURL
mediaSessionPlayer.restoreVideoSession()
check((mediaSessionPlayer.mpv.strings["lavfi-complex"] ?? "").contains("transpose=clock"),
      "A-B-A rebuilds the saved source graph after new-file cleanup")

let targetPopup = TrackSettingsPopUp(player: scopePlayer, group: .audioEQ)
check(targetPopup.item(at: 0)?.tag == 0 && targetPopup.itemArray.allSatisfy { $0.tag >= 0 }, "shared target popup contains only Master and track choices")
check(targetPopup.itemArray.filter { $0.tag > 0 }.count == scopePlayer.info.audioTracks.count, "target popup includes inactive existing tracks")
let writesBeforeTarget = scopePlayer.mpv.writes
let playingBeforeTarget = scopePlayer.info.activeTrackIDs(.audio)
targetPopup.selectItem(withTag: 4)
_ = targetPopup.sendAction(targetPopup.action!, to: targetPopup.target)
check(scopePlayer.scopedTrackSettings.target(.audioEQ) == 4 && scopePlayer.scopedTrackSettings.target(.audioDelay) == 4, "native target action updates both audio groups")
check(scopePlayer.mpv.writes == writesBeforeTarget && scopePlayer.info.activeTrackIDs(.audio) == playingBeforeTarget, "native target action performs no playback or engine writes")
print("Scoped target popup checks complete: \(checks) total checks.")

let restorePlayer = PlayerCore()
restorePlayer.scopedCropPreview = PlayerCore.CropPreview(id: 1)
check(restorePlayer.refreshTrackProcessing(.video), "temporary source preview can select an inactive source")
restorePlayer.scopedCropPreview = nil
check(restorePlayer.refreshTrackProcessing(.video, videoOverride: [2]) && restorePlayer.info.activeTrackIDs(.video) == [2], "ending scoped Crop restores a different native solo source")
restorePlayer.scopedCropPreview = PlayerCore.CropPreview(id: 1)
_ = restorePlayer.refreshTrackProcessing(.video)
restorePlayer.scopedCropPreview = nil
check(restorePlayer.refreshTrackProcessing(.video, videoOverride: []) && restorePlayer.info.activeTrackIDs(.video).isEmpty, "ending scoped Crop restores No video")
restorePlayer.scopedCropPreview = PlayerCore.CropPreview(id: 1)
restorePlayer.mainWindow.interactiveMode.isActive = true
restorePlayer.nextFile()
check(restorePlayer.mainWindow.interactiveMode.discards == 1 && !restorePlayer.mainWindow.interactiveMode.isActive, "new media exits a scoped crop before clearing its source context")
let resetRuntime = PlayerCore()
resetRuntime.mpv.supportsPersistentMixer = true; resetRuntime.prepareMixer()
var delayed = AudioTrackProcessing(); delayed.delay = 0.5
resetRuntime.scopedTrackSettings.audio[1] = delayed
_ = resetRuntime.refreshTrackProcessing(.audio)
let neutralGraph = resetRuntime.mpv.strings["lavfi-complex"]!
let neutralGains = delayed.gains; delayed.gains[2] = 9
resetRuntime.scopedTrackSettings.audio[1] = delayed
_ = resetRuntime.refreshTrackAudioEQ(id: 1, previous: neutralGains, gains: delayed.gains, audioRollback: [1: AudioTrackProcessing(delay: 0.5)])
check(resetRuntime.neutralizeTrackAudioEQ(resetRuntime.scopedTrackSettings.audio), "Reset all explicitly neutralizes runtime EQ setters")
resetRuntime.scopedTrackSettings.reset(.audioEQ)
_ = resetRuntime.refreshTrackProcessing(.audio)
check(resetRuntime.mpv.equalizerGains[ProcessedAudioGraph.equalizerTarget(trackID: 1, band: 2)] == "0.0" && resetRuntime.mpv.strings["lavfi-complex"] == neutralGraph, "Reset all clears audible runtime EQ even when canonical graph text is unchanged")
let soloRollback = PlayerCore()
var soloProfile = AudioTrackProcessing(); soloProfile.gains[0] = 1
soloRollback.scopedTrackSettings.audio[1] = soloProfile
_ = soloRollback.refreshTrackProcessing(.audio)
let beforeSolo = soloProfile.gains; soloProfile.gains[0] = 7
soloRollback.scopedTrackSettings.audio[1] = soloProfile
_ = soloRollback.refreshTrackAudioEQ(id: 1, previous: beforeSolo, gains: soloProfile.gains, audioRollback: [1: AudioTrackProcessing(gains: beforeSolo)])
soloRollback.scopedTrackSettings.video[1] = VideoTrackProcessing(rotation: 90)
soloRollback.mpv.failures = 1
check(!soloRollback.refreshTrackProcessing(.video), "failed replacement reports failure for a single-track processed mixer")
check(soloRollback.mpv.strings["lavfi-complex"]!.contains("g=7.000000000"), "single-track rollback reconstructs the latest runtime EQ gains")
print("Scoped restoration/reset regressions complete: \(checks) total checks.")

resetRuntime.scopedTrackSettings.audio[1]?.gains[2] = 6
let zeroForReset = Array(repeating: 0.0, count: 10)
_ = resetRuntime.refreshTrackAudioEQ(id: 1, previous: zeroForReset, gains: resetRuntime.scopedTrackSettings.audio[1]!.gains, audioRollback: [1: AudioTrackProcessing(delay: 0.5)])
resetRuntime.masterDelay = 1.25; resetRuntime.masterEQ[4] = 4
resetRuntime.scopedTrackSettings.setTarget(1, for: .audioEQ)
resetRuntime.resetTrackSettings(.audioEQ)
check(resetRuntime.masterEQ[4] == 4 && resetRuntime.masterDelay == 1.25 && resetRuntime.scopedTrackSettings.audio[1]?.delay == 0.5, "selected EQ reset preserves Master EQ and both delays")
check(resetRuntime.mpv.equalizerGains[ProcessedAudioGraph.equalizerTarget(trackID: 1, band: 2)] == "0.0", "selected EQ reset clears the selected engine runtime gains")
let inactiveReset = PlayerCore()
_ = inactiveReset.setAudioTracks([])
var inactiveProfile = AudioTrackProcessing(); inactiveProfile.gains[3] = 8
inactiveReset.scopedTrackSettings.audio[1] = inactiveProfile
inactiveReset.masterEQ[1] = 3
inactiveReset.scopedTrackSettings.setTarget(1, for: .audioEQ)
inactiveReset.resetTrackSettings(.audioEQ)
check(inactiveReset.scopedTrackSettings.audio.isEmpty && inactiveReset.masterEQ[1] == 3 && inactiveReset.info.activeTrackIDs(.audio).isEmpty, "selected inactive-track reset preserves Master and No audio")
print("Scoped group reset checks complete: \(checks) total checks.")

var lutVideo = VideoTrackProcessing()
lutVideo.lutPath = "/fixture.cube"
lutVideo.rotation = 90
scopePlayer.scopedTrackSettings.video[1] = lutVideo
scopePlayer.mpv.filters = [MPVFilter(label: "lyina_lut"), MPVFilter(label: "unrelated")]
scopePlayer.scopedTrackSettings.setTarget(1, for: .videoColor)
scopePlayer.resetTrackSettings(.videoColor)
check(scopePlayer.scopedTrackSettings.video[1]?.lutPath == nil && scopePlayer.scopedTrackSettings.video[1]?.rotation == 90,
      "actual color reset clears the per-track LUT and preserves geometry")
check(scopePlayer.mpv.filters.map(\.label) == ["lyina_lut", "unrelated"],
      "selected-track Color reset retains the Output LUT")
scopePlayer.scopedTrackSettings.setTarget(0, for: .videoColor)
scopePlayer.resetTrackSettings(.videoColor)
check(scopePlayer.mpv.filters.map(\.label) == ["unrelated"], "Output Color reset removes only its own LUT")

// Compact targets follow the visible row order while keeping stable editing IDs.
let compactPlayer = PlayerCore()
for group in TrackSettingsGroup.allCases {
  let popup = TrackSettingsPopUp(player:compactPlayer,group:group)
  let type: MPVTrack.TrackType = group.isAudio ? .audio : .video
  let ids = compactPlayer.info.trackList(type).map(\.id)
  let selected = ids.last!
  compactPlayer.scopedTrackSettings.setTarget(selected, for: group)
  if group.isAudio { compactPlayer.info.audioTrackOrder = ids.reversed() }
  else { compactPlayer.info.videoTrackOrder = ids.reversed() }
  let beforeWrites = compactPlayer.mpv.writes
  compactPlayer.postNotification(.iinaTrackOrderChanged)
  let items = popup.itemArray.filter { $0.tag > 0 }
  check(items.map(\.title) == ids.indices.map { "Track \($0 + 1)" }, "every editing group uses compact positional track labels")
  check(items.map(\.tag) == ids && popup.selectedTag() == selected,
        "popup ignores obsolete cached order and preserves its editing target by ID")
  check(compactPlayer.mpv.writes == beforeWrites, "renumbering popup targets does not change playback or processing")
}
compactPlayer.nextFile()
check(compactPlayer.info.audioTrackOrder.isEmpty && compactPlayer.info.videoTrackOrder.isEmpty,
      "both display orders reset with the media session")
print("Compact targets and overlay checks complete: \(checks) total checks.")

// One editing context per media type; each group retains its own reset scope.
let sharedPlayer = PlayerCore()
let audioContext = TrackSettingsPopUp(player: sharedPlayer, group: .audioDelay)
let videoContext = TrackSettingsPopUp(player: sharedPlayer, group: .videoGeometry)
audioContext.selectItem(withTag: 3)
_ = audioContext.sendAction(audioContext.action!, to: audioContext.target)
videoContext.selectItem(withTag: 2)
_ = videoContext.sendAction(videoContext.action!, to: videoContext.target)
check(sharedPlayer.scopedTrackSettings.target(.audioDelay) == 3 && sharedPlayer.scopedTrackSettings.target(.audioEQ) == 3,
      "audio context routes Delay and EQ to the same stable track ID")
check(sharedPlayer.scopedTrackSettings.target(.videoGeometry) == 2 && sharedPlayer.scopedTrackSettings.target(.videoColor) == 2,
      "video context routes geometry, color and LUT to the same stable track ID")
check(sharedPlayer.info.activeTrackIDs(.audio) == Set([1]) && sharedPlayer.info.activeTrackIDs(.video) == Set([1]),
      "shared context selections leave playback membership untouched")
var sharedProfile = AudioTrackProcessing(); sharedProfile.delay = 0.75; sharedProfile.gains[2] = 4
sharedPlayer.scopedTrackSettings.audio[3] = sharedProfile
sharedPlayer.scopedTrackSettings.video[2] = VideoTrackProcessing(rotation: 90, brightness: 20)
let audioEQActions = TrackSettingsGroupReset(player: sharedPlayer, group: .audioEQ)
audioEQActions.performClick(nil)
check(sharedPlayer.scopedTrackSettings.audio[3]?.gains.allSatisfy({ $0 == 0 }) == true
      && sharedPlayer.scopedTrackSettings.audio[3]?.delay == 0.75,
      "EQ group button resets the selected target while retaining Delay")
check(sharedPlayer.scopedTrackSettings.audioTarget == 3 && sharedPlayer.scopedTrackSettings.videoTarget == 2,
      "group reset preserves both shared editing contexts")
let geometryActions = TrackSettingsGroupReset(player: sharedPlayer, group: .videoGeometry)
geometryActions.performClick(nil)
check(sharedPlayer.scopedTrackSettings.video[2]?.rotation == 0 && sharedPlayer.scopedTrackSettings.video[2]?.brightness == 20
      && sharedPlayer.scopedTrackSettings.videoTarget == 2,
      "geometry group button resets geometry only and retains video context")
sharedPlayer.mainWindow.interactiveMode.isActive = true
sharedPlayer.postNotification(.iinaTrackSettingsChanged)
videoContext.selectItem(withTag: 1)
_ = videoContext.sendAction(videoContext.action!, to: videoContext.target)
check(!videoContext.isEnabled && !geometryActions.isEnabled && audioContext.isEnabled
      && sharedPlayer.scopedTrackSettings.videoTarget == 2,
      "source crop locks video target and group actions without locking audio")
sharedPlayer.mainWindow.interactiveMode.isActive = false
sharedPlayer.info.audioTracks.removeAll { $0.id == 3 }
sharedPlayer.postNotification(.iinaTracklistChanged)
check(sharedPlayer.scopedTrackSettings.audioTarget == 0 && sharedPlayer.scopedTrackSettings.videoTarget == 2
      && audioContext.selectedTag() == 0,
      "disappearing selected track falls back to Master for the whole audio context")
print("Shared processing contexts complete: \(checks) total checks.")

// Every direct Reset targets the current Configure selection only.
let resetScopePlayer = PlayerCore()
resetScopePlayer.mpv.supportsPersistentMixer = true
resetScopePlayer.prepareMixer()
resetScopePlayer.masterDelay = 1.5
resetScopePlayer.masterEQ = Array(repeating: 3, count: 10)
resetScopePlayer.scopedTrackSettings.audio[1] = AudioTrackProcessing(delay: 0.5, gains: Array(repeating: 2, count: 10))
resetScopePlayer.scopedTrackSettings.audio[2] = AudioTrackProcessing(delay: -0.5, gains: Array(repeating: 5, count: 10))
resetScopePlayer.scopedTrackSettings.video[1] = VideoTrackProcessing(rotation: 90, brightness: 15, lutPath: "/tmp/reset-first.cube")
resetScopePlayer.scopedTrackSettings.video[2] = VideoTrackProcessing(rotation: 180, brightness: 25, lutPath: "/tmp/reset-second.cube")
resetScopePlayer.scopedTrackSettings.setTarget(2, for: .audioDelay)
resetScopePlayer.scopedTrackSettings.setTarget(2, for: .videoGeometry)
let resetPlayback = (resetScopePlayer.info.activeTrackIDs(.audio), resetScopePlayer.info.activeTrackIDs(.video))
func invokeReset(_ button: TrackSettingsGroupReset) { button.performClick(nil) }
let delayReset = TrackSettingsGroupReset(player: resetScopePlayer, group: .audioDelay)
let eqReset = TrackSettingsGroupReset(player: resetScopePlayer, group: .audioEQ)
let geometryResetMenu = TrackSettingsGroupReset(player: resetScopePlayer, group: .videoGeometry)
let colorReset = TrackSettingsGroupReset(player: resetScopePlayer, group: .videoColor)
let stateBeforeReset = resetScopePlayer.scopedTrackSettings
let writesBeforeReset = resetScopePlayer.mpv.writes
for button in [delayReset, eqReset, geometryResetMenu, colorReset] {
  check(button.menu == nil && button.action != nil && button.resetContextMenu?().items.count == 2, "Reset keeps a direct primary action and two context choices")
}
check(resetScopePlayer.scopedTrackSettings.audio == stateBeforeReset.audio
      && resetScopePlayer.scopedTrackSettings.video == stateBeforeReset.video
      && resetScopePlayer.mpv.writes == writesBeforeReset,
      "constructing Reset buttons never changes profiles or engine state")
invokeReset(delayReset)
check(resetScopePlayer.scopedTrackSettings.audio[2]?.delay == 0
      && resetScopePlayer.scopedTrackSettings.audio[2]?.gains[0] == 5
      && resetScopePlayer.scopedTrackSettings.audio[1]?.delay == 0.5
      && resetScopePlayer.masterDelay == 1.5,
      "selected-track Delay reset preserves other tracks, EQ and Master")
invokeReset(eqReset)
check(resetScopePlayer.scopedTrackSettings.audio[2] == nil
      && resetScopePlayer.scopedTrackSettings.audio[1]?.gains[0] == 2
      && resetScopePlayer.masterEQ[0] == 3,
      "selected-track EQ reset preserves other tracks and Master, dropping only a neutral profile")
invokeReset(geometryResetMenu)
check(resetScopePlayer.scopedTrackSettings.video[2]?.rotation == 0
      && resetScopePlayer.scopedTrackSettings.video[2]?.brightness == 25
      && resetScopePlayer.scopedTrackSettings.video[2]?.lutPath == "/tmp/reset-second.cube"
      && resetScopePlayer.scopedTrackSettings.video[1]?.rotation == 90,
      "selected-track Geometry reset preserves its Color/LUT and other sources")
resetScopePlayer.mpv.filters = [MPVFilter(label: "lyina_lut"), MPVFilter(label: "unrelated")]
invokeReset(colorReset)
check(resetScopePlayer.scopedTrackSettings.video[2] == nil
      && resetScopePlayer.scopedTrackSettings.video[1]?.brightness == 15
      && resetScopePlayer.mpv.filters.map(\.label) == ["lyina_lut", "unrelated"],
      "selected-track Color reset clears only its LUT/colors and retains Output LUT")
resetScopePlayer.scopedTrackSettings.setTarget(0, for: .audioDelay)
invokeReset(delayReset)
check(resetScopePlayer.masterDelay == 0 && resetScopePlayer.scopedTrackSettings.audio[1]?.delay == 0.5,
      "Master-only Delay reset leaves individual overrides intact")
invokeReset(eqReset)
check(resetScopePlayer.masterEQ.allSatisfy { $0 == 0 }
      && resetScopePlayer.scopedTrackSettings.audio[1]?.gains[0] == 2,
      "Master-only EQ reset leaves individual overrides intact")
resetScopePlayer.scopedTrackSettings.setTarget(0, for: .videoColor)
invokeReset(colorReset)
check(resetScopePlayer.mpv.filters.map(\.label) == ["unrelated"]
      && resetScopePlayer.scopedTrackSettings.video[1]?.lutPath == "/tmp/reset-first.cube",
      "Output-only Color reset removes only the owned Output LUT")
resetScopePlayer.scopedTrackSettings.setTarget(1, for: .audioEQ)
invokeReset(eqReset)
check(resetScopePlayer.scopedTrackSettings.audio[1]?.gains.allSatisfy { $0 == 0 } == true
      && resetScopePlayer.scopedTrackSettings.audio[1]?.delay == 0.5
      && resetScopePlayer.scopedTrackSettings.audioTarget == 1,
      "direct EQ reset remains group-local and preserves the selected target")
check(resetScopePlayer.info.activeTrackIDs(.audio) == resetPlayback.0
      && resetScopePlayer.info.activeTrackIDs(.video) == resetPlayback.1,
      "direct group resets leave playback membership unchanged")
resetScopePlayer.scopedTrackSettings.setTarget(1, for: .videoGeometry)
resetScopePlayer.mpv.failures = 1
invokeReset(geometryResetMenu)
check(resetScopePlayer.scopedTrackSettings.video[1]?.rotation == 90,
      "failed selected-track graph replacement restores the previous source settings")
resetScopePlayer.mainWindow.interactiveMode.isActive = true
resetScopePlayer.postNotification(.iinaTrackSettingsChanged)
invokeReset(geometryResetMenu)
check(!geometryResetMenu.isEnabled && resetScopePlayer.scopedTrackSettings.video[1]?.rotation == 90,
      "Custom Crop blocks video group reset")
// The context menu is descriptive until one of its actions is selected.
let globalResetPlayer = PlayerCore()
globalResetPlayer.mpv.supportsPersistentMixer = true
globalResetPlayer.prepareMixer()
globalResetPlayer.masterDelay = 1.5
globalResetPlayer.masterEQ = Array(repeating: 3, count: 10)
for id in [1, 2, 3] {
  globalResetPlayer.scopedTrackSettings.audio[id] = AudioTrackProcessing(delay: Double(id) / 2, gains: Array(repeating: Double(id), count: 10))
}
for id in [1, 2] {
  globalResetPlayer.scopedTrackSettings.video[id] = VideoTrackProcessing(rotation: 90 * id, brightness: 10 * id, lutPath: "/fixture-\(id).cube")
}
globalResetPlayer.scopedTrackSettings.setTarget(2, for: .audioEQ)
globalResetPlayer.scopedTrackSettings.setTarget(2, for: .videoGeometry)
let beforeContextWrites = globalResetPlayer.mpv.writes
let contextEQ = TrackSettingsGroupReset(player: globalResetPlayer, group: .audioEQ)
let contextMenu = contextEQ.resetContextMenu!()
check(contextMenu.items.count == 2 && contextMenu.items[0].action != contextMenu.items[1].action && globalResetPlayer.mpv.writes == beforeContextWrites,
      "building the two-item Reset context menu performs no reset")
let localContext = contextMenu.items[0]
_ = NSApp.sendAction(localContext.action!, to: localContext.target, from: localContext)
check(globalResetPlayer.scopedTrackSettings.audio[2]?.gains.allSatisfy { $0 == 0 } == true && globalResetPlayer.scopedTrackSettings.audio[1]?.gains[0] == 1 && globalResetPlayer.masterEQ[0] == 3,
      "context Reset Track retains the same local behavior as left click")
func invokeGlobalContext(_ group: TrackSettingsGroup) {
  let button = TrackSettingsGroupReset(player: globalResetPlayer, group: group)
  let item = button.resetContextMenu!().items[1]
  _ = NSApp.sendAction(item.action!, to: item.target, from: item)
}
invokeGlobalContext(.audioEQ)
check(globalResetPlayer.scopedTrackSettings.audio.values.allSatisfy { $0.gains.allSatisfy { $0 == 0 } } && globalResetPlayer.masterEQ.allSatisfy { $0 == 0 } && globalResetPlayer.scopedTrackSettings.audio[3]?.delay == 1.5 && globalResetPlayer.masterDelay == 1.5,
      "context Reset All Tracks clears every EQ including inactive sources and Master, preserving Delay")
globalResetPlayer.mpv.filters = [MPVFilter(label: "lyina_lut"), MPVFilter(label: "unrelated")]
invokeGlobalContext(.videoColor)
check(globalResetPlayer.scopedTrackSettings.video.values.allSatisfy { $0.lutPath == nil && $0.brightness == 0 } && globalResetPlayer.scopedTrackSettings.video[2]?.rotation == 180 && globalResetPlayer.mpv.filters.map(\.label) == ["unrelated"],
      "context Reset All Tracks clears source and Output color/LUT while preserving Geometry")
invokeGlobalContext(.audioDelay)
check(globalResetPlayer.scopedTrackSettings.audio.isEmpty && globalResetPlayer.masterDelay == 0 && globalResetPlayer.scopedTrackSettings.video[1]?.rotation == 90,
      "global Delay reset clears all audio overrides and Master without touching video")
invokeGlobalContext(.videoGeometry)
check(globalResetPlayer.scopedTrackSettings.video.isEmpty && globalResetPlayer.scopedTrackSettings.audioTarget == 2 && globalResetPlayer.scopedTrackSettings.videoTarget == 2 && globalResetPlayer.info.activeTrackIDs(.audio) == [1] && globalResetPlayer.info.activeTrackIDs(.video) == [1],
      "global Geometry reset preserves Configure targets and playback membership")
globalResetPlayer.scopedTrackSettings.video[1] = VideoTrackProcessing(rotation: 90)
globalResetPlayer.scopedTrackSettings.video[2] = VideoTrackProcessing(rotation: 180)
check(globalResetPlayer.refreshTrackProcessing(.video), "install processed video before testing global reset rollback")
globalResetPlayer.mpv.failures = 1
globalResetPlayer.resetTrackSettings(.videoGeometry, allTracks: true)
check(globalResetPlayer.scopedTrackSettings.video[1]?.rotation == 90 && globalResetPlayer.scopedTrackSettings.video[2]?.rotation == 180,
      "failed global reset restores every source profile")
print("Current Configure reset checks complete: \(checks) total checks.")

// A stale enter event or native cell highlight cannot light Reset away from the pointer.
final class ResetPointerWindow: NSWindow {
  var pointer = NSPoint(x: -100, y: -100)
  var key = true
  override var isKeyWindow: Bool { key }
  override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
}
let resetPointerWindow = ResetPointerWindow(contentRect: NSRect(x: -1000, y: -1000, width: 200, height: 100),
                                          styleMask: .borderless, backing: .buffered, defer: false)
resetPointerWindow.isReleasedWhenClosed = false
let pointerReset = TrackSettingsGroupReset(player: scopePlayer, group: .audioDelay)
pointerReset.translatesAutoresizingMaskIntoConstraints = true
pointerReset.frame = NSRect(x: 20, y: 20, width: 60, height: 24)
resetPointerWindow.contentView!.addSubview(pointerReset)
resetPointerWindow.orderFrontRegardless()
func resetPixels() -> Data {
  let image = NSImage(size: pointerReset.bounds.size)
  image.lockFocus()
  NSColor.gray.setFill(); pointerReset.bounds.fill()
  pointerReset.draw(pointerReset.bounds)
  image.unlockFocus()
  return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
}
let quietReset = resetPixels()
pointerReset.highlight(true)
check(resetPixels() == quietReset, "Reset ignores a native highlighted cell while the pointer is outside")
pointerReset.highlight(false)
let staleEnter = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
  windowNumber: resetPointerWindow.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
pointerReset.mouseEntered(with: staleEnter)
check(resetPixels() == quietReset, "Reset ignores stale mouse-enter events after scrolling or switching panes")
resetPointerWindow.pointer = pointerReset.convert(NSPoint(x: 30, y: 12), to: nil)
check(resetPixels() != quietReset, "Reset highlights under the current pointer")
resetPointerWindow.key = false
check(resetPixels() == quietReset, "Reset is quiet in an inactive window")
resetPointerWindow.key = true
resetPointerWindow.pointer = NSPoint(x: -100, y: -100)
pointerReset.updateTrackingAreas()
check(resetPixels() == quietReset, "Reset clears after geometry changes without needing a mouse-exit event")
resetPointerWindow.close()
print("Reset hover checks complete: \(checks) total checks.")
