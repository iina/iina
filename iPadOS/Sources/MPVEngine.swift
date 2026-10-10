// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import Foundation
import AVFoundation
import Libmpv
import UIKit

struct MediaTrack: Identifiable {
    let id: Int64
    let kind: String
    let title: String
    let language: String
    let externalPath: String
    let albumArt: Bool
    var codec = ""
    var width = 0
    var height = 0
    var fps = 0.0
    var bitrate = 0.0
    var isDefault = false

    var label: String {
        let parts = [title, language].filter { !$0.isEmpty }
        return parts.isEmpty ? "Track \(id)" : parts.joined(separator: " · ")
    }

    var videoLabel: String {
        var details: [String] = []
        if !codec.isEmpty { details.append(codec) }
        if width > 0 && height > 0 { details.append("\(width)×\(height)") }
        if fps > 0 { details.append("\(fps.formatted(.number.precision(.fractionLength(0...2)))) fps") }
        if isDefault { details.append("Default") }
        let name = title.isEmpty ? "No Title" : title
        return details.isEmpty ? name : "\(name) (\(details.joined(separator: ", ")))"
    }
}

struct MediaChapter: Identifiable {
    let id: Int
    let title: String
    let time: Double
}

enum PlayerEvent {
    case number(String, Double)
    case flag(String, Bool)
    case text(String, String)
    case tracks([MediaTrack])
    case chapters([MediaChapter])
    case metadata(artist: String, album: String)
    case diagnostics(PlaybackDiagnostics)
    case stepping(forward: Bool, backward: Bool)
    case toolFailure(String)
    case seekFinished(Double?)
    case videoSettingsApplied(VideoSettings)
    case requiresMPV(String)
    case loaded
    case ended
    case failure(String)
}

/// All libmpv access and event consumption run on one serial worker.
/// mpv owns its decoding/rendering threads; this worker never decodes on the UI thread.
final class MPVEngine: PlaybackEngine {
    private let queue = DispatchQueue(label: "dev.local.iinapad.mpv", qos: .userInitiated)
    private let queueKey = DispatchSpecificKey<Bool>()
    private var handle: OpaquePointer?
    private let timebase: CMTimebase
    private let frame: (CMSampleBuffer) -> Void
    private var renderer: MPVSampleRenderer?
    private let deliver: (PlayerEvent) -> Void
    private var appliedVideoSettings: VideoSettings?
    private let lookupFolder = FileManager.default.temporaryDirectory.appendingPathComponent("IINA-Video-\(UUID().uuidString)", isDirectory: true)
    private var lookupFiles: [URL] = []
    private var currentLookup: URL?
    private var appliedCrop = ""
    private var diagnosticsTimer: DispatchSourceTimer?

    init(timebase: CMTimebase, frame: @escaping (CMSampleBuffer) -> Void, deliver: @escaping (PlayerEvent) -> Void) {
        self.timebase = timebase
        self.frame = frame
        self.deliver = deliver
        queue.setSpecific(key: queueKey, value: true)
        queue.async { [weak self] in self?.initialize() }
    }

