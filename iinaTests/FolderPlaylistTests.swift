//
//  FolderPlaylistTests.swift
//  iinaTests
//
//  Tests for adding the playable files in the folder of the opened file to its playlist.
//

import Foundation
import Testing
@testable import IINA

/// A playlist that holds the paths added to it, in playlist order, and can be abandoned after a number of additions.
final class RecordingFolderPlaylist: FolderPlaylist {
  /// The paths in the playlist, in playlist order.
  private(set) var paths: [String]
  /// The additions made, in order.
  private(set) var additions: [String] = []
  /// The number of additions after which the playlist is abandoned, or `nil` if it never is.
  var abandonAfter: Int?

  init(paths: [String]) {
    self.paths = paths
  }

  func checkFolderTicket() throws {
    if let abandonAfter, additions.count >= abandonAfter {
      throw PlayerCore.TicketExpiredError.ticketExpired
    }
  }

  func append(_ path: String) {
    additions.append("append \(path)")
    paths.append(path)
  }

  func insert(_ path: String, at index: Int) {
    additions.append("insert \(path) at \(index)")
    paths.insert(path, at: index)
  }
}

@Suite("Adding the files in the folder of the opened file")
struct FolderPlaylistAssemblyTests {

  let folder = ["a.mp4", "b.mp4", "c.mp4", "d.mp4", "e.mp4"]

  @Test("The files after the opened file are appended before the files before it are inserted")
  func afterFilesFirst() throws {
    let playlist = RecordingFolderPlaylist(paths: ["c.mp4"])
    try FolderPlaylistAssembly.add(folder, openedPath: "c.mp4", to: playlist)
    #expect(playlist.additions == ["append d.mp4", "append e.mp4", "insert a.mp4 at 0", "insert b.mp4 at 1"])
    #expect(playlist.paths == folder)
  }

  @Test("When the opened file is the first file only appends are made")
  func openedFirst() throws {
    let playlist = RecordingFolderPlaylist(paths: ["a.mp4"])
    try FolderPlaylistAssembly.add(folder, openedPath: "a.mp4", to: playlist)
    #expect(playlist.additions == ["append b.mp4", "append c.mp4", "append d.mp4", "append e.mp4"])
    #expect(playlist.paths == folder)
  }

  @Test("When the opened file is the last file only inserts are made")
  func openedLast() throws {
    let playlist = RecordingFolderPlaylist(paths: ["e.mp4"])
    try FolderPlaylistAssembly.add(folder, openedPath: "e.mp4", to: playlist)
    #expect(playlist.additions == ["insert a.mp4 at 0", "insert b.mp4 at 1", "insert c.mp4 at 2", "insert d.mp4 at 3"])
    #expect(playlist.paths == folder)
  }

  @Test("When the opened file is not among the files every file is inserted", arguments: [nil, "z.mp4"])
  func openedAbsent(openedPath: String?) throws {
    let playlist = RecordingFolderPlaylist(paths: ["z.mp4"])
    try FolderPlaylistAssembly.add(folder, openedPath: openedPath, to: playlist)
    #expect(playlist.additions == ["insert a.mp4 at 0", "insert b.mp4 at 1", "insert c.mp4 at 2", "insert d.mp4 at 3",
                                   "insert e.mp4 at 4"])
    #expect(playlist.paths == folder + ["z.mp4"])
  }

  @Test("A file opened through a symbolic link is found among the files listed through its target, and the other way round",
        arguments: [false, true])
  func openedThroughSymlink(openedThroughTarget: Bool) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for name in folder {
      FileManager.default.createFile(atPath: directory.appendingPathComponent(name).path, contents: nil)
    }
    let throughLink = folder.map { directory.appendingPathComponent($0).path }
    try #require(throughLink[0].hasPrefix("/var/"), "the temporary directory is reached through the /var symbolic link")
    let throughTarget = throughLink.map { "/private" + $0 }
    let listed = openedThroughTarget ? throughLink : throughTarget
    let opened = openedThroughTarget ? throughTarget[2] : throughLink[2]
    let playlist = RecordingFolderPlaylist(paths: [opened])
    try FolderPlaylistAssembly.add(listed, openedPath: opened, to: playlist)
    #expect(playlist.additions == ["append \(listed[3])", "append \(listed[4])", "insert \(listed[0]) at 0",
                                   "insert \(listed[1]) at 1"])
  }

  @Test("Adding stops once the playlist is abandoned", arguments: [0, 1, 2, 3])
  func abandonedStops(abandonAfter: Int) {
    let playlist = RecordingFolderPlaylist(paths: ["c.mp4"])
    playlist.abandonAfter = abandonAfter
    #expect(throws: PlayerCore.TicketExpiredError.ticketExpired) {
      try FolderPlaylistAssembly.add(folder, openedPath: "c.mp4", to: playlist)
    }
    let all = ["append d.mp4", "append e.mp4", "insert a.mp4 at 0", "insert b.mp4 at 1"]
    #expect(playlist.additions == Array(all.prefix(abandonAfter)))
  }

  @Test("An empty folder adds nothing")
  func emptyFolder() throws {
    let playlist = RecordingFolderPlaylist(paths: ["c.mp4"])
    try FolderPlaylistAssembly.add([], openedPath: "c.mp4", to: playlist)
    #expect(playlist.additions.isEmpty)
  }
}

@Suite("The folder playlist ticket")
struct FolderPlaylistTicketTests {

  @Test("A ticket held since the playlist was created passes its check")
  func currentTicketPasses() throws {
    let ticket = FolderPlaylistTicket()
    let held = ticket.value
    try ticket.check(held)
  }

  @Test("A ticket held from before the playlist was abandoned fails its check")
  func abandonedTicketFails() throws {
    let ticket = FolderPlaylistTicket()
    let held = ticket.value
    ticket.abandon()
    #expect(ticket.value == held + 1)
    #expect(throws: PlayerCore.TicketExpiredError.ticketExpired) { try ticket.check(held) }
    try ticket.check(ticket.value)
  }

  @Test("The request to match the folder is taken once")
  func requestTakenOnce() {
    var request = true
    #expect(FolderPlaylistTicket.takeRequest(&request))
    #expect(!request)
    #expect(!FolderPlaylistTicket.takeRequest(&request))
    #expect(!request)
  }
}
