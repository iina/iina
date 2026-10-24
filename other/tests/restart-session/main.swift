import Cocoa

var checks = 0
func expect(_ value: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  guard value() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
guard let testBundle = Bundle.main.bundleIdentifier, testBundle.hasPrefix("org.iina.tests.restart-session.") else {
  fatalError("Run inside the unique test bundle created by run.py")
}
let suiteName = "org.iina.tests.restart-session.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suiteName)!
defer {
  defaults.removePersistentDomain(forName: suiteName)
  UserDefaults.standard.removePersistentDomain(forName: testBundle)
}
let settings = SettingsWindow.default
let frame = AppRestartSession.Frame(NSRect(x: 125, y: 145, width: 740, height: 460))
func saved(_ suffix: String = "one", position: Double = 42.125, paused: Bool = true) -> AppRestartSession.Window {
  AppRestartSession.Window(mediaURL: "https://example.invalid/\(suffix).mp4",
    playlist: ["before.mp4", "https://example.invalid/\(suffix).mp4", "after.mp4", "before.mp4"],
    playlistIndex: 1, position: position, paused: paused, frame: frame, mainFrame: frame,
    musicMode: false, minimized: false, fullscreen: false, pictureInPicture: false)
}
func begin(_ windows: [AppRestartSession.Window]) -> [PlayerCore] {
  PlayerCore.playerCores = []
  settings.frontCount = 0
  AppRestartSession.restore(AppRestartSession.Snapshot(windows: windows), settings: settings)
  return PlayerCore.playerCores
}
func load(_ player: PlayerCore, windowReady: Bool = true, setupFinished: Bool = true, initialRestart: Bool = true) {
  player.info.trackSelectionGeneration += 1
  AppRestartSession.fileStarted(player)
  player.info.state = .loaded
  AppRestartSession.fileLoaded(player)
  if windowReady {
    AppRestartSession.applyWindowFrame(player)
    AppRestartSession.windowReady(player)
  }
  if setupFinished { AppRestartSession.fileSetupFinished(player) }
  if initialRestart { AppRestartSession.playbackRestarted(player) }
}
func restartSeek(_ player: PlayerCore, position: Double? = nil) {
  AppRestartSession.seekStarted(player)
  player.mpv.time = position ?? player.mpv.seekRequests.last!.0
  AppRestartSession.playbackRestarted(player)
}

// Recovery of a removed display preserves size while keeping titlebars reachable.
let survivingScreen = NSRect(x: -400, y: 20, width: 800, height: 580)
let oversizedFrame = NSRect(x: 5000, y: 5000, width: 1200, height: 1000)
let recovered = AppRestartSession.recoveredFrame(oversizedFrame, on: [survivingScreen])
expect(recovered.size == oversizedFrame.size, "display recovery preserves saved dimensions")
expect(recovered.maxY == survivingScreen.maxY && recovered.midX == survivingScreen.midX,
       "oversized removed-display window retains reachable centered titlebar")
expect(AppRestartSession.recoveredFrame(frame.rect, on: [NSRect(x: 0, y: 0, width: 2000, height: 1200)]) == frame.rect,
       "connected display preserves exact rectangle")
expect(AppRestartSession.recoveredFrame(frame.rect, on: []) == frame.rect, "no display does not invent geometry")

// Property-list model, version/size limits, malformed entry isolation and one-shot read.
let original = AppRestartSession.Snapshot(windows: [saved()])
let encoded = try PropertyListEncoder().encode(original)
expect(AppRestartSession.Snapshot.decode(encoded) == original, "lossless snapshot round trip")
expect(AppRestartSession.Snapshot.decode(encoded)?.windows.first?.playbackState == nil,
       "legacy window payload without processing state remains readable")
let editedOutput = PlayerCore()
editedOutput.restartOptionDefaults = ["hwdec": "auto", "brightness": "0", "contrast": "0"]
editedOutput.restartVideoFilterDefault = "startup-vf"
editedOutput.restartAudioFilterDefault = "startup-af"
editedOutput.mpv.strings = ["hwdec": "no", "brightness": "23", "contrast": "0", "vf": "edited-vf", "af": "edited-af"]
let editedOutputState = editedOutput.playbackStateForRestart()!
expect(editedOutputState.options == ["hwdec": "no", "brightness": "23"],
       "unchanged startup settings are omitted from the runtime handoff")
let newlyConfigured = PlayerCore()
newlyConfigured.restartOptionDefaults = ["hwdec": "videotoolbox", "brightness": "0", "contrast": "12"]
newlyConfigured.restartVideoFilterDefault = "newly-requested-vf"
newlyConfigured.restartAudioFilterDefault = "startup-af"
newlyConfigured.mpv.strings = ["hwdec": "videotoolbox", "brightness": "0", "contrast": "12", "vf": "newly-requested-vf", "af": "startup-af"]
newlyConfigured.restorePlaybackStateAfterRestart(editedOutputState)
expect(newlyConfigured.mpv.strings["hwdec"] == "videotoolbox" && newlyConfigured.mpv.strings["contrast"] == "12",
       "new initialization settings win over older decoder edits and unchanged startup controls")
expect(newlyConfigured.mpv.strings["brightness"] == "23" && newlyConfigured.mpv.strings["af"] == "edited-af",
       "deliberate per-window edits survive when the initialization baseline is unchanged")
expect(newlyConfigured.mpv.strings["vf"] == "newly-requested-vf",
       "changed startup filters take precedence over the old per-window filter chain")
let outputCropEditor = PlayerCore()
outputCropEditor.mpv.strings["vf"] = ""
outputCropEditor.mainWindow.isCropTransitionInProgress = true
outputCropEditor.mainWindow.interactiveMode.onExit = { discarding in
  outputCropEditor.mainWindow.transitionEvents.append("exit")
  if !discarding {
    outputCropEditor.mpv.strings["vf"] = "@iina_crop:crop=300:160:2:4"
    outputCropEditor.cropDescription = "Custom"
  }
}
expect(outputCropEditor.playbackStateForRestart()?.videoFilters == "@iina_crop:crop=300:160:2:4",
       "Restart capture exits the output crop editor by restoring its previously committed crop")
expect(outputCropEditor.mainWindow.transitionEvents == ["interrupt", "cancel", "exit"],
       "crop/geometry transitions settle before the editor restores its committed output")
let oldSelectionPolicy = PlayerCore()
oldSelectionPolicy.info.audioTracks = [MPVTrack(1, .audio, sourceID: 1), MPVTrack(2, .audio, sourceID: 2)]
oldSelectionPolicy.info.videoTracks = [MPVTrack(1, .video, sourceID: 1), MPVTrack(2, .video, sourceID: 2)]
oldSelectionPolicy.info.subTracks = [MPVTrack(1, .sub, sourceID: 1), MPVTrack(2, .sub, sourceID: 2)]
oldSelectionPolicy.mpv.integers = ["aid": 1, "vid": 1, "sid": 1, "secondary-sid": 0]
oldSelectionPolicy.restartSelectionDefaults = ["aid": "1", "vid": "1", "sid": "1", "alang": "en", "slang": "en"]
let oldSelectionState = oldSelectionPolicy.playbackStateForRestart()!
let newSelectionPolicy = PlayerCore()
newSelectionPolicy.info.audioTracks = oldSelectionPolicy.info.audioTracks
newSelectionPolicy.info.videoTracks = oldSelectionPolicy.info.videoTracks
newSelectionPolicy.info.subTracks = oldSelectionPolicy.info.subTracks
newSelectionPolicy.restartSelectionDefaults = ["aid": "2", "vid": "2", "sid": "2", "alang": "en", "slang": "en"]
newSelectionPolicy.mpv.integers = ["aid": 2, "vid": 2, "sid": 2, "secondary-sid": 0]
newSelectionPolicy.getSelectedTracks()
newSelectionPolicy.restorePlaybackStateAfterRestart(oldSelectionState)
expect(newSelectionPolicy.restoredMembership.last?.0 == [2] && newSelectionPolicy.restoredMembership.last?.1 == [2],
       "new aid/vid startup choices remain selected when no per-window track edit was made")
expect(newSelectionPolicy.info.sid == 2 && newSelectionPolicy.info.secondSid == 0,
       "new primary subtitle startup choice is not overwritten by the old role")
newSelectionPolicy.restartSelectionDefaults = oldSelectionPolicy.restartSelectionDefaults
newSelectionPolicy.restartSelectionDefaults["alang"] = "ja"
newSelectionPolicy.restartSelectionDefaults["slang"] = "ja"
newSelectionPolicy.mpv.integers["aid"] = 2; newSelectionPolicy.mpv.integers["sid"] = 2
newSelectionPolicy.getSelectedTracks()
newSelectionPolicy.restorePlaybackStateAfterRestart(oldSelectionState)
expect(newSelectionPolicy.restoredMembership.last?.0 == [2] && newSelectionPolicy.info.sid == 2,
       "changed audio/subtitle language policy keeps the new engine's selected sources")
var unknown = original; unknown.version = 2
let unknownData = try PropertyListEncoder().encode(unknown)
expect(AppRestartSession.Snapshot.decode(unknownData) == nil, "future version rejected")
expect(AppRestartSession.Snapshot.decode(Data("invalid".utf8)) == nil, "malformed payload rejected")
expect(AppRestartSession.Snapshot.decode(Data(repeating: 0, count: 16 * 1_024 * 1_024 + 1)) == nil, "oversize payload rejected")
expect(AppRestartSession.Snapshot(windows: Array(repeating: saved(), count: 129)).sanitized == nil, "unbounded window count rejected")
for value in [Double.nan, Double.infinity, -1, 1_000_000_001] {
  var invalid = saved(); invalid.position = value
  expect(invalid.sanitized == nil, "invalid time rejected \(value)")
}
for volume in [Double.nan, Double.infinity, -0.1, 1001] {
  var invalid = saved(); invalid.volume = volume
  expect(invalid.sanitized == nil, "invalid volume rejected \(volume)")
}
for speed in [Double.nan, Double.infinity, 0, 101] {
  var invalid = saved(); invalid.speed = speed
  expect(invalid.sanitized == nil, "invalid speed rejected \(speed)")
}
for invalidURL in ["stdin", "stdin://input", "fd://0", "memory://unsafe", "data:text/plain,unsafe", "relative.mp4"] {
  var invalid = saved(); invalid.mediaURL = invalidURL
  expect(invalid.sanitized == nil, "nonrestartable URL rejected \(invalidURL)")
}
var badFrame = saved(); badFrame.frame.width = 0
expect(badFrame.sanitized == nil, "zero-sized frame rejected")
badFrame.frame.width = 740; badFrame.mainFrame.x = .nan
expect(badFrame.sanitized == nil, "nonfinite hidden normal frame rejected")
var badPlaylist = saved(); badPlaylist.playlistIndex = 500
expect(badPlaylist.sanitized?.playlist == [badPlaylist.mediaURL], "bad index recovers current media")
badPlaylist = saved(); badPlaylist.playlist[1] = "https://example.invalid/different.mp4"
expect(badPlaylist.sanitized?.playlist == [badPlaylist.mediaURL], "mismatched in-bounds current index recovers current media")
badPlaylist = saved(); badPlaylist.playlist[0] = "bad\0entry"
expect(badPlaylist.sanitized?.playlistIndex == 0, "bad playlist entry recovers current media")
var music = saved(); music.musicMode = true; music.fullscreen = true; music.pictureInPicture = true
expect(music.sanitized?.fullscreen == false && music.sanitized?.pictureInPicture == false, "music mode clears incompatible modes")
expect(AppRestartSession.Snapshot(windows: [saved(), badFrame]).sanitized?.windows.count == 1, "bad window does not discard good window")
defaults.set(encoded, forKey: AppRestartSession.preferenceKey)
expect(AppRestartSession.consume(defaults: defaults) == original, "consume returns saved session")
expect(defaults.object(forKey: AppRestartSession.preferenceKey) == nil, "handoff removed before restoring")
expect(AppRestartSession.consume(defaults: defaults) == nil, "handoff consumed once")
defaults.set(Data("invalid".utf8), forKey: AppRestartSession.preferenceKey)
expect(AppRestartSession.consume(defaults: defaults) == nil && defaults.object(forKey: AppRestartSession.preferenceKey) == nil,
       "corrupt handoff removed rather than retried")

// Exercise real production Progress across every ordering of independent readiness events.
func permutations<T>(_ array: [T]) -> [[T]] {
  if array.isEmpty { return [[]] }
  return array.indices.flatMap { index in
    var rest = array; let first = rest.remove(at: index)
    return permutations(rest).map { [first] + $0 }
  }
}
for order in permutations([0, 1, 2]) {
  var progress = AppRestartSession.Progress()
  progress.loaded(seekRequired: true)
  progress.restarted()
  expect(!progress.complete(), "initial playback restart cannot satisfy explicit seek")
  for (offset, event) in order.enumerated() {
    switch event {
    case 0: progress.ready()
    case 1: progress.configured()
    default: progress.seeking(); progress.restarted()
    }
    expect(progress.complete() == (offset == 2), "event barrier \(order) step \(offset)")
  }
  expect(!progress.complete(), "completion is once per player")
}
var failedProgress = AppRestartSession.Progress()
failedProgress.loaded(seekRequired: true); failedProgress.ready(); failedProgress.configured(); failedProgress.seekFailed()
expect(failedProgress.complete(), "command failure releases barrier")

// Actual session coordinator with controlled engine/window boundaries.
var firstSaved = saved("one", paused: true)
firstSaved.volume = 17.5; firstSaved.muted = true; firstSaved.speed = 0.75
var secondSaved = saved("two", position: 95.75, paused: false)
secondSaved.volume = 82; secondSaved.speed = 1.5
let pair = begin([firstSaved, secondSaved])
expect(pair.count == 2, "separate player allocated for each window")
expect(pair.allSatisfy { $0.autoLoadArgument == false }, "automatic folder media loading disabled")
expect(settings.frontCount == 0, "coordinator waits for window completion")
load(pair[0], initialRestart: false)
expect(pair[0].mpv.seekRequests.isEmpty, "explicit seek waits for initial load restart")
AppRestartSession.seekStarted(pair[0])
AppRestartSession.playbackRestarted(pair[0])
expect(AppRestartSession.isRestoring(pair[0]), "initial queued seek/restart cannot complete handoff")
expect(pair[0].mpv.paused, "load stays paused before seek")
expect(pair[0].mpv.volume == 17.5 && pair[0].mpv.muted && pair[0].mpv.speed == 0.75,
       "per-window volume, mute and speed restored while paused before seek")
expect(pair[0].mpv.playlist == saved().playlist && pair[0].mpv.currentIndex == 1, "playlist order, duplicates, and current index restored")
expect(pair[0].mpv.seekRequests.last?.1 == "absolute+exact", "head uses absolute exact seek")
expect(pair[0].currentWindow?.frame == frame.rect, "frame restored before ready")
AppRestartSession.playbackRestarted(pair[0])
expect(AppRestartSession.isRestoring(pair[0]), "restart without explicit seek start ignored")
restartSeek(pair[0])
expect(!AppRestartSession.isRestoring(pair[0]) && pair[0].mpv.paused, "paused head completed")
expect(settings.frontCount == 0, "other pending player keeps Settings completion barrier")
load(pair[1], windowReady: false)
restartSeek(pair[1])
expect(pair[1].mpv.paused, "completed seek alone cannot start playback before its window")
AppRestartSession.applyWindowFrame(pair[1]); AppRestartSession.windowReady(pair[1])
expect(!pair[1].mpv.paused && pair[1].info.state == .playing, "playing state resumes after exact head and window")
expect(pair[1].mpv.volume == 82 && !pair[1].mpv.muted && pair[1].mpv.speed == 1.5,
       "independent playback scalars restored for second playing window")
expect(pair[1].mpv.writes.suffix(4) == ["volume=82.0", "mute=false", "speed=1.5", "pause=false"],
       "all playback scalars applied before final unpause")
expect(settings.frontCount == 1, "Settings re-fronted once all windows complete")
expect(pair.allSatisfy { !$0.disableWindowAnimation }, "temporary animation flags restored")

let limited = begin([saved("limited")])[0]
load(limited); restartSeek(limited, position: 41.0)
expect(!AppRestartSession.isRestoring(limited) && settings.frontCount == 1, "engine-completed nearby seek never hangs restoration")
expect(limited.logs.contains { $0.contains("completed exact seek") }, "limited seek mismatch logged")
let unseekable = begin([saved("unseekable")])[0]
unseekable.mpv.seekable = false
load(unseekable)
expect(!AppRestartSession.isRestoring(unseekable) && unseekable.mpv.seekRequests.isEmpty, "unseekable restores without impossible seek")
let failedSeek = begin([saved("seek-error")])[0]
failedSeek.mpv.seekError = -12
load(failedSeek)
expect(!AppRestartSession.isRestoring(failedSeek) && settings.frontCount == 1, "seek command error releases Settings")
expect(failedSeek.logs.contains { $0.contains("exact seek failed") }, "seek command error logged")
let noSeek = begin([saved("already-at-head", position: 0)])[0]
AppRestartSession.windowReady(noSeek)
load(noSeek, windowReady: false, setupFinished: false)
expect(AppRestartSession.isRestoring(noSeek), "no-op seek still waits for entire file setup")
noSeek.mainWindow.window?.setFrame(.zero, display: false)
AppRestartSession.fileSetupFinished(noSeek)
expect(!AppRestartSession.isRestoring(noSeek) && noSeek.currentWindow?.frame == frame.rect, "final file setup reapplies exact frame")
let durationClamp = begin([saved("shortened", position: 500)])[0]
load(durationClamp)
expect(abs(durationClamp.mpv.seekRequests.last!.0 - 299.999) < 0.000001, "shortened media head clamps to valid duration")
restartSeek(durationClamp)

let failingPair = begin([saved("bad"), saved("good")])
NotificationCenter.default.post(name: .iinaPlayerStopped, object: failingPair[0])
expect(!AppRestartSession.isRestoring(failingPair[0]) && settings.frontCount == 0, "failed media does not release remaining window barrier")
load(failingPair[1]); restartSeek(failingPair[1])
expect(settings.frontCount == 1, "good window and Settings finish after failed media")
let shutdown = begin([saved("shutdown")])[0]
NotificationCenter.default.post(name: .iinaPlayerShutdown, object: shutdown)
expect(!AppRestartSession.isRestoring(shutdown) && !shutdown.disableWindowAnimation && settings.frontCount == 1, "shutdown cancels pending restore safely")
for stoppedState in [TestPlayerState.stopping, .shuttingDown, .shutDown] {
  let closing = begin([saved("closing")])[0]
  load(closing)
  closing.info.state = stoppedState
  let previousReads = closing.mpv.reads
  let previousWrites = closing.mpv.writes
  AppRestartSession.seekStarted(closing)
  AppRestartSession.playbackRestarted(closing)
  expect(!AppRestartSession.isRestoring(closing) && settings.frontCount == 1,
         "queued restart cancelled before stopped notification in \(stoppedState)")
  expect(closing.mpv.reads == previousReads && closing.mpv.writes == previousWrites,
         "closing core never queried or unpaused in \(stoppedState)")
}
let replacement = begin([saved("replaced")])[0]
replacement.info.trackSelectionGeneration = 1; AppRestartSession.fileStarted(replacement)
replacement.info.trackSelectionGeneration = 2; AppRestartSession.fileStarted(replacement)
expect(!AppRestartSession.isRestoring(replacement), "next file generation cannot inherit old session seek/frame")

var missing = saved("missing"); missing.mediaURL = URL(fileURLWithPath: "/nonexistent/iina-restart-test-\(UUID()).mp4").absoluteString
expect(begin([missing]).isEmpty && settings.frontCount == 1, "missing file skips cleanly and releases Settings")
expect(begin([]).isEmpty && settings.frontCount == 1, "empty media session still returns to Settings")
PlayerCore.onOpen = { player in
  if player.openedURL!.absoluteString.contains("reject") { player.openResult = 0 }
}
let rejectionPair = begin([saved("reject"), saved("accepted")])
expect(settings.frontCount == 0, "synchronous first failure cannot finish before opening later windows")
load(rejectionPair[1]); restartSeek(rejectionPair[1])
expect(settings.frontCount == 1, "opening batch retains completion ownership after synchronous failure")
PlayerCore.onOpen = nil

var miniSaved = saved("music", position: 0, paused: false)
miniSaved.musicMode = true; miniSaved.minimized = true
miniSaved.frame = AppRestartSession.Frame(NSRect(x: 225, y: 175, width: 350, height: 290))
let mini = begin([miniSaved])[0]; load(mini)
expect(mini.isInMiniPlayer && mini.miniPlayer.window?.frame == miniSaved.frame.rect, "music window retains saved size/origin")
expect(mini.currentWindow?.isMiniaturized == true && !mini.mpv.paused, "minimized music window retains play state")
var fsSaved = saved("fullscreen", position: 0); fsSaved.fullscreen = true
let fullscreen = begin([fsSaved])[0]; load(fullscreen)
expect(fullscreen.mainWindow.fsState.isFullscreen && fullscreen.mainWindow.appliedFrames.last == frame.rect, "fullscreen enters from saved normal rectangle")
var pipSaved = saved("pip", position: 0); pipSaved.pictureInPicture = true
let pip = begin([pipSaved])[0]; load(pip)
expect(pip.mainWindow.pipStatus == .inPIP && pip.mainWindow.appliedFrames.last == frame.rect, "PiP enters from saved normal rectangle")

// Capture reads cores, not only orderedWindows, and runs only at pending actual quit.
PlayerCore.playerCores = []
let captured = PlayerCore.playerCoreForRestart
captured.info.currentURL = URL(string: saved().mediaURL)
captured.info.state = .paused
captured.mpv.volume = 12.25; captured.mpv.muted = true; captured.mpv.speed = 0.5
captured.mpv.time = 42.125; captured.mpv.playlist = saved().playlist; captured.mpv.currentIndex = 1
let externalDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("iina-restart-tracks-\(UUID())")
try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: externalDirectory) }
let externalAudio = externalDirectory.appendingPathComponent("audio.mka")
let externalVideo = externalDirectory.appendingPathComponent("video.mkv")
let externalSubtitle = externalDirectory.appendingPathComponent("sub.srt")
let externalLUT = externalDirectory.appendingPathComponent("look.cube")
for url in [externalAudio, externalVideo, externalSubtitle, externalLUT] { try Data().write(to: url) }
captured.info.audioTracks = [MPVTrack(1, .audio, sourceID: 1), MPVTrack(4, .audio, sourceID: 0, file: externalAudio.path)]
captured.info.videoTracks = [MPVTrack(2, .video, sourceID: 2), MPVTrack(8, .video, sourceID: 0, file: externalVideo.path)]
captured.info.subTracks = [MPVTrack(1, .sub, sourceID: 3), MPVTrack(9, .sub, sourceID: 0, file: externalSubtitle.path)]
captured.info.audioTrackOrder = [4, 1]; captured.info.videoTrackOrder = [8, 2]
captured.info.mixedAudioTrackIDs = [1, 4]; captured.info.layeredVideoTrackIDs = [8, 2]
captured.mpv.integers = ["aid": 1, "vid": 2, "sid": 1, "secondary-sid": 9]
captured.scopedTrackSettings.audio[4] = AudioTrackProcessing(delay: -0.125, gains: [12, -12, 3, 0, 0, 0, 0, 0, 0, 0])
var videoProfile = VideoTrackProcessing()
videoProfile.rotation = 90; videoProfile.aspect = "4:3"
videoProfile.crop = TrackVideoCrop(x: 2, y: 4, width: 300, height: 160)
videoProfile.cropDescription = "Custom"; videoProfile.lutPath = externalLUT.path; videoProfile.brightness = 17
captured.scopedTrackSettings.video[8] = videoProfile
captured.scopedTrackSettings.setTarget(4, for: .audioEQ)
captured.scopedTrackSettings.setTarget(8, for: .videoColor)
captured.mpv.strings = ["video-aspect-override": "4:3", "video-rotate": "90", "video-zoom": "1.25",
  "brightness": "23", "audio-delay": "0.2", "secondary-sub-delay": "-0.3", "sub-visibility": "no",
  "sub-font-size": "41", "secondary-sub-font-size": "28", "ab-loop-a": "12.5", "ab-loop-b": "30",
  "vf": "@iina_crop:crop=300:160:2:4,@lyina_lut:lavfi=[lut3d=file=look.cube]", "af": "@iina_aeq:lavfi=[equalizer=f=100:g=3]"]
