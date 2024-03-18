//
//  OnlineSubtitle.swift
//  iina
//
//  Created by lhc on 10/1/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation
import PromiseKit

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
  var loggedIn: Bool { get }
  func fetch(from url: URL, withProviderID id: String, playerCore player: PlayerCore) -> Promise<[Subtitle]>
  func logout(timeout: TimeInterval?) -> Promise<Void>
}

class OnlineSubtitle: NSObject {
  enum CommonError: Error {
    case noResult
    case canceled
    case cannotConnect(Error)
    case networkError(Error?)
    case timedOut(Error)
    case fsError
  }

  static var loggedIn: Bool {
    let id = Preference.string(for: .onlineSubProvider) ?? Providers.openSub.id
    switch id {
    case Providers.openSub.id:
      return Providers.openSub.getFetcher().loggedIn
    case Providers.shooter.id:
      return Providers.shooter.getFetcher().loggedIn
    case Providers.assrt.id:
      return Providers.assrt.getFetcher().loggedIn
    default:
      guard let provider = Providers.fromPlugin[id] else {
        return Providers.openSub.getFetcher().loggedIn
      }
      return provider.getFetcher().loggedIn
    }
  }

  /** Prepend a number before file name to avoid overwriting. */
  var index: Int

  init(index: Int) {
    self.index = index
  }

  /// Check if the given error indicates IINA was unable to connect to the subtitle server.
  /// - Parameter error: the error object to inspect
  /// - Returns: `true` if the error represents a connection failure; otherwise `false`.
  static func isConnectFailure(_ error: Error?) -> Bool {
    guard let nsError = (error as NSError?) else { return false }
    return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCannotConnectToHost
  }

  /// Check if the given error indicates IINA timed out while trying to connect to the subtitle server.
  /// - Parameter error: the error object to inspect
  /// - Returns: `true` if the error represents a timed out failure; otherwise `false`.
  static func isTimedOutFailure(_ error: Error?) -> Bool {
    guard let nsError = (error as NSError?) else { return false }
    return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
  }

  func download() -> Promise<[URL]> { return .value([]) }
  func getDescription() -> (name: String, left: String, right: String) { return("", "", "") }

  class DefaultFetcher {
    var loggedIn: Bool { false }
    func logout(timeout: TimeInterval?) -> Promise<Void> { .value }
    required init() {}
  }

  class Providers {
    static let shooter = Provider<Shooter.Fetcher>(id: ":shooter", name: "shooter.cn")
    static let openSub = Provider<OpenSub.Fetcher>(id: ":opensubtitles", name: "opensubtitles.com")
    static let assrt = Provider<Assrt.Fetcher>(id: ":assrt", name: "assrt.net")

    static var fromPlugin: [String: Provider<JSPluginSub.Fetcher>] = [:]

    static func registerFromPlugin(_ pluginID: String, _ pluginName: String, id: String, name: String) {
      let providerID = "plugin:\(pluginID):\(id)"
      fromPlugin[providerID] = Provider(id: id,
                                        name: name,
                                        providerID: providerID,
                                        origin: .plugin(id: pluginID, name: pluginName))
    }

    static func removeAllFromPlugin(_ pluginID: String) {
      let prefix = "plugin:\(pluginID):"
      for key in fromPlugin.keys.filter({ $0.hasPrefix(prefix) }) {
        fromPlugin.removeValue(forKey: key)
      }
    }

    static func nameForID(_ id: String) -> String {
      switch id {
      case Providers.openSub.id:
        return Providers.openSub.name
      case Providers.shooter.id:
        return Providers.shooter.name
      case Providers.assrt.id:
        return Providers.assrt.name
      default:
        return Providers.fromPlugin[id]?.name ?? Providers.openSub.name
      }
    }
  }

  enum Origin {
    case legacy
    case plugin(id: String, name: String)
  }

  class Provider<F: OnlineSubtitleFetcher>: ProviderProtocol where F: DefaultFetcher {
    let id: String
    let providerID: String
    let name: String
    let origin: Origin

    init(id: String, name: String, providerID: String? = nil, origin: Origin = .legacy) {
      self.id = id
      self.providerID = providerID ?? id
      self.name = name
      self.origin = origin
    }

    func getFetcher() -> F {
      return F()
    }

    func fetchSubtitles(url: URL, player: PlayerCore) -> Promise<[URL]> {
      return getFetcher().fetch(from: url, withProviderID: providerID, playerCore: player)
      .get { [self] subtitles in
        if subtitles.isEmpty {
          throw OnlineSubtitle.CommonError.noResult
        } else {
          player.sendOSD(.downloadingSub(subtitles.count, name))
        }
      }.thenFlatMap { subtitle in
        subtitle.download()
      }
    }
  }

  static func logout(timeout: TimeInterval? = nil) {
    let id = Preference.string(for: .onlineSubProvider) ?? Providers.openSub.id
    switch id {
    case Providers.openSub.id:
      _logout(using: Providers.openSub, timeout: timeout)
    case Providers.shooter.id:
      _logout(using: Providers.shooter, timeout: timeout)
    case Providers.assrt.id:
      _logout(using: Providers.assrt, timeout: timeout)
    default:
      guard let provider = Providers.fromPlugin[id] else {
        _logout(using: Providers.openSub, timeout: timeout)
        return
      }
      _logout(using: provider, timeout: timeout)
    }
  }

