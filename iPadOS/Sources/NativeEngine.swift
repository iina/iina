// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import AVFoundation
import Foundation
import UIKit

/// AVPlayer owns decoding and presentation. Preparation is asynchronous and
/// either readiness or a real playback failure determines routing.
@MainActor
final class NativeEngine: @preconcurrency PlaybackEngine {
    let player = AVPlayer()
    private let deliver: (PlayerEvent) -> Void
    private var preparation: Task<Void, Never>?
    private var preparationTimeout: Task<Void, Never>?
    private var preparingAsset: AVURLAsset?
    private var observations: [NSKeyValueObservation] = []
    private var notifications: [NSObjectProtocol] = []
    private var timeObserver: Any?
    private var audioGroup: AVMediaSelectionGroup?
    private var subtitleGroup: AVMediaSelectionGroup?
    private var tracks: [MediaTrack] = []
    private var chapters: [MediaChapter] = []
    private var artist = ""
    private var album = ""
    private var title = ""
    private var codec = ""
    private var desiredPaused = false
    private var speed = 1.0
    private var speedUpdateQueued = false
    private var start = 0.0
    private var ready = false
    private var stopped = false
    private var seekGeneration = 0
    private var resumingAfterSeek = false
    private var loopRange: ClosedRange<Double>?
    private var lastDiagnostics = Date.distantPast
    private var captureGenerator: AVAssetImageGenerator?

