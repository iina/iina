//
//  ThumbnailCache.swift
//  iina
//
//  Created by lhc on 14/6/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

fileprivate let subsystem = Logger.makeSubsystem("thumbcache", ["photo.stack"])

class ThumbnailCache {
  private typealias CacheVersion = UInt8
  private typealias FileSize = UInt64
  private typealias FileTimestamp = Double

  private static let version: CacheVersion = 3
  private static let maxThumbnailCount = TimelineThumbnailBroker.maxThumbnailCount
  private static let maxBytesPerThumbnail = TimelineThumbnailBroker.maxBytesPerThumbnail
  private static let maxBytesPerCache = TimelineThumbnailBroker.maxBytesPerUpdate
  
  private static let imageProperties: [NSBitmapImageRep.PropertyKey: Any] = [
    .compressionFactor: 0.75
  ]
  
  private static func log(_ message: @autoclosure () -> String, level: Logger.Level = .debug) {
    Logger.log(message, level: level, subsystem: subsystem)
  }

  static func fileExists(forName name: String) -> Bool {
    return FileManager.default.fileExists(atPath: urlFor(name).path)
  }

  static func fileIsCached(forName name: String, forVideo videoPath: URL?) -> Bool {
    guard let fileAttr = try? FileManager.default.attributesOfItem(atPath: videoPath!.path) else {
      log("Cannot get video file attributes", level: .error)
      return false
    }

    // file size
    guard let fileSize = fileAttr[.size] as? FileSize else {
      log("Cannot get video file size", level: .error)
      return false
    }

    // modified date (stored with sub-second precision so a same-size edit
    // within one second cannot reuse an older cache)
    guard let fileModifiedDate = fileAttr[.modificationDate] as? Date else {
      log("Cannot get video file modification date", level: .error)
      return false
    }
    let fileTimestamp = FileTimestamp(fileModifiedDate.timeIntervalSince1970)

    // Check metadate in the cache
    if self.fileExists(forName: name) {
      guard let file = try? FileHandle(forReadingFrom: urlFor(name)) else {
        log("Cannot open cache file.", level: .error)
        return false
      }

      let cacheVersion = file.read(type: CacheVersion.self)
      if cacheVersion != version {
        file.closeFile()
        return false
      }

      let matches = file.read(type: FileSize.self) == fileSize &&
        file.read(type: FileTimestamp.self) == fileTimestamp
      file.closeFile()
      return matches
    }

    return false
  }

  /// Write thumbnail cache to file, replacing an existing entry atomically.
  static func write(_ thumbnails: [FFThumbnail], forName name: String, forVideo videoPath: URL?) {
    log("Writing thumbnail cache...")

    let maxCacheSize = Preference.integer(for: .maxThumbnailPreviewCacheSize) * FloatingPointByteCountFormatter.PrefixFactor.mi.rawValue
    if maxCacheSize == 0 {
      return
    } else if CacheManager.shared.getCacheSize() > maxCacheSize {
      CacheManager.shared.clearOldCache()
    }

    guard let fileAttr = try? FileManager.default.attributesOfItem(atPath: videoPath!.path) else {
      log("Cannot get video file attributes", level: .error)
      return
    }

    // file size
    guard let fileSize = fileAttr[.size] as? FileSize else {
      log("Cannot get video file size", level: .error)
      return
    }
    // modified date
    guard let fileModifiedDate = fileAttr[.modificationDate] as? Date else {
      log("Cannot get video file modification date", level: .error)
      return
    }
    let fileTimestamp = FileTimestamp(fileModifiedDate.timeIntervalSince1970)

    let pathURL = urlFor(name)
    let temporaryURL = pathURL.deletingLastPathComponent()
      .appendingPathComponent(".\(pathURL.lastPathComponent).\(UUID().uuidString).tmp")
    guard FileManager.default.createFile(atPath: temporaryURL.path, contents: nil, attributes: nil),
          let file = try? FileHandle(forWritingTo: temporaryURL) else {
      log("Cannot create cache file.", level: .error)
      try? FileManager.default.removeItem(at: temporaryURL)
      return
    }
    defer {
      file.closeFile()
      try? FileManager.default.removeItem(at: temporaryURL)
    }

    // version and metadata
    file.write(Data(bytesOf: version))
    let fileModificationDateData = Data(bytesOf: fileTimestamp)
    file.write(Data(bytesOf: fileSize))
    file.write(fileModificationDateData)

    // data blocks
    var imageCount = 0
    var totalBytes = 0
    for tb in thumbnails {
      guard imageCount < maxThumbnailCount else { break }
      let timestampData = Data(bytesOf: tb.realTime)
      guard let tiffData = tb.image?.tiffRepresentation else {
        log("Cannot generate tiff data.", level: .error)
        return
      }
      guard let jpegData = NSBitmapImageRep(data: tiffData)?.representation(using: .jpeg, properties: imageProperties) else {
        log("Cannot generate jpeg data.", level: .error)
        return
      }
      guard jpegData.count <= maxBytesPerThumbnail,
            totalBytes + jpegData.count <= maxBytesPerCache else {
        log("Skipping oversized thumbnail cache entry.", level: .warning)
        continue
      }
      let blockLength = Int64(timestampData.count + jpegData.count)
      let blockLengthData = Data(bytesOf: blockLength)
      file.write(blockLengthData)
      file.write(timestampData)
      file.write(jpegData)
      imageCount += 1
      totalBytes += jpegData.count
    }

    file.closeFile()
    do {
      if FileManager.default.fileExists(atPath: pathURL.path) {
        _ = try FileManager.default.replaceItemAt(pathURL, withItemAt: temporaryURL, backupItemName: nil, options: [])
      } else {
        try FileManager.default.moveItem(at: temporaryURL, to: pathURL)
      }
    } catch {
      log("Cannot install thumbnail cache: \(error)", level: .error)
      return
    }

    CacheManager.shared.needsRefresh = true
    log("Finished writing thumbnail cache.")
  }

