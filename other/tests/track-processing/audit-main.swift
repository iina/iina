// UX01: AppKit ends a pending field edit synchronously inside the target action.
final class PendingTargetEdit: NSObject {
  let player: PlayerCore
  var committed = false
  init(_ player: PlayerCore) { self.player = player }
  @objc func commit(_ sender: NSTextField) {
    committed = true
    player.scopedTrackSettings.audio[player.scopedTrackSettings.audioTarget] = AudioTrackProcessing(delay: sender.doubleValue)
    player.postNotification(.iinaTrackSettingsChanged)
  }
}
let pendingPlayer = PlayerCore()
pendingPlayer.scopedTrackSettings.setTarget(1, for: .audioDelay)
let pendingPopup = TrackSettingsPopUp(player: pendingPlayer, group: .audioDelay)
let pendingInput = NSTextField(frame: NSRect(x: 20, y: 20, width: 80, height: 24))
let pendingTarget = PendingTargetEdit(pendingPlayer)
pendingInput.target = pendingTarget
pendingInput.action = #selector(PendingTargetEdit.commit(_:))
pendingInput.cell?.sendsActionOnEndEditing = true
let pendingWindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 360, height: 200),
                             styleMask: [.titled], backing: .buffered, defer: false)
pendingWindow.isReleasedWhenClosed = false
pendingWindow.contentView!.addSubview(pendingInput)
pendingWindow.contentView!.addSubview(pendingPopup)
pendingWindow.makeFirstResponder(pendingInput)
pendingInput.currentEditor()?.string = "0.37"
pendingPopup.selectItem(withTag: 2)
_ = pendingPopup.sendAction(pendingPopup.action!, to: pendingPopup.target)
check(pendingTarget.committed && pendingPlayer.scopedTrackSettings.audio[1]?.delay == 0.37,
      "target switching commits pending input to the old source")
check(pendingPlayer.scopedTrackSettings.audioTarget == 2 && pendingPopup.selectedTag() == 2,
      "a synchronous field-commit notification cannot discard the requested target")
pendingWindow.makeFirstResponder(pendingInput)
pendingInput.currentEditor()?.string = "0.42"
pendingTarget.committed = false
pendingPopup.menuNeedsUpdate(pendingPopup.menu!)
check(pendingTarget.committed && pendingPlayer.scopedTrackSettings.audio[2]?.delay == 0.42
      && pendingPlayer.scopedTrackSettings.audioTarget == 2,
      "opening the native target menu commits to the old target before tracking begins")
pendingPopup.selectItem(withTag: 3)
_ = pendingPopup.sendAction(pendingPopup.action!, to: pendingPopup.target)
check(pendingPlayer.scopedTrackSettings.audioTarget == 3,
      "the native menu retains the chosen source after its opening commit")
pendingWindow.close()

// UX02/UX05/UX07: logical membership and visible order, including processed solos.
let orderedCycle = PlayerCore()
orderedCycle.info.audioTrackOrder = [1, 3, 4, 2]
_ = orderedCycle.setAudioTracks([1])
orderedCycle.cycleAudioTrack()
check(orderedCycle.info.activeTrackIDs(.audio) == [2], "audio Cycle follows source order despite an obsolete cached order")
orderedCycle.cycleAudioTrack(); orderedCycle.cycleAudioTrack(); orderedCycle.cycleAudioTrack()
check(orderedCycle.info.activeTrackIDs(.audio) == [1], "audio Cycle wraps in displayed order")
orderedCycle.info.videoTrackOrder = [3, 2, 1]
orderedCycle.scopedTrackSettings.video[2] = VideoTrackProcessing(rotation: 90)
_ = orderedCycle.setVideoTracks([2])
check(orderedCycle.info.layeredVideoTrackIDs == [2], "processed solo uses a one-source graph")
if case .track(let track, let position) = orderedCycle.osdMessages.last {
  check(track.id == 2 && position == 2, "processed solo OSD identifies its current displayed position")
} else { preconditionFailure("processed solo must show a source instead of a layer count") }
orderedCycle.cycleVideoTrack()
check(orderedCycle.info.activeTrackIDs(.video) == [3], "processed video Cycle advances in source order")
orderedCycle.cycleVideoTrack()
check(orderedCycle.info.activeTrackIDs(.video) == [1], "video Cycle wraps in source order")
if case .track(let track, let position) = orderedCycle.osdMessages.last {
  check(track.id == 1 && position == 1, "video OSD numbers follow the fixed source order")
} else { preconditionFailure("solo OSD missing") }
_ = orderedCycle.setAudioTracks([2])
if case .track(let track, let position) = orderedCycle.osdMessages.last {
  check(track.id == 2 && position == 2, "audio OSD follows the fixed source order")
} else { preconditionFailure("audio OSD missing") }

