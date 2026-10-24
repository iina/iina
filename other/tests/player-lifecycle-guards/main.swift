import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message)
  checks += 1
}
func player(_ state: PlayerState) -> PlayerCore {
  let result = PlayerCore()
  result.info.state = state
  return result
}
let states: [PlayerState] = [.loading, .starting, .loaded, .playing, .paused, .stopping, .idle, .shuttingDown, .shutDown]
for state in states {
  let audio = player(state)
  let preferenceWrites = Preference.writes
  audio.toggleMute()
  audio.setVolume(90)
  check(audio.mpv.calls.isEmpty == !state.active, "volume/mute respect \(state) activity")
  check(audio.info.volume == (state.active ? 90 : 50) && Preference.writes - preferenceWrites == (state.active ? 1 : 0),
        "late volume cannot mutate cached state or preferences in \(state)")
  audio.mpv.calls.removeAll()
  audio.info.chapters = [MPVChapter(title: "first", startTime: 5, index: 0)]
  check((audio.playChapter(0) != nil) == state.active, "chapter play respects \(state) activity")
  check(audio.mpv.calls.isEmpty == !state.active && audio.uiTimeSyncs == (state.active ? 1 : 0),
        "late chapter action cannot seek/resume/sync a closed engine in \(state)")

  let commands = player(state)
  commands.seek(percent: 50)
  commands.seek(relativeSecond: 5, option: .relative)
  commands.seek(relativeSecond: 5, option: .exact)
  commands.seek(relativeSecond: 5, option: .auto)
  commands.seek(absoluteSecond: 5)
  commands.setSpeed(1.2)
  commands.setTrack(1, forType: .audio)
  commands.setTrack(1, forType: .video)
  commands.setTrack(1, forType: .sub)
  commands.setTrack(2, forType: .secondSub)
  commands.setAudioDelay(0.3)
  commands.setSubDelay(0.4)
  commands.setSubDelay(0.5, forPrimary: false)
  commands.getChapters()
  commands.loadExternalSubFile(URL(fileURLWithPath: "/sub.ass"))
  check(commands.mpv.calls.isEmpty == !state.active, "public commands respect \(state) activity")
  check(commands.seekRequests == (state.active ? 5 : 0), "closed-state seeks create no feedback or seek listeners in \(state)")
  check(commands.trackRequests == (state.active ? 2 : 0), "public track selection respects \(state) activity")
  commands.mpv.calls.removeAll()
  commands.info.subTracks = [MPVTrack(id: 1, externalFilename: "/sub.ass")]
  commands.loadExternalSubFile(URL(fileURLWithPath: "/sub.ass"))
  check(commands.mpv.calls == (state.active ? ["command:subReload"] : []), "external subtitle reload respects \(state) activity")

  let paused = player(state)
  paused.pause()
  check(paused.mpv.calls.isEmpty == !state.active, "pause respects \(state) activity")
  let resumed = player(state)
  resumed.resume()
  check(resumed.mpv.calls.isEmpty == !state.active, "resume respects \(state) activity")
  check(resumed.mainWindow.videoView.activations == (state.active ? 1 : 0), "resume cannot reactivate a closed display in \(state)")

  let stopped = player(state)
  stopped.stop()
  if state == .shuttingDown || state == .shutDown {
    check(stopped.mpv.calls.isEmpty, "stop makes no engine calls after shutdown begins in \(state)")
    check(stopped.info.state == state && stopped.screenshotCancellations == 0, "late stop preserves closed lifecycle state in \(state)")
  } else if state == .idle {
    check(stopped.mpv.calls.isEmpty && stopped.info.state == .idle, "idle stop does not send redundant engine commands")
  } else {
    check(stopped.mpv.calls.filter { $0 == "command:stop" }.count == 1, "stop remains available in \(state)")
    check(stopped.info.state == .stopping, "stop retains the asynchronous stopping state in \(state)")
  }

  let shutdown = player(state)
  shutdown.pendingUrl = URL(fileURLWithPath: "/queued-replacement.mp4")
  shutdown.shutdown()
  if state == .shutDown {
    check(shutdown.mpv.calls.isEmpty && shutdown.info.state == .shutDown, "shutdown after engine destruction is inert")
  } else if state == .stopping {
    check(shutdown.mpv.calls.isEmpty && shutdown.info.state == .stopping, "shutdown waits for asynchronous stop completion")
    shutdown.shutdown()
    check(shutdown.mpv.calls.isEmpty, "repeated shutdown while stopping does not send quit")
    shutdown.idleActiveChanged()
    check(shutdown.mpv.calls == ["quit"] && shutdown.info.state == .shuttingDown, "actual stopped event continues deferred shutdown once")
    check(shutdown.openedURLs.isEmpty && shutdown.pendingUrl == nil, "deferred shutdown supersedes a queued media replacement")
    shutdown.idleActiveChanged()
    check(shutdown.mpv.calls == ["quit"] && shutdown.stoppedNotifications == 1, "late idle callback cannot repeat shutdown or stopped notifications")
  } else {
    check(shutdown.mpv.calls == ["quit"], "shutdown sends one quit in \(state)")
    shutdown.shutdown()
    check(shutdown.mpv.calls == ["quit"], "duplicate shutdown is idempotent in \(state)")
    shutdown.resume(); shutdown.stop()
    check(shutdown.mpv.calls == ["quit"], "late resume and stop cannot access the quitting engine in \(state)")
  }
}

