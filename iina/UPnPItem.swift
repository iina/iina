//
//  UPnPItem.swift
//  iina
//
//  Created for UPnP/DLNA support
//  Copyright © 2024 Contributors. All rights reserved.
//

import Foundation

/// Represents a media item or container from a UPnP ContentDirectory
struct UPnPItem: Identifiable, Hashable {
  let id: String // Object ID
  let title: String
  let itemType: ItemType
  let resourceURL: URL? // Direct playback URL (for items)
  let parentID: String
  let metadata: ItemMetadata
  
  enum ItemType: String {
    case container = "container"
    case item = "item"
  }
  
  struct ItemMetadata: Hashable {
    let artist: String?
    let album: String?
    let genre: String?
    let duration: String? // ISO 8601 duration
    let size: Int64? // File size in bytes
    let mimeType: String?
    let resolution: String? // e.g., "1920x1080"
    let bitrate: Int? // kbps
    let date: String? // Date string (various formats)
    let author: String? // Creator/author
    let description: String? // Description
  }
  
  var isPlayable: Bool {
    itemType == .item && resourceURL != nil
  }
  
  var isContainer: Bool {
    itemType == .container
  }
  
  /// Format duration for display
  var formattedDuration: String? {
    guard let duration = metadata.duration else { return nil }
    // Parse ISO 8601 duration (PT1H23M45S) to readable format
    return parseISODuration(duration)
  }
  
  /// Format file size for display
  var formattedSize: String? {
    guard let size = metadata.size else { return nil }
    return formatBytes(size)
  }
  
  /// Format date for display
  var formattedDate: String? {
    guard let dateStr = metadata.date else { return nil }
    // Try to parse and format the date
    // Try common date formats used by UPnP servers and present as a short, clean date (no time).
    let isoFormatter = ISO8601DateFormatter()
    if let date = isoFormatter.date(from: dateStr) {
      let displayFormatter = DateFormatter()
      displayFormatter.dateStyle = .short
      displayFormatter.timeStyle = .none
      return displayFormatter.string(from: date)
    }
    
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    
    // yyyy-MM-dd
    dateFormatter.dateFormat = "yyyy-MM-dd"
    if let date = dateFormatter.date(from: dateStr) {
      let displayFormatter = DateFormatter()
      displayFormatter.dateStyle = .short
      displayFormatter.timeStyle = .none
      return displayFormatter.string(from: date)
    }
    
    // yyyy-MM-dd HH:mm:ss
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    if let date = dateFormatter.date(from: dateStr) {
      let displayFormatter = DateFormatter()
      displayFormatter.dateStyle = .short
      displayFormatter.timeStyle = .none
      return displayFormatter.string(from: date)
    }
    
    return dateStr // Return as-is if can't parse
  }
  
  private func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }
  
  private func parseISODuration(_ iso: String) -> String {
    // Simple parser for PT1H23M45S format
    var hours = 0
    var minutes = 0
    var seconds = 0
    
    if let hRange = iso.range(of: #"(\d+)H"#, options: .regularExpression) {
      let hStr = String(iso[hRange])
      hours = Int(hStr.dropLast()) ?? 0
    }
    if let mRange = iso.range(of: #"(\d+)M"#, options: .regularExpression) {
      let mStr = String(iso[mRange])
      minutes = Int(mStr.dropLast()) ?? 0
    }
    if let sRange = iso.range(of: #"(\d+)S"#, options: .regularExpression) {
      let sStr = String(iso[sRange])
      seconds = Int(sStr.dropLast()) ?? 0
    }
    
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%d:%02d", minutes, seconds)
    }
  }
}

/// Error types for UPnP operations
enum UPnPError: LocalizedError {
  case discoveryFailed
  case deviceNotFound
  case serviceNotFound
  case browseFailed(String)
  case invalidResponse
  case networkError(Error)
  case xmlParseError
  
  var errorDescription: String? {
    switch self {
    case .discoveryFailed:
      return "Failed to discover UPnP devices"
    case .deviceNotFound:
      return "UPnP device not found"
    case .serviceNotFound:
      return "Required UPnP service not found"
    case .browseFailed(let reason):
      return "Failed to browse content: \(reason)"
    case .invalidResponse:
      return "Invalid response from UPnP device"
    case .networkError(let error):
      return "Network error: \(error.localizedDescription)"
    case .xmlParseError:
      return "Failed to parse XML response"
    }
  }
}

