//
//  PlayerState.swift
//  iina
//
//  Created by low-batt on 7/13/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

/// The mutually exclusive states a `PlayerCore` can be in.
struct PlayerState: OptionSet, CustomStringConvertible {
  let rawValue: Int

  var description: String {
    switch self {
    case .idle: return "idle"
    case .loading: return "loading"
    case .starting: return "starting"
    case .playing: return "playing"
    case .paused: return "paused"
    case .seeking: return "seeking"
    case .stopping: return "stopping"
    case .stopped: return "stopped"
    case .shuttingDown: return "shuttingDown"
    case .shutDown: return "shutDown"
    default:
      var result = ""
      for state in PlayerState.allStates {
        guard self.contains(state) else { continue }
        if !result.isEmpty {
          result += ","
        }
        result += state.description
      }
      return "[\(result)]"
    }
  }

  // MARK: - States

  /// No file is loaded.
  ///
  /// This is the initial state of a player. The player returns to this state when a
  /// [MPV_EVENT_PROPERTY_CHANGE](https://mpv.io/manual/stable/#command-interface-mpv-event-property-change)
  /// for the `idle-active` property is received with a value of `true`.
  static let idle = PlayerState(rawValue: 1 << 0)

  /// The asynchronous `loadfile` command has been sent to mpv.
  static let loading = PlayerState(rawValue: 1 << 1)

  /// Player is loading the file.
  ///
  /// A [MPV_EVENT_START_FILE](https://mpv.io/manual/stable/#command-interface-mpv-event-start-file)
  /// was received.
  static let starting = PlayerState(rawValue: 1 << 2)

  /// Player is playing the file.
  ///
  /// Initially entered when [MPV_EVENT_FILE_LOADED](https://mpv.io/manual/stable/#command-interface-mpv-event-file-loaded)
  /// is received indicating file is loaded and playing.
  static let playing = PlayerState(rawValue: 1 << 3)

  /// Playback has paused.
  ///
  /// A [MPV_EVENT_PROPERTY_CHANGE](https://mpv.io/manual/stable/#command-interface-mpv-event-property-change)
  /// for the `pause` property was received with a value of `true`.
  static let paused = PlayerState(rawValue: 1 << 4)

  /// Player is seeking.
  ///
  /// A [MPV_EVENT_SEEK](https://mpv.io/manual/stable/#command-interface-mpv-event-seek) was recieived
  /// indicating seeking is in progress.
  static let seeking = PlayerState(rawValue: 1 << 5)

  /// The asynchronous `stop` command has been sent to mpv.
  static let stopping = PlayerState(rawValue: 1 << 6)

  /// Playback has stopped and the media has been unloaded.
  ///
  /// A [MPV_EVENT_END_FILE](https://mpv.io/manual/stable/#command-interface-mpv-event-end-file)
  /// was received with a reason of [MPV_END_FILE_REASON_STOP](https://mpv.io/manual/stable/#command-interface-stop)
  /// indicating the `stop` command completed.
  static let stopped = PlayerState(rawValue: 1 << 7)

  /// The asynchronous `quit` command has been sent to mpv initiating shutdown.
  static let shuttingDown = PlayerState(rawValue: 1 << 8)

  /// Shutdown of the player has completed (mpv has shutdown).
  ///
  /// A [MPV_EVENT_SHUTDOWN](https://mpv.io/manual/stable/#command-interface-mpv-event-shutdown)
  /// was received indicating the `quit` command completed.
  static let shutDown = PlayerState(rawValue: 1 << 9)

  // MARK: - Sets

  /// States in which the player is considered active.
  ///
  /// These are the states in which the player normally interacts with the mpv core. The mpv core **must not** be accessed when the
  /// player is in the `shuttingDown` or `shutDown` states. Accessing the core in these states can trigger a crash.
  static let activeStates: PlayerState = [.loading, .starting, .playing, .paused, .seeking]

  static let allStates: [PlayerState] = [.idle, .loading, .starting, .playing, .paused, .seeking,
                                        .stopping, .stopped, .shuttingDown, .shutDown]
}
