//
//  ScrollSeekTests.swift
//  iinaTests
//
//  Tests for seeking by scrolling: which seek ended a file, what the end of a file does, and what each scroll event may do.
//

import Foundation
import Testing
@testable import IINA

@Suite("Attributing seeks to scrolling")
struct ScrollSeekAttributionTests {

  /// An attribution through which a seek issued by a scroll has been accepted and started.
  func scrollSeeking() -> ScrollSeekAttribution {
    var attribution = ScrollSeekAttribution()
    attribution.commandReplied(userdata: MPVController.UserData.scrollSeek, error: 0)
    attribution.seekStarted()
    return attribution
  }

  @Test("A file ended during a seek issued by a scroll was ended by that seek")
  func endedDuringScrollSeek() {
    var attribution = scrollSeeking()
    let ended = attribution.fileEnded(at: 10)
    #expect(ended)
  }

  @Test("A file ended soon after playback restarted from a seek issued by a scroll was ended by that seek")
  func endedSoonAfterScrollSeek() {
    var attribution = scrollSeeking()
    attribution.playbackRestarted(at: 10)
    let ended = attribution.fileEnded(at: 10 + ScrollSeekAttribution.maxSeekEndToFileEndInterval - 0.01)
    #expect(ended)
  }

  @Test("A file ended long after playback restarted from a seek issued by a scroll was not ended by that seek")
  func endedLongAfterScrollSeek() {
    var attribution = scrollSeeking()
    attribution.playbackRestarted(at: 10)
    let ended = attribution.fileEnded(at: 10 + ScrollSeekAttribution.maxSeekEndToFileEndInterval)
    #expect(!ended)
  }

  @Test("A seek not issued by a scroll does not end a file by scrolling")
  func otherSeekIsNotScrollSeek() {
    var attribution = ScrollSeekAttribution()
    attribution.commandReplied(userdata: MPVController.UserData.screenshot, error: 0)
    attribution.seekStarted()
    let ended = attribution.fileEnded(at: 10)
    #expect(!ended)
  }

  @Test("A seek issued by a scroll that mpv rejected is not performed")
  func rejectedScrollSeek() {
    var attribution = ScrollSeekAttribution()
    attribution.commandReplied(userdata: MPVController.UserData.scrollSeek, error: -1)
    attribution.seekStarted()
    let ended = attribution.fileEnded(at: 10)
    #expect(!ended)
  }

  @Test("A seek mpv has accepted but not started when the file ends is discarded")
  func pendingScrollSeekIsDiscarded() {
    var attribution = ScrollSeekAttribution()
    attribution.commandReplied(userdata: MPVController.UserData.scrollSeek, error: 0)
    let endedWhilePending = attribution.fileEnded(at: 10)
    attribution.seekStarted()
    let endedAfterDiscard = attribution.fileEnded(at: 11)
    #expect(!endedWhilePending)
    #expect(!endedAfterDiscard)
  }

  @Test("Playback restarting from a seek not issued by a scroll forgets an earlier seek issued by one")
  func laterSeekReplacesScrollSeek() {
    var attribution = scrollSeeking()
    attribution.playbackRestarted(at: 10)
    attribution.seekStarted()
    attribution.playbackRestarted(at: 10.1)
    let ended = attribution.fileEnded(at: 10.2)
    #expect(!ended)
  }

  @Test("The end of a file clears what was attributed")
  func fileEndClears() {
    var attribution = scrollSeeking()
    attribution.playbackRestarted(at: 10)
    let first = attribution.fileEnded(at: 10.1)
    let second = attribution.fileEnded(at: 10.2)
    #expect(first)
    #expect(!second)
  }
}

/// A player that records what the end of a file asks of it.
final class EndingPlayer: FileEndPlayer {
  var pausesWhenOpened = false
  /// What the player was asked to do, in order.
  private(set) var calls: [String] = []
  /// The messages logged, in order.
  private(set) var messages: [String] = []

  func pauseMpv() { calls.append("pauseMpv") }

  func cancelThumbnailGeneration() { calls.append("cancelThumbnailGeneration") }

  func log(_ message: @autoclosure () -> String, level: Logger.Level) { messages.append(message()) }
}

@Suite("The end of a file")
struct FileEndTests {

  @Test("The end of a file pauses playback when the \"pause when media is opened\" setting is on")
  func pauseWhenOpenedPauses() {
    let player = EndingPlayer()
    player.pausesWhenOpened = true
    var attribution = ScrollSeekAttribution()
    let endedByScrollSeek = FileEnd.fileEnded(player, dueToStopCommand: false, attribution: &attribution, at: 10)
    #expect(!endedByScrollSeek)
    #expect(player.calls == ["cancelThumbnailGeneration", "pauseMpv"])
    #expect(player.messages == ["Pausing playback because \"pause when media is opened\" is enabled"])
  }