    init(deliver: @escaping (PlayerEvent) -> Void) {
        self.deliver = deliver
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
                                                     queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                if time.seconds.isFinite { self.deliver(.number("time-pos", time.seconds)) }
                if let duration = self.player.currentItem?.duration.seconds, duration.isFinite {
                    self.deliver(.number("duration", duration))
                }
                self.reportDiagnostics()
            }
        }
        observations.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self, !self.stopped, self.ready else { return }
                let status = self.player.timeControlStatus
                // AVKit's PiP controls operate on AVPlayer directly.
                if status == .paused {
                    let atLoopEnd = self.loopRange.map { self.player.currentTime().seconds >= $0.upperBound - 0.001 } ?? false
                    if !atLoopEnd, !self.resumingAfterSeek { self.desiredPaused = true }
                }
                if status == .playing {
                    self.desiredPaused = false
                }
                self.deliver(.flag("paused-for-cache", status == .waitingToPlayAtSpecifiedRate))
                self.deliver(.flag("pause", self.desiredPaused))
            }
        })
    }

    func open(_ url: URL, start: Double, paused: Bool) {
        self.start = max(0, start)
        desiredPaused = paused
        let asset = AVURLAsset(url: url)
        preparingAsset = asset
        preparationTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(12)) }
            catch { return }
            guard let self, !self.stopped, !self.ready else { return }
            self.deliver(.failure("AVPlayer did not prepare this media within 12 seconds."))
        }
        preparation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let (playable, nativeTracks, metadata) = try await asset.load(.isPlayable, .tracks, .commonMetadata)
                guard !Task.isCancelled, !self.stopped else { return }
                guard playable else {
                    self.deliver(.failure("AVPlayer does not support this media.")); return
                }
                self.audioGroup = try await asset.loadMediaSelectionGroup(for: .audible)
                self.subtitleGroup = try await asset.loadMediaSelectionGroup(for: .legible)
                for track in nativeTracks where track.mediaType == .video {
                    let (descriptions, fps, bitrate) = try await track.load(.formatDescriptions, .nominalFrameRate, .estimatedDataRate)
                    var trackCodec = ""
                    var width = 0, height = 0
                    if let description = descriptions.first {
                        let code = CMFormatDescriptionGetMediaSubType(description)
                        let fourCC = String(bytes: [UInt8((code >> 24) & 255), UInt8((code >> 16) & 255),
                                                    UInt8((code >> 8) & 255), UInt8(code & 255)], encoding: .ascii) ?? "Video"
                        trackCodec = ["avc1": "h264", "hvc1": "hevc", "hev1": "hevc", "av01": "av1", "vp09": "vp9"][fourCC] ?? fourCC
                        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
                        width = Int(dimensions.width); height = Int(dimensions.height)
                    }
                    self.tracks.append(MediaTrack(id: Int64(track.trackID), kind: "video", title: "",
                                                   language: "", externalPath: "", albumArt: false,
                                                   codec: trackCodec, width: width, height: height,
                                                   fps: Double(fps), bitrate: Double(bitrate)))
                }
                if let group = self.audioGroup { self.appendTracks(group, kind: "audio") }
                else if nativeTracks.contains(where: { $0.mediaType == .audio }) {
                    self.tracks.append(MediaTrack(id: 1, kind: "audio", title: "Audio",
                                                   language: "", externalPath: "", albumArt: false))
                }
                if let group = self.subtitleGroup { self.appendTracks(group, kind: "sub") }
                for item in metadata {
                    guard let key = item.commonKey else { continue }
                    let value = try await item.load(.stringValue) ?? ""
                    switch key {
                    case .commonKeyTitle: self.title = value
                    case .commonKeyArtist: self.artist = value
                    case .commonKeyAlbumName: self.album = value
                    default: break
                    }
                }
                let locales = try await asset.load(.availableChapterLocales)
                if let locale = locales.first {
                    let groups = try await asset.loadChapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: [.commonKeyTitle])
                    for (index, group) in groups.enumerated() {
                        let item = group.items.first
                        let chapterTitle = try await item?.load(.stringValue) ?? "Chapter \(index + 1)"
                        self.chapters.append(MediaChapter(id: index, title: chapterTitle, time: group.timeRange.start.seconds))
                    }
                }
                guard !Task.isCancelled, !self.stopped else { return }
                let item = AVPlayerItem(asset: asset)
                item.audioTimePitchAlgorithm = .spectral
                self.observations.append(item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.statusChanged() }
                })
                self.notifications.append(NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, !self.stopped else { return }
                        if let range = self.loopRange, !self.desiredPaused {
                            self.seek(range.lowerBound, resumeAfter: true)
                            return
                        }
                        self.desiredPaused = true
                        self.deliver(.flag("pause", true))
                        self.deliver(.ended)
                    }
                })
                self.notifications.append(NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
                ) { [weak self] notification in
                    let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                    Task { @MainActor in
                        guard let self, !self.stopped else { return }
                        self.deliver(.failure(error?.localizedDescription ?? "AVPlayer could not finish playback."))
                    }
                })
                self.player.replaceCurrentItem(with: item)
            } catch {
                guard !Task.isCancelled, !self.stopped else { return }
                self.deliver(.failure("AVPlayer: \(error.localizedDescription)"))
            }
        }
    }

    private func appendTracks(_ group: AVMediaSelectionGroup, kind: String) {
        for (index, option) in group.options.enumerated() {
            tracks.append(MediaTrack(id: Int64(index + 1), kind: kind, title: option.displayName,
                                     language: option.extendedLanguageTag ?? "", externalPath: "", albumArt: false))
        }
    }

    private func statusChanged() {
        guard !stopped, let item = player.currentItem else { return }
        if item.status == .failed {
            deliver(.failure(item.error?.localizedDescription ?? "AVPlayer could not prepare this media."))
        } else if item.status == .readyToPlay, !ready {
            ready = true
            preparationTimeout?.cancel()
            preparationTimeout = nil
            let duration = item.duration.seconds
            if duration.isFinite { deliver(.number("duration", duration)) }
            deliver(.tracks(tracks))
            deliver(.chapters(chapters))
            deliver(.metadata(artist: artist, album: album))
            if !title.isEmpty { deliver(.text("media-title", title)) }
            reportVideoSelection()
            // AVPlayer does not expose the active decoder. Do not claim hardware use.
            deliver(.text("hwdec-current", "System managed"))
            reportSelection("aid", group: audioGroup)
            reportSelection("sid", group: subtitleGroup)
            deliver(.stepping(forward: item.canStepForward, backward: item.canStepBackward))
            applyLoop()
            deliver(.loaded)
            if start > 0 { seek(start, resumeAfter: true) }
            else { applyPlaybackState() }
        }
    }

    private func reportSelection(_ property: String, group: AVMediaSelectionGroup?) {
        guard let group, let option = player.currentItem?.currentMediaSelection.selectedMediaOption(in: group),
              let index = group.options.firstIndex(of: option) else {
            deliver(.text(property, property == "aid" ? "auto" : "no")); return
        }
        deliver(.text(property, String(index + 1)))
    }

    private func applyPlaybackState() {
        guard supportsRate(speed) else {
            deliver(.requiresMPV("AVPlayer cannot play this item at \(speed.formatted())×."))
            return
        }
        // AVKit resumes at defaultRate. Keep the chosen rate through PiP,
        // pause/resume, and buffering instead of sampling a transient rate.
        player.defaultRate = Float(speed)
        player.currentItem?.preferredForwardBufferDuration = min(120, 12 * max(1, speed))
        if desiredPaused { player.pause() }
        else { player.play() }
        deliver(.flag("pause", desiredPaused))
    }

    func supportsRate(_ value: Double) -> Bool {
        guard ready, let item = player.currentItem else { return true }
        if value < 1 { return item.canPlaySlowForward }
        return value <= 2 || item.canPlayFastForward
    }

    private func reportVideoSelection() {
        let enabled = player.currentItem?.tracks.first {
            $0.isEnabled && $0.assetTrack?.mediaType == .video
        }
        guard let id = enabled?.assetTrack?.trackID,
              let track = tracks.first(where: { $0.kind == "video" && $0.id == Int64(id) }) else {
            deliver(.text("vid", "no")); return
        }
        codec = track.codec
        deliver(.text("vid", String(id)))
        deliver(.text("video-codec", codec))
        deliver(.number("video-params/w", Double(track.width)))
        deliver(.number("video-params/h", Double(track.height)))
    }

    func set(_ name: String, _ value: String) {
        guard !stopped else { return }
        switch name {
        case "pause": desiredPaused = value == "yes"; if ready { applyPlaybackState() }
        case "speed":
            guard let number = Double(value) else { return }
            speed = number
            if ready, !speedUpdateQueued {
                // Apply the final choice once when several controls update in one turn.
                speedUpdateQueued = true
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.stopped else { return }
                    self.speedUpdateQueued = false
                    self.applyPlaybackState()
                }
            }
        case "volume":
            guard let number = Double(value) else { return }
            player.volume = Float(max(0, min(number, 100)) / 100)
            deliver(.number("volume", number))
        case "vid":
            guard ready, let item = player.currentItem else { return }
            let videos = item.tracks.filter { $0.assetTrack?.mediaType == .video }
            let target = value == "auto" ? videos.first?.assetTrack?.trackID : Int32(value)
            guard value == "no" || videos.contains(where: { $0.assetTrack?.trackID == target }) else {
                deliver(.failure("The selected native video track is unavailable.")); return
            }
            for track in videos {
                track.isEnabled = value != "no" && track.assetTrack?.trackID == target
            }
            reportVideoSelection()
        case "aid", "sid":
            guard let item = player.currentItem else { return }
            let group = name == "aid" ? audioGroup : subtitleGroup
            guard let group else { return }
            if value == "auto" { item.selectMediaOptionAutomatically(in: group) }
            else if value == "no" { item.select(nil, in: group) }
            else if let id = Int(value), group.options.indices.contains(id - 1) { item.select(group.options[id - 1], in: group) }
            else { deliver(.failure("The selected native media track is unavailable.")); return }
            reportSelection(name, group: group)
        default: deliver(.failure("AVPlayer cannot apply \(name)."))
        }
    }

    private func seek(_ seconds: Double, resumeAfter: Bool = false) {
        if !ready { start = seconds; return }
        seekGeneration += 1
        let generation = seekGeneration
        resumingAfterSeek = resumeAfter
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, !self.stopped, self.seekGeneration == generation else { return }
                if finished {
                    self.deliver(.seekFinished(self.player.currentTime().seconds))
                    if resumeAfter { self.applyPlaybackState() }
                } else { self.deliver(.failure("AVPlayer could not seek to the requested position.")) }
                self.resumingAfterSeek = false
            }
        }
    }

    func command(_ arguments: [String]) {
        if arguments.first == "frame-step" || arguments.first == "frame-back-step" {
            let forward = arguments.first == "frame-step"
            guard let item = player.currentItem, ready,
                  forward ? item.canStepForward : item.canStepBackward else {
                deliver(.toolFailure("This native media does not support stepping in that direction.")); return
            }
            desiredPaused = true
            player.pause()
            item.step(byCount: forward ? 1 : -1)
            deliver(.flag("pause", true))
            return
        }
        guard arguments.first == "seek", arguments.count > 1, let seconds = Double(arguments[1]) else {
            deliver(.failure("This command requires mpv.")); return
        }
        seek(seconds)
    }

    func setLoop(_ range: ClosedRange<Double>?) {
        loopRange = range
        applyLoop()
    }

    private func applyLoop() {
        player.currentItem?.forwardPlaybackEndTime = loopRange.map {
            CMTime(seconds: $0.upperBound, preferredTimescale: 600)
        } ?? .invalid
    }

    func captureFrame(completion: @escaping (Result<UIImage, Error>) -> Void) {
        guard let item = player.currentItem, ready, !stopped else {
            completion(.failure(PlaybackToolError.unavailable("Open a video before capturing a frame."))); return
        }
        let generator = AVAssetImageGenerator(asset: item.asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        captureGenerator = generator
        let time = player.currentTime()
        Task { @MainActor [weak self] in
            do {
                let result = try await generator.image(at: time)
                self?.captureGenerator = nil
                completion(.success(UIImage(cgImage: result.image)))
            } catch { self?.captureGenerator = nil; completion(.failure(error)) }
        }
    }

    private func reportDiagnostics() {
        guard ready, Date().timeIntervalSince(lastDiagnostics) >= 0.5, let item = player.currentItem else { return }
        lastDiagnostics = Date()
        var value = PlaybackDiagnostics()
        let position = player.currentTime().seconds
        let ranges = item.loadedTimeRanges.map { $0.timeRangeValue }
        if !ranges.isEmpty {
            value.bufferedSeconds = ranges.filter { CMTimeRangeContainsTime($0, time: player.currentTime()) }
                .map { max(0, CMTimeRangeGetEnd($0).seconds - position) }.max() ?? 0
        }
        if let log = item.accessLog()?.events.last {
            if log.numberOfDroppedVideoFrames >= 0 { value.droppedFrames = Double(log.numberOfDroppedVideoFrames) }
            if log.numberOfStalls >= 0 { value.stalls = Double(log.numberOfStalls) }
            if log.observedBitrate > 0 { value.observedBitrate = log.observedBitrate }
        }
        value.waitingReason = player.reasonForWaitingToPlay?.rawValue ?? ""
        deliver(.diagnostics(value))
    }

    func requestShutdown(completion: @escaping () -> Void) {
        guard !stopped else { completion(); return }
        stopped = true
        captureGenerator?.cancelAllCGImageGeneration()
        captureGenerator = nil
        preparation?.cancel()
        preparation = nil
        preparationTimeout?.cancel()
        preparationTimeout = nil
        preparingAsset?.cancelLoading()
        preparingAsset = nil
        observations.removeAll()
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        notifications.removeAll()
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        player.pause()
        player.currentItem?.asset.cancelLoading()
        player.replaceCurrentItem(with: nil)
        completion()
    }

    deinit {
        preparation?.cancel()
        preparationTimeout?.cancel()
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }
}
