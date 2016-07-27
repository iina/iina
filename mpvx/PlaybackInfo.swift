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

  var playSpeed: Double?
  
}
