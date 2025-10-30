//
//  LyricsManager.swift
//  iina
//
//  Copyright © 2025 lhc. All rights reserved.
//

import Foundation

/// Manager for handling automatic loading of lyrics from various sources
class LyricsManager {
  
  private weak var player: PlayerCore?
  
  init(player: PlayerCore) {
    self.player = player
  }
  
  /// Attempts to automatically load lyrics for the current media file
  /// - Parameter url: The URL of the media file
  func autoLoadLyrics(for url: URL) {
    guard url.isFileURL else { return }
    
    let pathWithoutExtension = url.deletingPathExtension().path
    
    // First, try to load .lrc file with the same name
    let lrcPath = pathWithoutExtension + ".lrc"
    if FileManager.default.fileExists(atPath: lrcPath) {
      Logger.log("Found LRC file: \(lrcPath)", subsystem: player?.subsystem ?? Logger.Subsystem(rawValue: "lyrics"))
      loadLRCFile(at: URL(fileURLWithPath: lrcPath))
      return
    }
    
    // If no .lrc file found, try to extract lyrics from metadata
    extractAndLoadLyricsFromMetadata(for: url)
  }
  
  /// Loads an external .lrc file as subtitles
  /// - Parameter url: The URL of the .lrc file
  private func loadLRCFile(at url: URL) {
    guard let player = player else { return }
    
    Logger.log("Loading LRC file as subtitles: \(url.path)", subsystem: player.subsystem)
    player.loadExternalSubFile(url)
  }
  
  /// Extracts lyrics from metadata and loads them as subtitles
  /// - Parameter url: The URL of the media file
  private func extractAndLoadLyricsFromMetadata(for url: URL) {
    guard let player = player else { return }
    
    guard let lyrics = FFmpegController.extractLyrics(from: url) else {
      Logger.log("No lyrics found in metadata for: \(url.path)", level: .verbose, subsystem: player.subsystem)
      return
    }
    
    guard isValidLRC(lyrics) else {
      Logger.log("Extracted lyrics are not in valid LRC format", level: .warning, subsystem: player.subsystem)
      return
    }
    
    Logger.log("Found valid lyrics in metadata, creating temporary LRC file", subsystem: player.subsystem)
    
    let tempDir = Utility.tempDirURL
    let tempFileName = url.deletingPathExtension().lastPathComponent + ".lrc"
    let tempLRCURL = tempDir.appendingPathComponent(tempFileName)
    
    do {
      try lyrics.write(to: tempLRCURL, atomically: true, encoding: .utf8)
      Logger.log("Created temporary LRC file: \(tempLRCURL.path)", subsystem: player.subsystem)
    } catch {
      Logger.log("Failed to create temporary LRC file: \(error.localizedDescription)", level: .error, subsystem: player.subsystem)
    }
    
    loadLRCFile(at: tempLRCURL)
    
    do {
      try FileManager.default.removeItem(at: tempLRCURL)
      Logger.log("Cleaned up temporary LRC file", level: .verbose, subsystem: player.subsystem)
    } catch {
      Logger.log("Failed to create temporary LRC file: \(error.localizedDescription)", level: .error, subsystem: player.subsystem)
    }
  }

  /// Validates if the provided string is in valid LRC format according to MPV
  /// - Parameter content: The string content to validate
  /// - Returns: True if the content contains valid LRC timestamps
  private func isValidLRC(_ content: String) -> Bool {
    // Empty lines are skipped by MPV, but whitespace is not
    guard let firstLine = content.split(separator: "\n", omittingEmptySubsequences: true).first else {
      return false
    }
    
    // [mm:ss.xx] or [mm:ss.xxx] or [mm:ss]
    let timestampPattern = #"^\[\d{1,2}:\d{2}(?:\.\d{2,3})?\]"#
    // [tag:data]
    let tagPattern = #"^\[[^:\]]+:[^\]]*\]"#
    
    let isTimestamp = firstLine.range(of: timestampPattern, options: .regularExpression) != nil
    let isTag = firstLine.range(of: tagPattern, options: .regularExpression) != nil

    // As long as the first line is valid, MPV won't complain and simply ignore further invalid lines
    return isTimestamp || isTag
  }
}
