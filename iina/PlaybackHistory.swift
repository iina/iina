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
fileprivate let KeyDuration = "IINAPHDuration"

class PlaybackHistory: NSObject, NSCoding {

  var url: URL
  var name: String
  var mpvMd5: String

  var played: Bool
  var addedDate: Date

  var duration: VideoTime
  var mpvProgress: VideoTime?

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
    let duration = aDecoder.decodeDouble(forKey: KeyDuration)

    self.url = url
    self.name = name
    self.mpvMd5 = md5
    self.played = played
    self.addedDate = date
    self.duration = VideoTime(duration)

    // try read mpv watch_later file

    let fileURL = Utility.watchLaterURL.appendingPathComponent(mpvMd5)
    if let reader = StreamReader(path: fileURL.path) {
      if let firstLine = reader.nextLine(),
        firstLine.hasPrefix("start="),
        let progressString = firstLine.components(separatedBy: "=").last,
        let progress = Double(progressString) {
        self.mpvProgress = VideoTime(progress)
      }
    }
  }

  init(url: URL, duration: Double, name: String? = nil) {
    self.url = url
    self.name = name ?? url.lastPathComponent
    self.mpvMd5 = Utility.mpvWatchLaterMd5(url.path)
    self.played = true
    self.addedDate = Date()
    self.duration = VideoTime(duration)
  }

  func encode(with aCoder: NSCoder) {
    aCoder.encode(url, forKey: KeyUrl)
    aCoder.encode(name, forKey: KeyName)
    aCoder.encode(mpvMd5, forKey: KeyMpvMd5)
    aCoder.encode(played, forKey: KeyPlayed)
    aCoder.encode(addedDate, forKey: KeyAddedDate)
    aCoder.encode(duration.second, forKey: KeyDuration)
  }

}
