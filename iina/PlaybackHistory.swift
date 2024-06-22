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

/// An entry in the playback history file.
/// - Important: This class conforms to [NSSecureCoding](https://developer.apple.com/documentation/foundation/nssecurecoding).
///     When making changes be certain the requirements for secure coding are not violated by the changes.
class PlaybackHistory: NSObject, NSSecureCoding {

  /// Indicate this class supports secure coding.
  static var supportsSecureCoding: Bool { true }

  var url: URL
  var name: String
  var mpvMd5: String

  var played: Bool
  var addedDate: Date

  var duration: VideoTime
  var mpvProgress: VideoTime?

  required init?(coder aDecoder: NSCoder) {
    guard
      let url = aDecoder.decodeObject(of: NSURL.self, forKey: KeyUrl),
      let name = aDecoder.decodeObject(of: NSString.self, forKey: KeyName),
      let md5 = aDecoder.decodeObject(of: NSString.self, forKey: KeyMpvMd5),
      let date = aDecoder.decodeObject(of: NSDate.self, forKey: KeyAddedDate)
    else {
      return nil
    }

    let played = aDecoder.decodeBool(forKey: KeyPlayed)
    let duration = aDecoder.decodeDouble(forKey: KeyDuration)

    self.url = url as URL
    self.name = name as String
    self.mpvMd5 = md5 as String
    self.played = played
    self.addedDate = date as Date
    self.duration = VideoTime(duration)

    self.mpvProgress = Utility.playbackProgressFromWatchLater(mpvMd5)
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
