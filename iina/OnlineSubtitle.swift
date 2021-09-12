//
//  OnlineSubtitle.swift
//  iina
//
//  Created by lhc on 10/1/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation
import PromiseKit

fileprivate let subsystem = Logger.Subsystem(rawValue: "onlinesub")

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

  /// Check if the given error indicates IINA was unable to connect to the subtitle server.
  /// - Parameter error: the error object to inspect
  /// - Returns: `true` if the error represents a connection failure; otherwise `false`.
  private static func isConnectFailure(_ error: Error?) -> Bool {
    guard let nsError = (error as NSError?) else {return false }
    return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCannotConnectToHost
  }

  static func getSubtitle(forFile url: URL, from userSource: Source? = nil, playerCore: PlayerCore, callback: @escaping SubCallback) {

    var source: Source

    if userSource == nil {
      source = Source(rawValue: Preference.integer(for: .onlineSubSource)) ?? .openSub
    } else {
      source = userSource!
    }

    Logger.log("Search subtitle from \(source.name)...", subsystem: subsystem)

    playerCore.sendOSD(.startFindingSub(source.name), autoHide: false)

    switch source {
    case .shooter:
      // shooter
      let subSupport = ShooterSupport()
      subSupport.hash(url)
      .then { info -> Promise<[ShooterSubtitle]> in
        Logger.log("Searching for subtitles of movie with hash \(info.hashValue)", subsystem: subsystem)
        return subSupport.request(info)
      }.done { subs in
        callback(subs)
      }.ensure {
        playerCore.hideOSD()
      }.catch { error in
        // Log the failure.
        let prefix = "Failed to obtain subtitles for \(url) from \(source.name). "
        switch error {
        case ShooterSupport.ShooterError.cannotReadFile(let cause):
          Logger.log("\(prefix)Cannot get file handle. \(cause)", level: .error, subsystem: subsystem)
        case ShooterSupport.ShooterError.networkError(let cause):
          if isConnectFailure(cause) {
            Logger.log("\(prefix)Could not connect to the server.", level: .error, subsystem: subsystem)
          } else {
            Logger.log("\(prefix)\(error) \(String(describing: cause))", level: .error, subsystem: subsystem)
          }
        case ShooterSupport.ShooterError.noResult:
          // Not an error.
          Logger.log("No subtitles found", subsystem: subsystem)
        default:
          Logger.log("\(prefix)\(error)", level: .error, subsystem: subsystem)
        }
        let osdMessage: OSDMessage
        switch error {
        case ShooterSupport.ShooterError.cannotReadFile,
             ShooterSupport.ShooterError.fileTooSmall:
          osdMessage = .fileError
        case ShooterSupport.ShooterError.networkError:
          osdMessage = .networkError
        case ShooterSupport.ShooterError.noResult:
          callback([])
          return
        default:
          osdMessage = .networkError
        }
        playerCore.sendOSD(osdMessage)
        playerCore.isSearchingOnlineSubtitle = false
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
        subSupport.hash(url, playerCore)
      }.then { info -> Promise<[OpenSubSubtitle]> in
        Logger.log("Searching for subtitles of movie with hash \(info.hashValue)", subsystem: subsystem)
        return subSupport.request(info.dictionary)
      }.recover { error -> Promise<[OpenSubSubtitle]> in
        if case OpenSubSupport.OpenSubError.noResult = error {
          return subSupport.requestByName(url, playerCore)
        } else {
          throw error
        }
      }.then { subs in
        subSupport.showSubSelectWindow(with: subs)
      }.done { selectedSubs in
        callback(selectedSubs)
      }.catch { err in
        // Log the failure.
        let prefix = "Failed to obtain subtitles for \(url) from \(source.name). "
        switch err {
        case OpenSubSupport.OpenSubError.cannotReadFile(let cause):
          Logger.log("\(prefix)Cannot get file handle. \(cause)", level: .error, subsystem: subsystem)
        case OpenSubSupport.OpenSubError.loginFailed(let status):
          Logger.log("\(prefix)\(err) Status: \(status)", level: .error, subsystem: subsystem)
        case OpenSubSupport.OpenSubError.noResult:
          // Not an error.
          Logger.log("No subtitles found", subsystem: subsystem)
        case OpenSubSupport.OpenSubError.userCanceled:
          // Not an error.
          Logger.log("User canceled download of subtitles", subsystem: subsystem)
        case OpenSubSupport.OpenSubError.xmlRpcError(let rpcError):
          if let cause = rpcError.underlyingError {
            if isConnectFailure(cause) {
              Logger.log("\(prefix)Could not connect to the server.", level: .error, subsystem: subsystem)
            } else {
              Logger.log("\(prefix)\(err) \(cause)", level: .error, subsystem: subsystem)
            }
          } else {
            Logger.log("\(prefix)\(err)", level: .error, subsystem: subsystem)
          }
        default:
          Logger.log("\(prefix)\(err)", level: .error, subsystem: subsystem)
        }
        let osdMessage: OSDMessage
        switch err {
        case OpenSubSupport.OpenSubError.cannotReadFile,
             OpenSubSupport.OpenSubError.fileTooSmall:
          osdMessage = .fileError
        case OpenSubSupport.OpenSubError.loginFailed:
          osdMessage = .cannotLogin
        case OpenSubSupport.OpenSubError.userCanceled:
          osdMessage = .canceled
        case OpenSubSupport.OpenSubError.xmlRpcError:
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
        // Log the failure.
        let prefix = "Failed to obtain subtitles for \(url) from \(source.name). "
        let osdMessage: OSDMessage
        switch err {
        case AssrtSupport.AssrtError.userCanceled:
          // Not an error.
          Logger.log("User canceled download of subtitles", subsystem: subsystem)
          osdMessage = .canceled
        default:
          Logger.log("\(prefix)\(err)", level: .error, subsystem: subsystem)
          osdMessage = .networkError
        }
        playerCore.sendOSD(osdMessage)
        playerCore.isSearchingOnlineSubtitle = false
      }
    }
  }

  func download(callback: @escaping DownloadCallback) { }

}

