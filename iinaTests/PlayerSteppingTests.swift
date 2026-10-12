//
//  PlayerSteppingTests.swift
//  iinaTests
//
//  Tests for the members through which PlayerCore, MPVController and AutoFileMatcher take part in moving between playlist
//  entries, made against real players whose mpv cores have nothing loaded.
//

import Foundation
import Testing
@testable import IINA

/// Each test makes its own player, labelled before it logs and kept for the rest of the run, as in `MPVAsyncRequestTests`. No test
/// loads a file, so no entry is ever played, and no test sends a synchronous command `mpv` refuses, which `MPVController.chkErr`
/// treats as fatal.
@Suite("The player's side of moving between playlist entries")
@MainActor
struct PlayerSteppingTests {

  /// The players the tests made.
  private static var players: [PlayerCore] = []

  /// A player whose `mpv` core was never started.
  private static func unstartedPlayer() -> PlayerCore {
    let player = PlayerCore()
    // Like PlayerCore.createPlayerCore, label the player before it logs anything, since its log subsystem is named after it.
    player.label = "iinaTests-stepping-\(players.count)"
    players.append(player)
    return player
  }

  /// A player whose `mpv` core is running with nothing loaded.
  private static func startedPlayer() -> PlayerCore {
    let player = unstartedPlayer()
    player.startMPV()
    return player
  }

  /// Wait until every block the main queue holds has run.
  private static func drainMain() async {
    await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
  }

  /// Ask `mpv` whether playback is paused and wait for the reply, which comes after the replies to every request made before.
  private static func paused(_ player: PlayerCore) async -> Bool? {
    await withCheckedContinuation { continuation in
      player.mpv.getFlagAsync(MPVOption.PlaybackControl.pause) { continuation.resume(returning: $0) }
    }
  }

  /// The queue the player's FFmpeg controller generates thumbnails on, suspended so that no operation added to it starts.
  private static func suspendedThumbnailQueue(of player: PlayerCore) throws -> OperationQueue {
    let queue = try #require(player.ffmpegController.value(forKey: "queue") as? OperationQueue)
    queue.isSuspended = true
    return queue
  }

  @Test("The play state, the pause for loading and the count of user pauses are the player's own")
  func playbackInfo() {
    let player = Self.unstartedPlayer()
    player.playerState = .paused
    player.pausedForLoading = true
    player.userPauseCount = 3
    #expect(player.info.state == .paused)
    #expect(player.info.pausedForLoading)
    #expect(player.info.userPauseCount == 3)
    #expect(player.playerState == .paused)
    #expect(player.pausedForLoading)
    #expect(player.userPauseCount == 3)
  }

  @Test("The first entry is playing only when mpv reports it playing")
  func firstEntryPlaying() {
    let player = Self.unstartedPlayer()
    #expect(!player.isFirstEntryPlaying)
    player.info.playlist = [MPVPlaylistItem(filename: "/iinaTests/a.mp4", isCurrent: true, isPlaying: true, title: nil),
                            MPVPlaylistItem(filename: "/iinaTests/b.mp4", isCurrent: false, isPlaying: false, title: nil)]
    #expect(player.isFirstEntryPlaying)
  }

  @Test("A player that has opened nothing is in no interactive mode and has no video loaded")
  func nothingOpened() {
    let player = Self.unstartedPlayer()
    #expect(!player.isInteractiveModeActive)
    #expect(!player.isVideoLoaded)
  }

  @Test("Whether playback pauses when media is opened follows the setting")
  func pausesWhenOpened() {
    let player = Self.unstartedPlayer()
    #expect(player.pausesWhenOpened == Preference.bool(for: .pauseWhenOpen))
    #expect(player.mpv.pausesWhenOpened == Preference.bool(for: .pauseWhenOpen))
  }

  @Test("A pause or resume sent for a step is seen by a read asked for after it")
  func pauseAndResume() async {
    let player = Self.startedPlayer()
    player.pauseMpv()
    #expect(await Self.paused(player) == true)
    player.resumeMpv()
    #expect(await Self.paused(player) == false)
    // At the end of a file MPVController pauses on the thread of the queue for reading mpv events, waiting for mpv.
    player.mpv.pauseMpv()
    #expect(await Self.paused(player) == true)
  }

  @Test("Whether mpv has playback paused is answered on the main thread")
  func fetchPaused() async {
    let player = Self.startedPlayer()
    player.pauseMpv()
    let answer = await withCheckedContinuation { continuation in
      player.fetchMpvPaused { continuation.resume(returning: ($0, Thread.isMainThread)) }
    }
    #expect(answer.0 == true)
    #expect(answer.1)
  }

