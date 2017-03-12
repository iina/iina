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

  struct SubFile {
    var ext: String
    var path: String
  }

  var desc: String
  var delay: Int
  var files: [SubFile]

  init(index: Int, desc: String, delay: Int, files: [SubFile]) {
    self.desc = desc
    self.delay = delay
    self.files = files
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
    // lower level error
    case xmlRpcError(JustXMLRPC.XMLRPCError)
  }

  struct FileInfo {
    var hashValue: String
    var fileSize: UInt64

    var dictionary: [String: Any] {
      get {
        return [:]
      }
    }
  }

  typealias ResponseData = [[String: Any]]
  typealias ResponseFilesData = [[String: String]]

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
      }
      // login
      xmlRpc.call("LogIn", ["", "", "eng", ua]) { status in
        switch status {
        case .ok(let response):
          // OK
          guard let parsed = (response as? [String: Any]) else { return }
          let pStatus = parsed["status"] as! String
          // check status
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

    }
  }

  var loggedIn: Bool {
    return token != nil
  }

}