captured.aspectDescription = "4:3"; captured.cropDescription = "Custom"
let committedVF = captured.mpv.strings["vf"]!
captured.mpv.strings["vf"] = ""
captured.info.layeredVideoTrackIDs = [8]
captured.mainWindow.interactiveMode.onExit = { discarding in
  if !discarding {
    captured.mpv.strings["vf"] = committedVF
    captured.info.layeredVideoTrackIDs = [8, 2]
  }
}
expect(!captured.mpv.getFlag("save-position-on-quit"), "processing regression explicitly disables watch-later saving")
captured.mainWindow.window?.testVisible = false
captured.mainWindow.window?.testMinimized = true
captured.mainWindow.window?.setFrame(frame.rect, display: false)
let hidden = PlayerCore.playerCoreForRestart
hidden.info.state = .paused; hidden.info.currentURL = URL(string: saved("hidden").mediaURL)
hidden.mainWindow.window?.testVisible = false
hidden.mpv.time = 12.5; hidden.mpv.playlist = [saved("hidden").mediaURL]
let managed = PlayerCore.playerCoreForRestart
managed.info.state = .playing; managed.isManagedByPlugin = true
managed.info.currentURL = URL(string: saved("plugin-owned").mediaURL)
AppRestart.captureSessionIfRequested(defaults: defaults)
expect(defaults.object(forKey: AppRestartSession.preferenceKey) == nil, "ordinary quit has no explicit session handoff")
// An older build's Later bool must not reopen Settings on the next launch.
defaults.set(true, forKey: "restoreSettingsAfterRestart")
expect(!AppRestart.consumeSettingsRestoreRequest(defaults: defaults), "legacy Later flag does not reopen Settings after upgrade")
expect(defaults.object(forKey: "restoreSettingsAfterRestart") == nil, "legacy Later flag removed on launch")
defaults.set(true, forKey: "immediateSettingsRestart")
expect(!AppRestart.consumeSettingsRestoreRequest(defaults: defaults), "incomplete immediate marker does not restore Settings")
expect(defaults.object(forKey: "immediateSettingsRestart") == nil, "incomplete immediate marker consumed once")
// A legacy persisted request cannot arm normal quit by itself.
defaults.set(true, forKey: "restoreSettingsAfterRestart")
defaults.set(encoded, forKey: AppRestartSession.preferenceKey)
AppRestart.captureSessionIfRequested(defaults: defaults)
expect(defaults.data(forKey: AppRestartSession.preferenceKey) == encoded, "legacy request alone cannot capture on normal quit")
defaults.set(3, forKey: "accentColorSource")
defaults.set("#803344", forKey: "customAccentColor")
AppRestart.discardRestoreRequest(defaults: defaults)
expect(defaults.object(forKey: "restoreSettingsAfterRestart") == nil && defaults.object(forKey: "immediateSettingsRestart") == nil &&
       defaults.object(forKey: AppRestartSession.preferenceKey) == nil,
       "Later clears legacy/pending settings and player handoffs")
