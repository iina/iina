//
//  AutoFileMatcher.swift
//  iina
//
//  Created by lhc on 7/7/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

class AutoFileMatcher {

  private enum AutoMatchingError: Error {
    case ticketExpired
  }

  weak private var player: PlayerCore!
  var ticket: Int

  private let fm = FileManager.default
  private let searchOptions: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]

  private var currentFolder: URL!
  private var filesGroupedByMediaType: [MPVTrack.TrackType: [FileInfo]] = [.video: [], .audio: [], .sub: []]
  private var videosGroupedBySeries: [String: [FileInfo]] = [:]
  private var subtitles: [FileInfo] = []
  private var subsGroupedBySeries: [String: [FileInfo]] = [:]
  private var unmatchedVideos: [FileInfo] = []
  
  private let subsystem: Logger.Subsystem

  private func log(_ message: String, level: Logger.Level = .debug) {
    Logger.log(message, level: level, subsystem: subsystem)
  }

  init(player: PlayerCore, ticket: Int) {
    self.player = player
    self.ticket = ticket
    subsystem = Logger.makeSubsystem("fmatcher\(player.playerNumber)")
  }

  /// checkTicket
  private func checkTicket() throws {
    try player.checkTicket(ticket)
  }

  private func getAllMediaFiles() throws {
    // get all files in current directory
    guard let files = try? fm.contentsOfDirectory(at: currentFolder, includingPropertiesForKeys: nil, options: searchOptions) else { return }

    log("Getting all media files...")
    // group by extension
    for file in files {
      try checkTicket()
      let fileInfo = FileInfo(file)
      if let mediaType = Utility.mediaType(forExtension: fileInfo.ext) {
        filesGroupedByMediaType[mediaType]!.append(fileInfo)
      }
    }

    log("Got all media files, video=\(filesGroupedByMediaType[.video]!.count), audio=\(filesGroupedByMediaType[.audio]!.count)")

    // natural sort
    filesGroupedByMediaType[.video]!.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
    filesGroupedByMediaType[.audio]!.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
  }

  private func getAllPossibleSubs() throws -> [FileInfo] {
    try checkTicket()
    log("Getting all sub files...")

    // search subs
    let subExts = Utility.supportedFileExt[.sub]!
    var subDirs: [URL] = []

    // search subs in other directories
    let rawUserDefinedSearchPaths = Preference.string(for: .subAutoLoadSearchPath) ?? "./*"
    let userDefinedSearchPaths = rawUserDefinedSearchPaths.components(separatedBy: ":").filter { !$0.isEmpty }
    for path in userDefinedSearchPaths {
      var p = path
      // handle `~`
      if path.hasPrefix("~") {
        p = NSString(string: path).expandingTildeInPath
      }
      if path.hasSuffix("/") { p.deleteLast(1) }
      // only check wildcard at the end
      let hasWildcard = path.hasSuffix("/*")
      if hasWildcard { p.deleteLast(2) }
      // handle absolute paths
      let pathURL = path.hasPrefix("/") || path.hasPrefix("~") ? URL(fileURLWithPath: p, isDirectory: true) : currentFolder.appendingPathComponent(p, isDirectory: true)
      // handle wildcards
      if hasWildcard {
        // append all sub dirs
        if let contents = try? fm.contentsOfDirectory(at: pathURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
          subDirs.append(contentsOf: contents.filter { $0.isExistingDirectory })
        }
      } else {
        subDirs.append(pathURL)
      }
    }

    log("Searching subtitles from \(subDirs.count) directories...")
    log("\(subDirs)", level: .verbose)
    // get all possible sub files
    var subtitles = filesGroupedByMediaType[.sub]!
    for subDir in subDirs {
      try checkTicket()
      if let contents = try? fm.contentsOfDirectory(at: subDir, includingPropertiesForKeys: nil, options: searchOptions) {
        subtitles.append(contentsOf: contents.compactMap { subExts.contains($0.pathExtension.lowercased()) ? FileInfo($0) : nil })
      }
    }

    log("Got \(subtitles.count) subtitles")
    return subtitles
  }

  private func addFilesToPlaylist() throws {
    var addedCurrentVideo = false
    var needQuit = false

    log("Adding files to playlist")
    // add videos
    for video in filesGroupedByMediaType[.video]! + filesGroupedByMediaType[.audio]! {
      // add to playlist
      if video.url.path == player.info.currentURL?.path {
        addedCurrentVideo = true
      } else if addedCurrentVideo {
        try checkTicket()
        player.addToPlaylist(video.path, silent: true)
      } else {
        let count = player.mpv.getInt(MPVProperty.playlistCount)
        let current = player.mpv.getInt(MPVProperty.playlistPos)
        try checkTicket()
        player.addToPlaylist(video.path, silent: true)
        player.mpv.command(.playlistMove, args: ["\(count)", "\(current)"], checkError: false,
                           level: .verbose) { err in
          if err == MPV_ERROR_COMMAND.rawValue { needQuit = true }
          if err != 0 {
            self.log("Error \(err) when adding files to playlist", level: .error)
          }
        }
      }
      if needQuit { break }
    }
  }

  private func matchVideoAndSubSeries() throws -> [String: String] {
    var prefixDistance: [String: [String: UInt]] = [:]
    var closestVideoForSub: [String: String] = [:]

    log("Matching video and sub series...")
    // calculate edit distance between each v/s prefix
    for (sp, _) in subsGroupedBySeries {
      try checkTicket()
      prefixDistance[sp] = [:]
      var minDist = UInt.max
      var minVideo = ""
      for (vp, vl) in videosGroupedBySeries {
        guard vl.count > 2 else { continue }
        let dist = ObjcUtils.levDistance(vp, and: sp)
        prefixDistance[sp]![vp] = dist
        if dist < minDist {
          minDist = dist
          minVideo = vp
        }
      }
      closestVideoForSub[sp] = minVideo
    }
    log("Calculated editing distance")

    var matchedPrefixes: [String: String] = [:]  // video: sub
    for (vp, vl) in videosGroupedBySeries {
      try checkTicket()
      guard vl.count > 2 else { continue }
      var minDist = UInt.max
      var minSub = ""
      for (sp, _) in subsGroupedBySeries {
        let dist = prefixDistance[sp]![vp]!
        if dist < minDist {
          minDist = dist
          minSub = sp
        }
      }
      let threshold = UInt(Double(vp.count + minSub.count) * 0.6)
      if closestVideoForSub[minSub] == vp && minDist < threshold {
        matchedPrefixes[vp] = minSub
        log("Matched \(vp) with \(minSub)")
      }
    }

    log("Finished matching")
    return matchedPrefixes
  }

  private func matchSubs(withMatchedSeries matchedPrefixes: [String: String]) throws {
    log("Matching subs with matched series, prefixes=\(matchedPrefixes.count)...")

    // get auto load option
    let subAutoLoadOption: Preference.IINAAutoLoadAction = Preference.enum(for: .subAutoLoadIINA)
    guard subAutoLoadOption != .disabled else { return }

    for video in filesGroupedByMediaType[.video]! {
      var matchedSubs = Set<FileInfo>()
      log("Matching for \(video.filename)")

      // match video and sub if both are the closest one to each other
      if subAutoLoadOption.shouldLoadSubsMatchedByIINA() {
        log("Matching by IINA...", level: .verbose)
        // is in series
        if !video.prefix.isEmpty, let matchedSubPrefix = matchedPrefixes[video.prefix] {
          // find sub with same name
          for sub in subtitles {
            guard let vn = video.nameInSeries, let sn = sub.nameInSeries else { continue }
            var nameMatched: Bool
            if let vnInt = Int(vn), let snInt = Int(sn) {
              nameMatched = vnInt == snInt
            } else {
              nameMatched = vn == sn
            }
            if nameMatched {
              log("Matched \(video.filename)(\(vn)) and \(sub.filename)(\(sn)) ...", level: .verbose)
              video.relatedSubs.append(sub)
              if sub.prefix == matchedSubPrefix {
                try checkTicket()
                player.info.$matchedSubs.withLock { $0[video.path, default: []].append(sub.url) }
                sub.isMatched = true
                matchedSubs.insert(sub)
              }
            }
          }
        }
        log("Finished", level: .verbose)
      }

      // add subs that contains video name
      if subAutoLoadOption.shouldLoadSubsContainingVideoName() {
        log("Matching subtitles containing video name...", level: .verbose)
        try subtitles.filter {
          $0.filename.contains(video.filename) && !$0.isMatched
        }.forEach { sub in
          try checkTicket()
          log("Matched \(sub.filename) and \(video.filename)", level: .verbose)
          player.info.$matchedSubs.withLock { $0[video.path, default: []].append(sub.url) }
          sub.isMatched = true
          matchedSubs.insert(sub)
        }
        log("Finished", level: .verbose)
      }

      // if no match
      if matchedSubs.isEmpty {
        log("No matched sub for this file")
        unmatchedVideos.append(video)
      } else {
        log("Matched \(matchedSubs.count) subtitles")
      }

      // move the sub to front if it contains priority strings
      if let priorString = Preference.string(for: .subAutoLoadPriorityString), !matchedSubs.isEmpty {
        log("Moving sub containing priority strings...", level: .verbose)
        let stringList = priorString
          .components(separatedBy: ",")
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
        // find the min occurrence count first
        var minOccurrences = Int.max
        matchedSubs.forEach { sub in
          sub.priorityStringOccurrences = stringList.reduce(0, { $0 + sub.filename.countOccurrences(of: $1, in: nil) })
          if sub.priorityStringOccurrences < minOccurrences {
            minOccurrences = sub.priorityStringOccurrences
          }
        }
        try player.info.$matchedSubs.withLock { subs in
          try matchedSubs
            .filter { $0.priorityStringOccurrences > minOccurrences }  // eliminate false positives in filenames
            .compactMap { subs[video.path]!.firstIndex(of: $0.url) }   // get index
            .forEach { // move the sub with index to first
              try checkTicket()
              log("Move \(subs[video.path]![$0]) to front", level: .verbose)
              if let s = subs[video.path]?.remove(at: $0) {
                subs[video.path]!.insert(s, at: 0)
              }
            }
        }
        log("Finished", level: .verbose)
      }
    }

    try checkTicket()
    player.info.currentVideosInfo = filesGroupedByMediaType[.video]!
  }

  private func forceMatchUnmatchedVideos() throws {
    let unmatchedSubs = subtitles.filter { !$0.isMatched }
    guard unmatchedVideos.count * unmatchedSubs.count < 100 * 100 else {
      log("Stopped force matching subs - too many files", level: .warning)
      return
    }

    log("Force matching unmatched videos, video=\(unmatchedVideos.count), sub=\(unmatchedSubs.count)...")
    if unmatchedSubs.count > 0 && unmatchedVideos.count > 0 {
      // calculate edit distance
      log("Calculating edit distance...")
      for sub in unmatchedSubs {
        log("Calculating edit distance for \(sub.filename)", level: .verbose)
        var minDistToVideo: UInt = .max
        for video in unmatchedVideos {
          try checkTicket()
          let threshold = UInt(Double(video.filename.count + sub.filename.count) * 0.6)
          let rawDist = ObjcUtils.levDistance(video.prefix, and: sub.prefix) + ObjcUtils.levDistance(video.suffix, and: sub.suffix)
          let dist: UInt = rawDist < threshold ? rawDist : UInt.max
          sub.dist[video] = dist
          video.dist[sub] = dist
          if dist < minDistToVideo { minDistToVideo = dist }
        }
        guard minDistToVideo != .max else { continue }
        sub.minDist = filesGroupedByMediaType[.video]!.filter { sub.dist[$0] == minDistToVideo }
      }

      // match them
      log("Force matching...")
      for video in unmatchedVideos {
        let minDistToSub = video.dist.reduce(UInt.max, { min($0, $1.value) })
        guard minDistToSub != .max else { continue }
        try checkTicket()
        unmatchedSubs
          .filter { video.dist[$0]! == minDistToSub && $0.minDist.contains(video) }
          .forEach { sub in
            player.info.$matchedSubs.withLock { $0[video.path, default: []].append(sub.url) }
          }
      }
    }
  }

  func startMatching() throws {
    log("**Start matching")
    let shouldAutoLoad = Preference.bool(for: .playlistAutoAdd)

    do {
      guard let folder = player.info.currentURL?.deletingLastPathComponent(), folder.isFileURL else { return }
      currentFolder = folder

      player.info.isMatchingSubtitles = true
      try getAllMediaFiles()

      // get all possible subtitles
      subtitles = try getAllPossibleSubs()
      player.info.currentSubsInfo = subtitles

      // add files to playlist
      if shouldAutoLoad {
        try addFilesToPlaylist()
        player.postNotification(.iinaPlaylistChanged)
      }

      // group video and sub files
      log("Grouping video files...")
      videosGroupedBySeries = FileGroup.group(files: filesGroupedByMediaType[.video]!).flatten()
      log("Finished with \(videosGroupedBySeries.count) groups")

      log("Grouping sub files...")
      subsGroupedBySeries = FileGroup.group(files: subtitles).flatten()
      log("Finished with \(subsGroupedBySeries.count) groups")

      // match video and sub series
      let matchedPrefixes = try matchVideoAndSubSeries()

      // match sub stage 1
      try matchSubs(withMatchedSeries: matchedPrefixes)
      // match sub stage 2
      if shouldAutoLoad {
        try forceMatchUnmatchedVideos()
      }

      player.info.isMatchingSubtitles = false
      player.postNotification(.iinaPlaylistChanged)
      log("**Finished matching")
    } catch PlayerCore.TicketExpiredError.ticketExpired {
      player.info.isMatchingSubtitles = false
      throw PlayerCore.TicketExpiredError.ticketExpired
    } catch let err {
      player.info.isMatchingSubtitles = false
      log(err.localizedDescription, level: .error)
      return
    }
  }
}
