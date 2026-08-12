import Foundation

/// Remuxes the current file to a growing fMP4 HLS event playlist using libavformat
/// in-process (`HLSRemuxer`) — no bundled ffmpeg CLI. Reports ready as soon as the first
/// segment is written (the remux keeps running in the background).
final class HLSPackager {
  enum PackagerError: Error { case notReady }

  private(set) var outputDir: URL?
  private var remuxer: HLSRemuxer?
  private var pollTimer: DispatchSourceTimer?
  private var isStopped = false

  /// Remuxes the whole file to a paced HLS playlist. With `subtitleIndex` the output is a
  /// master playlist (`master.m3u8`) with a WebVTT subtitle rendition; without it, a single
  /// media playlist (`out.m3u8`).
  ///
  /// - `onReady` fires once the first segment exists (enough to engage the AirPlay route).
  /// - `onComplete` fires once the remux has finished.
  func start(input: URL, startSeconds: Double, audioIndex: Int, subtitleIndex: Int?,
             onReady: @escaping (Result<URL, Error>) -> Void,
             onComplete: @escaping (URL) -> Void) {
    isStopped = false
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iina-airplay-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    outputDir = dir
    // Subtitle mode emits a master playlist; otherwise a single media playlist.
    let playlist = dir.appendingPathComponent(subtitleIndex != nil ? "master.m3u8" : "out.m3u8")
    let initFile = dir.appendingPathComponent("init.mp4")

    let remuxer = HLSRemuxer(input: input.path, outputDir: dir.path, startSeconds: startSeconds,
                             audioIndex: Int32(audioIndex), subtitleIndex: Int32(subtitleIndex ?? -1))
    self.remuxer = remuxer
    remuxer.onFinished = { [weak self] in
      guard let self = self, !self.isStopped else { return }
      NSLog("AirPlay/libav: remux finished")
      onComplete(playlist)
    }
    Logger.log("AirPlay/libav: remuxing \(input.lastPathComponent) (audio \(audioIndex), sub \(String(describing: subtitleIndex)))")
    remuxer.start()

    // Poll until the served playlist exists and a media segment has been written — enough to
    // load an item and engage the route. (In subtitle mode the master playlist references a
    // variant, so check for a segment file on disk rather than ".m4s" in the playlist text.)
    var ticks = 0
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
    timer.schedule(deadline: .now() + 0.2, repeating: 0.2)
    timer.setEventHandler { [weak self] in
      guard let self = self else { timer.cancel(); return }
      if self.isStopped { timer.cancel(); return }
      ticks += 1
      let fm = FileManager.default
      let hasPlaylist = fm.fileExists(atPath: playlist.path)
      let hasInit = fm.fileExists(atPath: initFile.path)
      let hasSegment = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).contains { $0.hasSuffix(".m4s") }
      if hasPlaylist && hasInit && hasSegment {
        timer.cancel()
        Logger.log("AirPlay/libav: first segment ready after ~\(Double(ticks) * 0.2)s")
        DispatchQueue.main.async { onReady(.success(playlist)) }
      } else if ticks > 50 {   // ~10s: nothing written → fail (caller retries without subs)
        timer.cancel()
        Logger.log("AirPlay/libav: timed out (no segment)", level: .error)
        DispatchQueue.main.async { onReady(.failure(PackagerError.notReady)) }
      }
    }
    pollTimer = timer
    timer.resume()
  }

  /// Stops real-time pacing so the rest of the file is written quickly (fills the receiver's
  /// buffer, enables forward seeking). Call once playback has started near the beginning.
  func releasePacing() { remuxer?.releasePacing() }

  func stop() {
    isStopped = true
    pollTimer?.cancel(); pollTimer = nil
    remuxer?.stop()
    remuxer = nil
  }

  func cleanup() {
    if let dir = outputDir { try? FileManager.default.removeItem(at: dir) }
    outputDir = nil
  }
}
