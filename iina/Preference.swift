//
//  Preference.swift
//  iina
//
//  Created by lhc on 17/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

protocol InitializingFromKey {

  static var defaultValue: Self { get }

  init?(key: Preference.Key)

}

struct Preference {

  // MARK: - Keys

  // consider using RawRepresentable, but also need to extend UserDefaults
  struct Key: RawRepresentable {

    typealias RawValue = String

    var rawValue: RawValue

    init(_ string: String) { self.rawValue = string }

    init?(rawValue: RawValue) { self.rawValue = rawValue }


    static let actionAfterLaunch = Key("actionAfterLaunch")
    static let alwaysOpenInNewWindow = Key("alwaysOpenInNewWindow")
    static let enableCmdN = Key("enableCmdN")

    /** Record recent files */
    static let recordPlaybackHistory = Key("recordPlaybackHistory")
    static let recordRecentFiles = Key("recordRecentFiles")
    static let trackAllFilesInRecentOpenMenu = Key("trackAllFilesInRecentOpenMenu")

    /** Material for OSC and title bar (Theme(int)) */
    static let themeMaterial = Key("themeMaterial")

    /** Soft volume (int, 0 - 100)*/
    static let softVolume = Key("softVolume")

    /** Pause st first (pause) (bool) */
    static let pauseWhenOpen = Key("pauseWhenOpen")

    /** Enter fill screen when open (bool) */
    static let fullScreenWhenOpen = Key("fullScreenWhenOpen")

    static let useLegacyFullScreen = Key("useLegacyFullScreen")
    static let legacyFullScreenAnimation = Key("legacyFullScreenAnimation")

    /** Black out other monitors while fullscreen (bool) */
    static let blackOutMonitor = Key("blackOutMonitor")

    /** Quit when no open window (bool) */
    static let quitWhenNoOpenedWindow = Key("quitWhenNoOpenedWindow")

    /** Keep player window open on end of file / playlist. (bool) */
    static let keepOpenOnFileEnd = Key("keepOpenOnFileEnd")

    /** Resume from last position */
    static let resumeLastPosition = Key("resumeLastPosition")

    static let alwaysFloatOnTop = Key("alwaysFloatOnTop")

    /** Show chapter pos in progress bar (bool) */
    static let showChapterPos = Key("showChapterPos")

    static let screenshotFolder = Key("screenShotFolder")
    static let screenshotIncludeSubtitle = Key("screenShotIncludeSubtitle")
    static let screenshotFormat = Key("screenShotFormat")
    static let screenshotTemplate = Key("screenShotTemplate")

    static let playlistAutoAdd = Key("playlistAutoAdd")
    static let playlistAutoPlayNext = Key("playlistAutoPlayNext")

    // UI

    /** Horizontal positon of control bar. (float, 0 - 1) */
    static let controlBarPositionHorizontal = Key("controlBarPositionHorizontal")

    /** Horizontal positon of control bar. In percentage from bottom. (float, 0 - 1) */
    static let controlBarPositionVertical = Key("controlBarPositionVertical")

    /** Whether control bar stick to center when dragging. (bool) */
    static let controlBarStickToCenter = Key("controlBarStickToCenter")

    /** Timeout for auto hiding control bar (float) */
    static let controlBarAutoHideTimeout  = Key("controlBarAutoHideTimeout")

    /** OSD auto hide timeout (float) */
    static let osdAutoHideTimeout = Key("osdAutoHideTimeout")

    /** OSD text size (float) */
    static let osdTextSize = Key("osdTextSize")

    static let usePhysicalResolution = Key("usePhysicalResolution")

    /** IINA will adjust window size according to video size,
     but if the file is not opened by user manually (File > Open),
     e.g. jumping to next item in playlist, window size will remoain the same. */
    static let resizeOnlyWhenManuallyOpenFile = Key("resizeOnlyWhenManuallyOpenFile")

    static let oscPosition = Key("oscPosition")

    static let playlistWidth = Key("playlistWidth")

    static let enableThumbnailPreview = Key("enableThumbnailPreview")
    static let maxThumbnailPreviewCacheSize = Key("maxThumbnailPreviewCacheSize")

    static let autoSwitchToMusicMode = Key("autoSwitchToMusicMode")

    // Codec

