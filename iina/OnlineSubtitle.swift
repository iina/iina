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
    case ok([URL])
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

  static func getSubtitle(forFile url: URL, from userSource: Source? = nil, playerCore: PlayerCore, callback: @escaping SubCallback) {

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
      }.done { subs in
        callback(subs)
      }.ensure {
        playerCore.hideOSD()
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
          playerCore.isSearchingOnlineSubtitle = false
        }
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
        subSupport.request(info.dictionary)
      }.recover { error -> Promise<[OpenSubSubtitle]> in
        if case OpenSubSupport.OpenSubError.noResult = error {
          return subSupport.requestByName(url)
        } else {
          throw error
        }
      }.then { subs in
        subSupport.showSubSelectWindow(with: subs)
      }.done { selectedSubs in
        callback(selectedSubs)
      }.catch { err in
        let osdMessage: OSDMessage
        switch err {
        case OpenSubSupport.OpenSubError.cannotReadFile,
             OpenSubSupport.OpenSubError.fileTooSmall:
          osdMessage = .fileError
        case OpenSubSupport.OpenSubError.loginFailed(let reason):
          Utility.log("OpenSubtitles: \(reason)")
          osdMessage = .cannotLogin
        case OpenSubSupport.OpenSubError.userCanceled:
          osdMessage = .canceled
        case OpenSubSupport.OpenSubError.xmlRpcError(let error):
          Utility.log("OpenSubtitles: \(error.readableDescription)")
          osdMessage = .networkError
        case OpenSubSupport.OpenSubError.noResult:
          callback([])
          return
        default:
          osdMessage = .networkError
        }
        playerCore.sendOSD(osdMessage)
        playerCore.isSearchingOnlineSubtitle = false
      }
    case .assrt:
      let subSupport = AssrtSupport.shared
      firstly { () -> Promise<[AssrtSubtitle]> in
        if !subSupport.checkToken() {
          throw AssrtSupport.AssrtError.userCanceled
        }
        return subSupport.search(url.deletingPathExtension().lastPathComponent)
      }.then { subs in
        subSupport.showSubSelectWindow(with: subs)
      }.then { selectedSubs -> Promise<[AssrtSubtitle]> in
        return when(fulfilled: selectedSubs.map({ subSupport.loadDetails(forSub: $0) }))
      }.done { loadedSubs in
        callback(loadedSubs as [OnlineSubtitle])
      }.ensure {
        playerCore.hideOSD()
      }.catch { err in
        let osdMessage: OSDMessage
        switch err {
        case AssrtSupport.AssrtError.userCanceled:
          osdMessage = .canceled
        default:
          Utility.log("Assrt: \(err.localizedDescription)")
          osdMessage = .networkError
        }
        playerCore.sendOSD(osdMessage)
        playerCore.isSearchingOnlineSubtitle = false
      }
    }
  }

  func download(callback: @escaping DownloadCallback) { }

}

