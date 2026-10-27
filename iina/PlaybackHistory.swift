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
fileprivate let KeyTitle = "IINAPHTitle"

/// An entry in the playback history file.
/// - Important: This class conforms to [NSSecureCoding](https://developer.apple.com/documentation/foundation/nssecurecoding).
///     When making changes be certain the requirements for secure coding are not violated by the changes.
class PlaybackHistory: NSObject, NSSecureCoding {

  /// Indicate this class supports secure coding.
  static var supportsSecureCoding: Bool { true }

  private static let dateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "MM/dd/yyyy HH:mm:ss"
    return dateFormatter
  }()

  var url: URL
  var name: String
  var mpvMd5: String

  var played: Bool
  var addedDate: Date

  var duration: VideoTime
  var mpvProgress: VideoTime?

  var title: String?

  /// A description of this playback history entry suitable to include in a log message.
  override var description: String {
    var description = """
      added: \(PlaybackHistory.dateFormatter.string(from: addedDate)) \
      duration: \(duration.stringRepresentation)
      """
    if let mpvProgress { description += " progress: \(mpvProgress.stringRepresentation)" }
    description += "\n  \(url)"
    if let title { description += "\n  \(title)" }
    description += "\n  MD5: \(mpvMd5)"
    return description
  }

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
    let title = aDecoder.decodeObject(of: NSString.self, forKey: KeyTitle)

    self.url = url as URL
    self.name = name as String
    self.mpvMd5 = md5 as String
    self.played = played
    self.addedDate = date as Date
    self.duration = VideoTime(duration)
    self.title = title as String?

    self.mpvProgress = Utility.playbackProgressFromWatchLater(mpvMd5)
  }

  init(url: URL, duration: Double, name: String? = nil, title: String?, mpvMd5: String) {
    self.url = url
    self.name = name ?? url.lastPathComponent
    self.mpvMd5 = mpvMd5
    self.played = true
    self.addedDate = Date()
    self.duration = VideoTime(duration)
    self.title = title
  }

  func encode(with aCoder: NSCoder) {
    aCoder.encode(url, forKey: KeyUrl)
    aCoder.encode(name, forKey: KeyName)
    aCoder.encode(mpvMd5, forKey: KeyMpvMd5)
    aCoder.encode(played, forKey: KeyPlayed)
    aCoder.encode(addedDate, forKey: KeyAddedDate)
    aCoder.encode(duration.second, forKey: KeyDuration)
    aCoder.encode(title, forKey: KeyTitle)
  }
}
