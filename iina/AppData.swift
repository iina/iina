//
//  Data.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
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

  static let aspectsInPanel: [String] = ["Default", "4:3", "16:9", "16:10", "5:4"]
  static let cropsInPanel: [String] = ["None", "4:3", "16:9", "16:10", "5:4"]

  static let rotations: [Int] = [0, 90, 180, 270]

  /** Seek amount */
  static let seekAmountMap = [0, 0.05, 0.1, 0.25, 0.5]
  static let seekAmountMapMouse = [0, 0.5, 1, 2, 4]
  static let volumeMap = [0, 0.25, 0.5, 0.75, 1]

  static let encodings = CharEncoding.list

  static let userInputConfFolder = "input_conf"
  static let logFolder = "log"
  static let watchLaterFolder = "watch_later"
  static let historyFile = "history.plist"
  static let thumbnailCacheFolder = "thumb_cache"

  static let githubLink = "https://github.com/lhc70000/iina"
  static let wikiLink = "https://github.com/lhc70000/iina/wiki"
  static let websiteLink = "https://lhc70000.github.io/iina/"
  static let emailLink = "lhc199652@gmail.com"

  static let widthWhenNoVideo = 640
  static let heightWhenNoVideo = 360
}


struct Constants {
  struct String {
    static let degree = "°"
    static let dot = "●"
    static let play = "▶︎"
    static let videoTimePlaceholder = "--:--:--"
    static let trackNone = NSLocalizedString("track.none", comment: "<None>")
    static let chapter = "Chapter"
    static let fullScreen = NSLocalizedString("menu.fullscreen", comment: "Fullscreen")
    static let exitFullScreen = NSLocalizedString("menu.exit_fullscreen", comment: "Exit Fullscreen")
    static let pause = NSLocalizedString("menu.pause", comment: "Pause")
    static let resume = NSLocalizedString("menu.resume", comment: "Resume")
    static let `default` = NSLocalizedString("quicksetting.item_default", comment: "Default")
    static let none = NSLocalizedString("quicksetting.item_none", comment: "None")
    static let audioDelay = "Audio Delay"
    static let subDelay = "Subtitle Delay"
    static let pip = NSLocalizedString("menu.pip", comment: "Enter Picture-in-Picture")
    static let exitPIP = NSLocalizedString("menu.exit_pip", comment: "Exit Picture-in-Picture")
  }
  struct Noti {
    static let mainWindowChanged = Notification.Name("IINAMainWindowChanged")
    static let playlistChanged = Notification.Name("IINAPlaylistChanged")
    static let tracklistChanged = Notification.Name("IINATracklistChanged")
    static let vfChanged = Notification.Name("IINAVfChanged")
    static let afChanged = Notification.Name("IINAAfChanged")
    static let fsChanged = Notification.Name("IINAFullscreenChanged")
    static let ontopChanged = Notification.Name("IINAOnTopChanged")
    static let keyBindingInputChanged = Notification.Name("IINAkeyBindingInputChanged")
    static let windowScaleChanged = Notification.Name("IINAWindowScaleChanged")
    static let fileLoaded = Notification.Name("IINAFileLoaded")
    static let historyUpdated = Notification.Name("IINAHistoryUpdated")
    static let legacyFullScreen = Notification.Name("IINALegacyFullScreen")
  }
  struct Time {
    static let infinite = VideoTime(999, 0, 0)
  }
  struct FilterName {
    static let crop = "iina_crop"
    static let flip = "iina_flip"
    static let mirror = "iina_mirror"
    static let audioEq = "iina_aeq"
    static let delogo = "iina_delogo"
  }
}