  @Test("A player whose mpv core was never started gives no answer about pause")
  func fetchPausedUnstarted() async {
    let player = Self.unstartedPlayer()
    var answers: [Bool] = []
    player.fetchMpvPaused { answers.append($0) }
    // The request is refused at once, so an answer it scheduled on the main queue would run before this block.
    await Self.drainMain()
    #expect(answers.isEmpty)
  }

  @Test("A move mpv cannot make is answered on the main thread without leaving the entry")
  func moveRefused() async {
    let player = Self.startedPlayer()
    for forward in [true, false] {
      var left = false
      let reply = await withCheckedContinuation { continuation in
        player.movePlaylistPosition(forward: forward, whenAccepted: { left = true }) {
          continuation.resume(returning: ($0, Thread.isMainThread))
        }
      }
      #expect(reply.0 == false)
      #expect(reply.1)
      #expect(!left)
    }
  }

  @Test("A step mpv cannot make leaves the pause for loading as it was")
  func stepRefused() async {
    // A player in an active state is given a mpv core that is not started, since a started core's property changes would reach
    // a main window that was never loaded; a step is then refused at once.
    let player = Self.unstartedPlayer()
    player.info.state = .playing
    player.navigateInPlaylist(nextMedia: true)
    await Self.drainMain()
    #expect(!player.info.pausedForLoading)
    #expect(player.info.userPauseCount == 0)
  }

  @Test("The playlist is read from mpv")
  func playlistRead() {
    let player = Self.startedPlayer()
    player.mpv.playlistAppend("/iinaTests/a.mp4")
    player.mpv.playlistAppend("/iinaTests/b.mp4")
    player.getPlaylist()
    #expect(player.info.playlist.map(\.filename) == ["/iinaTests/a.mp4", "/iinaTests/b.mp4"])
    #expect(player.info.playlist.allSatisfy { !$0.isCurrent && !$0.isPlaying })
  }

  @Test("Refreshing the playlist reads it from mpv on the playlist queue")
  func playlistRefreshed() async {
    let player = Self.startedPlayer()
    player.mpv.playlistAppend("/iinaTests/a.mp4")
    player.refreshPlaylist()
    // The playlist queue runs its blocks in order, so this one runs after the refresh.
    await withCheckedContinuation { continuation in player.playlistQueue.async { continuation.resume() } }
    #expect(player.info.playlist.map(\.filename) == ["/iinaTests/a.mp4"])
  }

  @Test("An entry mpv cannot be asked to play leaves the player idle")
  func playRefused() {
    let player = Self.unstartedPlayer()
    player.playPlaylistEntry(at: 0)
    #expect(player.info.state == .idle)
  }

  @Test("Leaving an entry cancels the thumbnail generation of the player's FFmpeg controller")
  func thumbnailsCancelled() throws {
    let player = Self.unstartedPlayer()
    let queue = try Self.suspendedThumbnailQueue(of: player)
    defer { queue.isSuspended = false }
    let byPlayer = BlockOperation()
    queue.addOperation(byPlayer)
    player.cancelThumbnailGeneration()
    #expect(byPlayer.isCancelled)
    // At the end of a file MPVController cancels it through the same controller.
    let byMpv = BlockOperation()
    queue.addOperation(byMpv)
    player.mpv.cancelThumbnailGeneration()
    #expect(byMpv.isCancelled)
  }

  @Test("A pause the user gives counts a user pause and ends the pause for loading")
  func pause() {
    let player = Self.unstartedPlayer()
    player.info.state = .playing
    player.info.pausedForLoading = true
    player.pause()
    #expect(player.info.userPauseCount == 1)
    #expect(!player.info.pausedForLoading)
  }

  @Test("Toggling pause while playback is paused for loading pauses instead of resuming")
  func togglePauseWhileLoading() {
    let player = Self.unstartedPlayer()
    player.info.state = .paused
    player.info.pausedForLoading = true
    player.togglePause()
    #expect(player.info.userPauseCount == 1)
    #expect(!player.info.pausedForLoading)
  }

  @Test("The folder playlist adds entries to mpv's playlist until the playlist is abandoned")
  func folderPlaylist() throws {
    let player = Self.startedPlayer()
    let matcher = AutoFileMatcher(player: player, ticket: player.folderPlaylistTicket.value)
    try matcher.checkFolderTicket()
    matcher.append("/iinaTests/b.mp4")
    matcher.insert("/iinaTests/a.mp4", at: 0)
    player.getPlaylist()
    #expect(player.info.playlist.map(\.filename) == ["/iinaTests/a.mp4", "/iinaTests/b.mp4"])
    player.folderPlaylistTicket.abandon()
    #expect(throws: PlayerCore.TicketExpiredError.self) { try matcher.checkFolderTicket() }
  }
}
