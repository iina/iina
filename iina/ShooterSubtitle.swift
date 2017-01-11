//
//  ShooterSubtitle.swift
//  iina
//
//  Created by lhc on 10/1/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation
import Just

final class ShooterSubtitle: OnlineSubtitle, OnlineSubtitleSupport {

  var desc: String
  var delay: Int
  var files: [SubFile]

  struct ShooterRequestData {
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

  struct SubFile {
    var ext: String
    var path: String
  }

  typealias RequestData = ShooterRequestData
  typealias ResponseData = [[String: Any]]
  typealias ResponseFilesData = [[String: String]]

  private static let chunkSize: Int = 4096
  private static let apiPath = "https://www.shooter.cn/api/subapi.php"

  init(index: Int, desc: String, delay: Int, files: [SubFile]) {
    self.desc = desc
    self.delay = delay
    self.files = files
    super.init(index: index)
  }

  override func download(callback: @escaping DownloadCallback) {
    Just.get(files[0].path) { res in
      callback(res.saveDataToFolder(Utility.tempDirURL, index: self.index))
    }
  }

  static func hash(_ url: URL) -> RequestData? {

    guard let file = try? FileHandle(forReadingFrom: url) else {
      Utility.log("Cannot get file handle")
      return nil
    }

    file.seekToEndOfFile()
    let fileSize: UInt64 = file.offsetInFile

    guard fileSize >= 8192 else {
      Utility.log("File length less than 8k??")
      return nil
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

    return RequestData(hashValue: hash, path: url.path)
  }

  static func request(_ info: RequestData, callback: @escaping SubCallback) {
    Just.post(apiPath, params: info.dictionary, timeout: 10) { response in
      guard let json = response.json as? ResponseData else {
        Utility.showAlert(message: "Cannot find subtitles.")
        return
      }

      var subtitles: [ShooterSubtitle] = []
      var index = 1

      json.forEach { sub in
        let filesDic = sub["Files"] as! ResponseFilesData
        let files = filesDic.map { o -> SubFile in return SubFile(ext: o["Ext"]!, path: o["Link"]!) }
        let desc = sub["Desc"] as? String ?? ""
        let delay = sub["Delay"] as? Int ?? 0

        subtitles.append(ShooterSubtitle(index: index, desc: desc, delay: delay, files: files))
        index += 1
      }
      callback(subtitles)
    }
  }

}
