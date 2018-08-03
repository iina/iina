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

final class AssrtSubtitle: OnlineSubtitle {

  var id: Int
  var nativeName: String
  var uploadTime: String
  var subType: String

  var title: String?
  var filename: String?
  var size: String?
  var url: URL?

  init(index: Int, id: Int, nativeName: String, uploadTime: String, subType: String) {
    self.id = id
    self.nativeName = nativeName
    self.uploadTime = uploadTime
    self.subType = subType
    super.init(index: index)
  }

  override func download(callback: @escaping DownloadCallback) {
    Just.get("") { response in
      guard response.ok, let data = response.content else {
        callback(.failed)
        return
      }
      
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

  static let shared = AssrtSupport()

  init() {
    let userToken = Preference.string(for: .assrtToken)
    if let token = userToken, !token.isEmpty {
      self.token = token
    } else {
      self.token = "5IzWrb2J099vmA96ECQXwdRSe9xdoBUv"
    }
  }

  func search(_ query: String) -> Promise<[AssrtSubtitle]> {
    return Promise { fulfill, reject in
      Just.post(searchApi, params: ["q": query], headers: header) { result in
        guard let json = result.json as? [String: Any] else {
          reject(AssrtError.networkError)
          return
        }
        guard let status = json["status"] as? Int else {
          reject(AssrtError.wrongResponseFormat)
          return
        }
        if let error = AssrtError(rawValue: status) {
          reject(error)
          return
        }
        // handle result
        guard let subDict = json["sub"] as? [String: Any] else {
          reject(AssrtError.wrongResponseFormat)
          return
        }
        // assrt will return `sub: {}` when no result
        if let _ = subDict["subs"] as? [String: Any] {
          fulfill([])
          return
        }
        guard let subArray = subDict["subs"] as? [[String: Any]] else {
          reject(AssrtError.wrongResponseFormat)
          return
        }
        var subtitles: [AssrtSubtitle] = []
        var index = 0
        for sub in subArray {
          subtitles.append(AssrtSubtitle(index: index,
                                         id: sub["id"] as! Int,
                                         nativeName: sub["native_name"] as! String,
                                         uploadTime: sub["upload_time"] as! String,
                                         subType: sub["subtype"] as! String))
          index += 1
        }
        fulfill(subtitles)
      }
    }
  }

  private var header: [String: String] {
    return ["Authorization": "Bearer \(token)"]
  }
}