  @Test("The end of a file leaves playback as it is when the \"pause when media is opened\" setting is off")
  func settingOffLeavesPlayback() {
    let player = EndingPlayer()
    var attribution = ScrollSeekAttribution()
    let endedByScrollSeek = FileEnd.fileEnded(player, dueToStopCommand: false, attribution: &attribution, at: 10)
    #expect(!endedByScrollSeek)
    #expect(player.calls == ["cancelThumbnailGeneration"])
  }

  @Test("A file stopped by a command does not pause playback")
  func stopDoesNotPause() {
    let player = EndingPlayer()
    player.pausesWhenOpened = true
    var attribution = ScrollSeekAttribution()
    let endedByScrollSeek = FileEnd.fileEnded(player, dueToStopCommand: true, attribution: &attribution, at: 10)
    #expect(!endedByScrollSeek)
    #expect(player.calls == ["cancelThumbnailGeneration"])
  }

  @Test("A file ended by a seek issued by a scroll does not pause playback")
  func scrollSeekDoesNotPause() {
    let player = EndingPlayer()
    player.pausesWhenOpened = true
    var attribution = ScrollSeekAttribution()
    attribution.commandReplied(userdata: MPVController.UserData.scrollSeek, error: 0)
    attribution.seekStarted()
    let endedByScrollSeek = FileEnd.fileEnded(player, dueToStopCommand: false, attribution: &attribution, at: 10)
    #expect(endedByScrollSeek)
    #expect(player.calls == ["cancelThumbnailGeneration"])
  }
}

@Suite("Loading a file after a scroll ran into it")
struct ScrollSeekLoadingTests {

  @Test("A file ended by a seek issued by a scroll loads the next file until playback restarts")
  func loadingUntilRestart() {
    var loading = ScrollSeekLoading()
    loading.fileEnded(byScrollSeek: true)
    #expect(loading.isLoading)
    loading.playbackRestarted(at: 42)
    #expect(!loading.isLoading)
    #expect(loading.endTime == 42)
  }

  @Test("A file ended otherwise does not load the next file after a scroll")
  func otherEndIsNotLoading() {
    var loading = ScrollSeekLoading()
    loading.fileEnded(byScrollSeek: false)
    #expect(!loading.isLoading)
    loading.playbackRestarted(at: 42)
    #expect(loading.endTime == 0)
  }
}

@Suite("Deciding what a scroll event does")
struct ScrollGestureTests {

  typealias Event = ScrollGesture.Event

  static func wheel(at time: TimeInterval) -> Event {
    Event(isTrackpadBegan: false, isTrackpadEnded: false, isMouseWheel: true, timestamp: time)
  }

  static func trackpad(began: Bool = false, ended: Bool = false, at time: TimeInterval) -> Event {
    Event(isTrackpadBegan: began, isTrackpadEnded: ended, isMouseWheel: false, timestamp: time)
  }

  @Test("A mouse wheel scroll that begins after the previous one may seek")
  func wheelBeginsScroll() {
    var gesture = ScrollGesture()
    let outcome = gesture.handle(Self.wheel(at: 10), seeks: true, isPlaying: true, fileStartCount: 3,
                                 loading: ScrollSeekLoading())
    #expect(outcome == ScrollGesture.Outcome(pausesPlayback: false, resumesPlayback: false, maySeek: true))
  }

  @Test("Once a mouse wheel scroll has carried playback into another file it may not seek")
  func wheelScrollStopsAtNextFile() {
    var gesture = ScrollGesture()
    _ = gesture.handle(Self.wheel(at: 10), seeks: true, isPlaying: true, fileStartCount: 3, loading: ScrollSeekLoading())
    let later = 10 + ScrollGesture.maxMouseWheelEventInterval
    let outcome = gesture.handle(Self.wheel(at: later), seeks: true, isPlaying: true, fileStartCount: 4,
                                 loading: ScrollSeekLoading())
    #expect(!outcome.maySeek)
  }

  @Test("A mouse wheel event that follows the previous one later than the interval begins a new scroll")
  func wheelAfterIntervalBeginsScroll() {
    var gesture = ScrollGesture()
    _ = gesture.handle(Self.wheel(at: 10), seeks: true, isPlaying: true, fileStartCount: 3, loading: ScrollSeekLoading())
    let later = 10 + ScrollGesture.maxMouseWheelEventInterval + 0.01
    let outcome = gesture.handle(Self.wheel(at: later), seeks: true, isPlaying: true, fileStartCount: 4,
                                 loading: ScrollSeekLoading())
    #expect(outcome.maySeek)
  }

  @Test("A mouse wheel event while the next file loads after a scroll does not begin a new scroll")
  func wheelWhileLoadingContinuesScroll() {
    var gesture = ScrollGesture()
    _ = gesture.handle(Self.wheel(at: 10), seeks: true, isPlaying: true, fileStartCount: 3, loading: ScrollSeekLoading())
    var loading = ScrollSeekLoading()
    loading.fileEnded(byScrollSeek: true)
    let outcome = gesture.handle(Self.wheel(at: 20), seeks: true, isPlaying: true, fileStartCount: 4, loading: loading)
    #expect(!outcome.maySeek)
  }

