// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import AVFoundation
import Foundation
import Libmpv

/// Rendering and client commands use separate workers. A bounded pixel pool and
/// single-slot mailbox drop old frames when the UI is busy.
final class MPVSampleRenderer {
    private let queue = DispatchQueue(label: "dev.local.iinapad.render", qos: .userInitiated)
    private let lock = NSLock()
    private var scheduled = false
    private var stopped = false
    private var pendingFrame: CMSampleBuffer?
    private var deliveryScheduled = false
    private var context: OpaquePointer?
    private var pool: CVPixelBufferPool?
    private var size = CGSize(width: 640, height: 360)
    private var poolSize = CGSize.zero
    private let timebase: CMTimebase
    private let deliver: (CMSampleBuffer) -> Void
    private let failure: (String) -> Void
    private var reportedError = false
    private var renderedFrames = 0
    private var droppedFrames = 0
    private var renderingMilliseconds = 0.0

    func statistics(_ receive: @escaping (Double, Int, Int, CGSize) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            receive(self.renderingMilliseconds, self.renderedFrames, self.droppedFrames, self.poolSize)
        }
    }

    init(client: OpaquePointer, timebase: CMTimebase,
         deliver: @escaping (CMSampleBuffer) -> Void, failure: @escaping (String) -> Void) throws {
        self.timebase = timebase
        self.deliver = deliver
        self.failure = failure
        let status: Int32 = queue.sync {
            "sw".withCString { api in
                var parameters = [mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE,
                                                  data: UnsafeMutableRawPointer(mutating: api)),
                                  mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)]
                return mpv_render_context_create(&context, client, &parameters)
            }
        }
        guard status >= 0, let context else {
            throw NSError(domain: "IINA.mpv", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Create video renderer: \(String(cString: mpv_error_string(status)))."])
        }
        queue.sync {
            mpv_render_context_set_update_callback(context, { pointer in
                guard let pointer else { return }
                Unmanaged<MPVSampleRenderer>.fromOpaque(pointer).takeUnretainedValue().schedule()
            }, Unmanaged.passUnretained(self).toOpaque())
        }
    }

    func resize(_ value: CGSize) {
        queue.async { [weak self] in
            guard let self, self.size != value else { return }
            self.size = CGSize(width: max(2, floor(value.width / 2) * 2),
                               height: max(2, floor(value.height / 2) * 2))
            self.render(force: true)
        }
    }

    private func schedule() {
        lock.lock()
        guard !stopped, !scheduled else { lock.unlock(); return }
        scheduled = true
        lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.scheduled = false; self.lock.unlock()
            self.render(force: false)
        }
    }

    private func render(force: Bool) {
        guard let context else { return }
        let flags = mpv_render_context_update(context)
        guard force || flags & 1 != 0 else { return }
        let started = ProcessInfo.processInfo.systemUptime
        let width = Int(size.width), height = Int(size.height)
        if pool == nil || poolSize != size {
            pool = nil
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferBytesPerRowAlignmentKey as String: 64,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            let status = CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
            guard status == kCVReturnSuccess else { report("Create video buffer pool: \(status)."); return }
            poolSize = size
        }
        guard let pool else { return }
        var pixel: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            nil, pool, [kCVPixelBufferPoolAllocationThresholdKey as String: 4] as CFDictionary, &pixel)
        guard status == kCVReturnSuccess, let pixel else {
            if status != kCVReturnWouldExceedAllocationThreshold { report("Allocate video frame: \(status).") }
            skipFrame(context)
            droppedFrames += 1
            return
        }
        guard CVPixelBufferLockBaseAddress(pixel, []) == kCVReturnSuccess else {
            report("Unable to lock the video frame."); return
        }
        let stride = CVPixelBufferGetBytesPerRow(pixel)
        var dimensions = [Int32(width), Int32(height)]
        var rowBytes = stride
        guard let bytes = CVPixelBufferGetBaseAddress(pixel) else {
            CVPixelBufferUnlockBaseAddress(pixel, []); report("The video frame has no pixel storage."); return
        }
        let rendered = dimensions.withUnsafeMutableBytes { dimensionsPointer in
            withUnsafeMutablePointer(to: &rowBytes) { stridePointer in
                "bgr0".withCString { format in
                    var parameters = [
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: dimensionsPointer.baseAddress),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: UnsafeMutableRawPointer(mutating: format)),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: stridePointer),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: bytes),
                        mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                    ]
                    return mpv_render_context_render(context, &parameters)
                }
            }
        }
        if rendered >= 0 {
            // BGRX has undefined alpha; Core Video's BGRA must be opaque.
            let pixels = bytes.assumingMemoryBound(to: UInt32.self)
            for row in 0..<height {
                let offset = row * stride / 4
                for column in 0..<width { pixels[offset + column] |= 0xFF000000 }
            }
        }
        CVPixelBufferUnlockBaseAddress(pixel, [])
        guard rendered >= 0 else { report("Render video: \(String(cString: mpv_error_string(rendered)))."); return }
        var description: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixel,
                                                                       formatDescriptionOut: &description)
        guard formatStatus == noErr, let description else { report("Describe video frame: \(formatStatus)."); return }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTimebaseGetTime(timebase),
                                       decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixel,
            formatDescription: description, sampleTiming: &timing, sampleBufferOut: &sample)
        guard sampleStatus == noErr, let sample else { report("Package video frame: \(sampleStatus)."); return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary] {
            attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        renderedFrames += 1
        renderingMilliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1000
        if pendingFrame != nil { droppedFrames += 1 }
        pendingFrame = sample
        let needsDelivery = !deliveryScheduled
        deliveryScheduled = true
        lock.unlock()
        if needsDelivery {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let frame = self.pendingFrame
                self.pendingFrame = nil
                self.deliveryScheduled = false
                let active = !self.stopped
                self.lock.unlock()
                if active, let frame { self.deliver(frame) }
            }
        }
    }

    private func skipFrame(_ context: OpaquePointer) {
        var skip: Int32 = 1
        withUnsafeMutablePointer(to: &skip) { pointer in
            var parameters = [mpv_render_param(type: MPV_RENDER_PARAM_SKIP_RENDERING, data: pointer),
                              mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)]
            _ = mpv_render_context_render(context, &parameters)
        }
    }

    private func report(_ message: String) {
        guard !reportedError else { return }
        reportedError = true
        failure(message)
    }

    func shutdown(completion: @escaping () -> Void) {
        lock.lock(); stopped = true; pendingFrame = nil; lock.unlock()
        queue.async { [self] in
            if let context {
                mpv_render_context_set_update_callback(context, nil, nil)
                mpv_render_context_free(context)
                self.context = nil
            }
            pool = nil
            completion()
        }
    }
}
