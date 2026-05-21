//
//  LRCParser.swift
//  iina
//
//  Created by Erik Molina on 12/21/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Foundation

/// Parses LRC (Lyric) files into LyricsLine models.
///
/// Supports standard LRC timestamp format: [mm:ss.xx] or [mm:ss]
/// Handles multi-timestamp lines (e.g., [00:10][00:30]Same lyric)
/// by creating separate LyricsLine entries for each timestamp.
/// Empty or malformed lines are silently skipped.
struct LRCParser {
  
  // MARK: - Public API
  
  static func parse(_ content: String) -> [LyricsLine] {
    var allLines: [LyricsLine] = []
    
    let textLines = content.components(separatedBy: .newlines)
    
    for textLine in textLines {
      guard let parsedLines = parseLine(textLine) else {
        continue
      }
      allLines.append(contentsOf: parsedLines)
    }
    
    // Sort by time to handle out-of-order lines and multi-timestamp entries.
    return allLines.sorted { $0.time < $1.time }
  }
  
  // MARK: - Private Parsing
  
  private static func parseLine(_ line: String) -> [LyricsLine]? {
    // Regex matches LRC timestamps: [mm:ss.xx] or [mm:ss]
    // Captures minutes and seconds (with optional decimal) as separate groups.
    let pattern = #"\[(\d+):(\d+(?:\.\d+)?)\]"#
    
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return nil
    }
    
    let matches = regex.matches(
      in: line,
      range: NSRange(line.startIndex..., in: line)
    )
    
    guard !matches.isEmpty else {
      return nil
    }
    
    // Extract lyric text by removing all timestamps.
    let lyricText = regex.stringByReplacingMatches(
      in: line,
      range: NSRange(line.startIndex..., in: line),
      withTemplate: ""
    ).trimmingCharacters(in: .whitespaces)
    
    // Create a LyricsLine for each timestamp (supports multi-timestamp lines).
    var lyricsLines: [LyricsLine] = []
    
    for match in matches {
      guard
        let minRange = Range(match.range(at: 1), in: line),
        let secRange = Range(match.range(at: 2), in: line),
        let minutes = Double(line[minRange]),
        let seconds = Double(line[secRange])
      else {
        continue
      }
      
      let timeInSeconds = minutes * 60 + seconds
      lyricsLines.append(LyricsLine(time: timeInSeconds, text: lyricText))
    }
    
    return lyricsLines
  }
}
