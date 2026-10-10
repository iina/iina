// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import AVFoundation
import Libmpv
import UIKit

/// Copy the client API's frame before freeing the mpv node. This captures video
/// pixels at source size, independently of the inline sample-buffer size.
enum MPVFrameImage {
    static func capture(_ client: OpaquePointer) throws -> UIImage {
        let arguments: [String] = ["screenshot-raw", "video"]
        let strings = arguments.map { strdup($0) }
        defer { strings.forEach { free($0) } }
        var pointers = strings.map { $0.map { UnsafePointer<CChar>($0) } } + [nil]
        var node = mpv_node()
        let status = mpv_command_ret(client, &pointers, &node)
        defer { mpv_free_node_contents(&node) }
        guard status >= 0 else {
            throw PlaybackToolError.unavailable("Capture video frame: \(String(cString: mpv_error_string(status))).")
        }
        guard node.format == MPV_FORMAT_NODE_MAP, let list = node.u.list else {
            throw PlaybackToolError.unavailable("The decoder did not return a frame image.")
        }
        func field(_ name: String) -> mpv_node? {
            guard let keys = list.pointee.keys, let values = list.pointee.values else { return nil }
            for index in 0..<Int(list.pointee.num) {
                if let key = keys[index], String(cString: key) == name { return values[index] }
            }
            return nil
        }
        guard let w = field("w"), let h = field("h"), let s = field("stride"),
              let raw = field("data"), raw.format == MPV_FORMAT_BYTE_ARRAY, let array = raw.u.ba,
              let bytes = array.pointee.data else { throw PlaybackToolError.unavailable("The captured frame is incomplete.") }
        let width = Int(w.u.int64), height = Int(h.u.int64), stride = Int(s.u.int64)
        guard width > 0, height > 0, width <= 16384, height <= 16384, abs(stride) >= width * 4 else {
            throw PlaybackToolError.unavailable("The captured frame has invalid dimensions.")
        }
        var data = Data(count: width * height * 4)
        data.withUnsafeMutableBytes { destination in
            for row in 0..<height {
                memcpy(destination.baseAddress!.advanced(by: row * width * 4), bytes.advanced(by: row * stride), width * 4)
            }
        }
        guard let provider = CGDataProvider(data: data as CFData), let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue).union(.byteOrder32Little),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw PlaybackToolError.unavailable("Unable to create the captured frame image.")
        }
        return UIImage(cgImage: image)
    }
}

/// A separate, silent mpv client handles thumbnails for assets AVFoundation
/// cannot read. It never seeks or changes the playing client.
final class MPVThumbnailDecoder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.local.iinapad.thumbnails", qos: .utility)
    private let lock = NSLock()
    private var revision = 0

    func cancel() { lock.lock(); revision += 1; lock.unlock() }

    private func nextTicket() -> Int {
        lock.lock(); defer { lock.unlock() }; revision += 1; return revision
    }

    func image(url: URL, time: Double) async throws -> UIImage {
        let ticket = nextTicket()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do { continuation.resume(returning: try decode(url: url, time: time, ticket: ticket)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func current(_ ticket: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }; return revision == ticket
    }

    private func decode(url: URL, time: Double, ticket: Int) throws -> UIImage {
        guard current(ticket) else { throw CancellationError() }
        guard let client = mpv_create() else { throw PlaybackToolError.unavailable("Unable to create the thumbnail decoder.") }
        defer { mpv_terminate_destroy(client) }
        for (key, value) in [("vo", "null"), ("audio", "no"), ("sid", "no"), ("pause", "yes"),
                             ("keep-open", "yes"), ("config", "no"), ("load-scripts", "no"),
                             ("hwdec", "auto-copy"), ("vf", "scale=320:-2"), ("start", String(max(0, time)))] {
            let status = mpv_set_option_string(client, key, value)
            guard status >= 0 else { throw PlaybackToolError.unavailable("Thumbnail option \(key): \(String(cString: mpv_error_string(status))).") }
        }
        let initialized = mpv_initialize(client)
        guard initialized >= 0 else { throw PlaybackToolError.unavailable("Unable to initialize the thumbnail decoder.") }
        let strings = ["loadfile", url.isFileURL ? url.path : url.absoluteString].map { strdup($0) }
        defer { strings.forEach { free($0) } }
        var pointers = strings.map { $0.map { UnsafePointer<CChar>($0) } } + [nil]
        let opened = mpv_command(client, &pointers)
        guard opened >= 0 else { throw PlaybackToolError.unavailable("Unable to open this media for a preview.") }
        let deadline = Date().addingTimeInterval(8)
        while current(ticket), Date() < deadline {
            guard let event = mpv_wait_event(client, 0.05) else { continue }
            if event.pointee.event_id == MPV_EVENT_PLAYBACK_RESTART {
                return try MPVFrameImage.capture(client)
            }
            if event.pointee.event_id == MPV_EVENT_END_FILE, let data = event.pointee.data {
                let end = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                if end.reason == MPV_END_FILE_REASON_ERROR {
                    throw PlaybackToolError.unavailable("Thumbnail decode: \(String(cString: mpv_error_string(end.error))).")
                }
            }
        }
        guard current(ticket) else { throw CancellationError() }
        throw PlaybackToolError.unavailable("The preview decoder did not produce a frame within 8 seconds.")
    }
}

@MainActor
final class SeekPreview: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var message = ""
    @Published private(set) var time = 0.0
    private let cache = NSCache<NSString, UIImage>()
    private let decoder = MPVThumbnailDecoder()
    private var generator: AVAssetImageGenerator?
    private var url: URL?
    private var revision = UUID()

    init() { cache.countLimit = 80; cache.totalCostLimit = 16 * 1024 * 1024 }

    func cancel() {
        revision = UUID(); generator?.cancelAllCGImageGeneration(); decoder.cancel()
    }

    func show(url: URL?, seconds: Double, duration: Double, allowRemote: Bool) async {
        cancel()
        let ticket = revision
        image = nil; message = ""; time = seconds
        guard let url, seconds.isFinite else { return }
        let interval = max(1, duration / 120)
        let target = floor(seconds / interval) * interval
        let key = "\(url.absoluteString)|\(target)" as NSString
        if let cached = cache.object(forKey: key) { image = cached; time = target; return }
        // File-provider paths may conceal a network source. Default to no
        // extra reads for external documents until the user enables previews.
        if !allowRemote && (!url.isFileURL || !url.path.hasPrefix(NSHomeDirectory() + "/")) {
            message = "Enable Files / network previews in Layout"; return
        }
        do {
            try await Task.sleep(for: .milliseconds(250))
            guard ticket == revision, !Task.isCancelled else { return }
            if self.url != url {
                self.url = url
                generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator?.appliesPreferredTrackTransform = true
                generator?.maximumSize = CGSize(width: 320, height: 180)
            }
            let result: UIImage
            do {
                guard let generator else { throw PlaybackToolError.unavailable("The preview generator is unavailable.") }
                let native = try await generator.image(at: CMTime(seconds: target, preferredTimescale: 600))
                result = UIImage(cgImage: native.image)
            } catch {
                guard ticket == revision, !Task.isCancelled else { return }
                result = try await decoder.image(url: url, time: target)
            }
            guard ticket == revision, !Task.isCancelled else { return }
            cache.setObject(result, forKey: key, cost: Int(result.size.width * result.size.height * 4))
            image = result; time = target
        } catch is CancellationError { }
        catch {
            if ticket == revision, !Task.isCancelled { message = error.localizedDescription }
        }
    }
}
