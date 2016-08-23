//
//  MPVPlaylistItem.swift
//  mpvx
//
//  Created by lhc on 23/8/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class MPVPlaylistItem: NSObject {
  
  var filename: String
  
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
