//
//  PlaylistStepping.swift
//  iina
//
//  Moving playback between playlist entries at the user's command, and starting playback of an entry
//  once its first frame is ready.
//

import Foundation

// MARK: - Stepping between entries

/// The player as stepping between playlist entries and pausing during a step use it.
protocol PlaylistSteppingPlayer: AnyObject {
  /// The state of the player.
  var playerState: PlayerState { get }
  /// Whether playback is paused for the loading of an entry the user chose to play, see `PlaybackInfo.pausedForLoading`.
  var pausedForLoading: Bool { get set }
  /// The number of pauses the user has given, see `PlaybackInfo.userPauseCount`.
  var userPauseCount: Int { get set }
  /// Whether the window is in interactive mode, during which the playlist position must not change.
  var isInteractiveModeActive: Bool { get }
  /// Whether the first entry of the playlist is the entry playing.
  var isFirstEntryPlaying: Bool { get }
  /// Seek to the start of the entry playing.
  func seekToStart()
  /// Ask `mpv` to move to the next or the previous entry, without waiting for it.
  ///
  /// `mpv` replies on the thread of the queue for reading `mpv` events. When it accepted the move `whenAccepted` is called on that
  /// thread, so that what must happen before the entry moved to loads happens as soon as possible. Then `reply` is called on the
  /// main thread with whether `mpv` accepted the move.
  func movePlaylistPosition(forward: Bool, whenAccepted: @escaping () -> Void, reply: @escaping (Bool) -> Void)
  /// Ask `mpv` to play the entry at the given index, without waiting for it.
  func playPlaylistEntry(at index: Int)
  /// Fetch the playlist from `mpv` off the main thread, once `mpv` has handled the requests made before.
  func refreshPlaylist()
  /// Ask `mpv` to pause playback, without waiting for it. This may be called from any thread.
  func pauseMpv()
  /// Resume playback at the user's command.
  func resume()
  /// Stop generating thumbnails for the entry playing. This may be called from any thread.
  func cancelThumbnailGeneration()
  /// Keep the video display running while the entry changes.
  func displayActive()
  /// Log the given message. This may be called from any thread.
  func log(_ message: @autoclosure () -> String, level: Logger.Level)
}

/// Moving playback to another playlist entry at the user's command, and pausing playback while it moves.
enum PlaylistStepping {

  /// Step to the next or the previous entry of the playlist.
  ///
  /// A step back while the first entry is playing restarts that entry. Any other step asks `mpv` to move, without waiting for it.
  /// `mpv` refuses when there is no entry to move to, as when the last entry is playing and the playlist does not loop, and playback
  /// is then left as it is. As soon as `mpv` has accepted the move playback leaves the entry, see `leaveEntry`, and playback is
  /// paused for the loading of the entry moved to unless the user paused playback after asking for the step.
  static func step(_ player: PlaylistSteppingPlayer, forward: Bool) {
    guard !player.isInteractiveModeActive else { return }
    if !forward && player.isFirstEntryPlaying {
      player.seekToStart()
      return
    }
    let destination = "\(forward ? "next" : "previous") entry in playlist"
    let userPausesBeforeStep = player.userPauseCount
    player.movePlaylistPosition(forward: forward, whenAccepted: {
      leaveEntry(player, for: destination)
    }, reply: { accepted in
      guard accepted else {
        player.log("Not playing \(destination), there is no entry to move to", level: .debug)
        return
      }
      // A pause the user gave after asking for the step must hold once the entry has loaded.
      if player.userPauseCount == userPausesBeforeStep {
        player.pausedForLoading = true
      }
      player.displayActive()
    })
  }

  /// Play the entry at the given index of the playlist.
  static func play(_ player: PlaylistSteppingPlayer, at index: Int) {
    leaveEntry(player, for: "entry at index \(index) in the playlist")
    player.pausedForLoading = true
    player.displayActive()
    player.playPlaylistEntry(at: index)
    player.refreshPlaylist()
  }

  /// Leave the entry playing for another one.
  ///
  /// Scanning the entry left for thumbnails stops. Playback is paused until the entry moved to has loaded, otherwise audio can start
  /// playing before video is shown. This is most noticeable with high resolution videos encoded with newer high compression codecs
  /// (such as AV1), when running on older Macs that lack support for hardware decoding of the codec used. Pausing playback that is
  /// already paused changes nothing, so the pause is asked for without reading whether playback is paused.
  ///
  /// This may be called from any thread.
  private static func leaveEntry(_ player: PlaylistSteppingPlayer, for destination: String) {
    player.cancelThumbnailGeneration()
    player.log("Pausing playback before playing \(destination)", level: .debug)
    player.pauseMpv()
  }

