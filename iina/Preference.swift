//
//  Preference.swift
//  iina
//
//  Created by lhc on 17/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

struct Preference {

  // MARK: - Keys

  // consider using RawRepresentable, but also need to extend UserDefaults
  struct Key {

    /** Record recent files */
    static let recordRecentFiles = "recordRecentFiles"

    /** Material for OSC and title bar (Theme(int)) */
    static let themeMaterial = "themeMaterial"

    /** Soft volume (int, 0 - 100)*/
    static let softVolume = "softVolume"

    /** Pause st first (pause) (bool) */
    static let pauseWhenOpen = "pauseWhenOpen"

    /** Enter fill screen when open (bool) */
    static let fullScreenWhenOpen = "fullScreenWhenOpen"

    /** Quit when no open window (bool) */
    static let quitWhenNoOpenedWindow = "quitWhenNoOpenedWindow"

    /** Keep player window open on end of file / playlist. (bool) */
    static let keepOpenOnFileEnd = "keepOpenOnFileEnd"
    
    /** Open a choose file panel after opening (bool) */
    static let openStartPanel = "openStartPanel"

    /** Resume from last position */
    static let resumeLastPosition = "resumeLastPosition"

    static let alwaysFloatOnTop = "alwaysFloatOnTop"

    /** Show chapter pos in progress bar (bool) */
    static let showChapterPos = "showChapterPos"

    static let screenshotFolder = "screenShotFolder"
    static let screenshotIncludeSubtitle = "screenShotIncludeSubtitle"
    static let screenshotFormat = "screenShotFormat"
    static let screenshotTemplate = "screenShotTemplate"

    // UI

    /** Horizontal positon of control bar. (float, 0 - 1) */
    static let controlBarPositionHorizontal = "controlBarPositionHorizontal"

    /** Horizontal positon of control bar. In percentage from bottom. (float, 0 - 1) */
    static let controlBarPositionVertical = "controlBarPositionVertical"

    /** Whether control bar stick to center when dragging. (bool) */
    static let controlBarStickToCenter = "controlBarStickToCenter"

    /** Timeout for auto hiding control bar (float) */
    static let controlBarAutoHideTimeout  = "controlBarAutoHideTimeout"

    /** OSD auto hide timeout (float) */
    static let osdAutoHideTimeout = "osdAutoHideTimeout"

    /** OSD text size (float) */
    static let osdTextSize = "osdTextSize"

    static let usePhysicalResolution = "usePhysicalResolution"

    /** IINA will adjust window size according to video size,
     but if the file is not opened by user manually (File > Open),
     e.g. jumping to next item in playlist, window size will remoain the same. */
    static let resizeOnlyWhenManuallyOpenFile = "resizeOnlyWhenManuallyOpenFile"

    // Codec

    static let videoThreads = "videoThreads"

    static let useHardwareDecoding = "useHardwareDecoding"

    static let audioThreads = "audioThreads"

    static let audioLanguage = "audioLanguage"

    // Subtitle

    static let subAutoLoad = "subAutoLoad"
    static let ignoreAssStyles = "ignoreAssStyles"
    static let subTextFont = "subTextFont"
    static let subTextSize = "subTextSize"
    static let subTextColor = "subTextColor"
    static let subBgColor = "subBgColor"
    static let subBold = "subBold"
    static let subItalic = "subItalic"
    static let subBorderSize = "subBorderSize"
    static let subBorderColor = "subBorderColor"
    static let subShadowSize = "subShadowSize"
    static let subShadowColor = "subShadowColor"
    static let subAlignX = "subAlignX"
    static let subAlignY = "subAlignY"
    static let subMarginX = "subMarginX"
    static let subMarginY = "subMarginY"
    static let subLang = "subLang"
    static let onlineSubSource = "onlineSubSource"
    static let displayInLetterBox = "displayInLetterBox"

    // Network

    static let enableCache = "enableCache"
    static let defaultCacheSize = "defaultCacheSize"
    static let cacheBufferSize = "cacheBufferSize"
    static let secPrefech = "secPrefech"
    static let userAgent = "userAgent"
    static let transportRTSPThrough = "transportRTSPThrough"

    // Control

    /** Seek option */
    static let useExactSeek = "useExactSeek"

    /** Seek speed for non-exact relative seek (Int, 1~5) */
    static let relativeSeekAmount = "relativeSeekAmount"

    static let arrowButtonAction = "arrowBtnAction"

    static let singleClickAction = "singleClickAction"

    static let doubleClickAction = "doubleClickAction"
    static let rightClickAction = "rightClickAction"

    // Input

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

    /** unused */
    // static let resizeFrameBuffer = "resizeFrameBuffer"

    /** User defined options ([string, string]) */
    static let userOptions = "userOptions"

    /** User defined conf directory */
    static let useUserDefinedConfDir = "useUserDefinedConfDir"
    static let userDefinedConfDir = "userDefinedConfDir"

  }

  // MARK: - Enums

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

  enum SeekOption: Int {
    case relative = 0
    case extract
    case auto
  }

  enum MouseClickAction: Int {
    case none = 0
    case fullscreen
    case pause
    case hideOSC
  }