    private func initialize() {
        guard let client = mpv_create() else {
            deliver(.failure("The playback engine could not be created."))
            return
        }
        handle = client
        #if targetEnvironment(simulator)
        // This simulator runtime rejects VideoToolbox H.264 sessions (-12906).
        let hardwareDecoder = "no"
        #else
        let hardwareDecoder = "videotoolbox-copy"
        #endif
        let options = [
            ("vo", "libmpv"),
            ("hwdec", hardwareDecoder), ("keep-open", "yes"), ("idle", "yes"),
            ("config", "no"), ("load-scripts", "no"),
            ("input-default-bindings", "no"), ("osd-level", "0"),
            ("target-colorspace-hint", "no"), ("volume-max", "100"),
            ("demuxer-max-bytes", "128MiB"), ("demuxer-max-back-bytes", "16MiB"),
            ("cache-secs", "30"), ("cache-pause-wait", "2")
        ]
        for (name, value) in options {
            guard check(mpv_set_option_string(client, name, value), operation: "Set \(name)") else {
                destroyOnWorker()
                return
            }
        }
        guard check(mpv_initialize(client), operation: "Initialize playback") else {
            destroyOnWorker()
            return
        }
        guard check(mpv_request_log_messages(client, "error"), operation: "Observe video-processing errors") else {
            destroyOnWorker()
            return
        }
        do {
            renderer = try MPVSampleRenderer(client: client, timebase: timebase, deliver: frame) { [weak self] message in
                self?.deliver(.failure(message))
            }
        } catch {
            deliver(.failure(error.localizedDescription))
            destroyOnWorker()
            return
        }

        for name in ["time-pos", "duration", "volume", "sub-delay", "secondary-sub-delay", "audio-delay",
                     "video-params/w", "video-params/h", "video-out-params/w", "video-out-params/h"] {
            guard check(mpv_observe_property(client, 0, name, MPV_FORMAT_DOUBLE), operation: "Observe \(name)") else {
                destroyOnWorker()
                return
            }
        }
        for name in ["pause", "paused-for-cache", "eof-reached"] {
            guard check(mpv_observe_property(client, 0, name, MPV_FORMAT_FLAG), operation: "Observe \(name)") else {
                destroyOnWorker()
                return
            }
        }
        for name in ["aid", "vid", "sid", "secondary-sid", "media-title", "hwdec-current", "video-codec"] {
            guard check(mpv_observe_property(client, 0, name, MPV_FORMAT_STRING), operation: "Observe \(name)") else {
                destroyOnWorker()
                return
            }
        }
        guard check(mpv_observe_property(client, 0, "track-list", MPV_FORMAT_NODE), operation: "Observe tracks"),
              check(mpv_observe_property(client, 0, "chapter-list", MPV_FORMAT_NODE), operation: "Observe chapters"),
              check(mpv_observe_property(client, 0, "metadata", MPV_FORMAT_NODE), operation: "Observe metadata") else {
            destroyOnWorker()
            return
        }
        mpv_set_wakeup_callback(client, { context in
            guard let context else { return }
            let engine = Unmanaged<MPVEngine>.fromOpaque(context).takeUnretainedValue()
            engine.queue.async { [weak engine] in engine?.drainEvents() }
        }, Unmanaged.passUnretained(self).toOpaque())
        drainEvents()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in self?.reportDiagnostics() }
        diagnosticsTimer = timer
        timer.resume()
    }

    func open(_ url: URL, start: Double = 0, paused: Bool = false) {
        // A file URL's path avoids percent-encoding ambiguities; network URLs retain their encoding.
        // Files exposes SMB documents as file URLs, so mpv's automatic
        // network detection cannot reliably enable its cache for them.
        set("cache", url.isFileURL ? "yes" : "auto")
        set("cache-pause-initial", url.isFileURL ? "yes" : "no")
        set("stream-buffer-size", url.isFileURL ? "1MiB" : "128KiB")
        set("start", String(max(0, start)))
        set("pause", paused ? "yes" : "no")
        command(["loadfile", url.isFileURL ? url.path : url.absoluteString, "replace"])
    }

    func resize(_ size: CGSize) {
        queue.async { [weak self] in self?.renderer?.resize(size) }
    }

    func applyVideoSettings(_ settings: VideoSettings) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let client = self.handle else {
                self.deliver(.failure("The playback engine is unavailable. Close and reopen the app."))
                return
            }
            let previous = self.appliedVideoSettings
            var changes: [(String, String)] = []
            if previous?.aspectValue != settings.aspectValue {
                changes.append(("video-aspect-override", settings.aspectValue))
            }
            let colorsChanged = previous == nil || VideoAdjustment.allCases.contains {
                previous?[$0] != settings[$0]
            }
            if colorsChanged {
                if settings.hasColorAdjustments {
                    do {
                        try FileManager.default.createDirectory(at: self.lookupFolder, withIntermediateDirectories: true)
                        let file = self.lookupFolder.appendingPathComponent("\(UUID().uuidString).cube")
                        try settings.colorLookupTable().write(to: file, atomically: true, encoding: .utf8)
                        self.lookupFiles.append(file)
                        self.currentLookup = file
                    } catch {
                        self.deliver(.failure("Unable to prepare video color adjustments: \(error.localizedDescription)"))
                        return
                    }
                } else { self.currentLookup = nil }
            }
            if previous?.rotation != settings.rotation || colorsChanged {
                changes.append(("vf", settings.filterGraph(colorLUT: self.currentLookup)))
            }
            if previous?.hardwareDecoding != settings.hardwareDecoding {
                #if targetEnvironment(simulator)
                let decoder = "no"
                #else
                let decoder = settings.hardwareDecoding ? "videotoolbox-copy" : "no"
                #endif
                changes.append(("hwdec", decoder))
            }
            for (name, value) in changes {
                guard self.check(mpv_set_property_string(client, name, value), operation: "Set \(name)") else {
                    self.appliedVideoSettings = nil
                    return
                }
            }
            self.appliedVideoSettings = settings
            guard self.refreshVideoCrop() else { return }
            // Reprocess the paused source frame through a replaced filter graph.
            // Otherwise mpv can keep showing the cached output of the old graph.
            if changes.contains(where: { $0.0 == "vf" }), self.readString("pause") == "yes",
               self.readDouble("time-pos") != nil {
                guard self.commandOnWorker(["seek", "0", "relative+exact"]) else { return }
            }
            self.deliver(.videoSettingsApplied(settings))
        }
    }

    @discardableResult
    private func refreshVideoCrop() -> Bool {
        guard let settings = appliedVideoSettings, let client = handle else { return true }
        let width = readDouble("video-out-params/w") ?? 0
        let height = readDouble("video-out-params/h") ?? 0
        if settings.crop != .original && (width < 2 || height < 2) { return true }
        let value = settings.cropRectangle(in: CGSize(width: width, height: height))
        guard value != appliedCrop else { return true }
        guard check(mpv_set_property_string(client, "video-crop", value), operation: "Set video crop") else { return false }
        appliedCrop = value
        return true
    }

    func set(_ name: String, _ value: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let client = self.handle else {
                self.deliver(.failure("The playback engine is unavailable. Close and reopen the app."))
                return
            }
            guard self.check(mpv_set_property_string(client, name, value), operation: "Set \(name)") else { return }
            if name == "speed", let rate = Double(value) {
                // These are media seconds: 2× consumes twice as much data
                // per wall-clock second. Keep memory bounded independently.
                let buffering = [("cache-secs", min(120, 30 * max(1, rate))),
                                 ("cache-pause-wait", 2 * max(1, rate))]
                for (option, seconds) in buffering {
                    guard self.check(mpv_set_property_string(client, option, String(seconds)),
                                     operation: "Set \(option)") else { return }
                }
            }
        }
    }

    func command(_ arguments: [String]) {
        queue.async { [weak self] in
            self?.commandOnWorker(arguments)
        }
    }

    func captureFrame(completion: @escaping (Result<UIImage, Error>) -> Void) {
        queue.async { [weak self] in
            let result = Result<UIImage, Error> {
                guard let client = self?.handle else { throw PlaybackToolError.unavailable("The playback engine is unavailable.") }
                return try MPVFrameImage.capture(client)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func reportDiagnostics() {
        guard handle != nil else { return }
        var value = PlaybackDiagnostics()
        value.bufferedSeconds = readDouble("demuxer-cache-duration")
        value.cacheBytes = readDouble("demuxer-cache-state/fw-bytes")
        value.droppedFrames = readDouble("frame-drop-count")
        value.decoderDroppedFrames = readDouble("decoder-frame-drop-count")
        renderer?.statistics { [weak self] milliseconds, frames, dropped, size in
            value.renderingMilliseconds = milliseconds
            value.renderedFrames = frames
            value.rendererDroppedFrames = dropped
            value.renderedSize = size
            self?.deliver(.diagnostics(value))
        }
    }

    @discardableResult
    private func commandOnWorker(_ arguments: [String]) -> Bool {
        guard let client = handle else {
            deliver(.failure("The playback engine is unavailable. Close and reopen the app."))
            return false
        }
        let strings = arguments.map { strdup($0) }
        defer { strings.forEach { free($0) } }
        guard strings.allSatisfy({ $0 != nil }) else {
            deliver(.failure("Not enough memory to send a playback command.")); return false
        }
        var pointers = strings.map { $0.map { UnsafePointer<CChar>($0) } }
        pointers.append(nil)
        return check(mpv_command(client, &pointers), operation: arguments.first ?? "Playback command")
    }

    @discardableResult
    private func check(_ status: Int32, operation: String) -> Bool {
        guard status < 0 else { return true }
        deliver(.failure("\(operation): \(String(cString: mpv_error_string(status)))."))
        return false
    }

    private func drainEvents() {
        guard let client = handle else { return }
        while let event = mpv_wait_event(client, 0), event.pointee.event_id != MPV_EVENT_NONE {
            switch event.pointee.event_id {
            case MPV_EVENT_LOG_MESSAGE:
                if let data = event.pointee.data {
                    let message = data.assumingMemoryBound(to: mpv_event_log_message.self).pointee
                    let prefix = String(cString: message.prefix)
                    if prefix.hasPrefix("vf") || prefix == "lavfi" {
                        deliver(.failure("Video processing: \(String(cString: message.text).trimmingCharacters(in: .whitespacesAndNewlines))"))
                    }
                }
            case MPV_EVENT_FILE_LOADED:
                let tracks = readTracks()
                deliver(.tracks(tracks))
                deliver(.stepping(forward: tracks.contains { $0.kind == "video" && !$0.albumArt },
                                  backward: readString("seekable") == "yes" && tracks.contains { $0.kind == "video" && !$0.albumArt }))
                deliver(.chapters(readChapters()))
                readMetadata()
                deliver(.loaded)
            case MPV_EVENT_VIDEO_RECONFIG:
                refreshVideoCrop()
            case MPV_EVENT_PLAYBACK_RESTART:
                refreshVideoCrop()
                pruneLookupFiles()
                deliver(.seekFinished(readDouble("time-pos")))
            case MPV_EVENT_END_FILE:
                guard let data = event.pointee.data else { continue }
                let end = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                if end.reason == MPV_END_FILE_REASON_ERROR {
                    deliver(.failure("Unable to play this media: \(String(cString: mpv_error_string(end.error)))."))
                }
            case MPV_EVENT_PROPERTY_CHANGE:
                guard let raw = event.pointee.data else { continue }
                let property = raw.assumingMemoryBound(to: mpv_event_property.self).pointee
                let name = String(cString: property.name)
                guard let data = property.data else { continue } // mpv marks unavailable properties with nil.
                switch property.format {
                case MPV_FORMAT_DOUBLE:
                    let value = data.assumingMemoryBound(to: Double.self).pointee
                    if value.isFinite { deliver(.number(name, value)) }
                case MPV_FORMAT_FLAG:
                    let value = data.assumingMemoryBound(to: Int32.self).pointee != 0
                    if name == "eof-reached", value { deliver(.ended) }
                    else { deliver(.flag(name, value)) }
                case MPV_FORMAT_STRING:
                    if let string = data.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee {
                        deliver(.text(name, String(cString: string)))
                    }
                case MPV_FORMAT_NODE:
                    if name == "track-list" { deliver(.tracks(readTracks())) }
                    if name == "chapter-list" { deliver(.chapters(readChapters())) }
                    if name == "metadata" { readMetadata() }
                default: break
                }
            case MPV_EVENT_SHUTDOWN:
                deliver(.failure("The playback engine shut down unexpectedly."))
                return
            default: break
            }
        }
    }

    private func readString(_ name: String) -> String {
        guard let client = handle, let result = mpv_get_property_string(client, name) else { return "" }
        defer { mpv_free(result) }
        return String(cString: result)
    }

    private func readInt(_ name: String) -> Int64 {
        guard let client = handle else { return 0 }
        var value: Int64 = 0
        let result = mpv_get_property(client, name, MPV_FORMAT_INT64, &value)
        // Track/chapter metadata is optional and can disappear when a file is replaced.
        return result >= 0 ? value : 0
    }

    private func readDouble(_ name: String) -> Double? {
        guard let client = handle else { return nil }
        var value = 0.0
        guard mpv_get_property(client, name, MPV_FORMAT_DOUBLE, &value) >= 0, value.isFinite else { return nil }
        return value
    }

    private func readTracks() -> [MediaTrack] {
        let count = Int(readInt("track-list/count"))
        guard count > 0 else { return [] }
        return (0..<count).compactMap { index in
            let root = "track-list/\(index)"
            let kind = readString("\(root)/type")
            guard ["audio", "sub", "video"].contains(kind) else { return nil }
            return MediaTrack(id: readInt("\(root)/id"), kind: kind,
                              title: readString("\(root)/title"), language: readString("\(root)/lang"),
                              externalPath: readString("\(root)/external-filename"),
                              albumArt: readString("\(root)/albumart") == "yes",
                              codec: readString("\(root)/codec"),
                              width: Int(readInt("\(root)/demux-w")), height: Int(readInt("\(root)/demux-h")),
                              fps: readDouble("\(root)/demux-fps") ?? 0,
                              bitrate: readDouble("\(root)/demux-bitrate") ?? 0,
                              isDefault: readString("\(root)/default") == "yes")
        }
    }

    private func readMetadata() {
        deliver(.metadata(artist: readString("metadata/by-key/ARTIST"), album: readString("metadata/by-key/ALBUM")))
    }

    private func pruneLookupFiles() {
        while lookupFiles.count > 2 {
            do {
                try FileManager.default.removeItem(at: lookupFiles[0])
                lookupFiles.removeFirst()
            } catch {
                deliver(.failure("Unable to remove an old video lookup file: \(error.localizedDescription)"))
                return
            }
        }
    }

    private func readChapters() -> [MediaChapter] {
        let count = Int(readInt("chapter-list/count"))
        guard count > 0, let client = handle else { return [] }
        return (0..<count).compactMap { index in
            var time = 0.0
            guard mpv_get_property(client, "chapter-list/\(index)/time", MPV_FORMAT_DOUBLE, &time) >= 0 else { return nil }
            let title = readString("chapter-list/\(index)/title")
            return MediaChapter(id: index, title: title.isEmpty ? "Chapter \(index + 1)" : title, time: time)
        }
    }

    private func destroyOnWorker(completion: @escaping () -> Void = {}) {
        diagnosticsTimer?.cancel()
        diagnosticsTimer = nil
        guard let client = handle else { completion(); return }
        handle = nil
        mpv_set_wakeup_callback(client, nil, nil)
        if let renderer {
            self.renderer = nil
            renderer.shutdown { [self] in queue.async {
                mpv_terminate_destroy(client)
                self.cleanupLookupFiles()
                completion()
            } }
        } else { mpv_terminate_destroy(client); cleanupLookupFiles(); completion() }
    }

    private func cleanupLookupFiles() {
        guard FileManager.default.fileExists(atPath: lookupFolder.path) else { return }
        do { try FileManager.default.removeItem(at: lookupFolder); lookupFiles = [] }
        catch { deliver(.failure("Unable to remove temporary video lookup files: \(error.localizedDescription)")) }
    }

    func shutdown() {
        if DispatchQueue.getSpecific(key: queueKey) == true { destroyOnWorker() }
        else { queue.sync { destroyOnWorker() } }
    }

    /// Free the render context before destroying the client, without blocking the UI.
    func requestShutdown(completion: @escaping () -> Void) {
        queue.async { [self] in destroyOnWorker(completion: completion) }
    }

    deinit { shutdown() }
}