  fileprivate static func _logout<P: ProviderProtocol>(using provider: P, timeout: TimeInterval? = nil) {
    provider.getFetcher().logout(timeout: timeout).catch { err in
      let prefix = "Failed to log out of \(provider.name). "
      switch err {
      case CommonError.cannotConnect(let cause):
        log("\(prefix)\(cause.localizedDescription)", level: .error)
      case CommonError.networkError(let cause):
        let error = cause ?? err
        log("\(prefix)\(error.localizedDescription)", level: .error)
      case CommonError.timedOut(let cause):
        log("\(prefix)\(cause.localizedDescription)", level: .error)
      case JSPluginSub.Error.pluginError(let message):
        log("\(prefix)\(message)", level: .error)
      default:
        log("\(prefix)\(err.localizedDescription)", level: .error)
      }
    }.finally {
      NotificationCenter.default.post(Notification(name: .iinaLogoutCompleted, object: self))
    }
  }

  static func search(forFile url: URL, player: PlayerCore, providerID: String? = nil, callback: @escaping ([URL]) -> Void) {
    let id = providerID ?? Preference.string(for: .onlineSubProvider) ?? Providers.openSub.id
    switch id {
    case Providers.openSub.id:
      _search(using: Providers.openSub, forFile: url, player, callback)
    case Providers.shooter.id:
      _search(using: Providers.shooter, forFile: url, player, callback)
    case Providers.assrt.id:
      _search(using: Providers.assrt, forFile: url, player, callback)
    default:
      if let provider = Providers.fromPlugin[id] {
        _search(using: provider, forFile: url, player, callback)
      } else {
        _search(using: Providers.openSub, forFile: url, player, callback)
      }
    }
  }

  fileprivate static func _search<P: ProviderProtocol>(using provider: P, forFile url: URL, _ player: PlayerCore, _ callback: @escaping ([URL]) -> Void) {
    log("Search subtitle from \(provider.name)...")
    player.sendOSD(.startFindingSub(provider.name), autoHide: false)

    provider.fetchSubtitles(url: url, player: player).done {
      callback($0)
    }.ensure {
      player.hideOSD()
    }.catch { err in
      let osdMessage: OSDMessage
      let prefix = "Failed to obtain subtitles for \(url) from \(provider.name). "
      switch err {
      case CommonError.noResult:
        // Not an error.
        log("No subtitles found")
        callback([])
        return
      case CommonError.cannotConnect(let cause):
        osdMessage = .cannotConnect
        log("\(prefix)\(cause.localizedDescription)", level: .error)
      case CommonError.networkError(let cause):
        osdMessage = .networkError
        let error = cause ?? err
        log("\(prefix)\(error.localizedDescription)", level: .error)
      case CommonError.timedOut(let cause):
        osdMessage = .timedOut
        log("\(prefix)\(cause.localizedDescription)", level: .error)
      case Shooter.Error.cannotReadFile(let cause),
           OpenSub.Error.cannotReadFile(let cause):
        osdMessage = .fileError
        log("\(prefix)Cannot get file handle. \(cause)", level: .error)
      case Shooter.Error.fileTooSmall(let minimumFileSize),
           OpenSub.Error.fileTooSmall(let minimumFileSize):
        osdMessage = .fileError
        log("\(prefix)File is too small. Minimum file size supported by the site is \(minimumFileSize)",
            level: .error)
      case OpenSub.Error.emptyFile(let reason):
        osdMessage = .fileError
        log("\(prefix)Invalid file, \(reason)", level: .error)
      case OpenSub.Error.loginFailed(let reason):
        osdMessage = .cannotLogin
        log("\(prefix)Login failed, \(reason)", level: .error)
      case JSPluginSub.Error.pluginError(let message):
        osdMessage = .customWithDetail(message, provider.name)
        log("\(prefix)\(message)", level: .error)
      case CommonError.canceled:
        osdMessage = .canceled
        // Not an error.
        log("User canceled download of subtitles")
      default:
        osdMessage = .networkError
        log("\(prefix)\(err.localizedDescription)", level: .error)
      }
      player.sendOSD(osdMessage)
      player.isSearchingOnlineSubtitle = false
    }
  }

  static func populateMenu(_ menu: NSMenu, action: Selector? = nil, insertSeparator: Bool = true) {
    let defaultProviders = [
      (Providers.openSub.name, Providers.openSub.id),
      (Providers.assrt.name, Providers.assrt.id),
      (Providers.shooter.name, Providers.shooter.id)
    ]
    menu.removeAllItems()
    for (name, id) in defaultProviders {
      menu.addItem(withTitle: name, action: action, tag: nil, obj: id)
    }
    if insertSeparator {
      menu.addItem(.separator())
    }
    for (id, provider) in OnlineSubtitle.Providers.fromPlugin {
      guard case .plugin(_, let pluginName) = provider.origin else { break }
      menu.addItem(withTitle: provider.name + " — " + pluginName, action: action, tag: nil, obj: id)
    }
  }

  private static func log(_ message: String, level: Logger.Level = .debug) {
    Logger.log(message, level: level, subsystem: Logger.Sub.onlinesub)
  }
}

extension Logger {
  struct Sub {
    static let onlinesub = Logger.makeSubsystem("onlinesub")
  }
}