  /// Pause or resume playback at the user's command.
  ///
  /// While playback is paused for the loading of an entry the entry is about to play, so the command asks for a pause.
  static func togglePause(_ player: PlaylistSteppingPlayer) {
    if player.playerState == .paused && !player.pausedForLoading {
      player.resume()
    } else {
      pause(player)
    }
  }

  /// Pause playback.
  ///
  /// A pause given while an entry is loading must not be undone once the entry has loaded, so the pause for loading ends.
  static func pause(_ player: PlaylistSteppingPlayer) {
    guard player.playerState.active else { return }
    player.log("Pausing playback", level: .debug)
    player.userPauseCount += 1
    player.pausedForLoading = false
    player.pauseMpv()
  }
}

// MARK: - Start of an entry

/// The player as the start of playback of an entry uses it.
protocol EntryStartPlayer: AnyObject {
  /// The state of the player.
  var playerState: PlayerState { get set }
  /// Whether playback is paused for the loading of an entry the user chose to play, see `PlaybackInfo.pausedForLoading`.
  var pausedForLoading: Bool { get set }
  /// Whether the "Pause" setting under "When media is opened" is enabled.
  var pausesWhenOpened: Bool { get }
  /// Ask `mpv` whether playback is paused, without waiting for it. `reply` is called on the main thread once `mpv` has handled the
  /// requests made before, and is not called if `mpv` cannot answer.
  func fetchMpvPaused(_ reply: @escaping (Bool) -> Void)
  /// Ask `mpv` to resume playback, without waiting for it.
  func resumeMpv()
  /// Keep the video display running.
  func displayActive()
  /// Whether the window has loaded video.
  var isVideoLoaded: Bool { get }
  /// Start generating thumbnails for the entry playing.
  func generateThumbnails()
  func log(_ message: @autoclosure () -> String, level: Logger.Level)
}

/// Starting playback of an entry once its first frame is ready.
enum EntryStart {

  /// Decide the play state of an entry whose first frame is ready, without waiting for `mpv`.
  ///
  /// When the player is in the `loaded` state `mpv` is asked whether playback is paused, and the play state is decided once it
  /// answers, see `decidePlayState(_:paused:)`. `mpv` answers after handling every request made before, so the answer includes the
  /// pause asked for before the entry loaded and any pause or resume the user gave until the question was asked.
  /// - Parameter decided: Called on the main thread once the play state has been decided.
  static func decidePlayState(_ player: EntryStartPlayer, then decided: @escaping () -> Void) {
    guard player.playerState == .loaded else { return }
    player.fetchMpvPaused { paused in
      if decidePlayState(player, paused: paused) {
        decided()
      }
    }
  }

  /// Decide the play state of an entry whose first frame is ready, given whether `mpv` has playback paused.
  ///
  /// Playback paused for the loading of the entry resumes, unless the "Pause" setting under "When media is opened" is enabled. A
  /// pause the user gave while the entry loaded ended the pause for loading, so playback then stays paused. The state becomes
  /// paused or playing to match `mpv`.
  /// - Returns: `true` when the player was in the `loaded` state and its play state has been decided, otherwise `false`.
  @discardableResult
  static func decidePlayState(_ player: EntryStartPlayer, paused: Bool) -> Bool {
    guard player.playerState == .loaded else { return false }
    var paused = paused
    if paused, player.pausedForLoading, !player.pausesWhenOpened {
      player.log("Resuming playback now that file has been loaded", level: .debug)
      player.displayActive()
      player.resumeMpv()
      paused = false
    }
    player.pausedForLoading = false
    player.playerState = paused ? .paused : .playing
    return true
  }

  /// Whether a change of `mpv`'s pause flag changes the state of a player in the given state.
  ///
  /// `mpv` delivers property changes only once its event queue is empty, so the change caused by pausing playback before loading a
  /// file can arrive after `MPV_EVENT_FILE_LOADED`. Until the first frame is ready the state must remain `loaded`, otherwise
  /// `decidePlayState` would not resume playback.
  static func pauseChangeUpdatesState(_ state: PlayerState) -> Bool {
    return state != .loaded
  }

  /// Start generating thumbnails for an entry whose play state has been decided.
  ///
  /// Thumbnails are generated only once playback has started so that scanning the file does not delay it.
  static func startThumbnails(_ player: EntryStartPlayer) {
    if player.isVideoLoaded {
      player.generateThumbnails()
    }
  }

  /// Whether the window generates thumbnails when it first loads video, for a player in the given state.
  ///
  /// When the entry has just been loaded the player generates thumbnails itself once the play state is decided, see
  /// `startThumbnails`.
  static func windowGeneratesThumbnails(_ state: PlayerState) -> Bool {
    return state != .loaded
  }
}
