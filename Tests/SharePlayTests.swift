// Copyright © 2026 IINA contributors. Licensed under GPLv3.

import Foundation
import XCTest

private final class TestPlayer: SharePlayPlayer {
  var sharePlaySnapshot = SharePlaySnapshot(url: URL(fileURLWithPath: "/synthetic/video.mkv"), position: 10,
    duration: 120, speed: 1, paused: true, buffering: false, loaded: true, seekable: true)
  var seekCompletion: ((Bool) -> Void)?
  var seeks: [Double] = []
  func sharePlaySetPaused(_ paused: Bool) { sharePlaySnapshot.paused = paused }
  func sharePlaySetSpeed(_ speed: Double) { sharePlaySnapshot.speed = speed }
  func sharePlaySeek(to time: Double, completion: @escaping (Bool) -> Void) {
    seeks.append(time)
    seekCompletion = completion
  }
  func finishSeek(success: Bool = true) {
    if success, let time = seeks.last { sharePlaySnapshot.position = time }
    let callback = seekCompletion
    seekCompletion = nil
    callback?(success)
  }
}

private final class TestCoordinator: SharePlayCoordinating {
  var rates: [Double] = []
  var seeks: [Double] = []
  var suspended: [SharePlaySuspension] = []
  var resumed: [SharePlaySuspension] = []
  var resyncs = 0
  var expected: Double?
  func coordinate(rate: Double) { rates.append(rate) }
  func coordinate(seek: Double) { seeks.append(seek) }
  func suspend(_ reason: SharePlaySuspension) { suspended.append(reason) }
  func resume(_ reason: SharePlaySuspension) { resumed.append(reason) }
  func resynchronize() { resyncs += 1 }
  func expectedPosition(at hostTime: Double) -> Double? { expected }
}

final class SharePlayTests: XCTestCase {
  private let media = SharePlayMedia(id: UUID(), title: "Synthetic video", duration: 120)
  private var player: TestPlayer!
  private var coordinator: TestCoordinator!
  private var playback: SharePlayPlayback!
  private var now = 100.0
  private var failures: [String] = []

  override func setUp() {
    player = TestPlayer()
    coordinator = TestCoordinator()
    playback = SharePlayPlayback(media: media, player: player, coordinator: coordinator, clock: { self.now })
    playback.onFailure = { self.failures.append($0) }
  }

  override func tearDown() {
    playback.stop()
    playback = nil
    player = nil
    coordinator = nil
  }

  @objc func testMediaValidationAndDurationMismatch() throws {
    XCTAssertTrue(media.matches(duration: 120.8))
    XCTAssertFalse(media.matches(duration: 123))
    XCTAssertFalse(media.matches(duration: .nan))
    XCTAssertFalse(SharePlayMedia(id: UUID(), title: "", duration: 120).isValid)
    XCTAssertFalse(SharePlayMedia(id: UUID(), title: "Test", duration: .infinity).isValid)
    let text = String(decoding: try JSONEncoder().encode(media), as: UTF8.self)
    XCTAssertFalse(text.contains("synthetic/video"))
    XCTAssertFalse(text.contains("url"))
    XCTAssertEqual(try JSONDecoder().decode(SharePlayMedia.self, from: Data(text.utf8)), media)
  }

  @objc func testCommonKeyboardAndPluginTransportCommands() {
    let state = player.sharePlaySnapshot
    XCTAssertEqual(SharePlayCommandRouter.raw("cycle pause", snapshot: state), .pause(false))
    XCTAssertEqual(SharePlayCommandRouter.raw("set pause yes", snapshot: state), .pause(true))
    XCTAssertEqual(SharePlayCommandRouter.raw("set_property speed 2", snapshot: state), .speed(2))
    XCTAssertEqual(SharePlayCommandRouter.raw("multiply speed 0.5", snapshot: state), .speed(0.5))
    XCTAssertEqual(SharePlayCommandRouter.raw("no-osd seek -5 relative+exact", snapshot: state), .seek(5))
    XCTAssertEqual(SharePlayCommandRouter.raw("seek 50 absolute-percent", snapshot: state), .seek(60))
    XCTAssertEqual(SharePlayCommandRouter.raw("seek 10 relative-percent", snapshot: state), .seek(22))
    XCTAssertEqual(SharePlayCommandRouter.raw("set time-pos 24", snapshot: state), .seek(24))
    XCTAssertEqual(SharePlayCommandRouter.raw("set chapter 2", snapshot: state), .chapter(2))
  }

