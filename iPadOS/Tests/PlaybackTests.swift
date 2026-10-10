// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import XCTest
import UIKit
import SwiftUI
import MediaPlayer
import AVFoundation
@testable import IINAPad

final class PlaybackTests: XCTestCase {
    @MainActor
    private func waitUntil(_ message: String, timeout: Double = 12, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(condition(), message)
    }

    @MainActor
    func testPlaybackDualSubtitlesAndBackgroundAudio() async throws {
        let player = PlayerModel()
        let savedStyle = player.subtitleStyle
        defer { player.updateSubtitleStyle(savedStyle) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let surface = VideoSurfaceView(frame: controller.view.bounds)
        controller.view.addSubview(surface)
        player.attach(to: surface)
        let bundle = Bundle(for: Self.self)
        player.add([try XCTUnwrap(bundle.url(forResource: "playback", withExtension: "mkv"))])
        try await waitUntil("The MKV did not load") { player.duration > 10 && player.tracks.contains { $0.kind == "sub" } }
        XCTAssertNil(player.failure, player.failure?.message ?? "")
        XCTAssertEqual(player.backend, .mpv)
        try await waitUntil("Playback did not advance") { player.position > 0.5 }
        #if !targetEnvironment(simulator)
        XCTAssertTrue(player.decoder.hasPrefix("videotoolbox"), "The physical iPad did not use VideoToolbox: \(player.decoder)")
        #endif
        player.setPaused(true)
        try await waitUntil("Pause was not acknowledged") { player.paused }
        let primary = try XCTUnwrap(player.tracks.first { $0.kind == "sub" })
        player.selectSubtitle(String(primary.id))
        player.addSubtitle(try XCTUnwrap(bundle.url(forResource: "secondary", withExtension: "srt")), target: .secondary)
        try await waitUntil("The secondary subtitle was not selected") { player.secondarySubtitleID != "no" && player.secondarySubtitleID != "auto" }
        XCTAssertEqual(player.subtitleID, String(primary.id))
        XCTAssertNotEqual(player.subtitleID, player.secondarySubtitleID)
        player.setSubtitleDelay(0.5)
        player.setSecondarySubtitleDelay(-0.5)
        try await waitUntil("Separate subtitle delays were not acknowledged") { player.subtitleDelay == 0.5 && player.secondarySubtitleDelay == -0.5 }
        var style = SubtitleStyle()
        style.overrideASS = true
        style.font = "Helvetica"
        style.size = 40
        style.color = "#FF00FF00"
        style.primaryPosition = 90
        style.secondaryPosition = 10
        player.updateSubtitleStyle(style)
        player.seek(to: 3)
        try await waitUntil("Exact seeking did not complete") { abs(player.position - 3) < 0.25 }
        XCTAssertEqual(player.position, 3, accuracy: 0.25)
        XCTAssertNil(player.failure, player.failure?.message ?? "")
        player.enterBackground()
        let backgroundStart = player.position
        player.setPaused(false)
        try await waitUntil("Audio did not advance after the background transition") { player.position > backgroundStart + 1 }
        player.enterForeground()
        player.setPaused(true)
        try await waitUntil("Foreground pause was not acknowledged") { player.paused }
        XCTAssertNil(player.failure, player.failure?.message ?? "")
        window.isHidden = true
    }

    @MainActor
    func testSpeedPresetsForBothBackends() async throws {
        let player = PlayerModel()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let surface = VideoSurfaceView(frame: controller.view.bounds)
        controller.view.addSubview(surface)
        player.attach(to: surface)
        defer { player.setPaused(true); window.isHidden = true }
        let bundle = Bundle(for: Self.self)
        for ext in ["mp4", "mkv"] {
            player.add([try XCTUnwrap(bundle.url(forResource: "playback", withExtension: ext))])
            try await waitUntil("\(ext) did not load for rate checks") { !player.loading && player.duration > 10 }
            for rate in [0.5, 2.0, 4.0, 8.0] {
                player.setPaused(true)
                try await waitUntil("Pause failed before \(rate)×") { player.paused }
                var sought = false
                player.seek(to: 1) { sought = true }
                try await waitUntil("Seek failed before \(rate)×") { sought }
                player.setSpeed(rate)
                try await waitUntil("\(rate)× was not accepted") { !player.loading && player.speed == rate }
                player.setPaused(false)
                try await waitUntil("\(rate)× did not start") { !player.paused && player.position > 1.03 }
                if player.backend == .native {
                    XCTAssertEqual(try XCTUnwrap(surface.nativeLayer.player).rate, Float(rate), accuracy: 0.01)
                }
                let mediaStart = player.position
                let wallStart = Date()
                try await Task.sleep(for: .milliseconds(800))
                let measuredRate = (player.position - mediaStart) / Date().timeIntervalSince(wallStart)
                XCTAssertEqual(measuredRate, rate, accuracy: max(0.2, rate * 0.35),
                               "\(ext) requested \(rate)× but advanced at \(measuredRate)×")
                XCTAssertNil(player.failure, player.failure?.message ?? "")
            }
        }
        player.setSpeed(1)
    }

    @MainActor
    func testSpeedChangesWhilePlayingAndSystemResume() async throws {
        let player = PlayerModel()
        let deadline = Date().addingTimeInterval(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first(where: {
            $0.activationState == .foregroundActive
        }) as? UIWindowScene, "Rate checks require an active foreground scene")
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let surface = VideoSurfaceView(frame: controller.view.bounds)
        controller.view.addSubview(surface)
        player.attach(to: surface)
        defer { player.setPaused(true); window.isHidden = true }
        let bundle = Bundle(for: Self.self)
        for ext in ["mp4", "mkv"] {
            player.setSpeed(1)
            player.add([try XCTUnwrap(bundle.url(forResource: "playback", withExtension: ext))])
            try await waitUntil("\(ext) did not start for live rate changes") {
                !player.loading && !player.paused && player.position > 0.1
            }
            for rate in [2.0, 0.5, 1.5, 0.75] {
                // Queue multiple choices without pausing or seeking. The final
                // choice must survive delayed events from the earlier ones.
                player.setSpeed(1)
                player.setSpeed(2)
                player.setSpeed(rate)
                try await Task.sleep(for: .milliseconds(250))
                XCTAssertEqual(player.speed, rate)
                XCTAssertFalse(player.paused)
                let start = player.position, wall = Date()
                let native = surface.nativeLayer.player
                let nativeStart = native?.currentTime().seconds
                try await Task.sleep(for: .milliseconds(800))
                let measured = (player.position - start) / Date().timeIntervalSince(wall)
                let nativeState = "native \(nativeStart ?? -1)→\(native?.currentTime().seconds ?? -1), " +
                    "rate \(native?.rate ?? -1), status \(native?.timeControlStatus.rawValue ?? -1), " +
                    "waiting \(native?.reasonForWaitingToPlay?.rawValue ?? "none")"
                XCTAssertEqual(measured, rate, accuracy: max(0.25, rate * 0.35),
                               "\(ext) failed to change rate during playback: \(start)→\(player.position), " +
                               "paused \(player.paused), buffering \(player.buffering), " +
                               "scene \(scene.activationState.rawValue), \(nativeState)")
            }
            if ext == "mp4" {
                XCTAssertEqual(player.backend, .native)
                let native = try XCTUnwrap(surface.nativeLayer.player)
                // AVKit PiP and system controls can call AVPlayer directly.
                native.pause()
                try await waitUntil("System pause was not acknowledged") { player.paused }
                native.play()
                try await waitUntil("System resume lost the selected rate") {
                    !player.paused && native.rate == 0.75
                }
                XCTAssertEqual(player.speed, 0.75)
                var settings = player.videoSettings
                settings.rotation = 90
                player.updateVideoSettings(settings)
                player.setSpeed(0.5)
                player.setSpeed(2)
                player.setSpeed(1.5)
                try await waitUntil("Engine replacement did not preserve the latest rate") {
                    player.backend == .mpv && !player.loading && player.speed == 1.5
                }
                try await Task.sleep(for: .milliseconds(300))
                let start = player.position, wall = Date()
                try await Task.sleep(for: .milliseconds(800))
                XCTAssertEqual((player.position - start) / Date().timeIntervalSince(wall), 1.5, accuracy: 0.55)
                player.updateVideoSettings(VideoSettings())
            }
            XCTAssertNil(player.failure, player.failure?.message ?? "")
        }
        player.setSpeed(1)
    }

    @MainActor
    func testTouchSpeedRestorationAndSwipeSeekingForBothBackends() async throws {
        let player = PlayerModel()
        // The physical test host can start before its scene activates.
        let deadline = Date().addingTimeInterval(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let scene = UIApplication.shared.connectedScenes.first(where: {
            $0.activationState == .foregroundActive
        }) as? UIWindowScene else {
            throw XCTSkip("Touch playback checks require an active foreground scene; this test host did not provide one.")
        }
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: PlayerView(model: player))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { player.setPaused(true); window.isHidden = true; window.rootViewController = nil }
        func findSurface(_ view: UIView) -> VideoSurfaceView? {
            if let surface = view as? VideoSurfaceView { return surface }
            return view.subviews.lazy.compactMap { findSurface($0) }.first
        }
        let bundle = Bundle(for: Self.self)
        for ext in ["mp4", "mkv"] {
            player.add([try XCTUnwrap(bundle.url(forResource: "playback", withExtension: ext))])
            try await waitUntil("\(ext) did not start for touch checks") {
                !player.loading && player.duration > 10 && player.position > 0.1 && !player.paused
            }
            let surface = try XCTUnwrap(findSurface(controller.view))
            player.setSpeed(0.75)
            try await waitUntil("The original touch speed was not applied") { player.speed == 0.75 }
            let boostStart = player.position
            surface.onSpeedHold?(true)
            try await waitUntil("Holding did not enable advancing 2× playback") {
                player.touchSpeedBoostActive && player.speed == 2 && player.position > boostStart + 0.4 && !player.buffering
            }
            if player.backend == .native {
                XCTAssertEqual(try XCTUnwrap(surface.nativeLayer.player).rate, 2, accuracy: 0.01)
            }
            let mediaStart = player.position, wallStart = Date()
            try await Task.sleep(for: .milliseconds(800))
            let rate = (player.position - mediaStart) / Date().timeIntervalSince(wallStart)
            XCTAssertTrue(player.touchSpeedBoostActive, "The \(ext) hold was cancelled during measurement")
            XCTAssertEqual(rate, 2, accuracy: 0.7,
                           "The \(ext) held video did not actually advance at 2×; speed \(player.speed), paused \(player.paused), buffering \(player.buffering)")
            let capture = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: capture)
            attachment.name = "Hold for 2x \(ext)"
            attachment.lifetime = .keepAlways
            add(attachment)
            surface.onSpeedHold?(false)
            try await waitUntil("Release did not restore 0.75×") {
                !player.touchSpeedBoostActive && player.speed == 0.75 &&
                    (player.backend != .native || surface.nativeLayer.player?.rate == 0.75)
            }
            if player.backend == .native {
                XCTAssertEqual(try XCTUnwrap(surface.nativeLayer.player).rate, 0.75, accuracy: 0.01)
            }
            player.setPaused(true)
            try await waitUntil("Touch seek setup did not pause") { player.paused }
            var sought = false
            player.seek(to: 0.5) { sought = true }
            try await waitUntil("Touch seek setup did not seek") { sought }
            surface.onSpeedHold?(true)
            XCTAssertFalse(player.touchSpeedBoostActive, "A paused video must not start a boost")
            player.setPaused(false)
            try await waitUntil("Touch seek playback did not resume") { !player.paused }
            let forwardTarget = player.position + 10
            surface.onSeekSwipe?(10)
            try await waitUntil("The forward swipe did not seek ten seconds") {
                abs(player.position - forwardTarget) < 0.4
            }
            let backwardTarget = max(0, player.position - 10)
            surface.onSeekSwipe?(-10)
            try await waitUntil("The backward swipe did not seek ten seconds") {
                abs(player.position - backwardTarget) < 0.4
            }
            surface.onSpeedHold?(true)
            player.setPaused(true)
            try await waitUntil("Pausing did not cancel the hold") {
                player.paused && !player.touchSpeedBoostActive && player.speed == 0.75
            }
            player.setPaused(false)
            try await waitUntil("Playback did not resume for background cancellation") { !player.paused }
            surface.onSpeedHold?(true)
            player.enterBackground()
            try await waitUntil("Backgrounding left the temporary rate active") {
                !player.touchSpeedBoostActive && player.speed == 0.75
            }
            player.enterForeground()
            surface.onSpeedHold?(true)
            player.setSpeed(1.5)
            surface.onSpeedHold?(false)
            try await waitUntil("Release replaced the explicit speed choice") {
                !player.touchSpeedBoostActive && player.speed == 1.5
            }
            XCTAssertNil(player.failure, player.failure?.message ?? "")
            player.setSpeed(1)
            player.setPaused(true)
            try await waitUntil("Touch test teardown did not pause") { player.paused }
        }
    }

