import Darwin
setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message)
  checks += 1
  print("PASS: \(message)")
}
func fixture() -> MainWindowController {
  let main = MainWindowController()
  let mini = main.player.miniPlayer
  mini.videoView = main.videoView
  mini.window!.isReleasedWhenClosed = false
  mini.videoWrapperView.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
  mini.window!.contentView!.addSubview(mini.videoWrapperView)
  main.standardWindowButtons = [NSButton()]
  return main
}
func dispose(_ main: MainWindowController) {
  if main.interactiveMode.isActive { main.interactiveMode.exit() }
  if main.player.isInMiniPlayer {
    main.player.switchBackFromMiniPlayer(automatically: true, showMainWindow: false)
  }
  main.window?.close()
  main.player.miniPlayer.window?.close()
}

for state in [PlayerState.loading, .starting, .loaded, .playing, .paused] {
  for automatic in [false, true] {
    let main = fixture(), player = main.player
    player.info.state = state
    player.switchToMiniPlayer(automatically: automatic, showMiniPlayer: false)
    check(player.isInMiniPlayer && main.videoView.superview === player.miniPlayer.videoWrapperView,
          "\(state) permits \(automatic ? "automatic" : "manual") music-mode entry")
    check(player.overrideAutoSwitchToMusicMode == !automatic,
          "only an accepted manual switch changes the automatic-mode override")
    check(player.events.emitted == [true], "accepted entry publishes exactly one mode change")
    dispose(main)
  }
}

let blocked: [(String, (MainWindowController) -> Void)] = [
  ("stopping", { $0.player.info.state = .stopping }),
  ("idle", { $0.player.info.state = .idle }),
  ("shutting down", { $0.player.info.state = .shuttingDown }),
  ("shut down", { $0.player.info.state = .shutDown }),
  ("unloaded window", { $0.loaded = false }),
  ("crop/geometry transition", { $0.isCropTransitionInProgress = true }),
  ("PiP", { $0.pipStatus = .inPIP }),
  ("PiP return", { $0.pipStatus = .intermediate }),
  ("fullscreen transition", { $0.isFullscreenTransitionInProgress = true }),
  ("another video host", { $0.videoView.removeFromSuperview() })
]
for (name, configure) in blocked {
  let main = fixture(), player = main.player
  configure(main)
  let originalHost = main.videoView.superview
  player.switchToMiniPlayer()
  check(!player.isInMiniPlayer && main.videoView.superview === originalHost,
        "\(name) cannot transfer video ownership")
  check(!player.overrideAutoSwitchToMusicMode && player.events.emitted.isEmpty && !player.miniPlayer.pendingShow,
        "a rejected \(name) switch has no mode, preference or presentation side effects")
  dispose(main)
}

for mode in [InteractiveModeController.Mode.crop, .delogo] {
  let main = fixture(), player = main.player
  main.interactiveMode.enter(mode: mode, selectWholeVideoByDefault: true)
  main.videoViewContainer.layoutSubtreeIfNeeded()
  if mode == .crop {
    let crop = main.videoViewContainer.subviews.compactMap { $0 as? CropBoxView }.first!
    crop.setZoom(2)
    check(main.videoView.layer?.mask != nil, "crop attack uses the real zoom mask")
  }
  let transform = main.videoView.layer!.transform, mask = main.videoView.layer!.mask
  main.handleIINACommand(.toggleMusicMode)
  check(main.interactiveMode.isActive && !player.isInMiniPlayer && main.videoView.superview === main.videoViewContainer,
        "the internal music-mode shortcut cannot take video from an active \(mode) editor")
  check(main.videoView.layer!.mask === mask && CATransform3DEqualToTransform(main.videoView.layer!.transform, transform),
        "rejected editor shortcut preserves its native video projection")
  check(!main.standardWindowButtons[0].isEnabled && player.events.emitted.isEmpty,
        "rejected editor shortcut preserves editor controls and publishes no mode change")
  main.interactiveMode.exit()
  player.switchToMiniPlayer()
  check(player.isInMiniPlayer && main.videoView.layer!.mask == nil,
        "music mode becomes available after normal editor teardown")
  dispose(main)
}

do {
  let main = fixture(), player = main.player
  player.switchToMiniPlayer()
  let override = player.overrideAutoSwitchToMusicMode
  player.switchToMiniPlayer()
  check(player.overrideAutoSwitchToMusicMode == override && player.events.emitted == [true],
        "duplicate entry cannot toggle the override or publish another ownership change")
  player.switchBackFromMiniPlayer()
  let restoredOverride = player.overrideAutoSwitchToMusicMode
  player.switchBackFromMiniPlayer()
  check(player.overrideAutoSwitchToMusicMode == restoredOverride && player.events.emitted == [true, false],
        "duplicate return is harmless")
  dispose(main)
}
for state in [PlayerState.stopping, .idle] {
  let main = fixture(), player = main.player
  player.switchToMiniPlayer(automatically: true)
  player.info.state = state
  player.switchBackFromMiniPlayer(automatically: true, showMainWindow: false)
  check(!player.isInMiniPlayer && main.videoView.superview === main.videoViewContainer,
        "mini-player close can return video while \(state)")
  check(player.events.emitted == [true, false], "close cleanup publishes the completed return once")
  dispose(main)
}
print("Completed \(checks) production music-mode ownership checks with native Crop/Delogo and hidden windows.")
