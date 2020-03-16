//
//  JavascriptPluginSubtitle.swift
//  iina
//
//  Created by Collider LI on 3/6/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Foundation
import PromiseKit

class JSPluginSub {
  class Subtitle: OnlineSubtitle {

  }

  class Fetcher: OnlineSubtitle.DefaultFetcher, OnlineSubtitleFetcher {
    typealias Subtitle = JSPluginSub.Subtitle

    func fetch(from url: URL) -> Promise<[Subtitle]> {
//        if case .plugin(let id) = provider.origin,
//          let plugin = player.plugins.first(where: { $0.plugin.identifier == id }) {
//          let subAPI = plugin.apis["subtitle"] as! JavascriptAPISubtitle
//          subAPI.invokeProvider(id: provider.id) {
//
//          }
//        }
      .value([])
    }
  }
}