// UX04: the real graph owner rejects Save, restores the raw preview, then retries.
let cropTransaction = PlayerCore()
_ = cropTransaction.setAudioTracks([2, 4])
_ = cropTransaction.setVideoTracks([2, 3], order: [3, 2, 1])
let cropAudio = cropTransaction.info.activeTrackIDs(.audio)
let cropProfile = VideoTrackProcessing(brightness: 24)
cropTransaction.scopedTrackSettings.video[1] = cropProfile
var cropPreview = PlayerCore.CropPreview(id: 1)
cropPreview.originalTrack = cropProfile
cropPreview.activeVideo = [3, 2]
cropPreview.order = [3, 2, 1]
cropPreview.masterVF = "@output:unrelated"
cropPreview.masterAspect = "4:3"
cropPreview.masterRotation = "90"
cropTransaction.scopedCropPreview = cropPreview
cropTransaction.mainWindow.interactiveMode.isActive = true
_ = cropTransaction.refreshTrackProcessing(.video)
let requestedCrop = TrackVideoCrop(x: 10, y: 20, width: 200, height: 100)
cropTransaction.mpv.graphFailures = 1
check(!cropTransaction.finishScopedCustomCrop(crop: requestedCrop, applying: true), "rejected source Crop Save reports failure")
check(cropTransaction.mainWindow.interactiveMode.isActive && cropTransaction.scopedCropPreview?.id == 1
      && cropTransaction.scopedTrackSettings.video[1] == cropProfile,
      "rejected Save keeps the editor context and rolls back only the proposed source crop")
check(cropTransaction.mpv.getString("lavfi-complex")?.contains("[vid1]null[vo]") == true
      && cropTransaction.mpv.getString("vf") == "" && cropTransaction.mpv.getString("video-aspect-override") == "-1",
      "rejected Save restores the untransformed source preview for another edit")
check(cropTransaction.info.activeTrackIDs(.audio) == cropAudio, "source Crop failure preserves simultaneous audio")
check(cropTransaction.finishScopedCustomCrop(crop: requestedCrop, applying: true), "source Crop retries successfully")
check(cropTransaction.scopedTrackSettings.video[1]?.cropDescription == "Custom",
      "source Crop publishes Custom for the selected track after a successful Save")
check(cropTransaction.scopedCropPreview == nil && cropTransaction.scopedTrackSettings.video[1]?.crop == requestedCrop
      && cropTransaction.info.layeredVideoTrackIDs == [3, 2],
      "successful retry commits the crop and restores the previous video composition")
check(cropTransaction.mpv.getString("vf") == cropPreview.masterVF
      && cropTransaction.mpv.getString("video-aspect-override") == "4:3"
      && cropTransaction.mpv.getString("video-rotate") == "90",
      "successful source Crop restores Output processing")

// UX03: dormant sessions are included, and filesystem failure can undo detachment.
let lutSessions = PlayerCore()
let lutA = URL(fileURLWithPath: "/A.mkv"), lutB = URL(fileURLWithPath: "/B.mkv")
var savedLUT = MediaVideoGeometryState()
savedLUT.video[2] = VideoTrackProcessing(rotation: 90, brightness: 31, lutPath: "/managed/deleted.cube")
savedLUT.activeVideo = [2]; savedLUT.videoOrder = [3, 2, 1]; savedLUT.videoTarget = 2
lutSessions.videoGeometrySession[lutA] = savedLUT
savedLUT.video[2]?.lutPath = "/managed/retained.cube"
lutSessions.videoGeometrySession[lutB] = savedLUT
let undoLUT = lutSessions.detachSavedVideoLUT(atPath: "/managed/deleted.cube")
check(lutSessions.videoGeometrySession[lutA]?.video[2]?.lutPath == nil
      && lutSessions.videoGeometrySession[lutB]?.video[2]?.lutPath == "/managed/retained.cube",
      "LUT detachment reaches dormant media while preserving other library entries")
