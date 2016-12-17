//
//  Preference.swift
//  mpvx
//
//  Created by lhc on 17/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

struct Preference {
  
  struct Key {
    /** Window position. (float) */
    // static let windowPosition = "windowPosition"
    
    /** Horizontal positon of control bar. (float, 0 - 1) */
    static let controlBarPositionHorizontal = "controlBarPositionHorizontal"
    
    /** Horizontal positon of control bar. In percentage from bottom. (float, 0 - 1) */
    static let controlBarPositionVertical = "controlBarPositionVertical"
    
    /** Whether control bar stick to center when dragging. (bool) */
    static let controlBarStickToCenter = "controlBarStickToCenter"
    
    /** Timeout for auto hiding control bar (float) */
    static let controlBarAutoHideTimeout  = "controlBarAutoHideTimeout"
    
    /** Material for OSC and title bar (Theme(int)) */
    static let themeMaterial = "themeMaterial"
    
    /** OSD auto hide timeout (float) */
    static let osdAutoHideTimeout = "osdAutoHideTimeout"
    
    /** OSD text size (float) */
    static let osdTextSize = "osdTextSize"
    
    /** Soft volume (int, 0 - 100)*/
    static let softVolume = "softVolume"
    
    static let arrowButtonAction = "arrowBtnAction"
    
    /** Pause st first (pause) (bool) */
    static let pauseWhenOpen = "pauseWhenOpen"
    
    /** Enter fill screen when open (bool) */
    static let fullScreenWhenOpen = "fullScreenWhenOpen"
    
    /** Quit when no open window (bool) */
    static let quitWhenNoOpenedWindow = "quitWhenNoOpenedWindow"
    
    /** Resume from last position */
    
    /** Show chapter pos in progress bar (bool) */
    static let showChapterPos = "showChapterPos"
    
    /** Whether catch media keys event (bool) */
    static let useMediaKeys = "useMediaKeys"
    
    /** User created input config list (dic) */
    static let inputConfigs = "inputConfigs"
    
    /** Current input config name */
    static let currentInputConfigName = "currentInputConfigName"
    
    // Advanced
    
    /** Enable advanced settings */
    static let enableAdvancedSettings = "enableAdvancedSettings"
    
    /** Use mpv's OSD (bool) */
    static let useMpvOsd = "useMpvOsd"
    
    /** Log to log folder (bool) */
    static let enableLogging = "enableLogging"
    
    /** User defined options ([string, string]) */
    static let userOptions = "userOptions"
    
    /** User defined conf directory */
    static let useUserDefinedConfDir = "useUserDefinedConfDir"
    static let userDefinedConfDir = "userDefinedConfDir"
    
    static let useExactSeek = "useExactSeek"
    
    static let screenshotFolder = "screenShotFolder"
    static let screenshotIncludeSubtitle = "screenShotIncludeSubtitle"
    static let screenshotFormat = "screenShotFormat"
    static let screenshotTemplate = "screenShotTemplate"
    
  }
  
  enum ArrowButtonAction: Int {
    case speed = 0
    case playlist = 1
    case seek = 2
  }
  
  enum Theme: Int {
    case dark = 0
    case ultraDark
    case light
    case mediumLight
  }
  
  static let defaultPreference:[String : Any] = [
    Key.controlBarPositionHorizontal: Float(0.5),
    Key.controlBarPositionVertical: Float(0.1),
    Key.controlBarStickToCenter: true,
    Key.controlBarAutoHideTimeout: Float(5),
    Key.themeMaterial: Theme.dark.rawValue,
    Key.osdAutoHideTimeout: 1,
    Key.osdTextSize: Float(20),
    Key.softVolume: 50,
    Key.arrowButtonAction: ArrowButtonAction.speed.rawValue,
    Key.pauseWhenOpen: false,
    Key.fullScreenWhenOpen: false,
    Key.showChapterPos: false,
    Key.useMediaKeys: true,
    
    Key.inputConfigs: [],
    Key.currentInputConfigName: "Default",
    
    Key.enableAdvancedSettings: false,
    Key.useMpvOsd: false,
    Key.enableLogging: false,
    Key.userOptions: [],
    Key.useUserDefinedConfDir: false,
    Key.userDefinedConfDir: "",
    
    Key.quitWhenNoOpenedWindow: true,
    Key.useExactSeek: true,
    Key.screenshotFolder: "~/Pictures/ScreenShots",
    Key.screenshotIncludeSubtitle: true,
    Key.screenshotFormat: "png",
    Key.screenshotTemplate: "%F-%n"
  ]

}