  enum AutoLoadAction: Int {
    case no = 0
    case exact
    case fuzzy
    case all

    var string: String {
      get {
        switch self {
        case .no: return "no"
        case .exact: return "exact"
        case .fuzzy: return "fuzzy"
        case .all: return "all"
        }
      }
    }
  }

  enum SubAlign: Int {
    case top = 0  // left
    case center
    case bottom  // right

    var stringForX: String {
      get {
        switch self {
        case .top: return "left"
        case .center: return "center"
        case .bottom: return "right"
        }
      }
    }

    var stringForY: String {
      get {
        switch self {
        case .top: return "top"
        case .center: return "center"
        case .bottom: return "bottom"
        }
      }
    }
  }

  enum RTSPTransportation: Int {
    case lavf = 0
    case tcp
    case udp
    case http

    var string: String {
      get {
        switch self {
        case .lavf: return "lavf"
        case .tcp: return "tcp"
        case .udp: return "udp"
        case .http: return "http"
        }
      }
    }
  }

  enum ScreenshotFormat: Int {
    case png = 0
    case jpg
    case jpeg
    case ppm
    case pgm
    case pgmyuv
    case tga

    var string: String {
      get {
        switch self {
        case .png: return "png"
        case .jpg: return "jpg"
        case .jpeg: return "jpeg"
        case .ppm: return "ppm"
        case .pgm: return "pgm"
        case .pgmyuv: return "pgmyuv"
        case .tga: return "tga"
        }
      }
    }
  }

  // MARK: - Defaults

  static let defaultPreference:[String : Any] = [
    Key.recordRecentFiles: true,
    Key.controlBarPositionHorizontal: Float(0.5),
    Key.controlBarPositionVertical: Float(0.1),
    Key.controlBarStickToCenter: true,
    Key.controlBarAutoHideTimeout: Float(5),
    Key.themeMaterial: Theme.dark.rawValue,
    Key.osdAutoHideTimeout: Float(1),
    Key.osdTextSize: Float(20),
    Key.softVolume: 50,
    Key.arrowButtonAction: ArrowButtonAction.speed.rawValue,
    Key.pauseWhenOpen: false,
    Key.fullScreenWhenOpen: false,
    Key.showChapterPos: false,
    Key.resumeLastPosition: true,
    Key.useMediaKeys: true,
    Key.openStartPanel: false,
    Key.alwaysFloatOnTop: false,

    Key.usePhysicalResolution: true,
    Key.resizeOnlyWhenManuallyOpenFile: true,

    Key.videoThreads: 0,
    Key.useHardwareDecoding: true,
    Key.audioThreads: 0,
    Key.audioLanguage: "",

    Key.subAutoLoad: AutoLoadAction.fuzzy.rawValue,
    Key.ignoreAssStyles: false,
    Key.subTextFont: "sans-serif",
    Key.subTextSize: 55,
    Key.subTextColor: NSArchiver.archivedData(withRootObject: NSColor.white),
    Key.subBgColor: NSArchiver.archivedData(withRootObject: NSColor.clear),
    Key.subBold: false,
    Key.subItalic: false,
    Key.subBorderSize: 3,
    Key.subBorderColor: NSArchiver.archivedData(withRootObject: NSColor.black),
    Key.subShadowSize: 0,
    Key.subShadowColor: NSArchiver.archivedData(withRootObject: NSColor.clear),
    Key.subAlignX: SubAlign.center.rawValue,
    Key.subAlignY: SubAlign.bottom.rawValue,
    Key.subMarginX: 25,
    Key.subMarginY: 22,
    Key.subLang: "",
    Key.onlineSubSource: OnlineSubtitle.Source.shooter.rawValue,
    Key.displayInLetterBox: true,

    Key.enableCache: true,
    Key.defaultCacheSize: 75000,
    Key.cacheBufferSize: 75000,
    Key.secPrefech: 100,
    Key.userAgent: "",
    Key.transportRTSPThrough: RTSPTransportation.tcp.rawValue,

    Key.inputConfigs: [:],
    Key.currentInputConfigName: "IINA Default",

    Key.enableAdvancedSettings: false,
    Key.useMpvOsd: false,
    Key.enableLogging: false,
    Key.userOptions: [],
    Key.useUserDefinedConfDir: false,
    Key.userDefinedConfDir: "~/.config/mpv/",

    Key.keepOpenOnFileEnd: true,
    Key.quitWhenNoOpenedWindow: false,
    Key.useExactSeek: SeekOption.relative.rawValue,
    Key.relativeSeekAmount: 2,
    Key.singleClickAction: MouseClickAction.hideOSC.rawValue,
    Key.doubleClickAction: MouseClickAction.fullscreen.rawValue,
    Key.rightClickAction: MouseClickAction.pause.rawValue,

    Key.screenshotFolder: "~/Pictures/ScreenShots",
    Key.screenshotIncludeSubtitle: true,
    Key.screenshotFormat: ScreenshotFormat.png.rawValue,
    Key.screenshotTemplate: "%F-%n"
  ]

}
