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