    static let videoThreads = Key("videoThreads")
    static let hardwareDecoder = Key("hardwareDecoder")

    static let audioThreads = Key("audioThreads")
    static let audioLanguage = Key("audioLanguage")
    static let maxVolume = Key("maxVolume")

    static let spdifAC3 = Key("spdifAC3")
    static let spdifDTS = Key("spdifDTS")
    static let spdifDTSHD = Key("spdifDTSHD")

    static let enableInitialVolume = Key("enableInitialVolume")
    static let initialVolume = Key("initialVolume")

    // Subtitle

    static let subAutoLoadIINA = Key("subAutoLoadIINA")
    static let subAutoLoadPriorityString = Key("subAutoLoadPriorityString")
    static let subAutoLoadSearchPath = Key("subAutoLoadSearchPath")
    static let ignoreAssStyles = Key("ignoreAssStyles")
    static let subOverrideLevel = Key("subOverrideLevel")
    static let subTextFont = Key("subTextFont")
    static let subTextSize = Key("subTextSize")
    static let subTextColor = Key("subTextColor")
    static let subBgColor = Key("subBgColor")
    static let subBold = Key("subBold")
    static let subItalic = Key("subItalic")
    static let subBlur = Key("subBlur")
    static let subSpacing = Key("subSpacing")
    static let subBorderSize = Key("subBorderSize")
    static let subBorderColor = Key("subBorderColor")
    static let subShadowSize = Key("subShadowSize")
    static let subShadowColor = Key("subShadowColor")
    static let subAlignX = Key("subAlignX")
    static let subAlignY = Key("subAlignY")
    static let subMarginX = Key("subMarginX")
    static let subMarginY = Key("subMarginY")
    static let subPos = Key("subPos")
    static let subLang = Key("subLang")
    static let onlineSubSource = Key("onlineSubSource")
    static let displayInLetterBox = Key("displayInLetterBox")
    static let subScaleWithWindow = Key("subScaleWithWindow")
    static let openSubUsername = Key("openSubUsername")
    static let defaultEncoding = Key("defaultEncoding")

    // Network

    static let enableCache = Key("enableCache")
    static let defaultCacheSize = Key("defaultCacheSize")
    static let cacheBufferSize = Key("cacheBufferSize")
    static let secPrefech = Key("secPrefech")
    static let userAgent = Key("userAgent")
    static let transportRTSPThrough = Key("transportRTSPThrough")
    static let ytdlEnabled = Key("ytdlEnabled")
    static let ytdlSearchPath = Key("ytdlSearchPath")
    static let ytdlRawOptions = Key("ytdlRawOptions")
    static let httpProxy = Key("httpProxy")

    // Control

    /** Seek option */
    static let useExactSeek = Key("useExactSeek")

    /** Seek speed for non-exact relative seek (Int, 1~5) */
    static let relativeSeekAmount = Key("relativeSeekAmount")

    static let arrowButtonAction = Key("arrowBtnAction")
    /** (1~4) */
    static let volumeScrollAmount = Key("volumeScrollAmount")
    static let verticalScrollAction = Key("verticalScrollAction")
    static let horizontalScrollAction = Key("horizontalScrollAction")

    static let singleClickAction = Key("singleClickAction")
    static let doubleClickAction = Key("doubleClickAction")
    static let rightClickAction = Key("rightClickAction")
    static let middleClickAction = Key("middleClickAction")
    static let pinchAction = Key("pinchAction")
    static let forceTouchAction = Key("forceTouchAction")

    static let showRemainingTime = Key("showRemainingTime")

    // Input

    /** Whether catch media keys event (bool) */
    static let useMediaKeys = Key("useMediaKeys")
    static let useAppleRemote = Key("useAppleRemote")

    /** User created input config list (dic) */
    static let inputConfigs = Key("inputConfigs")

    /** Current input config name */
    static let currentInputConfigName = Key("currentInputConfigName")

    // Advanced

    /** Enable advanced settings */
    static let enableAdvancedSettings = Key("enableAdvancedSettings")

    /** Use mpv's OSD (bool) */
    static let useMpvOsd = Key("useMpvOsd")

    /** Log to log folder (bool) */
    static let enableLogging = Key("enableLogging")

    /** unused */
    // static let resizeFrameBuffer = Key("resizeFrameBuffer")