expect(defaults.integer(forKey: "accentColorSource") == 3 && defaults.string(forKey: "customAccentColor") == "#803344",
       "Later preserves saved accent selection")
captured.mpv.time = 89.75
AppRestart.captureSessionIfRequested(defaults: defaults)
expect(AppRestartSession.consume(defaults: defaults) == nil && !AppRestart.consumeSettingsRestoreRequest(defaults: defaults),
       "Later followed by normal Quit/launch has no explicit restoration")
AppRestart.prepareForImmediateRestart(settings, defaults: defaults)
expect(defaults.object(forKey: AppRestartSession.preferenceKey) == nil, "immediate Restart waits until actual termination to capture")
expect(defaults.bool(forKey: "restoreSettingsAfterRestart") && defaults.bool(forKey: "immediateSettingsRestart"),
       "immediate Restart arms explicit Settings handoff marker")
AppRestart.captureSessionIfRequested(defaults: defaults)
let quitSnapshot = AppRestartSession.consume(defaults: defaults)!
expect(quitSnapshot.windows.count == 2, "capture includes hidden and minimized normal players and excludes plugin-managed player")
let minimizedSnapshot = quitSnapshot.windows.first { $0.minimized }!
expect(minimizedSnapshot.position == 89.75, "immediate Restart captures latest actual-termination head")
expect(minimizedSnapshot.volume == 12.25 && minimizedSnapshot.muted && minimizedSnapshot.speed == 0.5,
       "capture stores actual per-window playback scalars")
