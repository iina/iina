//
//  PlaybackInfo.swift
//  mpvx
//
//  Created by lhc on 21/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Foundation

class PlaybackInfo {
  
  var currentURL: URL?
  
  var videoWidth: Int?
  
  var videoHeight: Int?
  
  var videoPosition: VideoTime?
  
  var videoDuration: VideoTime?
  
  var isPaused: Bool = false
  
  var volume: Int = 50 {
    didSet {
      if volume < 0 { volume = 0 }
      else if volume > 100 { volume = 100 }
    }
  }

  var playSpeed: Double = 0
  
}