undoLUT()
check(lutSessions.videoGeometrySession[lutA]?.video[2]?.lutPath == "/managed/deleted.cube", "failed library removal can restore dormant LUT references")
_ = lutSessions.detachSavedVideoLUT(atPath: "/managed/deleted.cube")
lutSessions.videoGeometryMediaURL = lutA
lutSessions.restoreVideoSession()
check(lutSessions.scopedTrackSettings.video[2]?.lutPath == nil
      && lutSessions.scopedTrackSettings.video[2]?.brightness == 31
      && lutSessions.scopedTrackSettings.video[2]?.rotation == 90
      && lutSessions.scopedTrackSettings.videoTarget == 2,
      "returning to a file after LUT removal retains its other source settings and target")

// UX09: import uses the same graph owner as explicit membership changes.
var externalImportGraphs: [[String: Any]] = []
for persistentMixer in [false, true] {
  let addedAudio = PlayerCore()
  if persistentMixer { addedAudio.mpv.supportsPersistentMixer = true; addedAudio.prepareMixer() }
  _ = addedAudio.setAudioTracks([1, 3])
  addedAudio.scopedTrackSettings.audio[1] = AudioTrackProcessing(delay: 0.2)
  _ = addedAudio.refreshTrackProcessing(.audio)
  _ = addedAudio.setVideoTracks([2, 3], order: [3, 2, 1])
  let beforeImportGraph = addedAudio.mpv.getString("lavfi-complex") ?? ""
  addedAudio.loadExternalAudioFile(URL(fileURLWithPath: "/external.wav"))
  externalImportGraphs.append(["persistent": persistentMixer, "before": beforeImportGraph,
    "after": addedAudio.mpv.getString("lavfi-complex") ?? ""])
  check(addedAudio.info.activeTrackIDs(.audio) == [1, 3, 5]
        && addedAudio.mpv.getString("lavfi-complex")?.contains("[aid5]") == true,
        "external audio joins the active selection with persistent mixer = \(persistentMixer)")
  check(addedAudio.info.layeredVideoTrackIDs == [3, 2] && addedAudio.scopedTrackSettings.audio[1]?.delay == 0.2,
        "external audio preserves video order and existing source processing")
  let before = addedAudio.info.activeTrackIDs(.audio)
  addedAudio.mpv.additionFails = true
  addedAudio.loadExternalAudioFile(URL(fileURLWithPath: "/invalid.wav"))
  check(addedAudio.info.activeTrackIDs(.audio) == before && addedAudio.info.audioTracks.count == 5,
        "failed import preserves membership and source list")
}
if CommandLine.arguments.count > 1 {
  let output = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent()
    .appendingPathComponent("external-audio-graphs.json")
  try! JSONSerialization.data(withJSONObject: externalImportGraphs, options: [.prettyPrinted, .sortedKeys]).write(to: output)
}
for target in [0, 1] {
  let blockedOpen = PlayerCore()
  blockedOpen.scopedTrackSettings.setTarget(target, for: .videoGeometry)
  blockedOpen.mainWindow.interactiveMode.ownerAvailable = false
  blockedOpen.mpv.strings["vf"] = "@output:unrelated"
  blockedOpen.mpv.strings["video-aspect-override"] = "4:3"
  let engineBeforeOpen = blockedOpen.mpv.strings
  let selectionBeforeOpen = blockedOpen.mpv.integers
  for _ in 0..<3 { blockedOpen.openScopedCustomCrop() }
  check(blockedOpen.scopedCropPreview == nil && !blockedOpen.mainWindow.interactiveMode.isActive &&
        blockedOpen.mainWindow.preparedWindowReferences == 0 && blockedOpen.mpv.strings == engineBeforeOpen &&
        blockedOpen.mpv.integers == selectionBeforeOpen && blockedOpen.mpv.graphWrites == 0,
        "rejected Output/source Crop entry cannot prepare layout or alter filters, graph or selection")
}
let allowedSourceOpen = PlayerCore()
allowedSourceOpen.scopedTrackSettings.setTarget(1, for: .videoGeometry)
allowedSourceOpen.openScopedCustomCrop()
check(allowedSourceOpen.mainWindow.interactiveMode.isActive && allowedSourceOpen.scopedCropPreview?.id == 1,
      "ordinary source Crop still prepares the preview and enters the editor")
