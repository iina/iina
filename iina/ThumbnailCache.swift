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
  
  static private let sizeofMetadata = MemoryLayout<UInt8>.size + MemoryLayout<UInt64>.size + MemoryLayout<Int64>.size


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

      let cacheVersion = Int(file.read(type: UInt8.self))
      if cacheVersion != version { return false }

      return file.read(type: UInt64.self) == fileSize &&
        file.read(type: Int64.self) == fileTimestamp
    }

    return false
  }

  /// Write thumbnail cache to file.
  /// This method is expected to be called when the file doesn't exist.
  static func write(_ thumbnails: [FFThumbnail], forName name: String, forVideo videoPath: URL?) {
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
    let versionData = Data(bytesOf: version)
    file.write(versionData)

    guard let fileAttr = try? FileManager.default.attributesOfItem(atPath: videoPath!.path) else {
      Logger.log("Cannot get video file attributes", level: .error, subsystem: subsystem)
      return
    }

    // file size
    guard let fileSize = fileAttr[.size] as? UInt64 else {
      Logger.log("Cannot get video file size", level: .error, subsystem: subsystem)
      return
    }
    let fileSizeData = Data(bytesOf: fileSize)
    file.write(fileSizeData)

    // modified date
    guard let fileModifiedDate = fileAttr[.modificationDate] as? Date else {
      Logger.log("Cannot get video file modification date", level: .error, subsystem: subsystem)
      return
    }
    let fileTimestamp = Int64(fileModifiedDate.timeIntervalSince1970)
    let fileModificationDateData = Data(bytesOf: fileTimestamp)
    file.write(fileModificationDateData)

    // data blocks
    for tb in thumbnails {
      let timestampData = Data(bytesOf: tb.realTime)
      guard let tiffData = tb.image?.tiffRepresentation else {
        Logger.log("Cannot generate tiff data.", level: .error, subsystem: subsystem)
        return
      }
      guard let jpegData = NSBitmapImageRep(data: tiffData)?.representation(using: .jpeg, properties: imageProperties) else {
        Logger.log("Cannot generate jpeg data.", level: .error, subsystem: subsystem)
        return
      }
      let blockLength = Int64(timestampData.count + jpegData.count)
      let blockLengthData = Data(bytesOf: blockLength)
      file.write(blockLengthData)
      file.write(timestampData)
      file.write(jpegData)
    }

    CacheManager.shared.needsRefresh = true
    Logger.log("Finished writing thumbnail cache.", subsystem: subsystem)
  }

  /// Read thumbnail cache to file.
  /// This method is expected to be called when the file exists.
  static func read(forName name: String) -> [FFThumbnail]? {
    Logger.log("Reading thumbnail cache...", subsystem: subsystem)

    let pathURL = urlFor(name)
    guard let file = try? FileHandle(forReadingFrom: pathURL) else {
      Logger.log("Cannot open file.", level: .error, subsystem: subsystem)
      return nil
    }
    Logger.log("Reading from \(pathURL.path)", subsystem: subsystem)

    var result: [FFThumbnail] = []

    // get file length
    file.seekToEndOfFile()
    let eof = file.offsetInFile

    // skip metadata
    file.seek(toFileOffset: UInt64(sizeofMetadata))

    // data blocks
    while file.offsetInFile != eof {
      // length
      let blockLength: Int64 = file.read(type: Int64.self)
      // timestamp
      let timestamp: Double = file.read(type: Double.self)
      // jpeg
      let jpegData = file.readData(ofLength: Int(blockLength) - MemoryLayout.size(ofValue: timestamp))
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
      let tb = FFThumbnail()
      tb.realTime = timestamp
      tb.image = image
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
