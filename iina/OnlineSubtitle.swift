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
    case assrt

    var name: String {
      switch self {
      case .shooter:
        return "shooter.cn"
      case .openSub:
        return "opensubtitles.org"
      case .assrt:
        return "assrt.net"
      }
    }
  }

  /** Prepend a number before file name to avoid overwritting. */
  var index: Int

  init(index: Int) {
    self.index = index
  }

  static func getSub(forFile url: URL, from userSource: Source? = nil, playerCore: PlayerCore, callback: @escaping SubCallback) {

    var source: Source

    if userSource == nil {
      source = Source(rawValue: Preference.integer(for: .onlineSubSource)) ?? .openSub
    } else {
      source = userSource!
    }

    playerCore.sendOSD(.startFindingSub(source.name), autoHide: false)

    switch source {
    case .shooter:
      // shooter
      let subSupport = ShooterSupport()
      subSupport.hash(url)
      .then { info in
        subSupport.request(info)
      }.then { subs in
        callback(subs)
      }.catch { error in
        let osdMessage: OSDMessage
        switch error {
        case ShooterSupport.ShooterError.cannotReadFile,
             ShooterSupport.ShooterError.fileTooSmall:
          osdMessage = .fileError
        case ShooterSupport.ShooterError.networkError:
          osdMessage = .networkError
        default:
          osdMessage = .networkError
          playerCore.sendOSD(osdMessage)
        }
      }.always {
        playerCore.hideOSD()
      }
    case .openSub:
      // opensubtitles
      let subSupport = OpenSubSupport.shared
      // - language
      let userLang = Preference.string(for: .subLang) ?? ""
      if userLang.isEmpty {
        Utility.showAlert("sub_lang_not_set")
        subSupport.language = "eng"
      } else {
        subSupport.language = userLang
      }
      // - request
      subSupport.login()
      .then { _ in
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
        playerCore.sendOSD(osdMessage)
      }.always {
        playerCore.hideOSD()
      }
    case .assrt:
      let subSupport = AssrtSupport.shared
      subSupport.search(url.deletingPathExtension().lastPathComponent)
      .then { subs -> Void in
        subSupport.showSubSelectWindow(subs: subs)
      }.always {
        //playerCore.hideOSD()
      }
    }
  }

  func download(callback: @escaping DownloadCallback) { }

}