expect(minimizedSnapshot.frame == frame, "minimized rectangle preserved")
expect(minimizedSnapshot.playlistIndex == 1 && minimizedSnapshot.playlist == saved().playlist, "capture retains playlist/current index")
let capturedPlayback = minimizedSnapshot.playbackState!
expect(capturedPlayback.processing == captured.scopedTrackSettings,
       "actual capture bridge stores scoped audio/video profiles and editing targets without watch-later")
expect(capturedPlayback.activeAudio == [1, 4] && capturedPlayback.activeVideo == [8, 2],
       "capture preserves mixed audio membership and ordered video layers")
expect(capturedPlayback.videoFilters == committedVF,
       "a source crop preview restores master output and the original layered selection before capture")
expect(capturedPlayback.videoFilters == captured.mpv.strings["vf"] && capturedPlayback.audioFilters == captured.mpv.strings["af"],
       "capture includes output crop/LUT and master audio filters")
let playbackRoundTrip = AppRestartSession.Snapshot.decode(try PropertyListEncoder().encode(quitSnapshot))!
expect(playbackRoundTrip == quitSnapshot, "complete processing payload survives actual property-list handoff")
var invalidPlayback = capturedPlayback; invalidPlayback.version = 99
var invalidPlaybackWindow = minimizedSnapshot; invalidPlaybackWindow.playbackState = invalidPlayback
expect(invalidPlaybackWindow.sanitized?.playbackState == nil && invalidPlaybackWindow.sanitized != nil,
       "unknown optional processing payload cannot discard an otherwise valid player window")
