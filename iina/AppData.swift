//
//  Data.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

struct AppData {

  /** time interval to sync play pos */
  static let getTimeInterval: Double = 0.1

  /** speed values when clicking left / right arrow button */

//  static let availableSpeedValues: [Double] = [-32, -16, -8, -4, -2, -1, 1, 2, 4, 8, 16, 32]
  // Stopgap for https://github.com/mpv-player/mpv/issues/4000
  static let availableSpeedValues: [Double] = [0.03125, 0.0625, 0.125, 0.25, 0.5, 1, 2, 4, 8, 16, 32]
  
  /** min/max speed for playback **/
  static let minSpeed = 0.25
  static let maxSpeed = 16.0
  
  /** generate aspect and crop options in menu */
  static let aspects: [String] = ["4:3", "5:4", "16:9", "16:10", "1:1", "3:2", "2.21:1", "2.35:1", "2.39:1"]

  static let rotations: [Int] = [0, 90, 180, 270]

  /** Seek amount */
  static let seekAmountMap: [Int: Double] = [
    1: 0.001,
    2: 0.01,
    3: 0.1,
    4: 0.5
  ]

  static let encodings = CharEncoding.list

  static let userInputConfFolder = "input_conf"
  static let logFolder = "log"
  static let watchLaterFolder = "watch_later"

  static let githubLink = "https://github.com/lhc70000/iina"
  static let githubReleaseLink = "https://github.com/lhc70000/iina/releases"
  static let websiteLink = "https://lhc70000.github.io/iina/"
  static let emailLink = "lhc199652@gmail.com"

  static let widthWhenNoVideo = 640
  static let heightWhenNoVideo = 360
}


struct Constants {
  struct Identifier {
    static let isChosen = "IsChosen"
    static let trackName = "TrackName"
    static let isPlayingCell = "IsPlayingCell"
    static let trackNameCell = "TrackNameCell"
    static let key = "Key"
    static let value = "Value"
    static let action = "Action"
  }
  struct String {
    static let degree = "°"
    static let dot = "●"
    static let play = "▶︎"
    static let none = NSLocalizedString("track.none", comment: "<None>")
    static let chapter = "Chapter"
    static let fullScreen = NSLocalizedString("menu.fullscreen", comment: "Fullscreen")
    static let exitFullScreen = NSLocalizedString("menu.exit_fullscreen", comment: "Exit Fullscreen")
  }
  struct Noti {
    static let playlistChanged = Notification.Name("IINAPlaylistChanged")
    static let tracklistChanged = Notification.Name("IINATracklistChanged")
    static let vfChanged = Notification.Name("IINAVfChanged")
    static let afChanged = Notification.Name("IINAAfChanged")
    static let fsChanged = Notification.Name("IINAFullscreenChanged")
  }
  struct Time {
    static let infinite = VideoTime(999, 0, 0)
  }
}
