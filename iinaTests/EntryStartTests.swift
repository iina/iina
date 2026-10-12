//
//  EntryStartTests.swift
//  iinaTests
//
//  Tests for starting playback of an entry once its first frame is ready.
//

import Testing
@testable import IINA

/// A player that records what the start of an entry asks of it.
final class StartingPlayer: EntryStartPlayer {
  var playerState: PlayerState = .loaded
  var isMpvPaused = false
  var pausedForLoading = false
  var pausesWhenOpened = false
  var isVideoLoaded = true
  /// What the player was asked to do, in order.
  private(set) var calls: [String] = []
  /// The messages logged, in order.
  private(set) var messages: [String] = []

  /// The replies waiting for `mpv` to answer whether playback is paused, oldest first.
  private(set) var pauseQuestions: [(Bool) -> Void] = []

  func fetchMpvPaused(_ reply: @escaping (Bool) -> Void) {
    calls.append("fetchMpvPaused")
    pauseQuestions.append(reply)
  }

  /// Answer the oldest waiting question with whether `mpv` has playback paused.
  func answerPauseQuestion() {
    pauseQuestions.removeFirst()(isMpvPaused)
  }

  func resumeMpv() {
    calls.append("resumeMpv")
    isMpvPaused = false
  }

  func displayActive() { calls.append("displayActive") }

  func generateThumbnails() { calls.append("generateThumbnails") }

  func log(_ message: @autoclosure () -> String, level: Logger.Level) { messages.append(message()) }
}

@Suite("Deciding the play state of an entry")
struct EntryPlayStateTests {

  @Test("Nothing is decided unless the player is in the loaded state",
        arguments: [PlayerState.loading, .starting, .playing, .paused, .stopping, .idle, .shuttingDown, .shutDown])
  func onlyLoadedDecides(state: PlayerState) {
    let player = StartingPlayer()
    player.playerState = state
    player.isMpvPaused = true
    player.pausedForLoading = true
    #expect(!EntryStart.decidePlayState(player, paused: player.isMpvPaused))
    #expect(player.playerState == state)
    #expect(player.pausedForLoading)
    #expect(player.calls.isEmpty)
  }

  @Test("An entry paused for its loading resumes")
  func pausedForLoadingResumes() {
    let player = StartingPlayer()
    player.isMpvPaused = true
    player.pausedForLoading = true
    #expect(EntryStart.decidePlayState(player, paused: player.isMpvPaused))
    #expect(player.calls == ["displayActive", "resumeMpv"])
    #expect(player.playerState == .playing)
    #expect(!player.pausedForLoading)
    #expect(player.messages == ["Resuming playback now that file has been loaded"])
  }

  @Test("An entry paused for its loading stays paused when the \"pause when media is opened\" setting is on")
  func pauseWhenOpenedKeepsPause() {
    let player = StartingPlayer()
    player.isMpvPaused = true
    player.pausedForLoading = true
    player.pausesWhenOpened = true
    #expect(EntryStart.decidePlayState(player, paused: player.isMpvPaused))
    #expect(player.calls.isEmpty)
    #expect(player.playerState == .paused)
    #expect(!player.pausedForLoading)
  }

  @Test("An entry the user paused while it loaded stays paused", arguments: [true, false])
  func userPauseHolds(pausesWhenOpened: Bool) {
    let player = StartingPlayer()
    player.isMpvPaused = true
    player.pausesWhenOpened = pausesWhenOpened
    #expect(EntryStart.decidePlayState(player, paused: player.isMpvPaused))
    #expect(player.calls.isEmpty)
    #expect(player.playerState == .paused)
  }

  @Test("An entry mpv is playing is playing", arguments: [true, false])
  func unpausedPlays(pausedForLoading: Bool) {
    let player = StartingPlayer()
    player.pausedForLoading = pausedForLoading
    #expect(EntryStart.decidePlayState(player, paused: player.isMpvPaused))
    #expect(player.calls.isEmpty)
    #expect(player.playerState == .playing)
    #expect(!player.pausedForLoading)
  }

  @Test("Nothing is asked of mpv unless the player is in the loaded state",
        arguments: [PlayerState.loading, .starting, .playing, .paused, .stopping, .idle, .shuttingDown, .shutDown])
  func onlyLoadedAsks(state: PlayerState) {
    let player = StartingPlayer()
    player.playerState = state
    var decided = 0
    EntryStart.decidePlayState(player) { decided += 1 }
    #expect(player.calls.isEmpty)
    #expect(decided == 0)
  }

  @Test("The play state is decided once mpv answers whether playback is paused")
  func decidedWhenMpvAnswers() {
    let player = StartingPlayer()
    player.isMpvPaused = true
    player.pausedForLoading = true
    var decided = 0
    EntryStart.decidePlayState(player) { decided += 1 }
    #expect(player.calls == ["fetchMpvPaused"])
    #expect(player.playerState == .loaded)
    #expect(decided == 0)
    player.answerPauseQuestion()
    #expect(player.calls == ["fetchMpvPaused", "displayActive", "resumeMpv"])
    #expect(player.playerState == .playing)
    #expect(decided == 1)
  }

  @Test("A pause the user gives before mpv answers keeps the entry paused")
  func pauseBeforeAnswerHolds() {
    let player = StartingPlayer()
    player.isMpvPaused = true
    player.pausedForLoading = true
    EntryStart.decidePlayState(player) {}
    player.pausedForLoading = false
    player.answerPauseQuestion()
    #expect(player.calls == ["fetchMpvPaused"])
    #expect(player.playerState == .paused)
  }

  @Test("An answer arriving after the play state was decided changes nothing")
  func laterAnswerChangesNothing() {
    let player = StartingPlayer()
    player.isMpvPaused = true
    player.pausedForLoading = true
    var decided = 0
    EntryStart.decidePlayState(player) { decided += 1 }
    EntryStart.decidePlayState(player) { decided += 1 }
    player.answerPauseQuestion()
    player.isMpvPaused = true
    player.answerPauseQuestion()
    #expect(decided == 1)
    #expect(player.playerState == .playing)
  }

  @Test("A pause notice leaves the state unchanged only while the entry is loaded")
  func pauseChangeUpdatesStateOutsideLoaded() {
    for state in [PlayerState.loading, .starting, .loaded, .playing, .paused, .stopping, .idle, .shuttingDown, .shutDown] {
      #expect(EntryStart.pauseChangeUpdatesState(state) == (state != .loaded))
    }
  }
}

@Suite("Starting thumbnail generation for an entry")
struct EntryThumbnailStartTests {

  @Test("Thumbnails are generated once the window has loaded video")
  func videoLoadedGeneratesThumbnails() {
    let player = StartingPlayer()
    EntryStart.startThumbnails(player)
    #expect(player.calls == ["generateThumbnails"])
  }

  @Test("No thumbnails are generated before the window has loaded video")
  func noVideoGeneratesNothing() {
    let player = StartingPlayer()
    player.isVideoLoaded = false
    EntryStart.startThumbnails(player)
    #expect(player.calls.isEmpty)
  }

  @Test("The window generates thumbnails itself except while the entry is loaded")
  func windowGeneratesThumbnailsOutsideLoaded() {
    for state in [PlayerState.loading, .starting, .loaded, .playing, .paused, .stopping, .idle, .shuttingDown, .shutDown] {
      #expect(EntryStart.windowGeneratesThumbnails(state) == (state != .loaded))
    }
  }
}
