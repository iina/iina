//
//  ThumbnailCache.swift
//  iina
//
//  Created by lhc on 14/6/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

fileprivate let subsystem = Logger.Subsystem(rawValue: "thumbcache")

class ThumbnailCache {
  static private var version = 2

  static private let sizeofDouble = MemoryLayout<Double>.size
  static private let sizeofInt64 = MemoryLayout<Int64>.size
  static private let sizeofUInt64 = MemoryLayout<UInt64>.size
  static private let sizeofUInt8 = MemoryLayout<UInt8>.size

  static private let sizeofMetadata = sizeofUInt8 + sizeofUInt64 + sizeofInt64


  static private let imageProperties: [NSBitmapImageRep.PropertyKey: Any] = [
    .compressionFactor: 0.75
  ]

  static func fileExists(forName name: String) -> Bool {
    return FileManager.default.fileExists(atPath: urlFor(name).path)
  }

  static func fileIsCached(forName name: String, forVideo videoPath: URL?) -> Bool {
    guard let fileAttr = try? FileManager.default.attributesOfItem(atPath: videoPath!.path) else {
      Logger.log("Cannot get video file attributes", level: .error, subsystem: subsystem)
      return false
    }

    // file size
    guard let fileSize = fileAttr[.size] as? UInt64 else {
      Logger.log("Cannot get video file size", level: .error, subsystem: subsystem)
      return false
    }

    // modified date
    guard let fileModifiedDate = fileAttr[.modificationDate] as? Date else {
      Logger.log("Cannot get video file modification date", level: .error, subsystem: subsystem)
      return false
    }
    let fileTimestamp = Int64(fileModifiedDate.timeIntervalSince1970)

    // Check metadate in the cache
    if self.fileExists(forName: name) {
      guard let file = try? FileHandle(forReadingFrom: urlFor(name)) else {
        Logger.log("Cannot open cache file.", level: .error, subsystem: subsystem)
        return false
      }

      let cacheVersion: Int = file.readData(ofLength: sizeofUInt8).withUnsafeBytes { $0.pointee }
      if cacheVersion != version { return false }

      return file.readData(ofLength: sizeofUInt64).withUnsafeBytes { $0.pointee } == fileSize &&
             file.readData(ofLength: sizeofInt64).withUnsafeBytes { $0.pointee } == fileTimestamp
    }

    return false
  }

  /// Write thumbnail cache to file.
  /// This method is expected to be called when the file doesn't exist.
  static func write(_ thumbnails: [FFmpegThumbnail], forName name: String, forVideo videoPath: URL?) {
    Logger.log("Writing thumbnail cache...", subsystem: subsystem)

    let maxCacheSize = Preference.integer(for: .maxThumbnailPreviewCacheSize) * FloatingPointByteCountFormatter.PrefixFactor.mi.rawValue
    if maxCacheSize == 0 {
      return
    } else if CacheManager.shared.getCacheSize() > maxCacheSize {
      CacheManager.shared.clearOldCache()
    }

    let pathURL = urlFor(name)
    guard FileManager.default.createFile(atPath: pathURL.path, contents: nil, attributes: nil) else {
      Logger.log("Cannot create file.", level: .error, subsystem: subsystem)
      return
    }
    guard let file = try? FileHandle(forWritingTo: pathURL) else {
      Logger.log("Cannot write to file.", level: .error, subsystem: subsystem)
      return
    }

    // version
    let versionData = Data(bytes: &version, count: sizeofUInt8)
    file.write(versionData)

    guard let fileAttr = try? FileManager.default.attributesOfItem(atPath: videoPath!.path) else {
      Logger.log("Cannot get video file attributes", level: .error, subsystem: subsystem)
      return
    }

    // file size
    guard var fileSize = fileAttr[.size] as? UInt64 else {
      Logger.log("Cannot get video file size", level: .error, subsystem: subsystem)
      return
    }
    let fileSizeData = Data(bytes: &fileSize, count: sizeofUInt64)
    file.write(fileSizeData)

    // modified date
    guard let fileModifiedDate = fileAttr[.modificationDate] as? Date else {
      Logger.log("Cannot get video file modification date", level: .error, subsystem: subsystem)
      return
    }
    var fileTimestamp = Int64(fileModifiedDate.timeIntervalSince1970)
    let fileModificationDateData = Data(bytes: &fileTimestamp, count: sizeofInt64)
    file.write(fileModificationDateData)

    // data blocks
    for tb in thumbnails {
      var timestamp = tb.timestamp
      let timestampData = Data(bytes: &timestamp, count: sizeofDouble)
      guard let tiffData = tb.image.tiffRepresentation else {
        Logger.log("Cannot generate tiff data.", level: .error, subsystem: subsystem)
        return
      }
      guard let jpegData = NSBitmapImageRep(data: tiffData)?.representation(using: .jpeg, properties: imageProperties) else {
        Logger.log("Cannot generate jpeg data.", level: .error, subsystem: subsystem)
        return
      }
      var blockLength = Int64(timestampData.count + jpegData.count)
      let blockLengthData = Data(bytes: &blockLength, count: sizeofInt64)
      file.write(blockLengthData)
      file.write(timestampData)
      file.write(jpegData)
    }

    CacheManager.shared.needsRefresh = true
    Logger.log("Finished writing thumbnail cache.", subsystem: subsystem)
  }

  /// Read thumbnail cache to file.
  /// This method is expected to be called when the file exists.
  static func read(forName name: String) -> [FFmpegThumbnail]? {
    Logger.log("Reading thumbnail cache...", subsystem: subsystem)

    let pathURL = urlFor(name)
    guard let file = try? FileHandle(forReadingFrom: pathURL) else {
      Logger.log("Cannot open file.", level: .error, subsystem: subsystem)
      return nil
    }
    Logger.log("Reading from \(pathURL.path)", subsystem: subsystem)

    var result: [FFmpegThumbnail] = []

    // get file length
    file.seekToEndOfFile()
    let eof = file.offsetInFile

    // skip metadata
    file.seek(toFileOffset: UInt64(sizeofMetadata))

    // data blocks
    while file.offsetInFile != eof {
      // length
      let lengthData = file.readData(ofLength: sizeofInt64)
      let blockLength: Int64 = lengthData.withUnsafeBytes { $0.pointee }
      // timestamp
      let timestampData = file.readData(ofLength: sizeofDouble)
      let timestamp: Double = timestampData.withUnsafeBytes { $0.pointee }
      // jpeg
      let jpegData = file.readData(ofLength: Int(blockLength) - sizeofDouble)
      guard let image = NSImage(data: jpegData) else {
        Logger.log("Cannot read image. Cache file will be deleted.", level: .warning, subsystem: subsystem)
        file.closeFile()
        // try deleting corrupted cache
        do {
          try FileManager.default.removeItem(at: pathURL)
        } catch {
          Logger.log("Cannot delete corrupted cache.", level: .error, subsystem: subsystem)
        }
        return nil
      }
      // construct
      let tb = FFmpegThumbnail(image: image, timestamp: timestamp)
      result.append(tb)
    }

    file.closeFile()
    Logger.log("Finished reading thumbnail cache, \(result.count) in total", subsystem: subsystem)
    return result
  }

  static private func urlFor(_ name: String) -> URL {
    return Utility.thumbnailCacheURL.appendingPathComponent(name)
  }

}
