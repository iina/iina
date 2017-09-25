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
import Gzip

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
    Just.get(subDlLink) { response in
      guard response.ok, let data = response.content, let unzipped = try? data.gunzipped() else {
        callback(.failed)
        return
      }
      let subFilename = "[\(self.index)]\(self.filename)"
      if let url = unzipped.saveToFolder(Utility.tempDirURL, filename: subFilename) {
        callback(.ok(url))
      }
    }
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
    // user canceled
    case userCanceled
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
          "moviehash": hashValue,
          "moviebytesize": "\(fileSize)"
        ]
      }
    }
  }

  typealias ResponseFilesData = [[String: Any]]

  private let chunkSize: Int = 65536
  private let apiPath = "https://api.opensubtitles.org:443/xml-rpc"
  private static let serviceName: NSString = "IINA OpenSubtitles Account"
  private let xmlRpc: JustXMLRPC

  var language: String
  var username: String = ""

  let ua: String = {
    let version = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
    return "IINA v\(version)"
  }()
  var token: String!

  var heartBeatTimer: Timer?
  let heartbeatInterval = TimeInterval(800)

  static let shared = OpenSubSupport()

  init(language: String? = nil) {
    self.language = language ?? ""
    self.xmlRpc = JustXMLRPC(apiPath)
  }

  func login(testUser username: String? = nil, password: String? = nil) -> Promise<Void> {
    return Promise { fulfill, reject in
      var finalUser = ""
      var finalPw = ""
      if let testUser = username, let testPw = password {
        // if test login
        finalUser = testUser
        finalPw = testPw
      } else {
        // check logged in
        if self.loggedIn {
          fulfill(())
          return
        }
        // read password
        if let udUsername = Preference.string(for: .openSubUsername), !udUsername.isEmpty {
          let (readResult, readPassword, _) = OpenSubSupport.findPassword(username: udUsername)
          if readResult == errSecSuccess {
            finalUser = udUsername
            finalPw = readPassword!
          }
        }
      }
      // login
      xmlRpc.call("LogIn", [finalUser, finalPw, "eng", ua]) { status in
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
            Utility.log("OpenSub: logged in as user \(finalUser)")
            self.startHeartbeat()
            fulfill(())
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
    return Promise { fulfill, reject in
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

      fulfill(FileInfo(hashValue: String(format: "%016qx", hash), fileSize: fileSize))
    }
  }

  func request(_ info: FileInfo) -> Promise<[OpenSubSubtitle]> {
    return Promise { fulfill, reject in
      let limit = 100
      var requestInfo = info.dictionary
      requestInfo["sublanguageid"] = self.language
      xmlRpc.call("SearchSubtitles", [token, [requestInfo], ["limit": limit]]) { status in
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
          fulfill(result)
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

  func showSubSelectWindow(subs: [OpenSubSubtitle]) -> Promise<[OpenSubSubtitle]> {
    return Promise { fulfill, reject in
      // return when found 0 or 1 sub
      if subs.count <= 1 {
        fulfill(subs)
        return
      }
      let subSelectWindow = (NSApp.delegate as! AppDelegate).subSelectWindow
      subSelectWindow.whenUserAction = { subs in
        fulfill(subs)
      }
      subSelectWindow.whenUserClosed = {
        reject(OpenSubError.userCanceled)
      }
      DispatchQueue.main.async {
        subSelectWindow.showWindow(self)
        subSelectWindow.arrayController.content = nil
        subSelectWindow.arrayController.add(contentsOf: subs)
      }
    }
  }

  static func savePassword(username: String, passwd: String) -> OSStatus {
    let service = OpenSubSupport.serviceName as NSString
    let accountName = username as NSString
    let pw = passwd as NSString
    let pwData = pw.data(using: String.Encoding.utf8.rawValue)! as NSData

    let status: OSStatus
    // try read password
    let (readResult, _, readItemRef) = findPassword(username: username)
    if readResult == errSecSuccess {
      // else, try modify the password
      status = SecKeychainItemModifyContent(readItemRef!,
                                            nil,
                                            UInt32(pw.length),
                                            pwData.bytes)
    } else {
      // if can't read, try add password
      status = SecKeychainAddGenericPassword(nil,
                                             UInt32(service.length),
                                             service.utf8String,
                                             UInt32(accountName.length),
                                             accountName.utf8String,
                                             UInt32(pw.length),
                                             pwData.bytes,
                                             nil)
    }
    return status
  }

  static func findPassword(username: String) -> (OSStatus, String?, SecKeychainItem?) {
    let service = OpenSubSupport.serviceName as NSString
    let accountName = username as NSString
    var pwLength = UInt32()
    var pwData: UnsafeMutableRawPointer? = nil
    var itemRef: SecKeychainItem? = nil
    let status = SecKeychainFindGenericPassword(nil,
                                                UInt32(service.length),
                                                service.utf8String,
                                                UInt32(accountName.length),
                                                accountName.utf8String,
                                                &pwLength,
                                                &pwData,
                                                &itemRef)
    var password: String? = ""
    if status == errSecSuccess {
      let data = Data(bytes: pwData!, count: Int(pwLength))
      password = String(data: data, encoding: .utf8)
    }
    if pwData != nil {
      SecKeychainItemFreeContent(nil, pwData)
    }
    return (status, password, itemRef)
  }

  private func startHeartbeat() {
    heartBeatTimer = Timer(timeInterval: heartbeatInterval, target: self, selector: #selector(sendHeartbeat), userInfo: nil, repeats: true)
  }

  @objc private func sendHeartbeat() {
    xmlRpc.call("NoOperation", [token]) { result in
      switch result {
      case .ok(let value):
        // 406 No session
        if let pValue = value as? [String: Any], (pValue["status"] as? String ?? "").hasPrefix("406") {
          Utility.log("OpenSub: heartbeat no session")
          self.token = nil
          self.login().catch { err in
            switch err {
            case OpenSubError.loginFailed(let reason):
              Utility.log("OpenSub: (re-login) \(reason)")
            case OpenSubError.xmlRpcError(let error):
              Utility.log("OpenSub: (re-login) \(error.readableDescription)")
            default:
              Utility.log("OpenSub: (re-login) other error")
            }
          }
        } else {
          Utility.log("OpenSub: heartbeat ok")
        }
      default:
        Utility.log("OpenSub: heartbeat failed")
        self.token = nil
      }
    }
  }

  var loggedIn: Bool {
    return token != nil
  }

}
