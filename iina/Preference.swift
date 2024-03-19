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
  struct Key: RawRepresentable, Hashable {

    typealias RawValue = String

    var rawValue: RawValue

    var hashValue: Int {
      return rawValue.hashValue
    }

    init(_ string: String) { self.rawValue = string }

    init?(rawValue: RawValue) { self.rawValue = rawValue }

    static let receiveBetaUpdate = Key("receiveBetaUpdate")

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
    static let alwaysShowOnTopIcon = Key("alwaysShowOnTopIcon")

    static let pauseWhenMinimized = Key("pauseWhenMinimized")
    static let pauseWhenInactive = Key("pauseWhenInactive")
    static let playWhenEnteringFullScreen = Key("playWhenEnteringFullScreen")
    static let pauseWhenLeavingFullScreen = Key("pauseWhenLeavingFullScreen")
    static let pauseWhenGoesToSleep = Key("pauseWhenGoesToSleep")

    /** Show chapter pos in progress bar (bool) */
    static let showChapterPos = Key("showChapterPos")

    static let screenshotSaveToFile = Key("screenshotSaveToFile")
    static let screenshotCopyToClipboard = Key("screenshotCopyToClipboard")
    static let screenshotFolder = Key("screenShotFolder")
    static let screenshotIncludeSubtitle = Key("screenShotIncludeSubtitle")
    static let screenshotFormat = Key("screenShotFormat")
    static let screenshotTemplate = Key("screenShotTemplate")
    static let screenshotShowPreview = Key("screenshotShowPreview")

    static let playlistAutoAdd = Key("playlistAutoAdd")
    static let playlistAutoPlayNext = Key("playlistAutoPlayNext")
    static let playlistShowMetadata = Key("playlistShowMetadata")
    static let playlistShowMetadataInMusicMode = Key("playlistShowMetadataInMusicMode")

    // UI

    /** Horizontal position of control bar. (float, 0 - 1) */
    static let controlBarPositionHorizontal = Key("controlBarPositionHorizontal")

    /** Horizontal position of control bar. In percentage from bottom. (float, 0 - 1) */
    static let controlBarPositionVertical = Key("controlBarPositionVertical")

    /** Whether control bar stick to center when dragging. (bool) */
    static let controlBarStickToCenter = Key("controlBarStickToCenter")

    /** Timeout for auto hiding control bar (float) */
    static let controlBarAutoHideTimeout = Key("controlBarAutoHideTimeout")

    static let controlBarToolbarButtons = Key("controlBarToolbarButtons")

    static let enableOSD = Key("enableOSD")
    static let osdAutoHideTimeout = Key("osdAutoHideTimeout")
    static let osdTextSize = Key("osdTextSize")

    static let usePhysicalResolution = Key("usePhysicalResolution")

    static let initialWindowSizePosition = Key("initialWindowSizePosition")
    static let resizeWindowTiming = Key("resizeWindowTiming")
    static let resizeWindowOption = Key("resizeWindowOption")

    static let oscPosition = Key("oscPosition")

    static let playlistWidth = Key("playlistWidth")
    static let prefetchPlaylistVideoDuration = Key("prefetchPlaylistVideoDuration")

    static let enableThumbnailPreview = Key("enableThumbnailPreview")
    static let maxThumbnailPreviewCacheSize = Key("maxThumbnailPreviewCacheSize")
    static let enableThumbnailForRemoteFiles = Key("enableThumbnailForRemoteFiles")
    static let thumbnailWidth = Key("thumbnailWidth")

    static let autoSwitchToMusicMode = Key("autoSwitchToMusicMode")
    static let musicModeShowPlaylist = Key("musicModeShowPlaylist")
    static let musicModeShowAlbumArt = Key("musicModeShowAlbumArt")

    static let displayTimeAndBatteryInFullScreen = Key("displayTimeAndBatteryInFullScreen")

    static let windowBehaviorWhenPip = Key("windowBehaviorWhenPip")
    static let pauseWhenPip = Key("pauseWhenPip")
    static let togglePipByMinimizingWindow = Key("togglePipByMinimizingWindow")

    // Codec

    static let videoThreads = Key("videoThreads")
    static let hardwareDecoder = Key("hardwareDecoder")
    static let forceDedicatedGPU = Key("forceDedicatedGPU")
    static let loadIccProfile = Key("loadIccProfile")
    static let enableHdrSupport = Key("enableHdrSupport")
    static let enableToneMapping = Key("enableToneMapping")
    static let toneMappingTargetPeak = Key("toneMappingTargetPeak")
    static let toneMappingAlgorithm = Key("toneMappingAlgorithm")

    static let audioThreads = Key("audioThreads")
    static let audioLanguage = Key("audioLanguage")
    static let maxVolume = Key("maxVolume")

    static let spdifAC3 = Key("spdifAC3")
    static let spdifDTS = Key("spdifDTS")
    static let spdifDTSHD = Key("spdifDTSHD")

    static let audioDevice = Key("audioDevice")
    static let audioDeviceDesc = Key("audioDeviceDesc")

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
    static let legacyOnlineSubSource = Key("onlineSubSource")
    static let onlineSubProvider = Key("onlineSubProvider")
    static let displayInLetterBox = Key("displayInLetterBox")
    static let subScaleWithWindow = Key("subScaleWithWindow")
    static let openSubUsername = Key("openSubUsername")
    static let assrtToken = Key("assrtToken")
    static let defaultEncoding = Key("defaultEncoding")
    static let autoSearchOnlineSub = Key("autoSearchOnlineSub")
    static let autoSearchThreshold = Key("autoSearchThreshold")

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

    static let videoViewAcceptsFirstMouse = Key("videoViewAcceptsFirstMouse")
    static let singleClickAction = Key("singleClickAction")
    static let doubleClickAction = Key("doubleClickAction")
    static let rightClickAction = Key("rightClickAction")
    static let middleClickAction = Key("middleClickAction")
    static let pinchAction = Key("pinchAction")
    static let forceTouchAction = Key("forceTouchAction")

    static let showRemainingTime = Key("showRemainingTime")
    static let scaleRemainingTime = Key("scaleRemainingTime")
    static let timeDisplayPrecision = Key("timeDisplayPrecision")
    static let touchbarShowRemainingTime = Key("touchbarShowRemainingTime")

    static let followGlobalSeekTypeWhenAdjustSlider = Key("followGlobalSeekTypeWhenAdjustSlider")

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
    static let logLevel = Key("logLevel")

    static let displayKeyBindingRawValues = Key("displayKeyBindingRawValues")

    /** unused */
    // static let resizeFrameBuffer = Key("resizeFrameBuffer")

    /** User defined options ([string, string]) */
    static let userOptions = Key("userOptions")

    /** User defined conf directory */
    static let useUserDefinedConfDir = Key("useUserDefinedConfDir")
    static let userDefinedConfDir = Key("userDefinedConfDir")

    static let watchProperties = Key("watchProperties")

    static let savedVideoFilters = Key("savedVideoFilters")
    static let savedAudioFilters = Key("savedAudioFilters")

    static let iinaLastPlayedFilePath = Key("iinaLastPlayedFilePath")
    static let iinaLastPlayedFilePosition = Key("iinaLastPlayedFilePosition")

    /** Alerts */
    static let suppressCannotPreventDisplaySleep = Key("suppressCannotPreventDisplaySleep")

    static let iinaEnablePluginSystem = Key("iinaEnablePluginSystem")

    /** Workaround for issue [#4688](https://github.com/iina/iina/issues/4688) */
    static let recentDocuments = Key("recentDocuments")
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
    case ultraDark // 1
    case light // 2
    case mediumLight // 3
    case system // 4

    static var defaultValue = Theme.dark

    init?(key: Key) {
      let value = Preference.integer(for: key)
      if #available(macOS 10.14, *) {
        if value == 1 || value == 3 {
          return nil
        }
      } else {
        if value == 4 {
          return nil
        }
      }
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum OSCPosition: Int, InitializingFromKey {
    case floating = 0
    case top
    case bottom

    static var defaultValue = OSCPosition.floating

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum SeekOption: Int, InitializingFromKey {
    case relative = 0
    case exact
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
    case togglePIP

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

  enum ToneMappingAlgorithmOption: Int, InitializingFromKey {
    case auto = 0
    case clip
    case mobius
    case reinhard
    case hable
    case bt_2390
    case gamma
    case linear

    static var defaultValue = ToneMappingAlgorithmOption.auto

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var mpvString: String {
      switch self {
      case .auto: return "auto"
      case .clip: return "clip"
      case .mobius: return "mobius"
      case .reinhard: return "reinhard"
      case .hable: return "hable"
      case .bt_2390: return "bt.2390"
      case .gamma: return "gamma"
      case .linear: return "linear"
      }
    }
  }

  enum ResizeWindowTiming: Int, InitializingFromKey {
    case always = 0
    case onlyWhenOpen
    case never

    static var defaultValue = ResizeWindowTiming.onlyWhenOpen

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum ResizeWindowOption: Int, InitializingFromKey {
    case fitScreen = 0
    case videoSize05
    case videoSize10
    case videoSize15
    case videoSize20

    static var defaultValue = ResizeWindowOption.videoSize10

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var ratio: Double {
      switch self {
      case .fitScreen: return -1
      case .videoSize05: return 0.5
      case .videoSize10: return 1
      case .videoSize15: return 1.5
      case .videoSize20: return 2
      }
    }
  }

  enum WindowBehaviorWhenPip: Int, InitializingFromKey {
    case doNothing = 0
    case hide
    case minimize

    static var defaultValue = WindowBehaviorWhenPip.doNothing

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum ToolBarButton: Int {
    case settings = 0
    case playlist
    case pip
    case fullScreen
    case musicMode
    case subTrack
    case screenshot

    func image() -> NSImage {
      switch self {
      case .settings: return NSImage(named: NSImage.actionTemplateName)!
      case .playlist: return #imageLiteral(resourceName: "playlist")
      case .pip: return #imageLiteral(resourceName: "pip")
      case .fullScreen: return #imageLiteral(resourceName: "fullscreen")
      case .musicMode: return #imageLiteral(resourceName: "toggle-album-art")
      case .subTrack: return #imageLiteral(resourceName: "sub-track")
      case .screenshot: return #imageLiteral(resourceName: "screenshot")
      }
    }

    func description() -> String {
      let key: String
      switch self {
      case .settings: key = "settings"
      case .playlist: key = "playlist"
      case .pip: key = "pip"
      case .fullScreen: key = "full_screen"
      case .musicMode: key = "music_mode"
      case .subTrack: key = "sub_track"
      case .screenshot: key = "screenshot"
      }
      return NSLocalizedString("osc_toolbar.\(key)", comment: key)
    }

    // Width will be identical
    static let frameHeight: CGFloat = 24

  }

  // MARK: - Defaults

  static let defaultPreference: [Preference.Key: Any] = [
    .receiveBetaUpdate: false,
    .actionAfterLaunch: ActionAfterLaunch.welcomeWindow.rawValue,
    .alwaysOpenInNewWindow: true,
    .enableCmdN: false,
    .recordPlaybackHistory: true,
    .recordRecentFiles: true,
    .trackAllFilesInRecentOpenMenu: true,
    .controlBarPositionHorizontal: Float(0.5),
    .controlBarPositionVertical: Float(0.1),
    .controlBarStickToCenter: true,
    .controlBarAutoHideTimeout: Float(2.5),
    .controlBarToolbarButtons: [ToolBarButton.pip.rawValue, ToolBarButton.playlist.rawValue, ToolBarButton.settings.rawValue],
    .oscPosition: OSCPosition.floating.rawValue,
    .playlistWidth: 270,
    .prefetchPlaylistVideoDuration: true,
    .themeMaterial: Theme.dark.rawValue,
    .enableOSD: true,
    .osdAutoHideTimeout: Float(1),
    .osdTextSize: Float(20),
    .softVolume: 100,
    .arrowButtonAction: ArrowButtonAction.speed.rawValue,
    .pauseWhenOpen: false,
    .fullScreenWhenOpen: false,
    .useLegacyFullScreen: false,
    .legacyFullScreenAnimation: false,
    .showChapterPos: false,
    .resumeLastPosition: true,
    .useMediaKeys: true,
    .useAppleRemote: false,
    .alwaysFloatOnTop: false,
    .alwaysShowOnTopIcon: false,
    .blackOutMonitor: false,
    .pauseWhenMinimized: false,
    .pauseWhenInactive: false,
    .pauseWhenLeavingFullScreen: false,
    .pauseWhenGoesToSleep: true,
    .playWhenEnteringFullScreen: false,

    .playlistAutoAdd: true,
    .playlistAutoPlayNext: true,
    .playlistShowMetadata: true,
    .playlistShowMetadataInMusicMode: true,

    .usePhysicalResolution: true,
    .initialWindowSizePosition: "",
    .resizeWindowTiming: ResizeWindowTiming.onlyWhenOpen.rawValue,
    .resizeWindowOption: ResizeWindowOption.videoSize10.rawValue,
    .showRemainingTime: false,
    .scaleRemainingTime: false,
    .timeDisplayPrecision: 0,
    .touchbarShowRemainingTime: true,
    .enableThumbnailPreview: true,
    .maxThumbnailPreviewCacheSize: 500,
    .enableThumbnailForRemoteFiles: false,
    .thumbnailWidth: 240,
    .autoSwitchToMusicMode: true,
    .musicModeShowPlaylist: false,
    .musicModeShowAlbumArt: true,
    .displayTimeAndBatteryInFullScreen: false,

    .windowBehaviorWhenPip: WindowBehaviorWhenPip.doNothing.rawValue,
    .pauseWhenPip: false,
    .togglePipByMinimizingWindow: false,

    .videoThreads: 0,
    .hardwareDecoder: HardwareDecoderOption.auto.rawValue,
    .forceDedicatedGPU: false,
    .loadIccProfile: true,
    .enableHdrSupport: true,
    .enableToneMapping: false,
    .toneMappingTargetPeak: 0,
    .toneMappingAlgorithm: "auto",
    .audioThreads: 0,
    .audioLanguage: "",
    .maxVolume: 100,
    .spdifAC3: false,
    .spdifDTS: false,
    .spdifDTSHD: false,
    .audioDevice: "auto",
    .audioDeviceDesc: "Autoselect device",
    .enableInitialVolume: false,
    .initialVolume: 100,

    .subAutoLoadIINA: IINAAutoLoadAction.iina.rawValue,
    .subAutoLoadPriorityString: "",
    .subAutoLoadSearchPath: "./*",
    .ignoreAssStyles: false,
    .subOverrideLevel: SubOverrideLevel.strip.rawValue,
    .subTextFont: "sans-serif",
    .subTextSize: Float(55),
    .subTextColor: NSArchiver.archivedData(withRootObject: NSColor.white),
    .subBgColor: NSArchiver.archivedData(withRootObject: NSColor.clear),
    .subBold: false,
    .subItalic: false,
    .subBlur: Float(0),
    .subSpacing: Float(0),
    .subBorderSize: Float(3),
    .subBorderColor: NSArchiver.archivedData(withRootObject: NSColor.black),
    .subShadowSize: Float(0),
    .subShadowColor: NSArchiver.archivedData(withRootObject: NSColor.clear),
    .subAlignX: SubAlign.center.rawValue,
    .subAlignY: SubAlign.bottom.rawValue,
    .subMarginX: Float(25),
    .subMarginY: Float(22),
    .subPos: Float(100),
    .subLang: "",
    .legacyOnlineSubSource: 1, /* openSub */
    .onlineSubProvider: OnlineSubtitle.Providers.openSub.id,
    .displayInLetterBox: true,
    .subScaleWithWindow: true,
    .openSubUsername: "",
    .assrtToken: "",
    .defaultEncoding: "auto",
    .autoSearchOnlineSub: false,
    .autoSearchThreshold: 20,

    .enableCache: true,
    .defaultCacheSize: 153600,
    .cacheBufferSize: 153600,
    .secPrefech: 36000,
    .userAgent: "",
    .transportRTSPThrough: RTSPTransportation.tcp.rawValue,
    .ytdlEnabled: true,
    .ytdlSearchPath: "",
    .ytdlRawOptions: "",
    .httpProxy: "",

    .inputConfigs: [String: Any](),
    .currentInputConfigName: "IINA Default",

    .enableAdvancedSettings: false,
    .useMpvOsd: false,
    .enableLogging: false,
    .logLevel: Logger.Level.debug.rawValue,
    .displayKeyBindingRawValues: false,
    .userOptions: [[String]](),
    .useUserDefinedConfDir: false,
    .userDefinedConfDir: "~/.config/mpv/",
    .iinaEnablePluginSystem: false,

    .keepOpenOnFileEnd: true,
    .quitWhenNoOpenedWindow: false,
    .useExactSeek: SeekOption.relative.rawValue,
    .followGlobalSeekTypeWhenAdjustSlider: false,
    .relativeSeekAmount: 3,
    .volumeScrollAmount: 3,
    .verticalScrollAction: ScrollAction.volume.rawValue,
    .horizontalScrollAction: ScrollAction.seek.rawValue,
    .videoViewAcceptsFirstMouse: false,
    .singleClickAction: MouseClickAction.hideOSC.rawValue,
    .doubleClickAction: MouseClickAction.fullscreen.rawValue,
    .rightClickAction: MouseClickAction.pause.rawValue,
    .middleClickAction: MouseClickAction.none.rawValue,
    .pinchAction: PinchAction.windowSize.rawValue,
    .forceTouchAction: MouseClickAction.none.rawValue,

    .screenshotSaveToFile: true,
    .screenshotCopyToClipboard: false,
    .screenshotFolder: "~/Pictures/Screenshots",
    .screenshotIncludeSubtitle: true,
    .screenshotFormat: ScreenshotFormat.png.rawValue,
    .screenshotTemplate: "%F-%n",
    .screenshotShowPreview: true,

    .watchProperties: [String](),
    .savedVideoFilters: [SavedFilter](),
    .savedAudioFilters: [SavedFilter](),

    .suppressCannotPreventDisplaySleep: false,

    .recentDocuments: [Any]()
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

  static func set(_ value: URL, for key: Key) {
    ud.set(value, forKey: key.rawValue)
  }

  static func set(_ value: Any?, for key: Key) {
    ud.set(value, forKey: key.rawValue)
  }

  static func `enum`<T: InitializingFromKey>(for key: Key) -> T {
    return T.init(key: key) ?? T.defaultValue
  }

}