check(allowedSourceOpen.finishScopedCustomCrop(), "ordinary source Crop can restore its preview")

let ownedCrop = PlayerCore()
_ = ownedCrop.setVideoTracks([2, 3], order: [3, 2, 1])
var ownedPreview = PlayerCore.CropPreview(id: 1)
ownedPreview.activeVideo = [3, 2]; ownedPreview.order = [3, 2, 1]
ownedCrop.scopedCropPreview = ownedPreview
ownedCrop.mainWindow.interactiveMode.isActive = true
check(ownedCrop.refreshTrackProcessing(.video), "internal source Crop refresh remains available while editing")
let ownedOrder = ownedCrop.info.videoTrackOrder
let ownedGraph = ownedCrop.mpv.getString("lavfi-complex")
let ownedNativeSelections = ownedCrop.mpv.integers
let ownedGraphWrites = ownedCrop.mpv.graphWrites
for _ in 0..<3 {
  check(!ownedCrop.setVideoTracks([2], order: [2, 1, 3]) && !ownedCrop.setVideoTracks([]),
        "public video selection rejects replacement and None during source Crop")
  ownedCrop.cycleVideoTrack()
  ownedCrop.setTrack(2, forType: .video)
  ownedCrop.loadExternalVideoFile(URL(fileURLWithPath: "/editor-video.mkv"))
}
check(ownedCrop.info.videoTrackOrder == ownedOrder && ownedCrop.mpv.getString("lavfi-complex") == ownedGraph &&
      ownedCrop.mpv.integers == ownedNativeSelections && ownedCrop.mpv.graphWrites == ownedGraphWrites &&
      ownedCrop.info.activeTrackIDs(.video) == [1] && ownedCrop.mpv.videoAdditions == 0,
      "reentrant Cycle/plugin selection cannot mutate Crop graph, source order or native membership")
check(ownedCrop.finishScopedCustomCrop() && ownedCrop.info.activeTrackIDs(.video) == [2, 3],
      "internal Crop exit restores the saved composition despite public selection rejection")
ownedCrop.mainWindow.interactiveMode.isActive = false
check(ownedCrop.setVideoTracks([2]) && ownedCrop.info.activeTrackIDs(.video) == [2],
      "normal public video selection resumes after Crop ownership ends")
ownedCrop.loadExternalVideoFile(URL(fileURLWithPath: "/ordinary-video.mkv"))
check(ownedCrop.mpv.videoAdditions == 1, "external video loading resumes after Crop ownership ends")
ownedCrop.info.state.active = false
ownedCrop.loadExternalVideoFile(URL(fileURLWithPath: "/stopped-video.mkv"))
check(ownedCrop.mpv.videoAdditions == 1, "stopped playback cannot attach an external video")
let unavailableSelection = PlayerCore()
_ = unavailableSelection.setAudioTracks([2, 3])
_ = unavailableSelection.setVideoTracks([2, 3], order: [3, 2, 1])
unavailableSelection.mpv.strings["lavfi-complex"] = "[vid1]null[vo]"
unavailableSelection.info.state.active = false
let unavailableAudio = unavailableSelection.info.mixedAudioTrackIDs
let unavailableVideo = unavailableSelection.info.layeredVideoTrackIDs
let unavailableOrder = unavailableSelection.info.videoTrackOrder
let unavailableNative = unavailableSelection.mpv.integers
let unavailableWrites = unavailableSelection.mpv.graphWrites
for _ in 0..<3 {
  check(!unavailableSelection.setAudioTracks([1]) &&
        !unavailableSelection.setVideoTracks([1], order: [1, 2, 3]),
        "unavailable playback rejects direct source selectors")
}
check(unavailableSelection.info.mixedAudioTrackIDs == unavailableAudio &&
      unavailableSelection.info.layeredVideoTrackIDs == unavailableVideo &&
      unavailableSelection.info.videoTrackOrder == unavailableOrder &&
      unavailableSelection.mpv.integers == unavailableNative &&
      unavailableSelection.mpv.graphWrites == unavailableWrites,
      "unavailable selectors cannot reconcile a foreign graph or mutate cached composition bookkeeping")
print("Audit correction regressions complete: \(checks) total checks.")