invalidPlayback = capturedPlayback; invalidPlayback.processing.audio[4]?.delay = .nan
expect(invalidPlayback.sanitized == nil, "nonfinite scoped processing rejected before engine restoration")
let reusedExternalID = AppRestartSession.Track(id: 4, type: "audio", sourceID: 99,
  externalFilename: externalVideo.path, isExternal: true, index: 0)
expect(capturedPlayback.trackMapping(type: "audio", available: [reusedExternalID]).isEmpty,
       "external identity never falls back to a reused numeric ID from another file")
var noSourceID = capturedPlayback
noSourceID.tracks = [AppRestartSession.Track(id: 8, type: "video", sourceID: nil,
  externalFilename: nil, isExternal: false, index: 0)]
let reordered = [AppRestartSession.Track(id: 2, type: "video", sourceID: nil, externalFilename: nil, isExternal: false, index: 0),
                 AppRestartSession.Track(id: 8, type: "video", sourceID: nil, externalFilename: nil, isExternal: false, index: 1)]
expect(noSourceID.trackMapping(type: "video", available: reordered)[8] == 8,
       "a stable embedded track ID takes priority over its former list index")
PlayerCore.onOpen = { player in
  player.info.audioTracks = [MPVTrack(11, .audio, sourceID: 1), MPVTrack(44, .audio, sourceID: 0, file: externalAudio.absoluteString)]
  player.info.videoTracks = [MPVTrack(22, .video, sourceID: 2)]
  player.info.subTracks = [MPVTrack(31, .sub, sourceID: 3)]
  player.mpv.onTrackAdd = { command, file in
    if command == "video-add" { player.info.videoTracks.append(MPVTrack(88, .video, sourceID: 0, file: file)) }
    if command == "sub-add" { player.info.subTracks.append(MPVTrack(99, .sub, sourceID: 0, file: file)) }
  }
}
let processingPlayer = begin([minimizedSnapshot])[0]
load(processingPlayer)
expect(!processingPlayer.mpv.savePositionOnQuit, "new process fixture has no watch-later fallback")
expect(processingPlayer.mpv.trackAdds.map(\.0) == ["video-add", "sub-add"],
       "external paths reopen only missing track types and reuse already loaded canonical file URLs")
