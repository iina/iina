//
//  OnlineSubtitle.swift
//  iina
//
//  Created by lhc on 10/1/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

class OnlineSubtitle {

  typealias SubCallback = ([OnlineSubtitle]) -> Void

  /** URL to downloaded subtitle*/
  typealias DownloadCallback = (URL) -> Void

  enum Source: Int {
    case shooter = 0
    // case openSub
  }

  /** Prepend a number before file name to avoid overwritting. */
  var index: Int

  init(index: Int) {
    self.index = index
  }

  static func getSub(forFile url: URL, from userSource: Source? = nil, callback: @escaping SubCallback) {

    var source: Source

    if userSource == nil {
      source = Source(rawValue: UserDefaults.standard.integer(forKey: ""))!
    } else {
      source = userSource!
    }

    switch source {
    case .shooter:
      if let info = ShooterSubtitle.hash(url) {
        ShooterSubtitle.request(info, callback: callback)
      } else {
        Utility.showAlert(message: "Cannot get file hash.")
      }
    }

  }

  func download(callback: @escaping DownloadCallback) { }

}

protocol OnlineSubtitleSupport {

  associatedtype RequestData

  static func request(_ info: RequestData, callback: @escaping OnlineSubtitle.SubCallback)
  static func hash(_ url: URL) -> RequestData?

}