  @objc func testUnsafeOrAmbiguousCommandsAreExplicitlyBlocked() {
    let state = player.sharePlaySnapshot
    for text in ["cycle pause; seek 5", "seek nan", "seek inf", "set speed -1", "set speed 101",
                 "seek 10 absolute+relative", "set chapter nan", "add chapter 1", "set playlist-pos 2",
                 "frame-step", "ab-loop", "playlist-next", "loadfile other.mp4", "seek ${time-pos}"] {
      XCTAssertEqual(SharePlayCommandRouter.raw(text, snapshot: state), .blocked, text)
    }
    XCTAssertEqual(SharePlayCommandRouter.raw("script-binding custom/action", snapshot: state), .suspend)
    XCTAssertEqual(SharePlayCommandRouter.raw("add volume 5", snapshot: state), .passthrough)
    XCTAssertEqual(SharePlayCommandRouter.raw("screenshot", snapshot: state), .passthrough)
  }

  @objc func testTimeMappingHandlesRateLateCommandsAndInvalidValues() {
    XCTAssertEqual(SharePlayTiming.position(itemTime: 10, hostTime: 100, rate: 2, now: 102, duration: 120), 14)
    XCTAssertEqual(SharePlayTiming.position(itemTime: 119, hostTime: 100, rate: 2, now: 102, duration: 120), 120)
    XCTAssertNil(SharePlayTiming.position(itemTime: .nan, hostTime: 100, rate: 1, now: 102, duration: 120))
    XCTAssertNil(SharePlayTiming.position(itemTime: 1, hostTime: 100, rate: 0, now: 102, duration: 120))
  }

  @objc func testUserActionsRequestCoordinationBeforeChangingPlayer() {
    playback.request(.pause(false))
    playback.request(.seek(30))
    XCTAssertEqual(coordinator.rates, [1])
    XCTAssertEqual(coordinator.seeks, [30])
    XCTAssertTrue(player.sharePlaySnapshot.paused)
    XCTAssertTrue(player.seeks.isEmpty)
  }

  @objc func testChangingSpeedWhilePausedDoesNotStartPlayback() {
    playback.request(.speed(2))
    XCTAssertTrue(coordinator.rates.isEmpty)
    XCTAssertEqual(player.sharePlaySnapshot.speed, 2)
    XCTAssertTrue(player.sharePlaySnapshot.paused)
    playback.request(.pause(false))
    XCTAssertEqual(coordinator.rates, [2])
  }

  @objc func testSeeksAreClampedAndInvalidRequestsFailVisibly() {
    playback.request(.seek(-20))
    playback.request(.seek(200))
    XCTAssertEqual(coordinator.seeks, [0, 119.999])
    playback.request(.seek(.nan))
    playback.request(.speed(.infinity))
    XCTAssertEqual(failures, ["shareplay.unsupported", "shareplay.unsupported"])
  }

  @objc func testPlaySeeksAndWaitsUntilHostDeadline() {
    var completed = 0
    playback.receive(.play(item: media.id, time: 20, hostTime: 101, rate: 2)) { completed += 1 }
    XCTAssertEqual(player.seeks, [20])
    XCTAssertEqual(completed, 0)
    player.finishSeek()
    XCTAssertTrue(player.sharePlaySnapshot.paused)
    now = 101
    playback.tick()
    XCTAssertFalse(player.sharePlaySnapshot.paused)
    XCTAssertEqual(player.sharePlaySnapshot.speed, 2)
    XCTAssertEqual(completed, 1)
    playback.tick()
    XCTAssertEqual(completed, 1)
  }

  @objc func testLatePlayMapsToCurrentGroupTime() {
    playback.receive(.play(item: media.id, time: 20, hostTime: 98, rate: 1)) {}
    XCTAssertEqual(player.seeks[0], 22.15, accuracy: 0.0001)
    player.finishSeek()
    now += 0.15
    playback.tick()
    XCTAssertFalse(player.sharePlaySnapshot.paused)
  }

  @objc func testSeekCompletionWaitsForPlayerAndDoesNotAutoResume() {
    player.sharePlaySnapshot.paused = false
    var completed = 0
    playback.receive(.seek(item: media.id, time: 35)) { completed += 1 }
    playback.tick()
    XCTAssertEqual(completed, 0)
    player.finishSeek()
    XCTAssertEqual(completed, 1)
    XCTAssertTrue(player.sharePlaySnapshot.paused)
    XCTAssertEqual(player.sharePlaySnapshot.position, 35)
  }

  @objc func testBufferReadinessAndTimeoutCompleteExactlyOnce() {
    player.sharePlaySnapshot.buffering = true
    var completed = 0
    playback.receive(.buffer(item: media.id)) { completed += 1 }
    XCTAssertEqual(completed, 0)
    now += 9
    playback.tick()
    XCTAssertEqual(completed, 1)
    XCTAssertEqual(failures, ["shareplay.not_ready"])
    XCTAssertTrue(playback.suspensions.contains(.automation))
    player.sharePlaySnapshot.buffering = false
    playback.tick()
    XCTAssertTrue(coordinator.resumed.isEmpty)
    XCTAssertEqual(completed, 1)
  }

  @objc func testFailedSeekSuspendsInsteadOfClaimingSuccess() {
    var completed = 0
    playback.receive(.seek(item: media.id, time: 40)) { completed += 1 }
    player.finishSeek(success: false)
    XCTAssertEqual(completed, 1)
    XCTAssertEqual(failures, ["shareplay.not_ready"])
    XCTAssertTrue(player.sharePlaySnapshot.paused)
  }

