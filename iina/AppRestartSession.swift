//
//  AppRestartSession.swift
//  iina
//

import Cocoa

/// An explicit, one-shot handoff for a settings-requested normal restart.
/// This is independent of mpv watch-later and ordinary playback-history options.
enum AppRestartSession {
  static let preferenceKey = "playerSessionAfterSettingsRestart"

  struct Frame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: NSRect) {
      x = rect.origin.x; y = rect.origin.y
      width = rect.width; height = rect.height
    }

    var rect: NSRect { NSRect(x: x, y: y, width: width, height: height) }
    var isValid: Bool {
      [x, y, width, height].allSatisfy(\.isFinite) &&
        abs(x) <= 1_000_000 && abs(y) <= 1_000_000 &&
        (1...16_000).contains(width) && (1...16_000).contains(height)
    }
  }

  struct Window: Codable, Equatable {
    var mediaURL: String
    var playlist: [String]
    var playlistIndex: Int
    var position: Double
    var paused: Bool
    var frame: Frame
    var mainFrame: Frame
    var musicMode: Bool
    var minimized: Bool
    var fullscreen: Bool
    var pictureInPicture: Bool
    var volume: Double = 50
    var muted: Bool = false
    var speed: Double = 1

    var sanitized: Window? {
      guard let url = URL(string: mediaURL), let scheme = url.scheme,
            !["stdin", "fd", "memory", "data"].contains(scheme.lowercased()),
            mediaURL.utf8.count <= 32_768, !mediaURL.contains("\0"),
            position.isFinite, (0...1_000_000_000).contains(position),
            volume.isFinite, (0...1_000).contains(volume),
            speed.isFinite, (0.01...100).contains(speed),
            frame.isValid, mainFrame.isValid, playlist.count <= 10_000 else { return nil }
      var result = self
      // Keep the current item/index together, including duplicate playlist paths.
      // A malformed playlist must not prevent reopening an otherwise valid window.
      if playlist.isEmpty || !playlist.indices.contains(playlistIndex) ||
          playlist.contains(where: { $0.isEmpty || $0.contains("\0") || $0.utf8.count > 32_768 }) ||
          !Self.playlistItem(playlist[playlistIndex], matches: url) {
        result.playlist = [url.isFileURL ? url.path : url.absoluteString]
        result.playlistIndex = 0
      }
      if musicMode { result.fullscreen = false; result.pictureInPicture = false }
      return result
    }

    private static func playlistItem(_ path: String, matches url: URL) -> Bool {
      if url.isFileURL {
        let itemURL = path.hasPrefix("file://") ? URL(string: path) : URL(fileURLWithPath: path)
        return itemURL?.standardizedFileURL == url.standardizedFileURL
      }
      return URL(string: path) == url
    }
  }

  struct Snapshot: Codable, Equatable {
    var version = 1
    var windows: [Window]

    var sanitized: Snapshot? {
      guard version == 1, windows.count <= 128 else { return nil }
      return Snapshot(windows: windows.compactMap(\.sanitized))
    }

    static func decode(_ data: Data?) -> Snapshot? {
      guard let data, data.count <= 16 * 1_024 * 1_024,
            let decoded = try? PropertyListDecoder().decode(Snapshot.self, from: data) else { return nil }
      return decoded.sanitized
    }
  }

  /// A seek restart cannot finish a restore until both media and its window are ready.
  /// Kept separate from AppKit/mpv so event ordering is directly testable.
  struct Progress {
    private(set) var mediaLoaded = false
    private(set) var windowReady = false
    private(set) var setupFinished = false
    private(set) var seekStarted = false
    private(set) var seekFinished = false
    private(set) var finished = false

    mutating func loaded(seekRequired: Bool) {
      guard !finished else { return }
      mediaLoaded = true
      seekFinished = !seekRequired
    }
    mutating func ready() { if !finished { windowReady = true } }
    mutating func configured() { if !finished { setupFinished = true } }
    mutating func seeking() { if mediaLoaded && !finished { seekStarted = true } }
    mutating func restarted() {
      if mediaLoaded && seekStarted && !finished { seekFinished = true }
    }
    mutating func seekFailed() { if !finished { seekFinished = true } }
    mutating func complete() -> Bool {
      guard mediaLoaded, setupFinished, windowReady, seekFinished, !finished else { return false }
      finished = true
      return true
    }
  }

  static func recoveredFrame(_ frame: NSRect, on screens: [NSRect]) -> NSRect {
    // Keep the saved dimensions while recovering a fully disconnected display.
    // Even an oversized frame must retain its titlebar at the new screen's top.
    guard !screens.contains(where: { $0.intersects(frame) }), let screen = screens.first else { return frame }
    var result = frame
    result.origin.x = screen.midX - frame.width / 2
    result.origin.y = screen.maxY - frame.height
    return result
  }

  static func consume(defaults: UserDefaults = .standard) -> Snapshot? {
    let data = defaults.data(forKey: preferenceKey)
    defaults.removeObject(forKey: preferenceKey)
    // Clear the handoff before any media/plugin code can run or fail.
    defaults.synchronize()
    return Snapshot.decode(data)
  }
}

