//
//  FolderPlaylist.swift
//  iina
//
//  Adding the files in the folder of the opened file to its playlist.
//

import Foundation

/// The playlist the files in the folder of the opened file are added to.
protocol FolderPlaylist: AnyObject {
  /// Throws `PlayerCore.TicketExpiredError.ticketExpired` once the playlist of the opened file has been abandoned.
  func checkFolderTicket() throws
  /// Add the file with the given path to the end of the playlist.
  func append(_ path: String)
  /// Insert the file with the given path into the playlist at the given index.
  func insert(_ path: String, at index: Int)
}

/// Adding the playable files in the folder of the opened file to its playlist.
enum FolderPlaylistAssembly {

  /// Add the files with the given paths, in folder order, around the opened file.
  ///
  /// The files after the opened file are appended first, in order, so that the next entry is available as soon as possible. Then the
  /// files before it are inserted ahead of it, each at its index in the folder. The opened file is found as described for
  /// `index(of:in:)`. If the opened file is not among the files then all of them are inserted. The ticket is checked before each file
  /// is added, and adding stops once the playlist has been abandoned.
  static func add(_ paths: [String], openedPath: String?, to playlist: FolderPlaylist) throws {
    let openedIndex = index(of: openedPath, in: paths)
    if let openedIndex {
      for path in paths[(openedIndex + 1)...] {
        try playlist.checkFolderTicket()
        playlist.append(path)
      }
    }
    for (index, path) in paths[..<(openedIndex ?? paths.count)].enumerated() {
      try playlist.checkFolderTicket()
      playlist.insert(path, at: index)
    }
  }

  /// The index among the paths of the file with the given path.
  ///
  /// A path equal to the given one is taken first. Failing that, the paths are compared with their symbolic links resolved, so that a
  /// file opened through a path that goes through a symbolic link, such as `/var` or `/tmp`, is found among the files of its folder
  /// listed under `/private/var` or `/private/tmp`, and the other way round.
  static func index(of path: String?, in paths: [String]) -> Int? {
    guard let path else { return nil }
    if let index = paths.firstIndex(of: path) { return index }
    let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    return paths.firstIndex { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == resolved }
  }
}

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