  @objc func testObsoleteItemCommandIsAcknowledgedWithoutChangingPlayer() {
    var completed = 0
    playback.receive(.seek(item: UUID(), time: 40)) { completed += 1 }
    XCTAssertEqual(completed, 1)
    XCTAssertTrue(player.seeks.isEmpty)
  }

  @objc func testNewCommandCancelsPreviousPendingWork() {
    var old = 0
    var current = 0
    playback.receive(.seek(item: media.id, time: 40)) { old += 1 }
    playback.receive(.pause(item: media.id, buffering: false)) { current += 1 }
    player.finishSeek()
    XCTAssertEqual(old, 1)
    XCTAssertEqual(current, 1)
    XCTAssertTrue(player.sharePlaySnapshot.paused)
  }

  @objc func testStopDiscardsLateSeekCallback() {
    var completed = 0
    playback.receive(.play(item: media.id, time: 30, hostTime: 101, rate: 1)) { completed += 1 }
    playback.stop()
    player.finishSeek()
    now += 2
    playback.tick()
    XCTAssertEqual(completed, 1)
    XCTAssertTrue(player.sharePlaySnapshot.paused)
    XCTAssertFalse(playback.active)
  }

  @objc func testSystemSuspensionDoesNotBroadcastPauseAndRejoins() {
    playback.suspend(.system)
    playback.suspend(.system)
    XCTAssertEqual(coordinator.suspended, [.system])
    XCTAssertTrue(coordinator.rates.isEmpty)
    playback.resume(.system)
    XCTAssertEqual(coordinator.resumed, [.system])
    XCTAssertTrue(playback.suspensions.isEmpty)
  }

  @objc func testUnexpectedPlaybackChangeSuspendsWithNotice() {
    player.sharePlaySnapshot.paused = false
    now += 1
    playback.tick()
    XCTAssertEqual(coordinator.suspended, [.automation])
    XCTAssertEqual(failures, ["shareplay.automation"])
    playback.rejoin()
    XCTAssertEqual(coordinator.resumed, [.automation])
    XCTAssertEqual(coordinator.resyncs, 1)
  }

  @objc func testForeignMediaCannotSilentlyBecomeShared() {
    player.sharePlaySnapshot.url = URL(fileURLWithPath: "/synthetic/another.mkv")
    playback.tick()
    XCTAssertEqual(coordinator.suspended, [.automation])
    XCTAssertEqual(failures, ["shareplay.media_changed"])
  }

  @objc func testDriftRecoveryIsBoundedAndStopsWhenPaused() {
    playback.receive(.play(item: media.id, time: 10, hostTime: 100, rate: 1)) {}
    player.finishSeek()
    now += 0.2; playback.tick()
    coordinator.expected = 50
    now += 1
    for _ in 0..<10 { playback.tick() }
    XCTAssertEqual(coordinator.resyncs, 1)
    now += 6
    for _ in 0..<3 { playback.tick() }
    XCTAssertEqual(coordinator.resyncs, 2)
    playback.receive(.pause(item: media.id, buffering: false)) {}
    now += 6
    for _ in 0..<10 { playback.tick() }
    XCTAssertEqual(coordinator.resyncs, 2)
  }

  @objc func testBufferRecoveryResumesOnlyLocalSuspension() {
    player.sharePlaySnapshot.buffering = true
    playback.tick()
    XCTAssertEqual(coordinator.suspended, [.buffering])
    XCTAssertTrue(coordinator.rates.isEmpty)
    player.sharePlaySnapshot.buffering = false
    playback.tick()
    XCTAssertEqual(coordinator.resumed, [.buffering])
  }

  @objc func testCoordinatorDueDateIsHonored() {
    player.sharePlaySnapshot.buffering = true
    var completed = 0
    playback.receive(.buffer(item: media.id), maximumWait: 0.2) { completed += 1 }
    now += 0.3
    playback.tick()
    XCTAssertEqual(completed, 1)
    XCTAssertEqual(failures, ["shareplay.not_ready"])
  }

  @objc func testAppleCoordinatorRegistersAndClearsContentIdentity() {
    let native = SharePlayCoordinator()
    let localPlayer = TestPlayer()
    let transport = SharePlayPlayback(media: media, player: localPlayer, coordinator: native,
                                     clock: { SharePlayCoordinator.hostTime })
    native.playback = transport
    native.prepare(position: 10, rate: 0)
    XCTAssertEqual(native.coordinator.currentItemIdentifier, media.id.uuidString)
    // Transport delegation requires a joined GroupSession; do not simulate that with a disconnected coordinator.
    XCTAssertTrue(localPlayer.sharePlaySnapshot.paused)
    transport.stop()
    native.disconnect()
    XCTAssertNil(native.coordinator.currentItemIdentifier)
  }

}