  @Test("A mouse wheel event soon after the next file started playing after a scroll continues that scroll")
  func wheelSoonAfterLoadingContinuesScroll() {
    var gesture = ScrollGesture()
    _ = gesture.handle(Self.wheel(at: 10), seeks: true, isPlaying: true, fileStartCount: 3, loading: ScrollSeekLoading())
    var loading = ScrollSeekLoading()
    loading.fileEnded(byScrollSeek: true)
    loading.playbackRestarted(at: 20)
    let outcome = gesture.handle(Self.wheel(at: 20 + ScrollGesture.maxMouseWheelEventInterval), seeks: true,
                                 isPlaying: true, fileStartCount: 4, loading: loading)
    #expect(!outcome.maySeek)
  }

  @Test("A trackpad scroll that seeks while playing pauses when the fingers touch and resumes when they lift")
  func trackpadPausesAndResumes() {
    var gesture = ScrollGesture()
    let began = gesture.handle(Self.trackpad(began: true, at: 10), seeks: true, isPlaying: true, fileStartCount: 3,
                               loading: ScrollSeekLoading())
    #expect(began == ScrollGesture.Outcome(pausesPlayback: true, resumesPlayback: false, maySeek: true))
    let moved = gesture.handle(Self.trackpad(at: 10.1), seeks: true, isPlaying: false, fileStartCount: 3,
                               loading: ScrollSeekLoading())
    #expect(moved == ScrollGesture.Outcome(pausesPlayback: false, resumesPlayback: false, maySeek: true))
    let ended = gesture.handle(Self.trackpad(ended: true, at: 10.2), seeks: true, isPlaying: false, fileStartCount: 3,
                               loading: ScrollSeekLoading())
    #expect(ended == ScrollGesture.Outcome(pausesPlayback: false, resumesPlayback: true, maySeek: true))
    let momentum = gesture.handle(Self.trackpad(at: 10.3), seeks: true, isPlaying: true, fileStartCount: 3,
                                  loading: ScrollSeekLoading())
    #expect(momentum == ScrollGesture.Outcome(pausesPlayback: false, resumesPlayback: false, maySeek: true))
  }

  @Test("A trackpad scroll that begins while paused neither pauses nor resumes")
  func trackpadWhilePausedLeavesPlayback() {
    var gesture = ScrollGesture()
    let began = gesture.handle(Self.trackpad(began: true, at: 10), seeks: true, isPlaying: false, fileStartCount: 3,
                               loading: ScrollSeekLoading())
    #expect(!began.pausesPlayback)
    let ended = gesture.handle(Self.trackpad(ended: true, at: 10.2), seeks: true, isPlaying: false, fileStartCount: 3,
                               loading: ScrollSeekLoading())
    #expect(!ended.resumesPlayback)
  }

  @Test("A trackpad scroll that does not seek neither pauses nor resumes")
  func trackpadWithoutSeekingLeavesPlayback() {
    var gesture = ScrollGesture()
    let began = gesture.handle(Self.trackpad(began: true, at: 10), seeks: false, isPlaying: true, fileStartCount: 3,
                               loading: ScrollSeekLoading())
    #expect(!began.pausesPlayback)
    let ended = gesture.handle(Self.trackpad(ended: true, at: 10.2), seeks: false, isPlaying: true, fileStartCount: 3,
                               loading: ScrollSeekLoading())
    #expect(!ended.resumesPlayback)
  }

  @Test("Once a trackpad scroll has carried playback into another file its momentum may not seek")
  func momentumStopsAtNextFile() {
    var gesture = ScrollGesture()
    _ = gesture.handle(Self.trackpad(began: true, at: 10), seeks: true, isPlaying: false, fileStartCount: 3,
                       loading: ScrollSeekLoading())
    _ = gesture.handle(Self.trackpad(ended: true, at: 10.2), seeks: true, isPlaying: false, fileStartCount: 4,
                       loading: ScrollSeekLoading())
    let momentum = gesture.handle(Self.trackpad(at: 10.3), seeks: true, isPlaying: false, fileStartCount: 4,
                                  loading: ScrollSeekLoading())
    #expect(!momentum.maySeek)
  }

  @Test("A new trackpad scroll after one carried playback into another file may seek in that file")
  func newTrackpadScrollMaySeek() {
    var gesture = ScrollGesture()
    _ = gesture.handle(Self.trackpad(began: true, at: 10), seeks: true, isPlaying: false, fileStartCount: 3,
                       loading: ScrollSeekLoading())
    let began = gesture.handle(Self.trackpad(began: true, at: 11), seeks: true, isPlaying: false, fileStartCount: 4,
                               loading: ScrollSeekLoading())
    #expect(began.maySeek)
  }
}
