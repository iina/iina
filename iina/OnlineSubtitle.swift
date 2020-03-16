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

fileprivate protocol ProviderProtocol {
  associatedtype F: OnlineSubtitleFetcher
  var id: String { get }
  var name: String { get }
  var origin: OnlineSubtitle.Origin { get }
  func getFetcher() -> F
  func fetchSubtitles(url: URL, player: PlayerCore) -> Promise<[URL]>
}

protocol OnlineSubtitleFetcher {
  associatedtype Subtitle: OnlineSubtitle
  func fetch(from url: URL) -> Promise<[Subtitle]>
}

class OnlineSubtitle: NSObject {
  enum CommonError: Error {
    case noResult
    case canceled
    case networkError
    case fsError
  }

  /** Prepend a number before file name to avoid overwriting. */
  var index: Int

  init(index: Int) {
    self.index = index
  }

  func download() -> Promise<[URL]> { return .value([]) }

  class DefaultFetcher {
    required init() {}
  }

  class Providers {
    static let shooter = Provider<Shooter.Fetcher>(id: ":shooter", name: "shooter.cn")
    static let openSub = Provider<OpenSub.Fetcher>(id: ":opensubtitles", name: "opensubtitles.org")
    static let assrt = Provider<Assrt.Fetcher>(id: ":assrt", name: "assrt.net")

    static var fromPlugin: [String: Provider<JSPluginSub.Fetcher>] = [:]
    static func registerFromPlugin(_ pluginID: String, id: String, name: String) {
      fromPlugin["plugin:\(pluginID):\(id)"] = Provider(id: id, name: name, origin: .plugin(id: pluginID))
    }
  }

  enum Origin {
    case legacy
    case plugin(id: String)
  }

  class Provider<F: OnlineSubtitleFetcher>: ProviderProtocol where F: DefaultFetcher {
    let id: String
    let name: String
    let origin: Origin

    init(id: String, name: String, origin: Origin = .legacy) {
      self.id = id
      self.name = name
      self.origin = origin
    }

    func getFetcher() -> F {
      return F()
    }

    func fetchSubtitles(url: URL, player: PlayerCore) -> Promise<[URL]> {
      return getFetcher().fetch(from: url)
      .get { subtitles in
        if subtitles.isEmpty {
          throw OnlineSubtitle.CommonError.noResult
        } else {
          player.sendOSD(.foundSub(subtitles.count))
        }
      }.thenFlatMap { subtitle in
        subtitle.download()
      }
    }
  }

  static func search(forFile url: URL, player: PlayerCore, callback: @escaping ([URL]) -> Void) {
    let val = Preference.string(for: .onlineSubProvider) ?? ""
    switch val {
    case Providers.openSub.id:
      _search(using: Providers.openSub, forFile: url, player, callback)
    case Providers.shooter.id:
      _search(using: Providers.shooter, forFile: url, player, callback)
    case Providers.assrt.id:
      _search(using: Providers.assrt, forFile: url, player, callback)
    default:
      if let provider = Providers.fromPlugin[val] {
        _search(using: provider, forFile: url, player, callback)
      }
      break
    }
  }

  fileprivate static func _search<P: ProviderProtocol>(using provider: P, forFile url: URL, _ player: PlayerCore, _ callback: @escaping ([URL]) -> Void) {
    Logger.log("Search subtitle from \(provider.name)...", subsystem: subsystem)
    player.sendOSD(.startFindingSub(provider.name), autoHide: false)

    provider.fetchSubtitles(url: url, player: player).done {
      callback($0)
    }.ensure {
      player.hideOSD()
    }.catch { err in
      let osdMessage: OSDMessage
      switch err {
      case CommonError.noResult:
        callback([])
        return
      case CommonError.networkError,
           OpenSub.Error.xmlRpcError:
        osdMessage = .networkError
      case Shooter.Error.cannotReadFile,
           Shooter.Error.fileTooSmall,
           OpenSub.Error.cannotReadFile,
           OpenSub.Error.fileTooSmall:
        osdMessage = .fileError
      case OpenSub.Error.loginFailed:
        osdMessage = .cannotLogin
      case CommonError.canceled:
        osdMessage = .canceled
      default:
        Logger.log(err.localizedDescription, level: .error, subsystem: subsystem)
        osdMessage = .networkError
      }
      player.sendOSD(osdMessage)
      player.isSearchingOnlineSubtitle = false
    }
  }
}