// MARK: - Runtime integration

extension AppRestartSession {
  private final class Pending {
    weak var player: PlayerCore?
    let saved: Window
    let previousAnimationSetting: Bool
    var progress = Progress()
    var generation: Int?
    var targetPosition: Double
    var requiresSeek = false
    var requestedSeek = false

    init(player: PlayerCore, saved: Window) {
      self.player = player
      self.saved = saved
      previousAnimationSetting = player.disableWindowAnimation
      targetPosition = saved.position
    }
  }

  private static var pending: [ObjectIdentifier: Pending] = [:]
  private static var stoppedObservers: [NSObjectProtocol] = []
  private static var isOpeningSession = false
  private static weak var settingsWindow: SettingsWindow?

  /// Called on the actual quit path, before closing any windows or stopping mpv.
  static func capture(defaults: UserDefaults = .standard) {
    precondition(Thread.isMainThread)
    let ordered = NSApp.orderedWindows
    let players = PlayerCore.playerCores.filter { player in
      // close() moves a player to stopping synchronously. A loaded core with
      // a window is still open even when the app/window is currently hidden.
      !player.isManagedByPlugin && player.info.state.loaded &&
        player.mainWindow.isWindowLoaded && player.currentWindow != nil
    }.sorted { first, second in
      let firstIndex = ordered.firstIndex(where: { $0 === first.currentWindow }) ?? Int.max
      let secondIndex = ordered.firstIndex(where: { $0 === second.currentWindow }) ?? Int.max
      return firstIndex > secondIndex // Reopen back-to-front.
    }
    let windows = players.compactMap { player -> Window? in
      guard let url = player.info.currentURL, let window = player.currentWindow,
            let mainWindow = player.mainWindow.window else { return nil }
      player.getPlaylist()
      let playlist = player.info.playlist
      let index = playlist.firstIndex(where: \.isCurrent) ?? playlist.firstIndex(where: \.isPlaying) ?? 0
      let normalFrame = player.mainWindow.fsState.priorWindowedFrame ?? mainWindow.frame
      let currentFrame = player.isInMiniPlayer ? window.frame : normalFrame
      let position = player.mpv.getDouble(MPVProperty.timePos)
      return Window(mediaURL: url.absoluteString, playlist: playlist.map(\.filename),
                    playlistIndex: index, position: max(0, position),
                    paused: player.mpv.getFlag(MPVOption.PlaybackControl.pause),
                    frame: Frame(currentFrame), mainFrame: Frame(normalFrame),
                    musicMode: player.isInMiniPlayer, minimized: window.isMiniaturized,
                    fullscreen: player.mainWindow.fsState.isFullscreen,
                    pictureInPicture: player.mainWindow.pipStatus == .inPIP,
                    volume: player.mpv.getDouble(MPVOption.Audio.volume),
                    muted: player.mpv.getFlag(MPVOption.Audio.mute),
                    speed: player.mpv.getDouble(MPVOption.PlaybackControl.speed)).sanitized
    }
    guard let data = try? PropertyListEncoder().encode(Snapshot(windows: windows)),
          data.count <= 16 * 1_024 * 1_024 else {
      defaults.removeObject(forKey: preferenceKey)
      return
    }
    defaults.set(data, forKey: preferenceKey)
    defaults.synchronize()
  }

