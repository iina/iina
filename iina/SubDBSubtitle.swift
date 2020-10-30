//
//  SubDBSubtitle.swift
//  iina
//
//  Created by Dmitry Khrykin on 28.10.2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Foundation

fileprivate let subsystem = Logger.Subsystem(rawValue: "subdb")

final class SubDBSubtitle: OnlineSubtitle {

  @objc var movieFilename: String = ""
  @objc var langID: String
  @objc var movieHash: String

  init(movieFilename: String, hash: String, langID: String, index: Int = 0) {
    self.movieFilename = movieFilename
    self.movieHash = hash
    self.langID = langID

    super.init(index: index)
  }

  override func download(callback: @escaping DownloadCallback) {
    let apiURL = URL(string: "\(SubDBSupport.apiEndpoint)?action=download&hash=\(movieHash)&language=\(langID)&version=\(index)")!

    let session = URLSession(configuration: SubDBSupport.urlSessionConfiguration)
    let task = session.dataTask(with: apiURL) { (data, response, error) in
      guard error == nil,
            let response = response as? HTTPURLResponse,
            response.statusCode >= 200 && response.statusCode < 400,
            let data = data else {
        callback(.failed)
        return
      }

      let subFilename = "[\(self.index)]\(self.movieFilename)-\(self.langID)-thesubdb.com.srt"

      if let url = data.saveToFolder(Utility.tempDirURL, filename: subFilename) {
        callback(.ok([url]))
      }
    }

    task.resume()
  }
}


class SubDBSupport {

  typealias Subtitle = SubDBSubtitle
  typealias AvaliableInfo = [String: Int]

  enum SubDBError: Error {
    case networkError
    case noResult
    // file error
    case cannotReadFile
    case cannotComputeHash
    case fileTooSmall
    // user canceled
    case userCanceled
  }

  static let shared = SubDBSupport()

  var language: String

  private var languageAliases: [String] {
    guard let firstLangAlias = ISO639Helper.languages
            .first(where: { $0.code == language }) else {
      return [language]
    }

    let languageFullName = firstLangAlias.name

    return ISO639Helper.languages
      .filter({$0.name == languageFullName})
      .map({ $0.code })
  }

  fileprivate static let apiEndpoint = "http://api.thesubdb.com/"
  fileprivate static var urlSessionConfiguration: URLSessionConfiguration {
    let configuration = URLSessionConfiguration.default
    configuration.httpAdditionalHeaders = [
      "User-Agent": "SubDB/1.0 (iina/0.1; http://github.com/inna/inna)"
    ]

    return configuration
  }

  init(language: String? = nil) {
    self.language = language ?? ""
  }

  func computeHash(fileUrl url: URL) throws -> String {
    // From http://thesubdb.com/api/:
    //
    // hash is composed by taking the first and the last 64kb of the video file,
    // putting all together and generating a md5 of the resulting data (128kb).

    let chunkSize = 64 * 1024
    let hashSize = 2 * chunkSize

    guard
      let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
      let file = try? FileHandle(forReadingFrom: url) else {
      Logger.log("Cannot get file size", level: .error, subsystem: subsystem)

      throw SubDBError.cannotReadFile
    }

    defer {
      file.closeFile()
    }

    let fileSize = (attr as NSDictionary).fileSize()
    if fileSize < hashSize {
      Logger.log("File length less than \(hashSize), skipped", level: .warning, subsystem: subsystem)

      throw SubDBError.fileTooSmall
    }

    var hashData = Data(capacity: hashSize)
    let tailOffset = fileSize - UInt64(chunkSize)

    #if swift(>=5.3) // Xcode 12 and above

    if #available(OSX 10.15.4, *) {
      try file.seek(toOffset: 0)
      guard let beginChunk = try file.read(upToCount: chunkSize) else {
        throw SubDBError.cannotComputeHash
      }

      hashData.append(beginChunk)

      try file.seek(toOffset: tailOffset)
      guard let endChunk = try file.read(upToCount: chunkSize) else {
        throw SubDBError.cannotComputeHash
      }

      hashData.append(endChunk)
    }

    #endif

    if #available(OSX 10.15.4, *) {} else {
      file.seek(toFileOffset: 0)
      hashData.append(file.readData(ofLength: chunkSize))

      file.seek(toFileOffset: tailOffset)
      hashData.append(file.readData(ofLength: chunkSize))
    }

    if hashData.count != hashSize {
      Logger.log("Wrong hash size, skipped", level: .warning, subsystem: subsystem)

      throw SubDBError.cannotComputeHash
    }

    return hashData.md5
  }

  func search(fileUrl url: URL, completion: @escaping (Error?, [SubDBSubtitle]?) -> ()) {
    do {
      let filename = url.deletingPathExtension().lastPathComponent
      let hash = try self.computeHash(fileUrl: url)

      let apiURL = URL(string: "\(SubDBSupport.apiEndpoint)?action=search&hash=\(hash)&versions")!

      let session = URLSession(configuration: SubDBSupport.urlSessionConfiguration)
      let task = session.dataTask(with: apiURL) { (data, response, error) in
        if error != nil {
          Logger.log("Network error: \(error!)", level: .warning, subsystem: subsystem)

          completion(SubDBError.networkError, nil)
          return
        }

        guard let response = response as? HTTPURLResponse,
              let data = data else {
          Logger.log("Network error", level: .warning, subsystem: subsystem)

          completion(SubDBError.networkError, nil)
          return
        }

        if response.statusCode == 404 {
          completion(SubDBError.noResult, nil)
          return
        }

        if response.statusCode < 200 && response.statusCode >= 400 {
          completion(SubDBError.networkError, nil)
          return
        }

        let stringResponse = String(data: data, encoding: .utf8)!
        let avaliable = self.parseResponse(stringResponse)

        var result: [SubDBSubtitle] = []
        for languageAlias in self.languageAliases {
          guard let variantsCount = avaliable[languageAlias] else {
            continue
          }

          for index in 0..<variantsCount {
            result.append(SubDBSubtitle(movieFilename: filename,
                                          hash: hash,
                                          langID: languageAlias,
                                          index: index))
          }
        }

        if result.isEmpty {
          completion(SubDBError.noResult, nil)
          return
        }

        completion(nil, result)
      }

      task.resume()
    } catch {
      completion(error, nil)
      return
    }
  }

  private func parseResponse(_ stringResponse: String) -> AvaliableInfo {
    var result: AvaliableInfo = [:]

    let langStrings = stringResponse.split(separator: ",")
    for string in langStrings {
      let info = string.split(separator: ":")
      let language = String(info[0])
      result[language] = info.count == 2 ? Int(info[1]) : 1
    }

    return result
  }

}

