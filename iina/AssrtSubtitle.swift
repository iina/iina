//
//  AssrtSubtitle.swift
//  iina
//
//  Created by Collider LI on 26/2/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation
import Just
import PromiseKit

fileprivate let subsystem = Logger.Subsystem(rawValue: "assrt")

final class AssrtSubtitle: OnlineSubtitle {

  struct File {
    var url: URL
    var filename: String
  }

  @objc var id: Int
  @objc var nativeName: String
  @objc var uploadTime: String
  @objc var subType: String

  @objc var subLang: String?
  @objc var title: String?
  @objc var filename: String?
  @objc var size: String?
  @objc var url: URL?
  var fileList: [File]?

  init(index: Int, id: Int, nativeName: String, uploadTime: String, subType: String?, subLang: String?) {
    self.id = id
    self.nativeName = nativeName
    if self.nativeName.isEmpty {
      self.nativeName = "[No title]"
    }
    self.uploadTime = uploadTime
    if let subType = subType {
      self.subType = subType
    } else {
      self.subType = "Unknown"
    }
    self.subLang = subLang
    super.init(index: index)
  }

  override func download(callback: @escaping DownloadCallback) {
    if let fileList = fileList {
      // download from file list
      when(fulfilled: fileList.map { file -> Promise<URL> in
        Promise { resolver in
          Just.get(file.url) { response in
            guard response.ok, let data = response.content else {
              resolver.reject(AssrtSupport.AssrtError.networkError)
              return
            }
            let subFilename = "[\(self.index)]\(file.filename)"
            if let url = data.saveToFolder(Utility.tempDirURL, filename: subFilename) {
              resolver.fulfill(url)
            }
          }
        }
      }).map { urls in
        callback(.ok(urls))
      }.catch { err in
        callback(.failed)
      }
    } else if let url = url, let filename = filename {
      // download from url
      Just.get(url) { response in
        guard response.ok, let data = response.content else {
          callback(.failed)
          return
        }
        let subFilename = "[\(self.index)]\(filename)"
        if let url = data.saveToFolder(Utility.tempDirURL, filename: subFilename) {
          callback(.ok([url]))
        }
      }
    } else {
      callback(.failed)
      return
    }
  }

}


class AssrtSupport {

  typealias Subtitle = AssrtSubtitle

  enum AssrtError: Int, Error {
    case noSuchUser = 1
    case queryTooShort = 101
    case missingArg = 20000
    case invalidToken = 20001
    case endPointNotFound = 20400
    case subNotFound = 20900
    case serverError = 30000
    case databaseError = 30001
    case searchEngineError = 30002
    case tempUnavailable = 30300
    case exceedLimit = 30900

    case userCanceled = 80000
    // lower level error
    case wrongResponseFormat = 90000
    case networkError = 90001
  }

  private let searchApi = "https://api.assrt.net/v1/sub/search"
  private let detailApi = "https://api.assrt.net/v1/sub/detail"

  var token: String
  var usesUserToken = false

  private let subChooseViewController = SubChooseViewController(source: .assrt)

  static let shared = AssrtSupport()

  init() {
    let userToken = Preference.string(for: .assrtToken)
    if let token = userToken, token.count == 32 {
      self.token = token
      usesUserToken = true
    } else {
      self.token = "5IzWrb2J099vmA96ECQXwdRSe9xdoBUv"
    }
  }

  func checkToken() -> Bool {
    if usesUserToken {
      return true
    }
    // show alert for unregistered users
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("alert.title_warning", comment: "Warning")
    alert.informativeText = String(format: NSLocalizedString("alert.assrt_register", comment: "alert.assrt_register"))
    alert.alertStyle = .warning
    alert.addButton(withTitle: NSLocalizedString("alert.assrt_register.register", comment: "alert.assrt_register.register"))
    alert.addButton(withTitle: NSLocalizedString("alert.assrt_register.try", comment: "alert.assrt_register.try"))
    let result = alert.runModal()
    if result == .alertFirstButtonReturn {
      // if user chose register
      NSWorkspace.shared.open(URL(string: AppData.assrtRegisterLink)!)
      var newToken = ""
      if Utility.quickPromptPanel("assrt_token_prompt", callback: { newToken = $0 }) {
        if newToken.count == 32 {
          Preference.set(newToken, for: .assrtToken)
          self.token = newToken
          return true
        } else {
          Utility.showAlert("assrt_token_invalid")
        }
      }
      return false
    }
    return true
  }

