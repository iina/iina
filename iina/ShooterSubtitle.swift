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

class Shooter {
  class Subtitle: OnlineSubtitle {
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

    override func download() -> Promise<[URL]> {
      return Promise { resolver in
        Just.get(files[0].path, asyncCompletionHandler: { response in
          guard response.ok, let data = response.content else {
            resolver.reject(OnlineSubtitle.CommonError.networkError)
            return
          }
          let fileName = "[\(self.index)]\(response.fileName ?? "")"
          guard let url = data.saveToFolder(Utility.tempDirURL, filename: fileName) else {
            resolver.reject(OnlineSubtitle.CommonError.fsError)
            return
          }
          resolver.fulfill([url])
        })
      }
    }
  }

  enum Error: Swift.Error {
    case cannotReadFile
    case fileTooSmall
  }

  class Fetcher: OnlineSubtitle.DefaultFetcher, OnlineSubtitleFetcher {
    typealias Subtitle = Shooter.Subtitle

    struct FileInfo {
      var hashValue: String
      var path: String

      var dictionary: [String: Any] {
        return [
          "filehash": hashValue,
          "pathinfo": path,
          "format": "json"
        ]
      }
    }

    typealias ResponseData = [[String: Any]]
    typealias ResponseFilesData = [[String: String]]

    private let chunkSize: Int = 4096
    private let apiPath = "https://www.shooter.cn/api/subapi.php"

    private var language: String?

    func fetch(from url: URL, withProviderID id: String, playerCore player: PlayerCore) -> Promise<[Subtitle]> {
      return hash(url).then { self.request($0) }
    }

    private func hash(_ url: URL) -> Promise<FileInfo> {
      return Promise { resolver in
        guard let file = try? FileHandle(forReadingFrom: url) else {
          resolver.reject(Error.cannotReadFile)
          return
        }

        file.seekToEndOfFile()
        let fileSize: UInt64 = file.offsetInFile

        guard fileSize >= 12288 else {
          resolver.reject(Error.fileTooSmall)
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

        file.closeFile()

        resolver.fulfill(FileInfo(hashValue: hash, path: url.path))
      }
    }

    private func request(_ info: FileInfo) -> Promise<[Subtitle]> {
      return Promise { resolver in
        Just.post(apiPath, params: info.dictionary, timeout: 10, asyncCompletionHandler: { response in
          guard response.ok else {
            resolver.reject(OnlineSubtitle.CommonError.networkError)
            return
          }
          guard let json = response.json as? ResponseData else {
            resolver.fulfill([])
            return
          }

          var subtitles: [Subtitle] = []
          var index = 1

          json.forEach { sub in
            let filesDic = sub["Files"] as! ResponseFilesData
            let files = filesDic.map { o -> Subtitle.SubFile in
              return Subtitle.SubFile(ext: o["Ext"]!, path: o["Link"]!)
            }
            let desc = sub["Desc"] as? String ?? ""
            let delay = sub["Delay"] as? Int ?? 0

            subtitles.append(Subtitle(index: index, desc: desc, delay: delay, files: files))
            index += 1
          }
          resolver.fulfill(subtitles)
        })
      }
    }
  }
}