  static func restore(_ snapshot: Snapshot?, settings: SettingsWindow?) {
    precondition(Thread.isMainThread)
    guard let snapshot = snapshot?.sanitized else { return }
    settingsWindow = settings
    isOpeningSession = true
    if stoppedObservers.isEmpty {
      stoppedObservers = [Notification.Name.iinaPlayerStopped, .iinaPlayerShutdown].map { name in
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
          guard let player = note.object as? PlayerCore else { return }
          cancel(player)
        }
      }
    }
    for saved in snapshot.windows {
      guard let url = URL(string: saved.mediaURL),
            !url.isFileURL || FileManager.default.fileExists(atPath: url.path) else { continue }
      let player = PlayerCore.playerCoreForRestart
      pending[ObjectIdentifier(player)] = Pending(player: player, saved: saved)
      player.disableWindowAnimation = true
      let opened = player.openURLs([url], shouldAutoLoad: false)
      if opened == 0 || !player.info.state.active { cancel(player) }
    }
    isOpeningSession = false
    finishIfReady()
  }

  static func isRestoring(_ player: PlayerCore) -> Bool { pending[ObjectIdentifier(player)] != nil }

  static func fileStarted(_ player: PlayerCore) {
    guard let item = current(player) else { return }
    item.generation = player.info.trackSelectionGeneration
  }

  static func fileLoaded(_ player: PlayerCore) {
    guard let item = current(player), !item.progress.mediaLoaded else { return }
    item.generation = player.info.trackSelectionGeneration
    player.mpv.setFlag(MPVOption.PlaybackControl.pause, true)
    player.mpv.setFlag(MPVOption.Window.fullscreen, false)
    restorePlaybackScalars(item, player: player)
    player.info.state = .paused
    let duration = player.info.videoDuration?.second
    if let duration, duration.isFinite, duration > 0 {
      item.targetPosition = min(item.saved.position, max(0, duration - 0.001))
    }
    let seekable = player.mpv.getFlag(MPVProperty.seekable)
    let currentPosition = player.mpv.getDouble(MPVProperty.timePos)
    let needsSeek = seekable && (!currentPosition.isFinite || abs(currentPosition - item.targetPosition) > 0.000_001)
    item.requiresSeek = needsSeek
    item.progress.loaded(seekRequired: needsSeek)

    // Rebuild around the already loaded current entry, so no earlier playlist
    // item is briefly played and normal resume/auto-next options cannot choose it.
    player.mpv.command(.playlistClear)
    for index in (0..<item.saved.playlistIndex).reversed() {
      player.mpv.playlistInsert(item.saved.playlist[index], index: 0)
    }
    for index in (item.saved.playlistIndex + 1)..<item.saved.playlist.count {
      player.mpv.playlistAppend(item.saved.playlist[index])
    }
    player.getPlaylist()
    player.postNotification(.iinaPlaylistChanged)

    if item.saved.musicMode != player.isInMiniPlayer {
      if item.saved.musicMode { player.switchToMiniPlayer(showMiniPlayer: false) }
      else { player.switchBackFromMiniPlayer(showMainWindow: false) }
    }
    if !seekable {
      player.log("Restart session: media is not seekable; restoring its window and play state")
    }
  }

  static func fileSetupFinished(_ player: PlayerCore) {
    guard let item = current(player) else { return }
    item.progress.configured()
    if item.progress.windowReady { applyWindowFrame(player) }
    completeIfReady(item)
  }

  static func applyWindowFrame(_ player: PlayerCore) {
    guard let item = current(player), item.progress.mediaLoaded else { return }
    player.mainWindow.applyRestartWindowFrame(visibleFrame(item.saved.mainFrame.rect))
    if player.isInMiniPlayer {
      player.miniPlayer.window?.setFrame(visibleFrame(item.saved.frame.rect), display: false, animate: false)
    }
  }

  static func windowReady(_ player: PlayerCore) {
    guard let item = current(player) else { return }
    item.progress.ready()
    completeIfReady(item)
  }

  static func seekStarted(_ player: PlayerCore) {
    guard let item = current(player), item.requestedSeek else { return }
    item.progress.seeking()
  }

  static func playbackRestarted(_ player: PlayerCore) {
    guard let item = current(player) else { return }
    if item.requiresSeek && !item.requestedSeek {
      // The first restart belongs to loading/watch-later. Seek only after it,
      // so its already queued SEEK/restart pair cannot complete our handoff.
      item.requestedSeek = true
      player.mpv.command(.seek, args: [String(item.targetPosition), "absolute+exact"], checkError: false) { code in
        if code < 0 {
          player.log("Restart session: exact seek failed (\(code)); restoring its window and play state")
          item.progress.seekFailed()
        }
      }
      completeIfReady(item)
      return
    }
    guard !player.mpv.getFlag(MPVProperty.seeking) else { return }
    let position = player.mpv.getDouble(MPVProperty.timePos)
    if item.progress.seekStarted && (!position.isFinite || abs(position - item.targetPosition) > 0.25) {
      player.log("Restart session: engine completed exact seek at \(position), requested \(item.targetPosition)")
    }
    item.progress.restarted()
    completeIfReady(item)
  }

  private static func current(_ player: PlayerCore) -> Pending? {
    guard let item = pending[ObjectIdentifier(player)] else { return nil }
    guard player.info.state.active,
          item.generation == nil || item.generation == player.info.trackSelectionGeneration else {
      cancel(player)
      return nil
    }
    return item
  }

  private static func completeIfReady(_ item: Pending) {
    guard item.progress.complete(), let player = item.player else { return }
    pending.removeValue(forKey: ObjectIdentifier(player))
    player.disableWindowAnimation = item.previousAnimationSetting
    if item.saved.fullscreen && !player.mainWindow.fsState.isFullscreen {
      player.mainWindow.toggleWindowFullScreen()
    } else if item.saved.pictureInPicture && !player.isInMiniPlayer {
      player.mainWindow.enterPIP()
    } else if item.saved.minimized {
      player.currentWindow?.miniaturize(nil)
    }
    restorePlaybackScalars(item, player: player)
    player.mpv.setFlag(MPVOption.PlaybackControl.pause, item.saved.paused)
    player.info.state = item.saved.paused ? .paused : .playing
    if !item.saved.paused { player.mainWindow.videoView.displayActive() }
    player.refreshSyncUITimer()
    player.syncUI([.time, .playButton])
    finishIfReady()
  }

  private static func restorePlaybackScalars(_ item: Pending, player: PlayerCore) {
    // Keep per-window values independent of the application's remembered volume.
    player.mpv.setDouble(MPVOption.Audio.volume, item.saved.volume)
    player.mpv.setFlag(MPVOption.Audio.mute, item.saved.muted)
    player.mpv.setDouble(MPVOption.PlaybackControl.speed, item.saved.speed)
    player.info.volume = item.saved.volume
    player.info.isMuted = item.saved.muted
    player.info.playSpeed = item.saved.speed
  }

  private static func cancel(_ player: PlayerCore) {
    if let item = pending.removeValue(forKey: ObjectIdentifier(player)) {
      player.disableWindowAnimation = item.previousAnimationSetting
    }
    finishIfReady()
  }

  private static func finishIfReady() {
    guard pending.isEmpty, !isOpeningSession else { return }
    stoppedObservers.forEach { NotificationCenter.default.removeObserver($0) }
    stoppedObservers.removeAll()
    // Media opens have completed; their showWindow calls must not steal Settings.
    settingsWindow?.makeKeyAndOrderFront(nil)
    settingsWindow = nil
  }

  private static func visibleFrame(_ frame: NSRect) -> NSRect {
    // Same connected displays retain exact saved coordinates.
    recoveredFrame(frame, on: NSScreen.screens.map(\.visibleFrame))
  }
}