  func search(_ query: String) -> Promise<[AssrtSubtitle]> {
    return Promise { resolver in
      Just.post(searchApi, params: ["q": query], headers: header) { result in
        guard let json = result.json as? [String: Any] else {
          resolver.reject(AssrtError.networkError)
          return
        }
        guard let status = json["status"] as? Int else {
          resolver.reject(AssrtError.wrongResponseFormat)
          return
        }
        if let error = AssrtError(rawValue: status) {
          resolver.reject(error)
          return
        }
        // handle result
        guard let subDict = json["sub"] as? [String: Any] else {
          resolver.reject(AssrtError.wrongResponseFormat)
          return
        }
        // assrt will return `sub: {}` when no result
        if let _ = subDict["subs"] as? [String: Any] {
          resolver.fulfill([])
          return
        }
        guard let subArray = subDict["subs"] as? [[String: Any]] else {
          resolver.reject(AssrtError.wrongResponseFormat)
          return
        }
        var subtitles: [AssrtSubtitle] = []
        var index = 0
        for sub in subArray {
          var subLang: String? = nil
          if let lang = sub["lang"] as? [String: Any], let desc = lang["desc"] as? String {
            subLang = desc
          }
          subtitles.append(AssrtSubtitle(index: index,
                                         id: sub["id"] as! Int,
                                         nativeName: sub["native_name"] as! String,
                                         uploadTime: sub["upload_time"] as! String,
                                         subType: sub["subtype"] as? String,
                                         subLang: subLang))
          index += 1
        }
        resolver.fulfill(subtitles)
      }
    }
  }

  func showSubSelectWindow(with subs: [AssrtSubtitle]) -> Promise<[AssrtSubtitle]> {
    return Promise { resolver in
      // return when found 0 or 1 sub
      if subs.count <= 1 {
        resolver.fulfill(subs)
        return
      }
      subChooseViewController.subtitles = subs

      subChooseViewController.userDoneAction = { subs in
        resolver.fulfill(subs as! [AssrtSubtitle])
      }
      subChooseViewController.userCanceledAction = {
        resolver.reject(AssrtError.userCanceled)
      }
      PlayerCore.active.sendOSD(.foundSub(subs.count), autoHide: false, accessoryView: subChooseViewController.view)
      subChooseViewController.tableView.reloadData()
    }
  }

  func loadDetails(forSub sub: AssrtSubtitle) -> Promise<AssrtSubtitle> {
    return Promise { resolver in
      Just.post(detailApi, params: ["id": sub.id], headers: header) { result in
        guard let json = result.jsonIgnoringError as? [String: Any] else {
          resolver.reject(AssrtError.networkError)
          return
        }
        guard let status = json["status"] as? Int else {
          resolver.reject(AssrtError.wrongResponseFormat)
          return
        }
        if let error = AssrtError(rawValue: status) {
          resolver.reject(error)
          return
        }
        guard let subDict = json["sub"] as? [String: Any] else {
          resolver.reject(AssrtError.wrongResponseFormat)
          return
        }
        guard let subArray = subDict["subs"] as? [[String: Any]], subArray.count == 1 else {
          resolver.reject(AssrtError.wrongResponseFormat)
          return
        }

        sub.url = URL(string: subArray[0]["url"] as! String)
        sub.filename = subArray[0]["filename"] as? String

        if let fileList = subArray[0]["filelist"] as? [[String: String]] {
          sub.fileList = fileList.map { info in
            AssrtSubtitle.File(url: URL(string: info["url"]!)!,
                               filename: info["f"]!)
          }
        }

        resolver.fulfill(sub)
      }
    }
  }

  private var header: [String: String] {
    return ["Authorization": "Bearer \(token)"]
  }
}
