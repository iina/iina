// Copyright © 2026 IINA contributors. Licensed under GPLv3.

import Foundation
import XCTest

private struct MPVTestError: Error { let code: Int32 }

private final class MPVTestPlayer: SharePlayPlayer {
  let handle: OpaquePointer
  let url: URL
  var seekCompletion: ((Bool) -> Void)?
  var target: Double?
  var errors: [Int32] = []

  init(url: URL) throws {
    guard let handle = mpv_create() else { throw MPVTestError(code: -1) }
    self.handle = handle
    self.url = url
    for (key, value) in ["config": "no", "load-scripts": "no", "vo": "null", "ao": "null",
                         "hwdec": "auto-safe", "pause": "yes", "keep-open": "always"] {
      let code = mpv_set_option_string(handle, key, value)
      if code < 0 { mpv_terminate_destroy(handle); throw MPVTestError(code: code) }
    }
    let code = mpv_initialize(handle)
    if code < 0 { mpv_terminate_destroy(handle); throw MPVTestError(code: code) }
    command(["loadfile", url.path])
  }

  deinit { mpv_terminate_destroy(handle) }

  private func number(_ name: String) -> Double {
    var value = 0.0
    mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &value)
    return value
  }

  private func flag(_ name: String) -> Bool {
    var value: Int32 = 0
    mpv_get_property(handle, name, MPV_FORMAT_FLAG, &value)
    return value != 0
  }

  var sharePlaySnapshot: SharePlaySnapshot {
    SharePlaySnapshot(url: url, position: number("time-pos"), duration: number("duration"), speed: number("speed"),
      paused: flag("pause"), buffering: flag("paused-for-cache"), loaded: number("duration") > 0, seekable: flag("seekable"))
  }

  func sharePlaySetPaused(_ paused: Bool) {
    var value: Int32 = paused ? 1 : 0
    let code = mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &value)
    if code < 0 { errors.append(code) }
  }

  func sharePlaySetSpeed(_ speed: Double) {
    var value = speed
    let code = mpv_set_property(handle, "speed", MPV_FORMAT_DOUBLE, &value)
    if code < 0 { errors.append(code) }
  }

  func sharePlaySeek(to time: Double, completion: @escaping (Bool) -> Void) {
    target = time
    seekCompletion = completion
    command(["seek", String(time), "absolute+exact"])
  }

  func command(_ arguments: [String]) {
    let allocated = arguments.map { strdup($0) }
    defer { allocated.forEach { free($0) } }
    var pointers = allocated.map { $0.map { UnsafePointer($0) } } + [nil]
    let code = mpv_command(handle, &pointers)
    if code < 0 { errors.append(code) }
  }

  func pump() {
    while let event = mpv_wait_event(handle, 0), event.pointee.event_id != MPV_EVENT_NONE {
      if event.pointee.event_id == MPV_EVENT_PLAYBACK_RESTART, let target,
         abs(number("time-pos") - target) < 0.15 {
        self.target = nil
        let callback = seekCompletion
        seekCompletion = nil
        callback?(true)
      }
    }
  }
}

private final class MPVTestCoordinator: SharePlayCoordinating {
  func coordinate(rate: Double) {}
  func coordinate(seek: Double) {}
  func suspend(_ reason: SharePlaySuspension) {}
  func resume(_ reason: SharePlaySuspension) {}
  func resynchronize() {}
  func expectedPosition(at hostTime: Double) -> Double? { nil }
}

final class MPVSharePlayTests: XCTestCase {
  @objc func testCoordinatedTransportOnRealMPV() throws {
    guard let path = ProcessInfo.processInfo.environment["IINA_SHAREPLAY_FIXTURE"] else {
      throw XCTSkip("Set IINA_SHAREPLAY_FIXTURE to a synthetic seekable video to exercise real mpv.")
    }
    let player = try MPVTestPlayer(url: URL(fileURLWithPath: path))
    let loadDeadline = Date().addingTimeInterval(5)
    while !player.sharePlaySnapshot.loaded, Date() < loadDeadline {
      player.pump()
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    XCTAssertTrue(player.sharePlaySnapshot.loaded)
    let media = SharePlayMedia(id: UUID(), title: "Synthetic fixture", duration: player.sharePlaySnapshot.duration)
    let playback = SharePlayPlayback(media: media, player: player, coordinator: MPVTestCoordinator(),
                                    clock: { SharePlayCoordinator.hostTime })
    defer { playback.stop() }
    var failures: [String] = []
    playback.onFailure = { failures.append($0) }
    var completed = 0
    playback.receive(.play(item: media.id, time: 2, hostTime: SharePlayCoordinator.hostTime + 0.2, rate: 2)) { completed += 1 }
    func advance(_ seconds: Double) {
      let deadline = Date().addingTimeInterval(seconds)
      while Date() < deadline {
        player.pump(); playback.tick()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
      }
    }
    advance(1)
    XCTAssertEqual(completed, 1)
    XCTAssertFalse(player.sharePlaySnapshot.paused)
    XCTAssertEqual(player.sharePlaySnapshot.speed, 2)
    XCTAssertGreaterThan(player.sharePlaySnapshot.position, 3)
    playback.receive(.seek(item: media.id, time: 7)) { completed += 1 }
    advance(0.3)
    XCTAssertEqual(completed, 2)
    XCTAssertTrue(player.sharePlaySnapshot.paused)
    XCTAssertEqual(player.sharePlaySnapshot.position, 7, accuracy: 0.15)
    playback.receive(.play(item: media.id, time: 7, hostTime: SharePlayCoordinator.hostTime + 0.2, rate: 0.5)) { completed += 1 }
    advance(0.8)
    XCTAssertEqual(completed, 3)
    XCTAssertEqual(player.sharePlaySnapshot.speed, 0.5)
    XCTAssertGreaterThan(player.sharePlaySnapshot.position, 7.1)
    XCTAssertLessThan(player.sharePlaySnapshot.position, 7.8)
    XCTAssertTrue(failures.isEmpty, "\(failures)")
    XCTAssertTrue(player.errors.isEmpty, "\(player.errors)")
  }
}
