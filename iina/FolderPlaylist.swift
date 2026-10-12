//
//  FolderPlaylist.swift
//  iina
//
//  Adding the files in the folder of the opened file to its playlist.
//

import Foundation

/// Identifies the playlist of the opened file, into which the files in its folder are added.
///
/// The ticket changes when the playlist is abandoned: when another file is opened with a load command and when the background task
/// is told to stop. Unlike `PlayerCore.backgroundQueueTicket` it does not change when playback moves to another entry, so that
/// the task matching the folder continues until every file in the folder has been added and matched.
final class FolderPlaylistTicket {

  @Atomic private var current = 0

  /// The current value of the ticket, held by the task matching the folder.
  var value: Int { current }

  /// Abandon the playlist of the opened file.
  func abandon() {
    $current.withLock { $0 += 1 }
  }

  /// Throws `PlayerCore.TicketExpiredError.ticketExpired` when the playlist identified by the given ticket value has been
  /// abandoned.
  func check(_ ticket: Int) throws {
    if current != ticket {
      throw PlayerCore.TicketExpiredError.ticketExpired
    }
  }

  /// Take the request, made when a file is opened, to add the files in its folder to the playlist.
  ///
  /// The folder is matched once, for the file that was opened. Moving to another entry must not match it again.
  /// - Returns: Whether the folder is to be matched now.
  static func takeRequest(_ request: inout Bool) -> Bool {
    defer { request = false }
    return request
  }
}
