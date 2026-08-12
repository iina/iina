import Foundation
import AVKit
import AVFoundation

/// Orchestrates an AirPlay video session.
///
/// The stream-copy remux (HLSRemuxer, libavformat in-process) converts the file to a growing
/// fMP4 HLS playlist, paced to ~real time so the AirPlay receiver plays from near the start
/// (a full-speed remux would race the playlist to the end and the TV would ride that live
/// edge). A local LAN server serves it; a hidden AVPlayer with allowsExternalPlayback streams
/// it to the TV. Playback is a single live stream — reliable, plays from the beginning; the
/// OSC follows the receiver's position and play/pause is forwarded to it. Seeking is
/// best-effort within the range remuxed so far. mpv stays paused behind an overlay.
final class AirPlayCoordinator: NSObject, AVRoutePickerViewDelegate {
  private weak var player: PlayerCore?
  private let avPlayer = AVPlayer()
  private let packager = HLSPackager()
  private let server = HLSFileServer()
  private var externalObs: NSKeyValueObservation?
  private var itemStatusObs: NSKeyValueObservation?

  private(set) var isCasting = false
  private var isPreparing = false
  private var resumeMpvOnEnd = false
  /// Bumped on each prepareCast so a stale cancel timer can't tear down a newer session.
  private var generation = 0
  /// Suppresses the external-playback-dropped transient while rebuilding for a track change.
  private var isRebuilding = false
  /// Movie time the current remux started from. The output HLS timeline is 0-based, so the
  /// movie position on the receiver = castStartOffset + avPlayer.currentTime. Seeking beyond
  /// what's been remuxed re-remuxes from the target and updates this offset.
  private var castStartOffset: Double = 0
  /// Debounce token for a pending re-remux (a slider drag issues many seeks; only recast once).
  private var recastGeneration = 0

  /// Current movie position on the receiver. nil if not casting.
  var castCurrentSeconds: Double? {
    guard isCasting else { return nil }
    let t = avPlayer.currentTime().seconds
    return t.isFinite ? castStartOffset + t : nil
  }
  var isCastPaused: Bool { avPlayer.rate == 0 }

  init(player: PlayerCore) {
    self.player = player
    super.init()
    avPlayer.allowsExternalPlayback = true
    avPlayer.automaticallyWaitsToMinimizeStalling = true  // buffer before starting playback
    externalObs = avPlayer.observe(\.isExternalPlaybackActive, options: [.new]) { [weak self] p, _ in
      DispatchQueue.main.async { self?.externalChanged(active: p.isExternalPlaybackActive) }
    }
    NotificationCenter.default.addObserver(self, selector: #selector(playerItemEnded(_:)),
                                           name: .AVPlayerItemDidPlayToEndTime, object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    endIfActive()
  }

  func attach(routePicker: AVRoutePickerView) { routePicker.delegate = self }

  // MARK: - AVRoutePickerViewDelegate

  func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
    prepareCast()
  }