let backgroundStop = player(.playing)
backgroundStop.backgroundTaskInUse = true
backgroundStop.stop()
check(backgroundStop.info.state == .stopping && !backgroundStop.mpv.calls.contains("command:stop"), "stop first cancels active background work")
backgroundStop.shutdown(); backgroundStop.shutdown()
check(!backgroundStop.mpv.calls.contains("quit") && backgroundStop.info.state == .stopping, "shutdown request cannot bypass background stop")
backgroundStop.backgroundTaskInUse = false
backgroundStop.stop()
check(backgroundStop.mpv.calls.filter { $0 == "command:stop" }.count == 1, "stopping continuation still sends stop after background completion")
backgroundStop.idleActiveChanged()
check(backgroundStop.mpv.calls.suffix(2) == ["command:stop", "quit"], "quit follows completed stop, never its background wait")

let backgroundShutdown = player(.idle)
backgroundShutdown.backgroundTaskInUse = true
backgroundShutdown.shutdown(); backgroundShutdown.shutdown()
check(backgroundShutdown.info.state == .shuttingDown && backgroundShutdown.mpv.calls.isEmpty, "shuttingDown can wait for background work without being mistaken for a sent quit")
backgroundShutdown.resume(); backgroundShutdown.stop()
check(backgroundShutdown.mpv.calls.isEmpty, "late playback actions cannot reach engine during shutdown background wait")
backgroundShutdown.backgroundTaskInUse = false
backgroundShutdown.shutdown(); backgroundShutdown.shutdown()
check(backgroundShutdown.mpv.calls == ["quit"], "background completion sends exactly one deferred quit")
backgroundShutdown.info.state = .shutDown
backgroundShutdown.shutdown(); backgroundShutdown.resume(); backgroundShutdown.stop(); backgroundShutdown.idleActiveChanged()
check(backgroundShutdown.mpv.calls == ["quit"], "all late lifecycle calls remain inert after actual engine shutdown")

let terminationObserver = player(.stopping)
terminationObserver.shutdown()
terminationObserver.pendingUrl = URL(fileURLWithPath: "/late-plugin-open.mp4")
terminationObserver.onStopped = { terminationObserver.shutdown() }
terminationObserver.idleActiveChanged()
check(terminationObserver.mpv.calls == ["quit"], "application stopped observer and deferred shutdown cannot send duplicate quit")
check(terminationObserver.openedURLs.isEmpty && terminationObserver.pendingUrl == nil, "observer-triggered shutdown prevents pending replacement from opening")

let normalReplacement = player(.stopping)
let replacementURL = URL(fileURLWithPath: "/normal-replacement.mp4")
normalReplacement.pendingUrl = replacementURL
normalReplacement.idleActiveChanged()
check(normalReplacement.openedURLs == [replacementURL] && normalReplacement.info.state == .loading, "ordinary stop completion still opens its queued replacement")
check(normalReplacement.mpv.calls.isEmpty, "ordinary replacement does not acquire shutdown intent")

let stillLoading = player(.loading)
stillLoading.idleActiveChanged()
check(stillLoading.info.state == .loading && stillLoading.stoppedNotifications == 0, "old idle event cannot finish a new load")
print("\(checks) lifecycle guard checks passed across every PlayerState and deferred/duplicate shutdown ordering")
