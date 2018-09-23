//
//  KankanSubtitle.swift
//  iina
//
//  Created by @tinkernels (don.johnny.cn@gmail.com) on 24/9/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation
import Just
import PromiseKit

fileprivate let subsystem = Logger.Subsystem(rawValue: "kankan")

final class KankanSubtitle: OnlineSubtitle {

  struct File {
    var url: URL
    var filename: String
  }

  @objc var filename: String = ""
  @objc var langID: String
  @objc var rating: String
  @objc var dlCount: String
  @objc var subDlLink: String
  
  init(index: Int, filename: String, langID: String, rating: String, dlCount: String, subDlLink: String) {
    self.filename = filename
    self.langID = langID
    self.rating = rating
    self.dlCount = dlCount
    self.subDlLink = subDlLink
    super.init(index: index)
  }

  override func download(callback: @escaping DownloadCallback) {
    Just.get(subDlLink) { response in
      guard response.ok, let data = response.content else {
        callback(.failed)
        return
      }
      let fileName = "[\(self.index)]\(self.filename)"
      if let url = data.saveToFolder(Utility.tempDirURL, filename: fileName) {
        callback(.ok([url]))
      }
    }
  }
}


class KankansubSupport {

  typealias Subtitle = KankanSubtitle

  enum KankanError: Int, Error {
    case userCanceled = 80000
    
    // lower level error
    case wrongResponseFormat = 90000
    case networkError = 90001
  }

  private var searchApi = "http://subtitle.kankan.xunlei.com:8000/search.json/mname="

  private let subChooseViewController = SubChooseViewController(source: .kankan)

  static let shared = KankansubSupport()
  
  func search(_ query: String ) -> Promise<[KankanSubtitle]> {
    return Promise { resolver in
      Just.get(searchApi + (query.addingPercentEncoding(withAllowedCharacters:
            .urlQueryAllowed) ?? "")) { result in
        guard result.ok else {
          resolver.reject(KankanError.networkError)
          return
        }
        guard let json = result.json as? [String: Any] else {
          resolver.reject(KankanError.networkError)
          return
        }
        // handle result
        guard let sublist = json["sublist"] as? [[String: Any]] else {
          resolver.reject(KankanError.wrongResponseFormat)
          return
        }
        var subtitles: [KankanSubtitle] = []
        var index = 0
        for sub in sublist {
          guard let d_url = sub["surl"] as? String else {
            continue
          }
          subtitles.append(KankanSubtitle(index: index,
                                          // cause of reusing OpenSubCell in SubChooseViewController, mapping values as beblow
                                          filename: (sub["sname"]) as! String + "." + (sub["sext"] as! String),
                                          langID: sub["language"] as! String,
                                          rating: sub["simility"] as! String,
                                          dlCount: "-",
                                          subDlLink: d_url
                                          ))
          index += 1
        }
        resolver.fulfill(subtitles)
      }
    }
  }

  func showSubSelectWindow(with subs: [KankanSubtitle]) -> Promise<[KankanSubtitle]> {
    return Promise { resolver in
      // return when found 0 or 1 sub
      if subs.count <= 1 {
        resolver.fulfill(subs)
        return
      }
      subChooseViewController.subtitles = subs

      subChooseViewController.userDoneAction = { subs in
        resolver.fulfill(subs as! [KankanSubtitle])
      }
      subChooseViewController.userCanceledAction = {
        resolver.reject(KankanError.userCanceled)
      }
      PlayerCore.active.sendOSD(.foundSub(subs.count), autoHide: false, accessoryView: subChooseViewController.view)
      subChooseViewController.tableView.reloadData()
    }
  }
}