  /// Menu closed — if no route was engaged shortly after, cancel the preparation.
  func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
    let gen = generation
    DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) { [weak self] in
      guard let self = self, gen == self.generation else { return }
      if self.isPreparing && !self.isCasting && !self.avPlayer.isExternalPlaybackActive {
        NSLog("AirPlay: no route engaged, cancelling preparation")
        self.teardown()
      }
    }
  }

  // MARK: - Session

  private func prepareCast() {
    guard !isPreparing, !isCasting, let player = player,
          let url = player.info.currentURL, url.isFileURL else { return }
    isPreparing = true
    generation += 1
    castStartOffset = 0
    resumeMpvOnEnd = !player.mpv.getFlag(MPVOption.PlaybackControl.pause)
    player.mpv.setFlag(MPVOption.PlaybackControl.pause, true)
    NSLog("AirPlay: prepare \(url.lastPathComponent)")
    let audioIndex = max(0, (player.info.aid ?? 1) - 1)
    let subtitleIndex: Int? = player.info.sid.flatMap { $0 >= 1 ? $0 - 1 : nil }
    runPackager(url: url, audioIndex: audioIndex, subtitleIndex: subtitleIndex)
  }

  /// Remuxes the file from `castStartOffset` to a paced HLS playlist. `onReady` (first segment)
  /// is enough to load the item and engage the route. Retries once without subtitles on failure.
  private func runPackager(url: URL, audioIndex: Int, subtitleIndex: Int?) {
    packager.start(input: url, startSeconds: castStartOffset, audioIndex: audioIndex, subtitleIndex: subtitleIndex,
      onReady: { [weak self] result in
        guard let self = self, self.isPreparing || self.isCasting else { return }
        switch result {
        case .failure(let e):
          if subtitleIndex != nil {
            NSLog("AirPlay: subtitle remux failed (\(e)); retrying without subtitles")
            self.packager.stop(); self.packager.cleanup()
            self.runPackager(url: url, audioIndex: audioIndex, subtitleIndex: nil)
          } else {
            NSLog("AirPlay: ffmpeg failed: \(e)")
            self.teardown()
          }
        case .success(let playlist):
          self.serveAndLoad(playlist)
        }
      },
      onComplete: { _ in NSLog("AirPlay: remux complete (full file available)") })
  }

  private func serveAndLoad(_ playlist: URL) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let lanURL = try self.server.start(servingFrom: playlist.deletingLastPathComponent(),
                                           playlist: playlist.lastPathComponent)
        DispatchQueue.main.async { self.loadItem(lanURL) }
      } catch {
        DispatchQueue.main.async {
          NSLog("AirPlay: server failed: \(error)")
          self.teardown()
        }
      }
    }
  }

  /// Loads the playlist (paused). A loaded item — even paused — is what lets the AirPlay route
  /// engage; we must NOT play() here, or the hidden AVPlayer would emit audio from the Mac
  /// speakers before a device is selected. Playback (on the TV) starts in beginCastingState.
  private func loadItem(_ lanURL: URL) {
    guard isPreparing || isCasting else { server.stop(); return }
    NSLog("AirPlay: serving \(lanURL); loading item (paused) to engage route")
    let item = AVPlayerItem(url: lanURL)
    avPlayer.replaceCurrentItem(with: item)
    observeItem(item)
    if avPlayer.isExternalPlaybackActive { beginCastingState() }
  }

  private func externalChanged(active: Bool) {
    NSLog("AirPlay: externalPlaybackActive=\(active) rebuilding=\(isRebuilding)")
    if active {
      isRebuilding = false
      if avPlayer.currentItem != nil { beginCastingState() }
    } else if isCasting && !isRebuilding {
      endCasting()
    }
  }

  /// Enters the casting state and starts playback on the TV (external playback is now active,
  /// so the audio plays on the TV, not the Mac).
  private func beginCastingState() {
    isPreparing = false
    if !isCasting {
      isCasting = true
      player?.mpv.setFlag(MPVOption.PlaybackControl.pause, true)
      player?.mainWindow.setCastingOverlay(true)
      NSLog("AirPlay: casting engaged")
      scheduleReleasePacing()
    }
    avPlayer.play()
    player?.mainWindow.updatePlayButtonState(paused: false)
  }

  /// Once the receiver has loaded the paced playlist and started near the beginning, stop pacing
  /// so the rest fills the buffer fast — prevents underrun stalls / audio drift and makes
  /// forward seeking available. Tied to `generation`, so a re-remux (new session) re-arms it.
  private func scheduleReleasePacing() {
    let gen = generation
    DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
      guard let self = self, self.isCasting, gen == self.generation else { return }
      NSLog("AirPlay: releasing pacing (fill buffer + enable seek)")
      self.packager.releasePacing()
    }
  }

  private func observeItem(_ item: AVPlayerItem) {
    itemStatusObs = item.observe(\.status, options: [.new]) { it, _ in
      if it.status == .failed {
        NSLog("AirPlay: item failed: \(String(describing: it.error))")
        return
      }
      guard it.status == .readyToPlay else { return }
      // Turn on the WebVTT subtitle rendition (we mux only the user's selected sub, so the
      // legible group has a single option).
      if let group = it.asset.mediaSelectionGroup(forMediaCharacteristic: .legible),
         let option = group.options.first {
        it.select(option, in: group)
        NSLog("AirPlay: subtitle rendition selected (\(group.options.count) option(s))")
      }
    }
  }

  // MARK: - Transport (called from PlayerCore while casting)

  func reloadForTrackChange() {
    guard isCasting, let player = player, let url = player.info.currentURL, url.isFileURL else { return }
    castStartOffset = castCurrentSeconds ?? castStartOffset   // rebuild from the current position
    generation += 1
    isRebuilding = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in self?.isRebuilding = false }
    NSLog("AirPlay: track changed, rebuilding from %.1fs", castStartOffset)
    server.stop(); packager.stop(); packager.cleanup()
    let audioIndex = max(0, (player.info.aid ?? 1) - 1)
    let subtitleIndex: Int? = player.info.sid.flatMap { $0 >= 1 ? $0 - 1 : nil }
    runPackager(url: url, audioIndex: audioIndex, subtitleIndex: subtitleIndex)
    scheduleReleasePacing()
  }

  func castSeek(toAbsolute seconds: Double) {
    guard isCasting, seconds.isFinite else { return }
    seekToMovieTime(seconds)
  }

  func castSeek(byRelative delta: Double) {
    guard isCasting else { return }
    seekToMovieTime((castCurrentSeconds ?? castStartOffset) + delta)
  }

  func setCastPaused(_ paused: Bool) {
    guard isCasting else { return }
    paused ? avPlayer.pause() : avPlayer.play()
    player?.mainWindow.updatePlayButtonState(paused: paused)
  }

  /// Seek to an absolute MOVIE time. Within the range remuxed so far → seek locally (instant).
  /// Beyond it (or before the current remux start) → re-remux from that position, so the cast
  /// restarts there. Debounced, so a slider drag re-remuxes only once (to where it settles).
  private func seekToMovieTime(_ movieSeconds: Double) {
    let target = max(0, movieSeconds)
    let local = target - castStartOffset
    var edge = -1.0
    if let r = avPlayer.currentItem?.seekableTimeRanges.first?.timeRangeValue {
      edge = r.start.seconds + r.duration.seconds
    }
    if local >= -1, edge.isFinite, local <= edge + 1 {
      recastGeneration += 1  // cancel any pending recast — this seek is inside the buffer
      let clamped = max(0, min(local, edge))
      avPlayer.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
    } else {
      scheduleRecast(toMovie: target)
    }
  }

  private func scheduleRecast(toMovie target: Double) {
    recastGeneration += 1
    let gen = recastGeneration
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      guard let self = self, self.isCasting, gen == self.recastGeneration else { return }
      self.recastFrom(target)
    }
  }

  /// Re-remuxes the file from `movieSeconds` and reloads the receiver there (like a track-change
  /// rebuild, but from a seek position). The output timeline is 0-based; castStartOffset carries
  /// the movie time so the OSC and later seeks stay in movie time.
  private func recastFrom(_ movieSeconds: Double) {
    guard isCasting, let player = player, let url = player.info.currentURL, url.isFileURL else { return }
    castStartOffset = max(0, movieSeconds)
    generation += 1
    isRebuilding = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in self?.isRebuilding = false }
    NSLog("AirPlay: recasting from %.1fs", castStartOffset)
    server.stop(); packager.stop(); packager.cleanup()
    let audioIndex = max(0, (player.info.aid ?? 1) - 1)
    let subtitleIndex: Int? = player.info.sid.flatMap { $0 >= 1 ? $0 - 1 : nil }
    runPackager(url: url, audioIndex: audioIndex, subtitleIndex: subtitleIndex)
    scheduleReleasePacing()
  }

  @objc private func playerItemEnded(_ note: Notification) {
    guard isCasting, (note.object as? AVPlayerItem) === avPlayer.currentItem else { return }
    DispatchQueue.main.async { [weak self] in self?.endCasting() }
  }

  private func endCasting() {
    teardown(resumeAt: castCurrentSeconds)   // hand the movie position back to mpv
  }

  /// Release all cast resources without handing position back to mpv (player stopping /
  /// switching files). No-op if not casting. Called from PlayerCore.
  func endIfActive() {
    guard isCasting || isPreparing else { return }
    NSLog("AirPlay: ending cast (player stop / file change)")
    cleanupSession()
  }

  /// Tears down the session and hands the current position back to mpv.
  private func teardown(resumeAt: Double? = nil) {
    let wasActive = isCasting || isPreparing
    cleanupSession()
    guard wasActive, let player = player else { return }
    if let pos = resumeAt, pos > 0 {
      player.mpv.command(.seek, args: ["\(pos)", "absolute+exact"])
    }
    if resumeMpvOnEnd {
      player.mpv.setFlag(MPVOption.PlaybackControl.pause, false)
    }
  }

  private func cleanupSession() {
    isCasting = false
    isPreparing = false
    isRebuilding = false
    castStartOffset = 0
    avPlayer.pause()
    avPlayer.replaceCurrentItem(with: nil)
    itemStatusObs = nil
    server.stop()
    packager.stop()
    packager.cleanup()
    player?.mainWindow.setCastingOverlay(false)
  }
}
