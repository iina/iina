//
//  LyricsEngine.swift
//  iina
//
//  Created by Erik Molina on 12/21/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Foundation

struct LyricsEngine {
  
  private enum Constants {
    static let defaultVisibleLinesCount = 7
    static let missingIndex = -1
  }
  
  private let lines: [LyricsLine]
  
  init(lines: [LyricsLine]) {
    // Keep lines sorted so time-based lookups remain deterministic.
    self.lines = lines.sorted { $0.time < $1.time }
  }
  
  // MARK: - Current line
  
  func currentLine(at time: TimeInterval) -> LyricsLine? {
    guard !lines.isEmpty else { return nil }
    
    // Before first line
    if time < lines[0].time {
      return nil
    }
    
    // Binary search for the last line at or before the requested time.
    // Assumes lines are sorted ascending by time; duplicate timestamps are allowed but the
    // exact matching duplicate is non-deterministic.
    var low = 0
    var high = lines.count - 1
    
    while low <= high {
      let mid = (low + high) / 2
      let midTime = lines[mid].time
      
      if midTime == time {
        return lines[mid]
      } else if midTime < time {
        low = mid + 1
      } else {
        high = mid - 1
      }
    }
    
    // high ends at the index of the last line that is <= time (or -1 if all are later).
    return lines[max(0, high)]
  }
  
  // MARK: - Neighbors
  
  func previousLine(at time: TimeInterval) -> LyricsLine? {
    // firstIndex(where:) will pick the earliest duplicate timestamp when duplicates exist.
    guard
      let current = currentLine(at: time),
      let index = lines.firstIndex(of: current),
      index > 0
    else {
      return nil
    }
    return lines[index - 1]
  }
  
  func nextLine(at time: TimeInterval) -> LyricsLine? {
    guard
      let current = currentLine(at: time),
      let index = lines.firstIndex(of: current),
      index < lines.count - 1
    else {
      return nil
    }
    return lines[index + 1]
  }
  
  // MARK: - Lines around current (for scrollable view)
  
  /// Returns an array of lines centered around the current line at the given time.
  /// - Parameters:
  ///   - time: Current playback time
  ///   - count: Number of lines to return (should be odd: 5, 7, or 9)
  /// - Returns: Array of lines with current line at the center index
  func linesAroundCurrent(at time: TimeInterval, count: Int) -> [LyricsLine] {
    guard !lines.isEmpty, count > 0 else { return [] }
    
    guard let current = currentLine(at: time),
          let currentIndex = lines.firstIndex(where: { $0.time == current.time }) else {
      // Before first line or no current line - return first N lines
      return Array(lines.prefix(count))
    }
    
    // count is expected to be odd; if even, the current line shifts right by one.
    let halfCount = count / 2
    let startIndex = max(0, currentIndex - halfCount)
    let endIndex = min(lines.count, currentIndex + halfCount + 1)
    // Clamp to edges; do not pad with placeholders when near the start or end.
    
    return Array(lines[startIndex..<endIndex])
  }
  
  func overlayState(at time: TimeInterval, visibleLinesCount: Int) -> LyricsOverlayState {
    guard let current = currentLine(at: time) else {
      return LyricsOverlayState(previous: nil, current: nil, next: nil, allLines: [], currentIndex: Constants.missingIndex)
    }
    
    guard let index = lines.firstIndex(where: { $0.time == current.time }) else {
      return LyricsOverlayState(previous: nil, current: current, next: nil, allLines: [current], currentIndex: 0)
    }
    
    let prev = index > 0 ? lines[index - 1] : nil
    let next = index + 1 < lines.count ? lines[index + 1] : nil
    
    // Collect the requested window around the current line (no padding near edges).
    let allLines = linesAroundCurrent(at: time, count: visibleLinesCount)
    let currentIndexInAllLines = allLines.firstIndex(where: { $0.time == current.time }) ?? Constants.missingIndex
    
    return LyricsOverlayState(
      previous: prev,
      current: current,
      next: next,
      allLines: allLines,
      currentIndex: currentIndexInAllLines
    )
  }
  
  // MARK: - Overlay state
  
  func overlayState(at time: TimeInterval) -> LyricsOverlayState {
    return overlayState(at: time, visibleLinesCount: Constants.defaultVisibleLinesCount)
  }
  
}