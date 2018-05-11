//
//  ThumbnailCache.swift
//  iina
//
//  Created by lhc on 14/6/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class ThumbnailCache {
  static private var version = 2

  static private let sizeofDouble = MemoryLayout<Double>.size
  static private let sizeofInt64 = MemoryLayout<Int64>.size
  static private let sizeofUInt64 = MemoryLayout<UInt64>.size
  static private let sizeofUInt8 = MemoryLayout<UInt8>.size

  static private let sizeofMetadata = sizeofInt64 + sizeofUInt64 + sizeofInt64


  static private let imageProperties: [NSBitmapImageRep.PropertyKey: Any] = [
    .compressionFactor: 0.75
  ]

  static func fileExists(forName name: String) -> Bool {
    return FileManager.default.fileExists(atPath: urlFor(name).path)
  }

  static func fileIsCached(forName name: String, forVideo videoPath: URL?) -> Bool {
    guard let fileAttr = try? FileManager.default.attributesOfItem(atPath: videoPath!.path) else {
      Utility.log("Cannot get video file attributes")
      return false
    }

    // file size
    guard let fileSize = fileAttr[.size] as? UInt64 else {
      Utility.log("Cannot get video file size")
      return false
    }

    // modified date
    guard let fileModifiedDate = fileAttr[.modificationDate] as? Date else {
      Utility.log("Cannot get video file modification date")
      return false
    }
    let fileTimestamp = Int64(fileModifiedDate.timeIntervalSince1970)

    // Check metadate in the cache
    if self.fileExists(forName: name) {
      guard let file = try? FileHandle(forReadingFrom: urlFor(name)) else {
        Utility.log("Cannot open cache file.")
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
  static func write(_ thumbnails: [FFThumbnail], forName name: String, forVideo videoPath: URL?) {
    // Utility.log("Writing thumbnail cache...")

    let maxCacheSize = Preference.integer(for: .maxThumbnailPreviewCacheSize) * FileSize.Unit.mb.rawValue
    if maxCacheSize == 0 {
      return
    } else if CacheManager.shared.getCacheSize() > maxCacheSize {
      CacheManager.shared.clearOldCache()
    }

    let pathURL = urlFor(name)
    guard FileManager.default.createFile(atPath: pathURL.path, contents: nil, attributes: nil) else {
      Utility.log("Cannot create file.")
      return
    }
    guard let file = try? FileHandle(forWritingTo: pathURL) else {
      Utility.log("Cannot write to file.")
      return
    }

    // version
    let versionData = Data(bytes: &version, count: sizeofUInt8)
    file.write(versionData)

    guard let fileAttr = try? FileManager.default.attributesOfItem(atPath: videoPath!.path) else {
      Utility.log("Cannot get video file attributes")
      return
    }

    // file size
    guard var fileSize = fileAttr[.size] as? UInt64 else {
      Utility.log("Cannot get video file size")
      return
    }
    let fileSizeData = Data(bytes: &fileSize, count: sizeofUInt64)
    file.write(fileSizeData)

    // modified date
    guard let fileModifiedDate = fileAttr[.modificationDate] as? Date else {
      Utility.log("Cannot get video file modification date")
      return
    }
    var fileTimestamp = Int64(fileModifiedDate.timeIntervalSince1970)
    let fileModificationDateData = Data(bytes: &fileTimestamp, count: sizeofInt64)
    file.write(fileModificationDateData)

    // data blocks
    for tb in thumbnails {
      let timestampData = Data(bytes: &tb.realTime, count: sizeofDouble)
      guard let tiffData = tb.image?.tiffRepresentation else {
        Utility.log("Cannot generate tiff data.")
        return
      }
      guard let jpegData = NSBitmapImageRep(data: tiffData)?.representation(using: .jpeg, properties: imageProperties) else {
        Utility.log("Cannot generate jpeg data.")
        return
      }
      var blockLength = Int64(timestampData.count + jpegData.count)
      let blockLengthData = Data(bytes: &blockLength, count: sizeofInt64)
      file.write(blockLengthData)
      file.write(timestampData)
      file.write(jpegData)
    }

    CacheManager.shared.needsRefresh = true
    // Utility.log("Finished writing thumbnail cache.")
  }

  /// Read thumbnail cache to file.
  /// This method is expected to be called when the file exists.
  static func read(forName name: String) -> [FFThumbnail]? {
    // Utility.log("Reading thumbnail cache...")

    let pathURL = urlFor(name)
    guard let file = try? FileHandle(forReadingFrom: pathURL) else {
      Utility.log("Cannot open file.")
      return nil
    }

    var result: [FFThumbnail] = []

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
        Utility.log("Cannot read image. Cache file will be deleted.")
        file.closeFile()
        // try deleting corrupted cache
        do {
          try FileManager.default.removeItem(at: pathURL)
        } catch {
          Utility.log("Cannot delete corrupted cache.")
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
    // Utility.log("Finished reading thumbnail cache...")
    return result
  }

  static private func urlFor(_ name: String) -> URL {
    return Utility.thumbnailCacheURL.appendingPathComponent(name)
  }

}
