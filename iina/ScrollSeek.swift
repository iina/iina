//
//  ScrollSeek.swift
//  iina
//
//  Seeking by scrolling, including a seek that runs past the end of a file into the next playlist entry.
//

import Foundation

/// Tracks, in the order of `mpv`'s events, whether the seek `mpv` is performing was issued by a scroll.
/// - Important: This must only be used by the thread of the queue for reading `mpv` events.
struct ScrollSeekAttribution {

  /// The longest time in seconds from `mpv` restarting playback after a seek to the file ending for the seek to have ended the
  /// file by running past its end.
  static let maxSeekEndToFileEndInterval: CFTimeInterval = 0.5

  /// Whether `mpv` has accepted a seek issued by a scroll and has not started it.
  private var isPending = false

  /// Whether the seek `mpv` is performing was issued by a scroll.
  private var isSeeking = false

  /// The time at which `mpv` restarted playback after its most recent seek, if that seek was issued by a scroll.
  private var endTime: CFTimeInterval?

  /// `mpv` replied to a command sent with the given user data.
  mutating func commandReplied(userdata: UInt64, error: Int32) {
    // mpv has accepted a seek issued by a scroll. The next seek mpv starts performs it.
    if userdata == MPVController.UserData.scrollSeek, error >= 0 {
      isPending = true
    }
  }

  /// `mpv` started a seek. The seek performs every seek `mpv` has accepted since it last started one.
  mutating func seekStarted() {
    isSeeking = isPending
    isPending = false
  }

  /// `mpv` restarted playback at the given time.
  mutating func playbackRestarted(at time: CFTimeInterval) {
    endTime = isSeeking ? time : nil
    isSeeking = false
  }

  /// `mpv` ended a file at the given time.
  ///
  /// When a seek runs past the end of a file during playback `mpv` restarts playback and then ends the file at once. A seek `mpv`
  /// has not started by now is discarded by `mpv`.
  /// - Returns: Whether a seek issued by a scroll ended the file.
  mutating func fileEnded(at time: CFTimeInterval) -> Bool {
    let endedByScrollSeek = isSeeking || endTime.map { time - $0 < Self.maxSeekEndToFileEndInterval } ?? false
    isPending = false
    isSeeking = false
    endTime = nil
    return endedByScrollSeek
  }
}

/// The player as the end of a file uses it, in the thread of the queue for reading `mpv` events.
protocol FileEndPlayer: AnyObject {
  /// Whether the "Pause" setting under "When media is opened" is enabled.
  var pausesWhenOpened: Bool { get }
  /// Set `mpv`'s pause flag.
  func pauseMpv()
  /// Stop generating thumbnails for the file that ended.
  func cancelThumbnailGeneration()
  func log(_ message: @autoclosure () -> String, level: Logger.Level)
}

/// The end of a file, handled in the thread of the queue for reading `mpv` events.
enum FileEnd {

  /// Handle the end of a file.
  ///
  /// Scanning the file for thumbnails stops here rather than in the main thread, so that the scan does not continue until the main
  /// thread is free. When the "Pause" setting under "When media is opened" is enabled playback is paused as soon as possible, as
  /// `mpv` may already be loading the next entry, unless the file ended because it was stopped or because a seek issued by a scroll
  /// ran past its end. After such a seek playback is left as the scroll has it, so that the next entry plays exactly when playback
  /// was playing before the scroll.
  /// - Returns: Whether a seek issued by a scroll ended the file.
  static func fileEnded(_ player: FileEndPlayer, dueToStopCommand: Bool, attribution: inout ScrollSeekAttribution,
                        at time: CFTimeInterval) -> Bool {
    player.cancelThumbnailGeneration()
    let endedByScrollSeek = attribution.fileEnded(at: time)
    if !dueToStopCommand, player.pausesWhenOpened, !endedByScrollSeek {
      player.pauseMpv()
      // Normally a log message is emitted before calling mpv, but in this case, due to the race
      // condition, playback must be paused as soon as possible, so logging is done afterward.
      player.log("Pausing playback because \"pause when media is opened\" is enabled", level: .debug)
    }
    return endedByScrollSeek
  }
}

