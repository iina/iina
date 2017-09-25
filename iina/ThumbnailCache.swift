//
//  ThumbnailCache.swift
//  iina
//
//  Created by lhc on 14/6/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class ThumbnailCache {

  static private let sizeofDouble = MemoryLayout<Double>.size
  static private let sizeofInt64 = MemoryLayout<Int64>.size

  static private let imageProperties: [NSBitmapImageRep.PropertyKey: Any] = [
    .compressionFactor: 0.75
  ]

  static func fileExists(forName name: String) -> Bool {
    return FileManager.default.fileExists(atPath: urlFor(name).path)
  }

  /// Write thumbnail cache to file. 
  /// This method is expected to be called when the file doesn't exist.
  static func write(_ thumbnails: [FFThumbnail], forName name: String) {
    // Utility.log("Writing thumbnail cache...")

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
    var version = Int64(1)
    let versionData = Data(bytes: &version, count: sizeofInt64)
    file.write(versionData)

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
    file.seek(toFileOffset: 0)

    // version
    let _ = file.readData(ofLength: sizeofInt64)

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
