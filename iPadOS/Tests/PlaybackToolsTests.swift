// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import XCTest
import AVFoundation
import SwiftUI
@testable import IINAPad

final class PlaybackToolsTests: XCTestCase {
    @MainActor
    private func wait(_ message: String, timeout: Double = 12, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(condition(), message)
    }

    @MainActor
    private func host(_ player: PlayerModel) throws -> (UIWindow, VideoSurfaceView) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller; window.makeKeyAndVisible()
        let surface = VideoSurfaceView(frame: controller.view.bounds)
        controller.view.addSubview(surface); player.attach(to: surface)
        return (window, surface)
    }

    private func fixture(_ ext: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: "playback", withExtension: ext))
    }

    func testTimestampValidation() {
        XCTAssertEqual(PlaybackTimestamp.parse("1:02:03.5"), 3723.5)
        XCTAssertEqual(PlaybackTimestamp.parse("90:00"), 5400)
        XCTAssertEqual(PlaybackTimestamp.parse("4.25"), 4.25)
        for value in ["-1", "1:60", "1::2", "1.5:00", "nan", "inf", "1:2:3:4", ""] {
            XCTAssertNil(PlaybackTimestamp.parse(value), value)
        }
    }

    func testFolderNaturalOrderAndPlaylistPersistence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("Episodes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: root) }
            catch { XCTFail("Could not clean temporary playlist fixtures: \(error)") }
        }
        for name in ["Episode 10.mp4", "Episode 2.mp4", "Episode 1.mp4", ".hidden.mp4"] {
            try FileManager.default.copyItem(at: fixture("mp4"), to: folder.appendingPathComponent(name))
        }
        try Data("not media".utf8).write(to: folder.appendingPathComponent("readme.txt"))
        let directory = root.appendingPathComponent("Saved", isDirectory: true)
        let store = PlaylistStore(directory: directory)
        let files = try await store.mediaInFolder(folder)
        XCTAssertEqual(files.map(\.lastPathComponent), ["Episode 1.mp4", "Episode 2.mp4", "Episode 10.mp4"])
        let saved = try await store.save(name: "Episodes", media: files, folders: [folder])
        let reopened = PlaylistStore(directory: directory)
        let lists = try await reopened.list()
        XCTAssertEqual(lists.count, 1); XCTAssertEqual(lists.first?.id, saved.id)
        let restored = try await reopened.restore(try XCTUnwrap(lists.first))
        XCTAssertEqual(restored.media.map(\.lastPathComponent), files.map(\.lastPathComponent))
        XCTAssertEqual(restored.folders.first?.lastPathComponent, "Episodes")
        try await reopened.remove(saved.id)
        let empty = try await reopened.list()
        XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: files[0].path), "Deleting a playlist deleted its media")
    }

    @MainActor
    func testPlaylistEditingPreservesCurrentItemAndRepeatWraps() throws {
        let player = PlayerModel()
        let urls = ["Episode 10.mp4", "Episode 2.mp4", "Episode 1.mp4"].map { URL(fileURLWithPath: "/tmp/\($0)") }
        player.add(urls)
        let id = player.currentID
        player.sortPlaylist()
        XCTAssertEqual(player.playlist.map(\.title), ["Episode 1.mp4", "Episode 2.mp4", "Episode 10.mp4"])
        XCTAssertEqual(player.currentID, id)
        player.movePlaylist(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(player.currentIndex, 0)
        player.shufflePlaylist()
        XCTAssertEqual(player.currentID, id)
        player.repeatMode = .all
        player.play(player.playlist.last!.id); player.next()
        XCTAssertEqual(player.currentIndex, 0)
        player.previous(); XCTAssertEqual(player.currentIndex, 2)
        player.removePlaylist(at: IndexSet(integer: 2))
        XCTAssertEqual(player.playlist.count, 2); XCTAssertNotNil(player.currentID)
        player.removePlaylist(at: IndexSet(integersIn: 0..<2))
        XCTAssertFalse(player.hasMedia)
    }

    @MainActor
    func testLoopJumpFrameCaptureAndDiagnosticsOnBothEngines() async throws {
        let player = PlayerModel()
        let (window, surface) = try host(player)
        defer { player.setPaused(true); window.isHidden = true }
        for ext in ["mp4", "mkv"] {
            player.add([try fixture(ext)])
            try await wait("\(ext) did not load") { !player.loading && player.duration > 10 && player.canStepForward }
            XCTAssertEqual(player.backend, ext == "mp4" ? .native : .mpv)
            player.setPaused(true)
            try await wait("Pause failed") { player.paused }
            XCTAssertTrue(player.jump(to: "00:02"))
            try await wait("Jump failed") { abs(player.position - 2) < 0.1 }
            player.markLoopStart()
            player.seek(to: 3)
            try await wait("Seek to loop end failed") { abs(player.position - 3) < 0.1 }
            player.markLoopEnd()
            player.seek(to: 2)
            try await wait("Seek to loop start failed") { abs(player.position - 2) < 0.1 }
            player.setPaused(false)
            try await Task.sleep(for: .seconds(3))
            XCTAssertFalse(player.paused, "\(ext) stopped at loop B")
            XCTAssertGreaterThanOrEqual(player.position, 1.9)
            XCTAssertLessThan(player.position, 3.2, "\(ext) escaped the A–B loop")
            player.clearLoop(); player.setPaused(true)
            try await wait("Pause failed after looping") { player.paused }
            player.seek(to: 4)
            try await wait("Seek before frame stepping failed") { abs(player.position - 4) < 0.1 }
            let before = player.position
            player.stepFrame(forward: true)
            try await wait("\(ext) did not step forward") { player.position > before + 0.02 }
            XCTAssertTrue(player.paused)
            if player.canStepBackward {
                let forward = player.position
                player.stepFrame(forward: false)
                try await wait("\(ext) did not step backward") { player.position < forward - 0.02 }
            }
            player.captureFrame()
            try await wait("\(ext) did not capture a clean frame") { player.capturedFrame != nil || player.failure != nil }
            let image = try XCTUnwrap(player.capturedFrame?.image.cgImage, player.failure?.message ?? "")
            XCTAssertEqual(image.width, player.selectedVideoTrack?.width)
            XCTAssertEqual(image.height, player.selectedVideoTrack?.height)
            XCTAssertNil(player.failure, player.failure?.message ?? "")
            if ext == "mkv" {
                try await wait("mpv render diagnostics are missing") { (player.diagnostics.renderedFrames ?? 0) > 0 }
                XCTAssertEqual(player.diagnostics.renderedSize, surface.presentedSize)
                XCTAssertNotNil(player.diagnostics.bufferedSeconds)
            } else {
                XCTAssertNil(player.diagnostics.renderedFrames, "Native rendering statistics were invented")
            }
            player.repeatMode = .one
            player.seek(to: player.duration - 0.3)
            try await wait("Seek near EOF failed") { player.position > player.duration - 0.5 }
            player.setPaused(false)
            try await wait("\(ext) did not repeat the file", timeout: 5) { player.position < 2 && !player.paused }
            player.repeatMode = .off
        }
    }

    @MainActor
    func testThumbnailsDoNotSeekThePlayingClient() async throws {
        let player = PlayerModel()
        let (window, _) = try host(player)
        defer { player.setPaused(true); window.isHidden = true }
        for ext in ["mp4", "mkv"] {
            let url = try fixture(ext)
            player.add([url])
            try await wait("\(ext) did not play for thumbnail checks") { !player.loading && player.position > 0.1 }
            let start = player.position
            await player.seekPreview.show(url: url, seconds: 8, duration: player.duration, allowRemote: true)
            let image = try XCTUnwrap(player.seekPreview.image?.cgImage, player.seekPreview.message)
            XCTAssertLessThanOrEqual(image.width, 320)
            XCTAssertGreaterThanOrEqual(player.position, start)
            XCTAssertLessThan(player.position, 6, "Preview generation sought the playing client")
            XCTAssertFalse(player.paused, "Preview generation paused the playing client")
            try await wait("Playback stopped advancing after thumbnail generation", timeout: 3) { player.position > start + 0.2 }
            XCTAssertNil(player.failure, player.failure?.message ?? "")
        }
    }

    @MainActor
    func testConfiguredTouchControlsAndPreferencePersistence() async throws {
        let saved = UserDefaults.standard.data(forKey: "IINA.ControlPreferences.v1")
        defer { UserDefaults.standard.set(saved, forKey: "IINA.ControlPreferences.v1") }
        let player = PlayerModel()
        let (window, _) = try host(player)
        defer { player.setPaused(true); window.isHidden = true }
        var value = ControlPreferences(); value.seekSeconds = 20; value.holdSpeed = 1.5
        value.dockControls = true; value.sidebarWidth = 480
        player.updateControlPreferences(value)
        XCTAssertEqual(try ControlPreferences.load(), value)
        value.shortcuts[PlayerControlAction.forward.rawValue] = .left
        XCTAssertFalse(value.isValid, "Duplicate shortcuts were accepted")
        player.add([try fixture("mp4")])
        try await wait("Playback did not start for custom hold checks") { player.canUsePlaybackGestures }
        player.setSpeed(0.75)
        XCTAssertTrue(player.beginTouchSpeedBoost())
        XCTAssertEqual(player.speed, 1.5)
        player.endTouchSpeedBoost(); XCTAssertEqual(player.speed, 0.75)
        var disabled = player.controlPreferences; disabled.holdEnabled = false
        player.updateControlPreferences(disabled)
        XCTAssertFalse(player.beginTouchSpeedBoost())
    }
}
