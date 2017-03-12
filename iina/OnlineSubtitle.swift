//
//  OnlineSubtitle.swift
//  iina
//
//  Created by lhc on 10/1/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation
import PromiseKit

class OnlineSubtitle {

  typealias SubCallback = ([OnlineSubtitle]) -> Void

  /** URL of downloaded subtitle*/
  typealias DownloadCallback = (URL) -> Void

  enum Source: Int {
    case shooter = 0
    case openSub
  }

  /** Prepend a number before file name to avoid overwritting. */
  var index: Int

  init(index: Int) {
    self.index = index
  }

  static func getSub(forFile url: URL, from userSource: Source? = nil, callback: @escaping SubCallback) {

    var source: Source

    if userSource == nil {
      source = Source(rawValue: UserDefaults.standard.integer(forKey: Preference.Key.onlineSubSource)) ?? .shooter
    } else {
      source = userSource!
    }

    switch source {
    case .shooter:
      // shooter
      let subSupport = ShooterSupport()
      if let info = subSupport.hash(url) {
        subSupport.request(info, callback: callback)
      } else {
        // if cannot get hash, treat as sub not found
        callback([])
      }
    case .openSub:
      // opensubtitles
      let subSupport = OpenSubSupport.shared
      subSupport.login()
      .then {
        subSupport.hash(url)
      }.then { info in
        subSupport.request(info)
      }.then { subs in
        callback(subs)
      }.catch { err in
        let osdMessage: OSDMessage
        switch err {
        case OpenSubSupport.OpenSubError.cannotReadFile,
             OpenSubSupport.OpenSubError.fileTooSmall:
          osdMessage = .fileError
        case OpenSubSupport.OpenSubError.loginFailed(_):
          osdMessage = .cannotLogin
        case OpenSubSupport.OpenSubError.xmlRpcError(_):
          osdMessage = .networkError
        default:
          osdMessage = .networkError
        }
        PlayerCore.shared.sendOSD(osdMessage)
      }
    }
  }

  func download(callback: @escaping DownloadCallback) { }

}

