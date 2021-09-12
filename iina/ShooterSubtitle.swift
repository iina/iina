//
//  ShooterSubtitle.swift
//  iina
//
//  Created by lhc on 10/1/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation
import Just
import PromiseKit

fileprivate let subsystem = Logger.Subsystem(rawValue: "shooter")

final class ShooterSubtitle: OnlineSubtitle {

  var desc: String
  var delay: Int
  var files: [SubFile]

  struct SubFile {
    var ext: String
    var path: String
  }

  init(index: Int, desc: String, delay: Int, files: [SubFile]) {
    self.desc = desc
    self.delay = delay
    self.files = files
    super.init(index: index)
  }

  override func download(callback: @escaping DownloadCallback) {
    Just.get(files[0].path) { response in
      guard response.ok, let data = response.content else {
        callback(.failed)
        return
      }
      let fileName = "[\(self.index)]\(response.fileName ?? "")"
      if let url = data.saveToFolder(Utility.tempDirURL, filename: fileName) {
        callback(.ok([url]))
      }
    }
  }

}


class ShooterSupport {

  struct FileInfo {
    var hashValue: String
    var path: String

    var dictionary: [String: Any] {
      get {
        return [
          "filehash": hashValue,
          "pathinfo": path,
          "format": "json"
        ]
      }
    }
  }

  enum ShooterError: Error {
    // file error
    case cannotReadFile(Error)
    case fileTooSmall
    case networkError(Error?)
    case noResult
  }

  typealias ResponseData = [[String: Any]]
  typealias ResponseFilesData = [[String: String]]

  private let chunkSize: Int = 4096
  private let apiPath = "https://www.shooter.cn/api/subapi.php"

  private var language: String?

  init(language: String? = nil) {
    self.language = language
  }

  func hash(_ url: URL) -> Promise<FileInfo> {
    return Promise { resolver in
      var file: FileHandle
      do {
        file = try FileHandle(forReadingFrom: url)
      } catch {
        resolver.reject(ShooterError.cannotReadFile(error))
        return
      }
      defer { file.closeFile() }

      file.seekToEndOfFile()
      let fileSize: UInt64 = file.offsetInFile

      guard fileSize >= 12288 else {
        resolver.reject(ShooterError.fileTooSmall)
        return
      }

      let offsets: [UInt64] = [
        4096,
        fileSize / 3 * 2,
        fileSize / 3,
        fileSize - 8192
      ]

      let hash = offsets.map { offset -> String in
        file.seek(toFileOffset: offset)
        return file.readData(ofLength: chunkSize).md5
        }.joined(separator: ";")

      resolver.fulfill(FileInfo(hashValue: hash, path: url.path))
    }
  }

  func request(_ info: FileInfo) -> Promise<[ShooterSubtitle]> {
    return Promise { resolver in
      Just.post(apiPath, params: info.dictionary, timeout: 10) { response in
        guard response.ok else {
          resolver.reject(ShooterError.networkError(response.error))
          return
        }
        guard let json = response.json as? ResponseData else {
          resolver.reject(ShooterError.noResult)
          return
        }

        var subtitles: [ShooterSubtitle] = []
        var index = 1

        json.forEach { sub in
          let filesDic = sub["Files"] as! ResponseFilesData
          let files = filesDic.map { o -> ShooterSubtitle.SubFile in
            return ShooterSubtitle.SubFile(ext: o["Ext"]!, path: o["Link"]!)
          }
          let desc = sub["Desc"] as? String ?? ""
          let delay = sub["Delay"] as? Int ?? 0

          subtitles.append(ShooterSubtitle(index: index, desc: desc, delay: delay, files: files))
          index += 1
        }
        resolver.fulfill(subtitles)
      }
    }
  }

}
