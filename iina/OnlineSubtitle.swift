//
//  OnlineSubtitle.swift
//  iina
//
//  Created by lhc on 10/1/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation
import PromiseKit

class OnlineSubtitle: NSObject {

  typealias SubCallback = ([OnlineSubtitle]) -> Void

  enum DownloadResult {
    case ok(URL)
    case failed
  }

  typealias DownloadCallback = (DownloadResult) -> Void

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
      // - language
      let userLang = UserDefaults.standard.string(forKey: Preference.Key.subLang) ?? ""
      if userLang.isEmpty {
        Utility.showAlert("sub_lang_not_set")
        callback([])
      } else {
        subSupport.language = userLang
      }
      // - request
      subSupport.login()
      .then {
        subSupport.hash(url)
      }.then { info in
        subSupport.request(info)
      }.then { subs in
        subSupport.showSubSelectWindow(subs: subs)
      }.then { selectedSubs -> Void in
        callback(selectedSubs)
      }.catch { err in
        let osdMessage: OSDMessage
        switch err {
        case OpenSubSupport.OpenSubError.cannotReadFile,
             OpenSubSupport.OpenSubError.fileTooSmall:
          osdMessage = .fileError
        case OpenSubSupport.OpenSubError.loginFailed(let reason):
          Utility.log("OpenSub: \(reason)")
          osdMessage = .cannotLogin
        case OpenSubSupport.OpenSubError.userCanceled:
          osdMessage = .canceled
        case OpenSubSupport.OpenSubError.xmlRpcError(let error):
          Utility.log("OpenSub: \(error.readableDescription)")
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

