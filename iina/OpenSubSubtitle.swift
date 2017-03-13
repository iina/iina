//
//  OSSubtitle.swift
//  iina
//
//  Created by lhc on 11/3/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation
import Just
import PromiseKit

final class OpenSubSubtitle: OnlineSubtitle {

  var filename: String = ""
  var langID: String
  var authorComment: String
  var addDate: String
  var rating: String
  var dlCount: String
  var movieFPS: String
  var subDlLink: String
  var zipDlLink: String

  init(index: Int, filename: String, langID: String, authorComment: String, addDate: String, rating: String, dlCount: String, movieFPS: String, subDlLink: String, zipDlLink: String) {
    self.filename = filename
    self.langID = langID
    self.authorComment = authorComment
    self.addDate = addDate
    self.rating = rating
    self.dlCount = dlCount
    self.movieFPS = movieFPS
    self.subDlLink = subDlLink
    self.zipDlLink = zipDlLink
    super.init(index: index)
  }

  override func download(callback: @escaping DownloadCallback) {

  }

}


class OpenSubSupport {

  typealias Subtitle = OpenSubSubtitle

  enum OpenSubError: Error {
    // login failed (reason)
    case loginFailed(String)
    // file error
    case cannotReadFile
    case fileTooSmall
    // search failed (reason)
    case searchFailed(String)
    // lower level error
    case wrongResponseFormat
    case xmlRpcError(JustXMLRPC.XMLRPCError)
  }

  struct FileInfo {
    var hashValue: String
    var fileSize: UInt64

    var dictionary: [String: String] {
      get {
        return [
          "sublanguageid": "eng,zho",
          "moviehash": hashValue,
          "moviebytesize": "\(fileSize)"
        ]
      }
    }
  }

  typealias ResponseFilesData = [[String: Any]]

  private let chunkSize: Int = 65536
  private let apiPath = "https://api.opensubtitles.org:443/xml-rpc"
  private let xmlRpc: JustXMLRPC

  var language: String
  var username: String = ""

  let ua: String = {
    let version = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
    return "IINA v\(version)"
  }()
  var token: String!

  static let shared = OpenSubSupport()

  init(language: String? = nil) {
    self.language = language ?? ""
    self.xmlRpc = JustXMLRPC(apiPath)
  }

  func login() -> Promise<Void> {
    return Promise { fullfill, reject in
      // check logged in
      if self.loggedIn {
        fullfill()
        return
      }
      // login
      xmlRpc.call("LogIn", ["", "", "eng", ua]) { status in
        switch status {
        case .ok(let response):
          // OK
          guard let parsed = (response as? [String: Any]) else {
            reject(OpenSubError.wrongResponseFormat)
            return
          }
          // check status
          let pStatus = parsed["status"] as! String
          if pStatus.hasPrefix("200") {
            self.token = parsed["token"] as! String
            Utility.log("OpenSub: logged in")
            fullfill()
          } else {
            Utility.log("OpenSub: login failed, \(pStatus)")
            reject(OpenSubError.loginFailed(pStatus))
          }
        case .failure(_):
          // Failure
          reject(OpenSubError.loginFailed("Failure"))
        case .error(let error):
          // Error
          reject(OpenSubError.xmlRpcError(error))
        }
      }
    }
  }

  func hash(_ url: URL) -> Promise<FileInfo> {
    return Promise { fullfill, reject in
      guard let file = try? FileHandle(forReadingFrom: url) else {
        Utility.log("OpenSub: cannot get file handle")
        reject(OpenSubError.cannotReadFile)
        return
      }

      file.seekToEndOfFile()
      let fileSize = file.offsetInFile

      if fileSize < 131072 {
        Utility.log("File length less than 131072, skipped")
        reject(OpenSubError.fileTooSmall)
      }

      let offsets: [UInt64] = [0, fileSize - UInt64(chunkSize)]

      var hash = offsets.map { offset -> UInt64 in
        file.seek(toFileOffset: offset)
        return file.readData(ofLength: chunkSize).chksum64
        }.reduce(0, &+)

      hash += fileSize

      file.closeFile()

      fullfill(FileInfo(hashValue: String(format: "%016qx", hash), fileSize: fileSize))
    }
  }

  func request(_ info: FileInfo) -> Promise<[OnlineSubtitle]> {
    return Promise { fullfill, reject in
      let limit = 100
      xmlRpc.call("SearchSubtitles", [token, [info.dictionary], ["limit": limit]]) { status in
        switch status {
        case .ok(let response):
          // OK
          guard let parsed = (response as? [String: Any]) else {
            reject(OpenSubError.wrongResponseFormat)
            return
          }
          // check status
          let pStatus = parsed["status"] as! String
          guard pStatus.hasPrefix("200") else {
            reject(OpenSubError.searchFailed(pStatus))
            return
          }
          // get data
          guard let pData = (parsed["data"] as? ResponseFilesData) else {
            reject(OpenSubError.wrongResponseFormat)
            return
          }
          var result: [OpenSubSubtitle] = []
          for (index, subData) in pData.enumerated() {
            let sub = OpenSubSubtitle(index: index,
                                      filename: subData["SubFileName"] as! String,
                                      langID: subData["SubLanguageID"] as! String,
                                      authorComment: subData["SubAuthorComment"] as! String,
                                      addDate: subData["SubAddDate"] as! String,
                                      rating: subData["SubRating"] as! String,
                                      dlCount: subData["SubDownloadsCnt"] as! String,
                                      movieFPS: subData["MovieFPS"] as! String,
                                      subDlLink: subData["SubDownloadLink"] as! String,
                                      zipDlLink: subData["ZipDownloadLink"] as! String)
            result.append(sub)
          }
          fullfill(result)
        case .failure(_):
          // Failure
          reject(OpenSubError.searchFailed("Failure"))
        case .error(let error):
          // Error
          reject(OpenSubError.xmlRpcError(error))
        }
      }
    }
  }

  var loggedIn: Bool {
    return token != nil
  }

}