    @MainActor
    func testVideoPanelSettingsAndTrackInformation() async throws {
        let player = PlayerModel()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: PlayerView(model: player, showingVideoSettings: true))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { player.setPaused(true); window.isHidden = true }
        let bundle = Bundle(for: Self.self)
        player.add([try XCTUnwrap(bundle.url(forResource: "playback", withExtension: "mp4"))])
        try await waitUntil("The native video information did not load") { !player.loading && player.selectedVideoTrack != nil }
        let track = try XCTUnwrap(player.selectedVideoTrack)
        XCTAssertEqual(player.backend, .native)
        XCTAssertEqual(track.codec, "h264")
        XCTAssertEqual(track.width, 320)
        XCTAssertEqual(track.height, 180)
        XCTAssertEqual(track.fps, 24, accuracy: 0.1)
        player.selectVideo("no")
        try await waitUntil("Disabling native video was not acknowledged") { player.videoID == "no" }
        player.selectVideo(String(track.id))
        try await waitUntil("Native video selection did not restore") { player.videoID == String(track.id) }
        player.setPaused(true)
        try await waitUntil("Video panel pause failed") { player.paused }
        var sought = false
        player.seek(to: 3) { sought = true }
        try await waitUntil("Video panel seek failed") { sought }
        func findSurface(_ view: UIView) -> VideoSurfaceView? {
            if let surface = view as? VideoSurfaceView { return surface }
            return view.subviews.lazy.compactMap { findSurface($0) }.first
        }
        let surface = try XCTUnwrap(findSurface(controller.view))
        var meanRGB = 0.0
        surface.onFramePresented = { frame in
            guard let pixel = CMSampleBufferGetImageBuffer(frame) else {
                XCTFail("The rendered frame has no pixels."); return
            }
            let status = CVPixelBufferLockBaseAddress(pixel, .readOnly)
            guard status == kCVReturnSuccess else { XCTFail("Pixel inspection failed: \(status)"); return }
            defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
            guard let storage = CVPixelBufferGetBaseAddress(pixel) else {
                XCTFail("The rendered frame has no pixel storage."); return
            }
            let bytes = storage.assumingMemoryBound(to: UInt8.self)
            let rowBytes = CVPixelBufferGetBytesPerRow(pixel)
            let width = CVPixelBufferGetWidth(pixel), height = CVPixelBufferGetHeight(pixel)
            var total = 0.0
            var samples = 0
            for y in stride(from: height / 8, to: height, by: max(1, height / 8)) {
                for x in stride(from: width / 8, to: width, by: max(1, width / 8)) {
                    let offset = y * rowBytes + x * 4
                    total += Double(bytes[offset]) + Double(bytes[offset + 1]) + Double(bytes[offset + 2])
                    samples += 1
                }
            }
            meanRGB = total / Double(samples * 3)
        }
        defer { surface.onFramePresented = nil }
        var settings = VideoSettings()
        settings.aspect = .fourThree
        player.updateVideoSettings(settings)
        try await waitUntil("Aspect adjustment did not route to mpv") {
            player.backend == .mpv && !player.loading && player.appliedVideoSettings == settings &&
            surface.presentedSize.height > 0 && abs(surface.presentedSize.width / surface.presentedSize.height - 4 / 3) < 0.02
        }
        XCTAssertTrue(player.paused)
        XCTAssertEqual(player.position, 3, accuracy: 0.3)
        XCTAssertEqual(player.selectedVideoTrack?.fps ?? 0, 24, accuracy: 0.1)
        settings.aspect = .original
        settings.rotation = 90
        player.updateVideoSettings(settings)
        try await waitUntil("Rotation did not produce portrait frames") {
            player.appliedVideoSettings == settings && player.outputVideoSize.height > player.outputVideoSize.width &&
            surface.presentedSize.height > surface.presentedSize.width
        }
        settings.rotation = 0
        settings.crop = .square
        player.updateVideoSettings(settings)
        try await waitUntil("Square crop did not produce square frames") {
            player.appliedVideoSettings == settings &&
            surface.presentedSize == CGSize(width: 180, height: 180)
        }
        XCTAssertEqual(player.outputVideoSize, CGSize(width: 320, height: 180), "VO crop retains encoded frame dimensions")
        XCTAssertEqual(surface.presentedSize, CGSize(width: 180, height: 180), "Actual cropped sample buffer")
        XCTAssertNil(player.failure, player.failure?.message ?? "")
        let baseline = meanRGB
        XCTAssertGreaterThan(baseline, 10, "The cropped frame was black.")
        settings.brightness = 25
        let brightnessFrames = surface.presentedFrames
        player.updateVideoSettings(settings)
        try await waitUntil("Brightness did not change the actual paused pixels") {
            player.appliedVideoSettings == settings && surface.presentedFrames > brightnessFrames &&
            meanRGB > baseline + 20
        }
        XCTAssertGreaterThan(meanRGB, baseline + 20, "Actual RGB brightness after adjustment; baseline \(baseline)")
        settings.contrast = 15
        settings.saturation = -20
        settings.gamma = 10
        settings.hue = 15
        settings.hardwareDecoding = false
        let frames = surface.presentedFrames
        player.updateVideoSettings(settings)
        player.setPaused(false)
        try await waitUntil("Color filters/software decode did not render") {
            player.appliedVideoSettings == settings && player.decoder == "no" && surface.presentedFrames > frames + 2
        }
        player.setPaused(true)
        try await waitUntil("Color-filter playback did not pause") { player.paused }
        XCTAssertNil(player.failure, player.failure?.message ?? "")
        try await Task.sleep(for: .milliseconds(300))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Video Quick Settings"
        attachment.lifetime = .keepAlways
        add(attachment)
        let video = try XCTUnwrap(player.videoTracks.first)
        player.selectVideo("no")
        try await waitUntil("mpv video disable failed") { player.videoID == "no" }
        player.enterBackground()
        player.enterForeground()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(player.videoID, "no")
        player.selectVideo(String(video.id))
        player.updateVideoSettings(VideoSettings())
        player.setPaused(false)
        try await waitUntil("Video settings reset did not restore playback") {
            player.videoID == String(video.id) && player.appliedVideoSettings == VideoSettings() &&
            player.outputVideoSize == CGSize(width: 320, height: 180) && surface.presentedSize == CGSize(width: 320, height: 180)
        }
        #if !targetEnvironment(simulator)
        try await waitUntil("Hardware decoding did not restore") { player.decoder.hasPrefix("videotoolbox") }
        #endif
        XCTAssertNil(player.failure, player.failure?.message ?? "")
    }

    @MainActor
    func testNativePlaybackAndSubtitleFallback() async throws {
        let player = PlayerModel()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let surface = VideoSurfaceView(frame: controller.view.bounds)
        controller.view.addSubview(surface)
        player.attach(to: surface)
        defer { window.isHidden = true }
        let bundle = Bundle(for: Self.self)
        player.add([try XCTUnwrap(bundle.url(forResource: "playback", withExtension: "mp4"))])
        try await waitUntil("Native MP4 did not start") { !player.loading && player.duration > 10 && player.position > 0.5 }
        XCTAssertFalse(player.paused, "Initial native playback paused; status \(surface.nativeLayer.player?.timeControlStatus.rawValue ?? -1), position \(player.position), duration \(player.duration)")
        XCTAssertEqual(player.backend, .native)
        XCTAssertNil(player.failure, player.failure?.message ?? "")
        let nativePlayer = try XCTUnwrap(surface.nativeLayer.player)
        nativePlayer.pause()
        try await waitUntil("AVKit pause was not reflected in IINA") { player.paused }
        nativePlayer.playImmediately(atRate: 1)
        try await waitUntil("AVKit resume was not reflected in IINA") { !player.paused && player.position > 0.7 }
        player.setPaused(true)
        try await waitUntil("Native pause failed") { player.paused }
        player.setSpeed(1.25)
        player.setVolume(60)
        var seekCompleted = false
        player.seek(to: 3) { seekCompleted = true }
        try await waitUntil("Native seek did not acknowledge completion") { seekCompleted }
        XCTAssertEqual(player.position, 3, accuracy: 0.25)
        player.addSubtitle(try XCTUnwrap(bundle.url(forResource: "primary", withExtension: "srt")))
        try await waitUntil("External subtitles did not select mpv") {
            player.backend == .mpv && !player.loading && player.tracks.contains {
                $0.kind == "sub" && $0.externalPath.hasSuffix("primary.srt") && String($0.id) == player.subtitleID
            }
        }
        XCTAssertTrue(player.paused)
        XCTAssertEqual(player.position, 3, accuracy: 0.3)
        XCTAssertEqual(player.speed, 1.25)
        XCTAssertEqual(player.volume, 60)
        XCTAssertNil(player.failure, player.failure?.message ?? "")
    }

    @MainActor
    func testPictureInPictureForBothBackends() async throws {
        let player = PlayerModel()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: PlayerView(model: player))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let bundle = Bundle(for: Self.self)
        for ext in ["mp4", "mkv"] {
            player.add([try XCTUnwrap(bundle.url(forResource: "playback", withExtension: ext))])
            try await waitUntil("\(ext) did not start") { !player.loading && player.position > 0.5 }
            let backend = player.backend
            if ext == "mkv" {
                player.addSubtitle(try XCTUnwrap(bundle.url(forResource: "secondary", withExtension: "srt")), target: .secondary)
                try await waitUntil("PiP secondary subtitle did not load") { player.secondarySubtitleID != "no" }
            }
            try await waitUntil("\(ext) PiP never became possible") { player.pictureInPicturePossible }
            player.togglePictureInPicture()
            try await waitUntil("\(ext) PiP did not start: \(player.failure?.message ?? "")") { player.pictureInPictureActive }
            XCTAssertEqual(player.backend, backend)
            player.enterBackground()
            let start = player.position
            try await waitUntil("\(ext) PiP did not keep playing") { player.position > start + 0.5 }
            player.togglePictureInPicture()
            try await waitUntil("\(ext) PiP did not stop") { !player.pictureInPictureActive }
            player.enterForeground()
            player.setPaused(true)
            try await waitUntil("\(ext) did not pause after PiP") { player.paused }
            XCTAssertEqual(player.backend, backend)
            XCTAssertNil(player.failure, player.failure?.message ?? "")
        }
    }

    @MainActor
    func testAudioOnlyFileOpensMiniPlayer() async throws {
        let player = PlayerModel()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: PlayerView(model: player))
        window.makeKeyAndVisible()
        player.add([try XCTUnwrap(Bundle(for: Self.self).url(forResource: "music", withExtension: "m4a"))])
        try await waitUntil("Music file did not open in the mini-player") { player.isAudioOnly && player.musicMode && player.duration > 10 }
        XCTAssertNil(player.failure, player.failure?.message ?? "")
        try await waitUntil("Music metadata was not read") { player.artist == "Synthetic fixture" && player.album == "Playback checks" }
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertEqual(info?[MPMediaItemPropertyArtist] as? String, "Synthetic fixture")
        XCTAssertTrue(MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled)
        try await Task.sleep(for: .milliseconds(500))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Music Mini-player"
        attachment.lifetime = .keepAlways
        add(attachment)
        player.toggleMusicMode()
        player.toggleMusicMode()
        player.add([try XCTUnwrap(Bundle(for: Self.self).url(forResource: "playback", withExtension: "mkv"))])
        try await waitUntil("Video mode did not restore after music playback") { !player.musicMode && !player.codec.isEmpty && player.position > 0.2 }
        XCTAssertNil(player.failure, player.failure?.message ?? "")
        player.setPaused(true)
        try await waitUntil("Movie did not pause before the music window closed") { player.paused }
        window.isHidden = true
        window.rootViewController = nil
    }

    func testStyleColorUsesMpvAlphaOrder() {
        XCTAssertEqual(Color(mpvColor: "#8000FF00").mpvColor, "#8000FF00")
        XCTAssertEqual(SubtitleStyle().borderColor, "#FF000000")
    }
}
