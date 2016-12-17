//
//  MPVPlaylistItem.swift
//  iina
//
//  Created by lhc on 23/8/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class MPVPlaylistItem: NSObject {
  
  /** Actually this is the path. Use `filename` to conform mpv API's naming. */
  var filename: String
  
  /** Title or the real filename */
  var filenameForDisplay: String {
    get {
      return title ?? NSString(string: filename).lastPathComponent
    }
  }
  
  var isCurrent: Bool
  var isPlaying: Bool
  
  var title: String?
  
  init(filename: String, isCurrent: Bool, isPlaying: Bool, title: String?) {
    self.filename = filename
    self.isCurrent = isCurrent
    self.isPlaying = isPlaying
    self.title = title
  }
}
