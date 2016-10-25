//
//  Data.swift
//  mpvx
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Foundation

struct AppData {
  
  /** time interval to sync play pos */
  static let getTimeInterval: Double = 0.5
  
  /** speed values when clicking left / right arrow button */
  static let availableSpeedValues: [Double] = [-32, -16, -8, -4, -2, 0, 2, 4, 8, 16, 32]
  
  /** generate aspect and crop options in menu */
  static let aspects: [String] = ["4:3", "5:4", "16:9", "16:10", "1:1", "3:2", "2.21:1", "2.35:1", "2.39:1"]
  
  static let aspectRegex = Utility.Regex("\\A\\d+(\\.\\d+)?:\\d+(\\.\\d+)?\\Z")
  
  static let rotations: [Int] = [0, 90, 180, 270]
  
  static let encodings = CharEncoding.list
}


struct Constants {
  struct Identifier {
    static let isChosen = "IsChosen"
    static let trackName = "TrackName"
    static let isPlayingCell = "IsPlayingCell"
    static let trackNameCell = "TrackNameCell"
  }
  struct String {
    static let degree = "°"
    static let dot = "●"
    static let play = "▶︎"
    static let none = "<None>"
    static let chapter = "Chapter"
    static let volume = "Volume"
    static let audioDelay = "Audio Delay"
    static let subDelay = "Subtitle Delay"
    static let fullScreen = "Full Screen"
    static let exitFullScreen = "Exit Full Screen"
  }
  struct Time {
    static let infinite = VideoTime(999, 0, 0)
  }
}
