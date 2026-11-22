// Copyright © 2026 IINA contributors. Licensed under GPLv3.

import Foundation

extension PlayerCore: SharePlayPlayer {
  var sharePlaySnapshot: SharePlaySnapshot {
    guard info.state.loaded else {
      return SharePlaySnapshot(url: info.currentURL, position: 0, duration: 0, speed: 1,
                               paused: true, buffering: true, loaded: false, seekable: false)
    }
    return SharePlaySnapshot(url: info.currentURL, position: mpv.getDouble(MPVProperty.timePos),
                             duration: info.videoDuration?.second ?? 0,
                             speed: mpv.getDouble(MPVOption.PlaybackControl.speed),
                             paused: mpv.getFlag(MPVOption.PlaybackControl.pause),
                             buffering: mpv.getFlag(MPVProperty.pausedForCache), loaded: true,
                             seekable: mpv.getFlag(MPVProperty.seekable) && !info.videoTracks.isEmpty)
  }

  func prepareForSharePlay() -> Bool {
    sharePlaySavedOptions = Dictionary(uniqueKeysWithValues:
      ["keep-open", "loop-file", "loop-playlist", "ab-loop-a", "ab-loop-b"].compactMap { key in
        mpv.getString(key).map { (key, $0) }
      })
    guard sharePlaySavedOptions.count == 5 else { sharePlaySavedOptions.removeAll(); return false }
    sharePlaySetPaused(true)
    for (key, value) in ["keep-open": "always", "loop-file": "no", "loop-playlist": "no", "ab-loop-a": "no", "ab-loop-b": "no"] {
      guard mpv.setString(key, value) >= 0 else { restoreAfterSharePlay(); return false }
    }
    syncAbLoop()
    return true
  }

  func restoreAfterSharePlay() {
    let completion = sharePlaySeekCompletion
    sharePlaySeekCompletion = nil
    sharePlaySeekTarget = nil
    completion?(false)
    for (key, value) in sharePlaySavedOptions { mpv.setString(key, value) }
    sharePlaySavedOptions.removeAll()
    syncAbLoop()
  }

  func sharePlaySetPaused(_ paused: Bool) {
    applyingSharePlayCommand = true
    defer { applyingSharePlayCommand = false }
    if paused { pause() }
    else {
      mainWindow.videoView.displayActive()
      mpv.setFlag(MPVOption.PlaybackControl.pause, false)
    }
  }

  func sharePlaySetSpeed(_ speed: Double) {
    applyingSharePlayCommand = true
    defer { applyingSharePlayCommand = false }
    setSpeed(speed)
  }

  func sharePlaySeek(to time: Double, completion: @escaping (Bool) -> Void) {
    let previous = sharePlaySeekCompletion
    sharePlaySeekCompletion = nil
    previous?(false)
    guard info.state.loaded, time.isFinite else { completion(false); return }
    sharePlaySeekCompletion = completion
    sharePlaySeekTarget = time
    applyingSharePlayCommand = true
    defer { applyingSharePlayCommand = false }
    mainWindow.videoView.displayActive()
    mpv.command(.seek, args: [String(time), "absolute+exact"], checkError: false) { [weak self] code in
      guard code < 0 else { return }
      let callback = self?.sharePlaySeekCompletion
      self?.sharePlaySeekCompletion = nil
      self?.sharePlaySeekTarget = nil
      callback?(false)
    }
  }

  /// All ordinary UI, keyboard and plugin transport requests converge here before reaching mpv.
  func routeSharePlay(_ control: SharePlayControl) -> Bool {
    guard Thread.isMainThread, !applyingSharePlayCommand, let playback = sharePlayPlayback else { return false }
    switch control {
    case .passthrough: return false
    case .suspend:
      playback.request(control)
      return false
    case .chapter(let index):
      if info.chapters.indices.contains(index) { playback.request(.seek(info.chapters[index].time.second)) }
      else { playback.request(.blocked) }
    default: playback.request(control)
    }
    return true
  }

  func routeSharePlayProperty(_ name: String, value: String) -> Bool {
    guard Thread.isMainThread, sharePlayPlayback != nil, !applyingSharePlayCommand else { return false }
    return routeSharePlay(SharePlayCommandRouter.command(["set", name, value], snapshot: sharePlaySnapshot))
  }
}