expect(processingPlayer.restoredMembership.last?.0 == [11, 44] && processingPlayer.restoredMembership.last?.1 == [88, 22],
       "actual restore bridge remaps mixed/layered membership after external IDs change")
expect(processingPlayer.scopedTrackSettings.audio[44] == capturedPlayback.processing.audio[4] &&
       processingPlayer.scopedTrackSettings.video[88] == videoProfile,
       "source delay/EQ/crop/rotation/color/LUT survive changed track IDs")
expect(processingPlayer.scopedTrackSettings.audioTarget == 44 && processingPlayer.scopedTrackSettings.videoTarget == 88,
       "editing targets follow stable source identities")
expect(processingPlayer.info.audioTrackOrder == [44, 11] && processingPlayer.info.videoTrackOrder == [88, 22],
       "source orders restore independently from playback membership")
expect(processingPlayer.info.sid == 31 && processingPlayer.info.secondSid == 99,
       "primary and secondary subtitle roles follow remapped embedded and external sources")
expect(processingPlayer.mpv.strings["vf"] == capturedPlayback.videoFilters &&
       processingPlayer.mpv.strings["af"] == capturedPlayback.audioFilters,
       "actual restore bridge writes output filters independently of watch-later")
expect(capturedPlayback.options.allSatisfy { processingPlayer.mpv.strings[$0.key] == $0.value },
       "geometry, colors, delays, subtitle styles and loop controls restore before completion")