    /** User defined options ([string, string]) */
    static let userOptions = Key("userOptions")

    /** User defined conf directory */
    static let useUserDefinedConfDir = Key("useUserDefinedConfDir")
    static let userDefinedConfDir = Key("userDefinedConfDir")

    static let watchProperties = Key("watchProperties")

  }

  // MARK: - Enums

  enum ActionAfterLaunch: Int, InitializingFromKey {
    case welcomeWindow = 0
    case openPanel
    case none

    static var defaultValue = ActionAfterLaunch.welcomeWindow

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum ArrowButtonAction: Int, InitializingFromKey {
    case speed = 0
    case playlist = 1
    case seek = 2

    static var defaultValue = ArrowButtonAction.speed

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum Theme: Int, InitializingFromKey {
    case dark = 0
    case ultraDark
    case light
    case mediumLight

    static var defaultValue = Theme.dark

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum OSCPosition: Int, InitializingFromKey {
    case floating = 0
    case top
    case bottom
    case always

    static var defaultValue = OSCPosition.floating

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum SeekOption: Int, InitializingFromKey {
    case relative = 0
    case extract
    case auto

    static var defaultValue = SeekOption.relative

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum MouseClickAction: Int, InitializingFromKey {
    case none = 0
    case fullscreen
    case pause
    case hideOSC

    static var defaultValue = MouseClickAction.none

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum ScrollAction: Int, InitializingFromKey {
    case volume = 0
    case seek
    case none
    case passToMpv

    static var defaultValue = ScrollAction.volume

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum PinchAction: Int, InitializingFromKey {
    case windowSize = 0
    case fullscreen
    case none

    static var defaultValue = PinchAction.windowSize

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum IINAAutoLoadAction: Int, InitializingFromKey {
    case disabled = 0
    case mpvFuzzy
    case iina

    static var defaultValue = IINAAutoLoadAction.iina

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    func shouldLoadSubsContainingVideoName() -> Bool {
      return self != .disabled
    }

    func shouldLoadSubsMatchedByIINA() -> Bool {
      return self == .iina
    }
  }

  enum AutoLoadAction: Int, InitializingFromKey {
    case no = 0
    case exact
    case fuzzy
    case all

    static var defaultValue = AutoLoadAction.fuzzy

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

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

  enum SubOverrideLevel: Int, InitializingFromKey {
    case yes = 0
    case force
    case strip

    static var defaultValue = SubOverrideLevel.yes

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var string: String {
      get {
        switch self {
        case .yes: return "yes"
        case .force : return "force"
        case .strip: return "strip"
        }
      }
    }
  }

  enum SubAlign: Int, InitializingFromKey {
    case top = 0  // left
    case center
    case bottom  // right

    static var defaultValue = SubAlign.center

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

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

  enum RTSPTransportation: Int, InitializingFromKey {
    case lavf = 0
    case tcp
    case udp
    case http

    static var defaultValue = RTSPTransportation.tcp

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

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

  enum ScreenshotFormat: Int, InitializingFromKey {
    case png = 0
    case jpg
    case jpeg
    case ppm
    case pgm
    case pgmyuv
    case tga

    static var defaultValue = ScreenshotFormat.png

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

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

  enum HardwareDecoderOption: Int, InitializingFromKey {
    case disabled = 0
    case auto
    case autoCopy

    static var defaultValue = HardwareDecoderOption.auto

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var mpvString: String {
      switch self {
      case .disabled: return "no"
      case .auto: return "auto"
      case .autoCopy: return "auto-copy"
      }
    }

    var localizedDescription: String {
      return NSLocalizedString("hwdec." + mpvString, comment: mpvString)
    }
  }

  // MARK: - Defaults

  static let defaultPreference:[String: Any] = [
    Key.actionAfterLaunch.rawValue: ActionAfterLaunch.welcomeWindow.rawValue,
    Key.alwaysOpenInNewWindow.rawValue: true,
    Key.enableCmdN.rawValue: false,
    Key.recordPlaybackHistory.rawValue: true,
    Key.recordRecentFiles.rawValue: true,
    Key.trackAllFilesInRecentOpenMenu.rawValue: true,
    Key.controlBarPositionHorizontal.rawValue: Float(0.5),
    Key.controlBarPositionVertical.rawValue: Float(0.1),
    Key.controlBarStickToCenter.rawValue: true,
    Key.controlBarAutoHideTimeout.rawValue: Float(2.5),
    Key.oscPosition.rawValue: OSCPosition.floating.rawValue,
    Key.playlistWidth.rawValue: 270,
    Key.themeMaterial.rawValue: Theme.dark.rawValue,
    Key.osdAutoHideTimeout.rawValue: Float(1),
    Key.osdTextSize.rawValue: Float(20),
    Key.softVolume.rawValue: 100,
    Key.arrowButtonAction.rawValue: ArrowButtonAction.speed.rawValue,
    Key.pauseWhenOpen.rawValue: false,
    Key.fullScreenWhenOpen.rawValue: false,
    Key.useLegacyFullScreen.rawValue: false,
    Key.legacyFullScreenAnimation.rawValue: false,
    Key.showChapterPos.rawValue: false,
    Key.resumeLastPosition.rawValue: true,
    Key.useMediaKeys.rawValue: true,
    Key.useAppleRemote.rawValue: true,
    Key.alwaysFloatOnTop.rawValue: false,
    Key.blackOutMonitor.rawValue: false,

    Key.playlistAutoAdd.rawValue: true,
    Key.playlistAutoPlayNext.rawValue: true,

    Key.usePhysicalResolution.rawValue: true,
    Key.resizeOnlyWhenManuallyOpenFile.rawValue: true,
    Key.showRemainingTime.rawValue: false,
    Key.enableThumbnailPreview.rawValue: true,
    Key.maxThumbnailPreviewCacheSize.rawValue: 500,
    Key.autoSwitchToMusicMode.rawValue: true,

    Key.videoThreads.rawValue: 0,
    Key.hardwareDecoder.rawValue: HardwareDecoderOption.auto.rawValue,
    Key.audioThreads.rawValue: 0,
    Key.audioLanguage.rawValue: "",
    Key.maxVolume.rawValue: 100,
    Key.spdifAC3.rawValue: false,
    Key.spdifDTS.rawValue: false,
    Key.spdifDTSHD.rawValue: false,
    Key.enableInitialVolume.rawValue: false,
    Key.initialVolume.rawValue: 100,

    Key.subAutoLoadIINA.rawValue: IINAAutoLoadAction.iina.rawValue,
    Key.subAutoLoadPriorityString.rawValue: "",
    Key.subAutoLoadSearchPath.rawValue: "./*",
    Key.ignoreAssStyles.rawValue: false,
    Key.subOverrideLevel.rawValue: SubOverrideLevel.strip.rawValue,
    Key.subTextFont.rawValue: "sans-serif",
    Key.subTextSize.rawValue: Float(55),
    Key.subTextColor.rawValue: NSArchiver.archivedData(withRootObject: NSColor.white),
    Key.subBgColor.rawValue: NSArchiver.archivedData(withRootObject: NSColor.clear),
    Key.subBold.rawValue: false,
    Key.subItalic.rawValue: false,
    Key.subBlur.rawValue: Float(0),
    Key.subSpacing.rawValue: Float(0),
    Key.subBorderSize.rawValue: Float(3),
    Key.subBorderColor.rawValue: NSArchiver.archivedData(withRootObject: NSColor.black),
    Key.subShadowSize.rawValue: Float(0),
    Key.subShadowColor.rawValue: NSArchiver.archivedData(withRootObject: NSColor.clear),
    Key.subAlignX.rawValue: SubAlign.center.rawValue,
    Key.subAlignY.rawValue: SubAlign.bottom.rawValue,
    Key.subMarginX.rawValue: Float(25),
    Key.subMarginY.rawValue: Float(22),
    Key.subPos.rawValue: Float(100),
    Key.subLang.rawValue: "",
    Key.onlineSubSource.rawValue: OnlineSubtitle.Source.shooter.rawValue,
    Key.displayInLetterBox.rawValue: true,
    Key.subScaleWithWindow.rawValue: true,
    Key.openSubUsername.rawValue: "",
    Key.defaultEncoding.rawValue: "auto",

    Key.enableCache.rawValue: true,
    Key.defaultCacheSize.rawValue: 153600,
    Key.cacheBufferSize.rawValue: 153600,
    Key.secPrefech.rawValue: 100,
    Key.userAgent.rawValue: "",
    Key.transportRTSPThrough.rawValue: RTSPTransportation.tcp.rawValue,
    Key.ytdlEnabled.rawValue: true,
    Key.ytdlSearchPath.rawValue: "",
    Key.ytdlRawOptions.rawValue: "",
    Key.httpProxy.rawValue: "",

    Key.inputConfigs.rawValue: [:],
    Key.currentInputConfigName.rawValue: "IINA Default",

    Key.enableAdvancedSettings.rawValue: false,
    Key.useMpvOsd.rawValue: false,
    Key.enableLogging.rawValue: false,
    Key.userOptions.rawValue: [],
    Key.useUserDefinedConfDir.rawValue: false,
    Key.userDefinedConfDir.rawValue: "~/.config/mpv/",

    Key.keepOpenOnFileEnd.rawValue: true,
    Key.quitWhenNoOpenedWindow.rawValue: false,
    Key.useExactSeek.rawValue: SeekOption.relative.rawValue,
    Key.relativeSeekAmount.rawValue: 3,
    Key.volumeScrollAmount.rawValue: 3,
    Key.verticalScrollAction.rawValue: ScrollAction.volume.rawValue,
    Key.horizontalScrollAction.rawValue: ScrollAction.seek.rawValue,
    Key.singleClickAction.rawValue: MouseClickAction.hideOSC.rawValue,
    Key.doubleClickAction.rawValue: MouseClickAction.fullscreen.rawValue,
    Key.rightClickAction.rawValue: MouseClickAction.pause.rawValue,
    Key.middleClickAction.rawValue: MouseClickAction.none.rawValue,
    Key.pinchAction.rawValue: PinchAction.windowSize.rawValue,
    Key.forceTouchAction.rawValue: MouseClickAction.none.rawValue,

    Key.screenshotFolder.rawValue: "~/Pictures/Screenshots",
    Key.screenshotIncludeSubtitle.rawValue: true,
    Key.screenshotFormat.rawValue: ScreenshotFormat.png.rawValue,
    Key.screenshotTemplate.rawValue: "%F-%n",

    Key.watchProperties.rawValue: []
  ]

  static private let ud = UserDefaults.standard

  static func object(for key: Key) -> Any? {
    return ud.object(forKey: key.rawValue)
  }

  static func array(for key: Key) -> [Any]? {
    return ud.array(forKey: key.rawValue)
  }

  static func url(for key: Key) -> URL? {
    return ud.url(forKey: key.rawValue)
  }

  static func dictionary(for key: Key) -> [String : Any]? {
    return ud.dictionary(forKey: key.rawValue)
  }

  static func string(for key: Key) -> String? {
    return ud.string(forKey: key.rawValue)
  }

  static func stringArray(for key: Key) -> [String]? {
    return ud.stringArray(forKey: key.rawValue)
  }

  static func data(for key: Key) -> Data? {
    return ud.data(forKey: key.rawValue)
  }

  static func bool(for key: Key) -> Bool {
    return ud.bool(forKey: key.rawValue)
  }

  static func integer(for key: Key) -> Int {
    return ud.integer(forKey: key.rawValue)
  }

  static func float(for key: Key) -> Float {
    return ud.float(forKey: key.rawValue)
  }

  static func double(for key: Key) -> Double {
    return ud.double(forKey: key.rawValue)
  }

  static func value(for key: Key) -> Any? {
    return ud.value(forKey: key.rawValue)
  }

  static func mpvColor(for key: Key) -> String? {
    return ud.mpvColor(forKey: key.rawValue)
  }

  static func set(_ value: Bool, for key: Key) {
    ud.set(value, forKey: key.rawValue)
  }

  static func set(_ value: Int, for key: Key) {
    ud.set(value, forKey: key.rawValue)
  }

  static func set(_ value: String, for key: Key) {
    ud.set(value, forKey: key.rawValue)
  }

  static func set(_ value: Float, for key: Key) {
    ud.set(value, forKey: key.rawValue)
  }

  static func set(_ value: Double, for key: Key) {
    ud.set(value, forKey: key.rawValue)
  }

  static func set(_ value: Any, for key: Key) {
    ud.set(value, forKey: key.rawValue)
  }

  static func `enum`<T: InitializingFromKey>(for key: Key) -> T {
    return T.init(key: key) ?? T.defaultValue
  }
  
}
