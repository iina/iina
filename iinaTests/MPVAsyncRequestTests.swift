//
//  MPVAsyncRequestTests.swift
//  iinaTests
//
//  Tests for the requests MPVController makes to a real mpv core without waiting for it.
//

import Foundation
import Testing
@testable import IINA

/// Each test makes its own player, so that no test shares an `mpv` core with another. Every player a test makes is kept for the
/// rest of the run, because a started `mpv` core calls back into its `MPVController` for as long as the core exists.
///
/// The tests run on the main thread. A reply `mpv` sends is handled on the thread of the queue for reading `mpv` events, while a
/// request that could not be made is answered on the thread that made it, so the thread a reply arrives on tells the two apart.
@Suite("Requests to mpv that do not wait for it")
@MainActor
struct MPVAsyncRequestTests {

  /// The players the tests made.
  private static var players: [PlayerCore] = []

  /// A player whose `mpv` core was never started.
  private static func unstartedPlayer() -> PlayerCore {
    let player = PlayerCore()
    // Like PlayerCore.createPlayerCore, label the player before it logs anything, since its log subsystem is named after it.
    player.label = "iinaTests-mpv-\(players.count)"
    players.append(player)
    return player
  }

  /// A player whose `mpv` core is running.
  private static func startedPlayer() -> PlayerCore {
    let player = unstartedPlayer()
    player.startMPV()
    return player
  }

  /// Ask `mpv` for a flag and wait for the reply.
  /// - Returns: The value replied with, and whether the reply arrived on the main thread.
  private static func flag(_ name: String, of player: PlayerCore) async -> (value: Bool?, onMain: Bool) {
    await withCheckedContinuation { continuation in
      player.mpv.getFlagAsync(name) { continuation.resume(returning: ($0, Thread.isMainThread)) }
    }
  }

  /// Run a command and wait for the reply.
  /// - Returns: The error code replied with, and whether the reply arrived on the main thread.
  private static func run(_ command: MPVCommand, _ args: [String], on player: PlayerCore) async -> (code: Int32, onMain: Bool) {
    await withCheckedContinuation { continuation in
      player.mpv.asyncCommand(command, args: args) { continuation.resume(returning: ($0, Thread.isMainThread)) }
    }
  }

  @Test("A flag asked for before mpv is initialized is answered at once with nil")
  func flagBeforeInitialized() {
    let player = Self.unstartedPlayer()
    var replies: [Bool?] = []
    player.mpv.getFlagAsync(MPVOption.PlaybackControl.pause) { replies.append($0) }
    #expect(replies == [nil])
  }

  @Test("A flag set before mpv is initialized is not sent")
  func setBeforeInitialized() {
    let player = Self.unstartedPlayer()
    player.mpv.setFlagAsync(MPVOption.PlaybackControl.pause, true)
    #expect(player.mpv.mpv == nil)
  }

  @Test("A command run before mpv is initialized is answered at once with an error")
  func commandBeforeInitialized() {
    let player = Self.unstartedPlayer()
    var codes: [Int32] = []
    player.mpv.asyncCommand(.set, args: [MPVOption.PlaybackControl.pause, "yes"]) { codes.append($0) }
    #expect(codes.count == 1)
    #expect(codes.allSatisfy { $0 < 0 })
  }

  @Test("A flag set without waiting is seen by a read asked for after it")
  func setThenRead() async {
    let player = Self.startedPlayer()
    player.mpv.setFlagAsync(MPVOption.PlaybackControl.pause, true)
    let paused = await Self.flag(MPVOption.PlaybackControl.pause, of: player)
    #expect(paused.value == true)
    #expect(!paused.onMain)
    player.mpv.setFlagAsync(MPVOption.PlaybackControl.pause, false)
    let resumed = await Self.flag(MPVOption.PlaybackControl.pause, of: player)
    #expect(resumed.value == false)
    #expect(!resumed.onMain)
  }

  @Test("A property mpv cannot read is answered with nil once mpv has tried")
  func unreadableProperty() async {
    let player = Self.startedPlayer()
    let reply = await Self.flag("iina-tests-no-such-property", of: player)
    #expect(reply.value == nil)
    #expect(!reply.onMain)
  }

  @Test("A command mpv runs is answered with success once it has run")
  func commandSucceeds() async {
    let player = Self.startedPlayer()
    let reply = await Self.run(.set, [MPVOption.PlaybackControl.pause, "yes"], on: player)
    #expect(reply.code >= 0)
    #expect(!reply.onMain)
    #expect(await Self.flag(MPVOption.PlaybackControl.pause, of: player).value == true)
  }

  @Test("A playlist move mpv cannot make is answered with an error once mpv has tried")
  func commandFails() async {
    let player = Self.startedPlayer()
    let reply = await Self.run(.playlistNext, [], on: player)
    #expect(reply.code < 0)
    #expect(!reply.onMain)
  }

  @Test("A command mpv cannot parse is answered at once with an error")
  func commandRefused() {
    let player = Self.startedPlayer()
    var codes: [Int32] = []
    player.mpv.asyncCommand(.seek, args: ["not-a-time"]) { codes.append($0) }
    #expect(codes.count == 1)
    #expect(codes.allSatisfy { $0 < 0 })
  }
}
