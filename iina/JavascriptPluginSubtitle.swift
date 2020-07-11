//
//  JavascriptPluginSubtitle.swift
//  iina
//
//  Created by Collider LI on 3/6/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore
import PromiseKit

class JSPluginSub {
  class Subtitle: OnlineSubtitle {
    var item: JavascriptPluginSubtitleItem

    init(index: Int, item: JavascriptPluginSubtitleItem) {
      self.item = item
      super.init(index: index)
    }

    override func getDescription() -> (name: String, left: String, right: String) {
      let data = item.data;
      return (
        data.objectForKeyedSubscript("$name")?.toString() ?? "",
        data.objectForKeyedSubscript("$left")?.toString() ?? "",
        data.objectForKeyedSubscript("$right")?.toString() ?? ""
      )
    }
  }

  enum Error: Swift.Error {
    case pluginError(String)
  }

  class Fetcher: OnlineSubtitle.DefaultFetcher, OnlineSubtitleFetcher {
    typealias Subtitle = JSPluginSub.Subtitle

    private let subChooseViewController = SubChooseViewController()

    func fetch(from url: URL, withProviderID id: String, playerCore player: PlayerCore) -> Promise<[Subtitle]> {
      guard let provider = OnlineSubtitle.Providers.fromPlugin[id] else {
        Logger.log("Cannot find subtitle provider \"\(id)\"", level: .error)
        return .value([])
      }
      guard case .plugin(let pluginID, _) = provider.origin,
        let plugin = player.plugins.first(where: { $0.plugin.identifier == pluginID }) else {
        Logger.log("Cannot find a plugin with id \"\(id)\"", level: .error)
        return .value([])
      }
      let api = plugin.apis["subtitle"] as! JavascriptAPISubtitle
      return search(api: api, id: provider.id).then { subs in
        self.showSubSelectWindow(with: subs)
      }
    }

    func search(api: JavascriptAPISubtitle, id: String) -> Promise<[Subtitle]> {
      return Promise { resolver in
        let completed: @convention(block) ([JavascriptPluginSubtitleItem]) -> Void = { subs in
          resolver.fulfill(subs.enumerated().map{ (i, v) in Subtitle(index: i, item: v) })
        }
        let failed: @convention(block) (String) -> Void = {
          resolver.reject(Error.pluginError($0))
        }
        api.invokeProvider(id: id, completed: completed, failed: failed)
      }
    }

    func showSubSelectWindow(with subs: [Subtitle]) -> Promise<[Subtitle]> {
      return Promise { resolver in
        // return when found 0 or 1 sub
        if subs.count <= 1 {
          resolver.fulfill(subs)
          return
        }
        subChooseViewController.subtitles = subs
        // prevent self being deallocated for unknown reason
        subChooseViewController.context = self

        subChooseViewController.userDoneAction = { subs in
          resolver.fulfill(subs as! [Subtitle])
        }
        subChooseViewController.userCanceledAction = {
          resolver.reject(OnlineSubtitle.CommonError.canceled)
        }
        PlayerCore.active.sendOSD(.foundSub(subs.count), autoHide: false, accessoryView: subChooseViewController.view)
        subChooseViewController.tableView.reloadData()
      }
    }
  }
}