/// Whether the current file is loading because a seek issued by a scroll ran past the end of the previous file.
/// - Important: This must only be accessed by the main thread.
struct ScrollSeekLoading {

  /// Whether the current file is loading because a seek issued by a scroll ran past the end of the previous file. This is `true`
  /// from the end of the previous file until playback of the current file has started.
  private(set) var isLoading = false

  /// The time at which `isLoading` last became `false`, as system uptime, the time base of `NSEvent.timestamp`.
  private(set) var endTime: TimeInterval = 0

  /// A file ended, by a seek issued by a scroll or otherwise.
  mutating func fileEnded(byScrollSeek: Bool) {
    isLoading = byScrollSeek
  }

  /// `mpv` restarted playback at the given time.
  mutating func playbackRestarted(at time: TimeInterval) {
    guard isLoading else { return }
    isLoading = false
    endTime = time
  }
}

/// Decides, for each scroll event, which scroll the event belongs to and what the scroll may do.
struct ScrollGesture {

  /// A scroll event.
  struct Event {
    /// Whether fingers started moving on a trackpad.
    var isTrackpadBegan: Bool
    /// Whether fingers were lifted from a trackpad.
    var isTrackpadEnded: Bool
    /// Whether the event comes from a mouse wheel. The momentum events that follow scrolling on a trackpad do not.
    var isMouseWheel: Bool
    /// The time of the event, as system uptime.
    var timestamp: TimeInterval
  }

  /// What a scroll event does.
  struct Outcome: Equatable {
    /// Whether the event pauses playback.
    var pausesPlayback = false
    /// Whether the event resumes playback.
    var resumesPlayback = false
    /// Whether the event may seek.
    var maySeek = true
  }

  /// The longest time in seconds between two events from a mouse wheel that are one scroll.
  static let maxMouseWheelEventInterval: TimeInterval = 0.5

  /// The value of `PlaybackInfo.fileStartCount` when the current scroll began.
  private var fileStartCountAtBegin = 0

  /// The time of the most recent scroll event from a mouse wheel.
  private var lastMouseWheelEventTime: TimeInterval = 0

  /// Whether playback was playing when the current trackpad scroll began seeking.
  private var wasPlayingBeforeSeeking = false

  /// Decide what the given scroll event does.
  ///
  /// A scroll begins when fingers start moving on a trackpad and lasts through the momentum that follows. A mouse wheel does not
  /// report when a scroll begins, its events are one scroll while they follow each other closely. The events of a scroll that has
  /// carried playback into another file can arrive late while that file loads, so the scroll lasts through the loading. Once the
  /// scroll has carried playback into another file the rest of the scroll, including its momentum, must not seek in that file. A
  /// trackpad scroll that seeks pauses playback while the fingers are down if playback was playing when it began.
  /// - Parameters:
  ///   - event: The scroll event.
  ///   - seeks: Whether the scroll seeks.
  ///   - isPlaying: Whether the player is playing.
  ///   - fileStartCount: The value of `PlaybackInfo.fileStartCount`.
  ///   - loading: Whether the current file is loading after a seek issued by a scroll.
  mutating func handle(_ event: Event, seeks: Bool, isPlaying: Bool, fileStartCount: Int,
                       loading: ScrollSeekLoading) -> Outcome {
    let lastScrollTime = max(lastMouseWheelEventTime, loading.endTime)
    let isMouseWheelBegan = event.isMouseWheel && !loading.isLoading
      && event.timestamp - lastScrollTime > Self.maxMouseWheelEventInterval
    if event.isMouseWheel {
      lastMouseWheelEventTime = event.timestamp
    }
    if event.isTrackpadBegan || isMouseWheelBegan {
      fileStartCountAtBegin = fileStartCount
    }
    var outcome = Outcome()
    outcome.maySeek = fileStartCount == fileStartCountAtBegin
    if seeks && event.isTrackpadBegan && isPlaying {
      outcome.pausesPlayback = true
      wasPlayingBeforeSeeking = true
    }
    if event.isTrackpadEnded && wasPlayingBeforeSeeking {
      outcome.resumesPlayback = true
      wasPlayingBeforeSeeking = false
    }
    return outcome
  }
}
