//
//  PlaybackHistory.swift
//  iina
//
//  Created by lhc on 28/4/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

fileprivate let KeyUrl = "IINAPHUrl"
fileprivate let KeyName = "IINAPHNme"
fileprivate let KeyMpvMd5 = "IINAPHMpvmd5"
fileprivate let KeyPlayed = "IINAPHPlayed"
fileprivate let KeyAddedDate = "IINAPHDate"

class PlaybackHistory: NSObject, NSCoding {

  var url: URL
  var name: String
  var mpvMd5: String

  var played: Bool
  var addedDate: Date

  required init?(coder aDecoder: NSCoder) {
    guard
    let url = (aDecoder.decodeObject(forKey: KeyUrl) as? URL),
    let name = (aDecoder.decodeObject(forKey: KeyName) as? String),
    let md5 = (aDecoder.decodeObject(forKey: KeyMpvMd5) as? String),
    let date = (aDecoder.decodeObject(forKey: KeyAddedDate) as? Date)
    else {
      return nil
    }

    let played = aDecoder.decodeBool(forKey: KeyPlayed)

    self.url = url
    self.name = name
    self.mpvMd5 = md5
    self.played = played
    self.addedDate = date
  }

  init(url: URL, name: String? = nil) {
    self.url = url
    self.name = name ?? url.lastPathComponent
    self.mpvMd5 = url.path.md5  // FIXME: should implement mpv's algorithm for dvd://, etc
    self.played = true
    self.addedDate = Date()
  }

  func encode(with aCoder: NSCoder) {
    aCoder.encode(url, forKey: KeyUrl)
    aCoder.encode(name, forKey: KeyName)
    aCoder.encode(mpvMd5, forKey: KeyMpvMd5)
    aCoder.encode(played, forKey: KeyPlayed)
    aCoder.encode(addedDate, forKey: KeyAddedDate)
  }

}
