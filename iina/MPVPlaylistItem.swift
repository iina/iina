//
//  MPVPlaylistItem.swift
//  iina
//
//  Created by lhc on 23/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class MPVPlaylistItem: NSObject, Identifiable {

  /** Actually this is the path. Use `filename` to conform mpv API's naming. */
  var filename: String

  /** Title or the real filename */
  var filenameForDisplay: String {
    return title ?? (isNetworkResource ? filename : NSString(string: filename).lastPathComponent)
  }

  var isCurrent: Bool
  var isPlaying: Bool
  var isNetworkResource: Bool

  var title: String?
  var playlistPath: String?

  init(filename: String, isCurrent: Bool, isPlaying: Bool, title: String?, playlistPath: String? = nil) {
    self.filename = filename
    self.isCurrent = isCurrent
    self.isPlaying = isPlaying
    self.title = title
    self.playlistPath = playlistPath
    self.isNetworkResource = Regex.url.matches(filename)
  }
}
