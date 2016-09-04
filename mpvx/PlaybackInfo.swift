//
//  PlaybackInfo.swift
//  mpvx
//
//  Created by lhc on 21/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Foundation

class PlaybackInfo {
  
  var fileLoading: Bool = false
  
  var currentURL: URL?
  
  var videoWidth: Int?
  var videoHeight: Int?
  
  var displayWidth: Int?
  var displayHeight: Int?
  
  var rotation: Int = 0
  
  var videoPosition: VideoTime?
  
  var videoDuration: VideoTime?
  
  var isPaused: Bool = false
  
  /** The current applied aspect, used for find current aspect in menu, etc. Maybe not a good approach. */
  var unsureAspect: String = "Default"
  var unsureCrop: String = "None"
  var cropFilter: MPVFilter?
  var flipFilter: MPVFilter?
  var mirrorFilter: MPVFilter?
  
  var volume: Int = 50 {
    didSet {
      if volume < 0 { volume = 0 }
      else if volume > 100 { volume = 100 }
    }
  }

  var playSpeed: Double = 0
  
  var audioTracks: [MPVTrack] = []
  var videoTracks: [MPVTrack] = []
  var subTracks: [MPVTrack] = []
  
  var abLoopStatus: Int = 0 // 0: none, 1: A set, 2: B set (looping) 
  
  /** Selected track IDs. Use these (instead of `isSelected` of a track) to check if selected */
  var aid: Int?
  var sid: Int?
  var vid: Int?
  var secondSid: Int?
  
  var playlist: [MPVPlaylistItem] = []
  var chapters: [MPVChapter] = []
  
}