expect(processingPlayer.mpv.paused && processingPlayer.restoredProcessing.count == 1,
       "processing restoration happens once while the media remains paused")
restartSeek(processingPlayer)
expect(!AppRestartSession.isRestoring(processingPlayer), "processing handoff retains the existing seek/window completion barrier")
PlayerCore.onOpen = nil
expect(quitSnapshot.windows.contains { $0.mediaURL == saved("hidden").mediaURL }, "hidden loaded ordinary window retained")
captured.mpv.time = 123
AppRestart.captureSessionIfRequested(defaults: defaults)
expect(defaults.object(forKey: AppRestartSession.preferenceKey) == nil, "repeat termination callback cannot overwrite captured handoff")
expect(AppRestart.consumeSettingsRestoreRequest(defaults: defaults), "immediate Restart restores Settings once")
expect(!AppRestart.consumeSettingsRestoreRequest(defaults: defaults), "immediate Settings request consumed once")
expect(defaults.object(forKey: "immediateSettingsRestart") == nil, "immediate marker removed before media restoration")
AppRestart.prepareForImmediateRestart(settings, defaults: defaults)
AppRestart.discardRestoreRequest(defaults: defaults)
AppRestart.captureSessionIfRequested(defaults: defaults)
expect(AppRestartSession.consume(defaults: defaults) == nil && !AppRestart.consumeSettingsRestoreRequest(defaults: defaults),
       "Later also cancels an armed immediate request and stale snapshot")
expect(!app.isActive, "test application remained inactive")
print("\(checks) restart-session checks passed")
