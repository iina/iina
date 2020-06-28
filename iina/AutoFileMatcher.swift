//
//  AutoFileMatcher.swift
//  iina
//
//  Created by lhc on 7/7/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

fileprivate let subsystem = Logger.Subsystem(rawValue: "fmatcher")

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

  init(player: PlayerCore, ticket: Int) {
    self.player = player
    self.ticket = ticket
  }

  /// checkTicket
  private func checkTicket() throws {
    if player.backgroundQueueTicket != ticket {
      throw AutoMatchingError.ticketExpired
    }
  }

  private func getAllMediaFiles() {
    // get all files in current directory
    guard let files = try? fm.contentsOfDirectory(at: currentFolder, includingPropertiesForKeys: nil, options: searchOptions) else { return }

    Logger.log("Getting all media files...", subsystem: subsystem)
    // group by extension
    for file in files {
      let fileInfo = FileInfo(file)
      if let mediaType = Utility.mediaType(forExtension: fileInfo.ext) {
        filesGroupedByMediaType[mediaType]!.append(fileInfo)
      }
    }

    Logger.log("Got all media files, video=\(filesGroupedByMediaType[.video]!.count), audio=\(filesGroupedByMediaType[.audio]!.count)", subsystem: subsystem)

    // natural sort
    filesGroupedByMediaType[.video]!.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
    filesGroupedByMediaType[.audio]!.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
  }

  private func getAllPossibleSubs() -> [FileInfo] {
    Logger.log("Getting all sub files...", subsystem: subsystem)

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

    Logger.log("Searching subtitles from \(subDirs.count) directories...", subsystem: subsystem)
    Logger.log("\(subDirs)", level: .verbose, subsystem: subsystem)
    // get all possible sub files
    var subtitles = filesGroupedByMediaType[.sub]!
    for subDir in subDirs {
      if let contents = try? fm.contentsOfDirectory(at: subDir, includingPropertiesForKeys: nil, options: searchOptions) {
        subtitles.append(contentsOf: contents.compactMap { subExts.contains($0.pathExtension.lowercased()) ? FileInfo($0) : nil })
      }
    }

    Logger.log("Got \(subtitles.count) subtitles", subsystem: subsystem)
    return subtitles
  }

  private func addFilesToPlaylist() throws {
    var addedCurrentVideo = false
    var needQuit = false

    Logger.log("Adding files to playlist", subsystem: subsystem)
    // add videos
    for video in filesGroupedByMediaType[.video]! + filesGroupedByMediaType[.audio]! {
      // add to playlist
      if video.url.path == player.info.currentURL?.path {
        addedCurrentVideo = true
      } else if addedCurrentVideo {
        try checkTicket()
        player.addToPlaylist(video.path)
      } else {
        let count = player.mpv.getInt(MPVProperty.playlistCount)
        let current = player.mpv.getInt(MPVProperty.playlistPos)
        try checkTicket()
        player.addToPlaylist(video.path)
        player.mpv.command(.playlistMove, args: ["\(count)", "\(current)"], checkError: false) { err in
          if err == MPV_ERROR_COMMAND.rawValue { needQuit = true }
          if err != 0 {
            Logger.log("Error \(err) when adding files to playlist", level: .error, subsystem: subsystem)
          }
        }
      }
      if needQuit { break }
    }
  }

  private func matchVideoAndSubSeries() -> [String: String] {
    var prefixDistance: [String: [String: UInt]] = [:]
    var closestVideoForSub: [String: String] = [:]

    Logger.log("Matching video and sub series...", subsystem: subsystem)
    // calculate edit distance between each v/s prefix
    for (sp, _) in subsGroupedBySeries {
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
    Logger.log("Calculated editing distance", subsystem: subsystem)

    var matchedPrefixes: [String: String] = [:]  // video: sub
    for (vp, vl) in videosGroupedBySeries {
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
        Logger.log("Matched \(vp) with \(minSub)", subsystem: subsystem)
      }
    }

    Logger.log("Finished matching.", subsystem: subsystem)
    return matchedPrefixes
  }

  private func matchSubs(withMatchedSeries matchedPrefixes: [String: String]) throws {
    Logger.log("Matching subs with matched series, prefixes=\(matchedPrefixes.count)...", subsystem: subsystem)

    // get auto load option
    let subAutoLoadOption: Preference.IINAAutoLoadAction = Preference.enum(for: .subAutoLoadIINA)
    guard subAutoLoadOption != .disabled else { return }

    for video in filesGroupedByMediaType[.video]! {
      var matchedSubs = Set<FileInfo>()
      Logger.log("Matching for \(video.filename)", subsystem: subsystem)

      // match video and sub if both are the closest one to each other
      if subAutoLoadOption.shouldLoadSubsMatchedByIINA() {
        Logger.log("Matching by IINA...", level: .verbose, subsystem: subsystem)
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
              Logger.log("Matched \(video.filename)(\(vn)) and \(sub.filename)(\(sn)) ...", level: .verbose, subsystem: subsystem)
              video.relatedSubs.append(sub)
              if sub.prefix == matchedSubPrefix {
                try checkTicket()
                player.info.matchedSubs[video.path, default: []].append(sub.url)
                sub.isMatched = true
                matchedSubs.insert(sub)
              }
            }
          }
        }
        Logger.log("Finished", level: .verbose, subsystem: subsystem)
      }

      // add subs that contains video name
      if subAutoLoadOption.shouldLoadSubsContainingVideoName() {
        Logger.log("Matching subtitles containing video name...", level: .verbose, subsystem: subsystem)
        try subtitles.filter {
          $0.filename.contains(video.filename) && !$0.isMatched
        }.forEach { sub in
          try checkTicket()
          Logger.log("Matched \(sub.filename) and \(video.filename)", level: .verbose, subsystem: subsystem)
          player.info.matchedSubs[video.path, default: []].append(sub.url)
          sub.isMatched = true
          matchedSubs.insert(sub)
        }
        Logger.log("Finished", level: .verbose, subsystem: subsystem)
      }

      // if no match
      if matchedSubs.isEmpty {
        Logger.log("No matched sub for this file", subsystem: subsystem)
        unmatchedVideos.append(video)
      } else {
        Logger.log("Matched \(matchedSubs.count) subtitles", subsystem: subsystem)
      }

      // move the sub to front if it contains priority strings
      if let priorString = Preference.string(for: .subAutoLoadPriorityString), !matchedSubs.isEmpty {
        Logger.log("Moving sub containing priority strings...", level: .verbose, subsystem: subsystem)
        let stringList = priorString
          .components(separatedBy: ",")
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
        // find the min occurance count first
        var minOccurances = Int.max
        matchedSubs.forEach { sub in
          sub.priorityStringOccurances = stringList.reduce(0, { $0 + sub.filename.countOccurances(of: $1, in: nil) })
          if sub.priorityStringOccurances < minOccurances {
            minOccurances = sub.priorityStringOccurances
          }
        }
        try matchedSubs
          .filter { $0.priorityStringOccurances > minOccurances }  // eliminate false positives in filenames
          .compactMap { player.info.matchedSubs[video.path]!.firstIndex(of: $0.url) }  // get index
          .forEach {  // move the sub with index to first
            try checkTicket()
            Logger.log("Move \(player.info.matchedSubs[video.path]![$0]) to front", level: .verbose, subsystem: subsystem)
            if let s = player.info.matchedSubs[video.path]?.remove(at: $0) {
              player.info.matchedSubs[video.path]!.insert(s, at: 0)
            }
        }
        Logger.log("Finished", level: .verbose, subsystem: subsystem)
      }
    }

    try checkTicket()
    player.info.currentVideosInfo = filesGroupedByMediaType[.video]!
  }

  private func forceMatchUnmatchedVideos() throws {
    let unmatchedSubs = subtitles.filter { !$0.isMatched }
    guard unmatchedVideos.count * unmatchedSubs.count < 100 * 100 else {
      Logger.log("Stopped force matching subs - too many files", level: .warning, subsystem: subsystem)
      return
    }

    Logger.log("Force matching unmatched videos, video=\(unmatchedVideos.count), sub=\(unmatchedSubs.count)...", subsystem: subsystem)
    if unmatchedSubs.count > 0 && unmatchedVideos.count > 0 {
      // calculate edit distance
      Logger.log("Calculating edit distance...", subsystem: subsystem)
      for sub in unmatchedSubs {
        Logger.log("Calculating edit distance for \(sub.filename)", level: .verbose, subsystem: subsystem)
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
      Logger.log("Force matching...", subsystem: subsystem)
      for video in unmatchedVideos {
        let minDistToSub = video.dist.reduce(UInt.max, { min($0, $1.value) })
        guard minDistToSub != .max else { continue }
        try checkTicket()
        unmatchedSubs
          .filter { video.dist[$0]! == minDistToSub && $0.minDist.contains(video) }
          .forEach { player.info.matchedSubs[video.path, default: []].append($0.url) }
      }
    }
  }

  func startMatching() {
    Logger.log("**Start matching", subsystem: subsystem)
    let shouldAutoLoad = Preference.bool(for: .playlistAutoAdd)

    do {
      guard let folder = player.info.currentURL?.deletingLastPathComponent(), folder.isFileURL else { return }
      currentFolder = folder

      player.info.isMatchingSubtitles = true
      getAllMediaFiles()

      // get all possible subtitles
      subtitles = getAllPossibleSubs()
      player.info.currentSubsInfo = subtitles

      // add files to playlist
      if shouldAutoLoad {
        try addFilesToPlaylist()
        player.postNotification(.iinaPlaylistChanged)
      }

      // group video and sub files
      Logger.log("Grouping video files...", subsystem: subsystem)
      videosGroupedBySeries = FileGroup.group(files: filesGroupedByMediaType[.video]!).flatten()
      Logger.log("Finished with \(videosGroupedBySeries.count) groups", subsystem: subsystem)

      Logger.log("Grouping sub files...", subsystem: subsystem)
      subsGroupedBySeries = FileGroup.group(files: subtitles).flatten()
      Logger.log("Finished with \(subsGroupedBySeries.count) groups", subsystem: subsystem)

      // match video and sub series
      let matchedPrefixes = matchVideoAndSubSeries()

      // match sub stage 1
      try matchSubs(withMatchedSeries: matchedPrefixes)
      // match sub stage 2
      if shouldAutoLoad {
        try forceMatchUnmatchedVideos()
      }

      player.info.isMatchingSubtitles = false
      player.postNotification(.iinaPlaylistChanged)
      Logger.log("**Finished matching", subsystem: subsystem)
    } catch let err {
      player.info.isMatchingSubtitles = false
      Logger.log(err.localizedDescription, level: .error, subsystem: subsystem)
      return
    }
  }

}
