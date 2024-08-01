//
//  PlayerState.swift
//  iina
//
//  Created by low-batt on 7/13/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

/// The mutually exclusive states a `PlayerCore` can be in.
/// - Important: The value of the computed properties `active` and `loaded` are dependent upon the declaration order of the
///     enum constants.
enum PlayerState: Int {

  /// The asynchronous `loadfile` command has been sent to mpv.
  case loading

  /// Player is loading the file.
  ///
  /// A [MPV_EVENT_START_FILE](https://mpv.io/manual/stable/#command-interface-mpv-event-start-file)
  /// was received.
  case starting

  /// Player is playing the file.
  ///
  /// Initially entered when
  /// [MPV_EVENT_FILE_LOADED](https://mpv.io/manual/stable/#command-interface-mpv-event-file-loaded)
  /// is received indicating file is loaded and playing.
  case playing

  /// Playback has paused.
  ///
  /// A [MPV_EVENT_PROPERTY_CHANGE](https://mpv.io/manual/stable/#command-interface-mpv-event-property-change)
  /// for the `pause` property was received with a value of `true`.
  case paused

  /// The asynchronous `stop` command has been sent to mpv.
  case stopping

  /// Playback has stopped and the media has been unloaded.
  ///
  /// This is the initial state of a player. The player returns to this state when a
  /// [MPV_EVENT_PROPERTY_CHANGE](https://mpv.io/manual/stable/#command-interface-mpv-event-property-change)
  /// for the `idle-active` property is received with a value of `true`.
  case idle

  /// The asynchronous `quit` command has been sent to mpv initiating shutdown.
  case shuttingDown

  /// Shutdown of the player has completed (mpv has shutdown).
  ///
  /// A [MPV_EVENT_SHUTDOWN](https://mpv.io/manual/stable/#command-interface-mpv-event-shutdown)
  /// was received indicating the `quit` command completed.
  case shutDown

  /// `True` if when the player is in this state the mpv core is considered active, otherwise `false`.
  ///
  /// These are the states in which the player normally interacts with the mpv core. The mpv core **must not** be accessed when the
  /// player is in the `shuttingDown` or `shutDown` states. Accessing the core in these states can trigger a crash.
  @inlinable var active: Bool { self.rawValue < PlayerState.stopping.rawValue }

  /// `True` if when the player is in this state the file is loaded, otherwise `false`.
  @inlinable var loaded: Bool { active && self.rawValue >= PlayerState.playing.rawValue }
}