  /// Read thumbnail cache to file.
  /// This method is expected to be called when the file exists.
  static func read(forName name: String) -> [FFThumbnail]? {
    log("Reading thumbnail cache...")

    let pathURL = urlFor(name)
    guard let file = try? FileHandle(forReadingFrom: pathURL) else {
      log("Cannot open file.", level: .error)
      return nil
    }
    log("Reading from \(pathURL.path)")

    var result: [FFThumbnail] = []

    // Validate and consume metadata before reading image blocks. Older cache
    // versions are intentionally discarded because they only stored integer
    // modification timestamps.
    guard file.read(type: CacheVersion.self) == version,
          file.read(type: FileSize.self) != nil,
          file.read(type: FileTimestamp.self) != nil else {
      file.closeFile()
      deleteCacheFile(at: pathURL)
      return nil
    }

    // get file length while preserving the first data-block offset.
    let dataStart = file.offsetInFile
    file.seekToEndOfFile()
    let eof = file.offsetInFile
    file.seek(toFileOffset: dataStart)

    // data blocks
    var totalBytes = 0
    while file.offsetInFile < eof {
      // length and timestamp
      guard let blockLength = file.read(type: Int64.self),
            blockLength >= Int64(MemoryLayout<Double>.size),
            blockLength <= Int64(MemoryLayout<Double>.size + maxBytesPerThumbnail),
            file.offsetInFile + UInt64(blockLength) <= eof,
            result.count < maxThumbnailCount,
            let timestamp = file.read(type: Double.self) else {
        log("Cannot read image header. Cache file will be deleted.", level: .warning)
        file.closeFile()
        deleteCacheFile(at: pathURL)
        return nil
      }
      // jpeg
      let jpegLength = Int(blockLength) - MemoryLayout.size(ofValue: timestamp)
      guard totalBytes + jpegLength <= maxBytesPerCache else {
        log("Cache file exceeds thumbnail byte limit.", level: .warning)
        file.closeFile()
        deleteCacheFile(at: pathURL)
        return nil
      }
      let jpegData = file.readData(ofLength: jpegLength)
      guard jpegData.count == jpegLength else {
        log("Cannot read complete image data. Cache file will be deleted.", level: .warning)
        file.closeFile()
        deleteCacheFile(at: pathURL)
        return nil
      }
      guard let image = NSImage(data: jpegData) else {
        log("Cannot read image. Cache file will be deleted.", level: .warning)
        file.closeFile()
        deleteCacheFile(at: pathURL)
        return nil
      }
      // construct
      let tb = FFThumbnail()
      tb.realTime = timestamp
      tb.image = image
      result.append(tb)
      totalBytes += jpegLength
    }

    guard file.offsetInFile == eof else {
      log("Cache file has trailing data. Cache file will be deleted.", level: .warning)
      file.closeFile()
      deleteCacheFile(at: pathURL)
      return nil
    }

    file.closeFile()
    log("Finished reading thumbnail cache, \(result.count) in total")
    return result
  }

  static func clearThumbnailCache() {
    try? FileManager.default.removeItem(atPath: Utility.thumbnailCacheURL.path)
    Utility.createDirIfNotExist(url: Utility.thumbnailCacheURL)
  }

  private static func deleteCacheFile(at pathURL: URL) {
    // try deleting corrupted cache
    do {
      try FileManager.default.removeItem(at: pathURL)
    } catch {
      log("Cannot delete corrupted cache.", level: .error)
    }
  }

  private static func urlFor(_ name: String) -> URL {
    return Utility.thumbnailCacheURL.appendingPathComponent(name)
  }

}
