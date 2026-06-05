//
//  Preference.swift
//  iina
//
//  Created by lhc on 17/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

protocol InitializingFromKey: CustomStringConvertible {

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
    static let alwaysOpenInNewWindow = Key("alwaysOpenInNewWindow") // now means "allow opening multiple windows"
    static let groupSimultaneousOpensInPlaylist = Key("groupSimultaneousOpensInPlaylist")
    static let allowDuplicatePlayers = Key("allowDuplicatePlayers")
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

    /** Black out other monitors while fullscreen (bool) */
    static let blackOutMonitor = Key("blackOutMonitor")

    /** Quit when no open window (bool) */
    static let quitWhenNoOpenedWindow = Key("quitWhenNoOpenedWindow")

    /** Keep player window open on end of file / playlist. (bool) */
    static let keepOpenOnFileEnd = Key("keepOpenOnFileEnd")

    /** Resume from last position */
    static let resumeLastPosition = Key("resumeLastPosition")

    static let preventScreenSaver = Key("preventScreenSaver")
    static let allowScreenSaverForAudio = Key("allowScreenSaverForAudio")

    static let alwaysFloatOnTop = Key("alwaysFloatOnTop")
    static let alwaysShowOnTopIcon = Key("alwaysShowOnTopIcon")

    static let pauseWhenMinimized = Key("pauseWhenMinimized")
    static let pauseWhenInactive = Key("pauseWhenInactive")
    static let playWhenEnteringFullScreen = Key("playWhenEnteringFullScreen")
    static let pauseWhenLeavingFullScreen = Key("pauseWhenLeavingFullScreen")
    static let pauseWhenGoesToSleep = Key("pauseWhenGoesToSleep")

    static let autoRepeat = Key("autoRepeat")
    static let defaultRepeatMode = Key("defaultRepeatMode")

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

    /** Whether auto hiding control bar is enabled. (bool)*/
    static let enableControlBarAutoHide = Key("enableControlBarAutoHide")

    static let controlBarToolbarButtons = Key("controlBarToolbarButtons")

    static let enableOSD = Key("enableOSD")
    static let disableOSDFileStartMsg = Key("disableOSDFileStartMsg")
    static let disableOSDPauseResumeMsgs = Key("disableOSDPauseResumeMsgs")
    static let disableOSDSeekMsg = Key("disableOSDSeekMsg")
    static let disableOSDSpeedMsg = Key("disableOSDSpeedMsg")

    static let osdAutoHideTimeout = Key("osdAutoHideTimeout")
    static let osdTextSize = Key("osdTextSize")

    static let usePhysicalResolution = Key("usePhysicalResolution")

    static let initialWindowSizePosition = Key("initialWindowSizePosition")
    static let resizeWindowTiming = Key("resizeWindowTiming")
    static let resizeWindowOption = Key("resizeWindowOption")

    static let oscPosition = Key("oscPosition")
    static let disablePlaySliderScrolling = Key("disablePlaySliderScrolling")
    static let disableVolumeSliderScrolling = Key("disableVolumeSliderScrolling")

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
    static let togglePipByMinimizingWindowForVideoOnly = Key("togglePipByMinimizingWindowForVideoOnly")

    static let disableAnimations = Key("disableAnimations")

    static let unlockWindowAspectRatio = Key("unlockWindowAspectRatio")
    static let compactUI = Key("compactUI")
    static let edgeToEdgeVideo = Key("edgeToEdgeVideo")

    // Codec

    static let videoThreads = Key("videoThreads")
    static let hardwareDecoder = Key("hardwareDecoder")
    static let forceDedicatedGPU = Key("forceDedicatedGPU")
    static let loadIccProfile = Key("loadIccProfile")
    static let enableHdrSupport = Key("enableHdrSupport")
    static let enableToneMapping = Key("enableToneMapping")
    static let toneMappingTargetPeak = Key("toneMappingTargetPeak")
    static let toneMappingAlgorithm = Key("toneMappingAlgorithm")

    static let audioDriverEnableAVFoundation = Key("audioDriverEnableAVFoundation")
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

    static let replayGain = Key("replayGain")
    static let replayGainPreamp = Key("replayGainPreamp")
    static let replayGainClip = Key("replayGainClip")
    static let replayGainFallback = Key("replayGainFallback")

    static let gaplessAudio = Key("gaplessAudio")

    static let userEQPresets = Key("userEQPresets")

    // Subtitle

    static let subAutoLoadIINA = Key("subAutoLoadIINA")
    static let subAutoLoadPriorityString = Key("subAutoLoadPriorityString")
    static let subAutoLoadSearchPath = Key("subAutoLoadSearchPath")
    static let ignoreAssStyles = Key("ignoreAssStyles")
    static let subOverrideLevel = Key("subOverrideLevel")
    static let secondarySubOverrideLevel = Key("secondarySubOverrideLevel")
    static let subTextFont = Key("subTextFont")
    static let subTextSize = Key("subTextSize")
    static let subTextColorString = Key("subTextColorString")
    static let subBgColorString = Key("subBgColorString")
    static let subBold = Key("subBold")
    static let subItalic = Key("subItalic")
    static let subBlur = Key("subBlur")
    static let subSpacing = Key("subSpacing")
    static let subBorderSize = Key("subBorderSize")
    static let subBorderColorString = Key("subBorderColorString")
    static let subShadowSize = Key("subShadowSize")
    static let subShadowColorString = Key("subShadowColorString")
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
    static let showBufferingThrobber = Key("showBufferingThrobber")
    static let showSeekingThrobber = Key("showSeekingThrobber")
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
    static let playbackSpeedScrollAmount = Key("playbackSpeedScrollAmount")
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

    /** Internal */
    static let iinaEnablePluginSystem = Key("iinaEnablePluginSystem")

    /// Workaround for issue [#4688](https://github.com/iina/iina/issues/4688)
    /// - Note: This workaround can cause significant slowdown at startup if the list of recent documents contains files on a mounted
    ///         volume that is unreachable. For this reason the workaround is disabled by default and must be enabled by running the
    ///         following command in [Terminal](https://support.apple.com/guide/terminal/welcome/mac):
    ///         `defaults write com.colliderli.iina enableRecentDocumentsWorkaround true`
    static let enableRecentDocumentsWorkaround = Key("enableRecentDocumentsWorkaround")
    static let recentDocuments = Key("recentDocuments")

    static let enableFFmpegImageDecoder = Key("enableFFmpegImageDecoder")

    /// The belief is that the workaround for issue #3844 that adds a tiny subview to the player window is no longer needed.
    /// To confirm this the workaround is being disabled by default using this preference. Should all go well this workaround will be
    /// removed in the future.
    static let enableHdrWorkaround = Key("enableHdrWorkaround")

    /// Internal setting to allow disabling the new feature that shows cover artwork in the Now Playing module in case a serious
    /// problem is encountered.
    static let enableNowPlayingArtwork = Key("enableNowPlayingArtwork")

    /// Internal setting to allow disabling the feature that detects when a display is idle and shuts down the display link to save energy
    /// in case a problem is found where the display link is shut down when it is needed.
    static let enableDisplayIdle = Key("enableDisplayIdle")

    /// Workaround for AppKit defect where showWindow moves the window to a different screen (fixed as of macOS Tahoe).
    static let enableWrongScreenWorkaround = Key("enableWrongScreenWorkaround")
  }

  // MARK: - Enums

  enum ActionAfterLaunch: Int, InitializingFromKey, CaseIterable {
    case welcomeWindow = 0
    case openPanel
    case none

    static var defaultValue = ActionAfterLaunch.welcomeWindow

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var description: String {
      switch self {
      case .welcomeWindow: "welcomeWindow"
      case .openPanel: "openPanel"
      case .none: "none"
      }
    }
  }

  enum ArrowButtonAction: Int, InitializingFromKey, CaseIterable {
    case speed = 0
    case playlist = 1
    case seek = 2

    static var defaultValue = ArrowButtonAction.speed

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var description: String {
      switch self {
      case .speed: "speed"
      case .playlist: "playlist"
      case .seek: "seek"
      }
    }
  }

  enum Theme: Int, InitializingFromKey, CaseIterable {
    case dark = 0
    // case ultraDark // 1
    case light = 2
    // case mediumLight // 3
    case system = 4

    static var defaultValue = Theme.dark

    init?(key: Key) {
      let value = Preference.integer(for: key)
      if value == 1 || value == 3 {
        return nil
      }
      self.init(rawValue: Preference.integer(for: key))
    }

    var description: String {
      switch self {
      case .dark: "dark"
      case .light: "light"
      case .system: "system"
      }
    }
  }

  enum OSCPosition: Int, InitializingFromKey, CaseIterable {
    case floating = 0
    case top
    case bottom

    static var defaultValue = OSCPosition.floating

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var description: String {
      switch self {
      case .floating: "floating"
      case .top: "top"
      case .bottom: "bottom"
      }
    }
  }

  enum SeekOption: Int, InitializingFromKey, CaseIterable {
    case relative = 0
    case exact
    case auto

    static var defaultValue = SeekOption.relative

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var description: String {
      switch self {
      case .relative: "relative"
      case .exact: "exact"
      case .auto: "auto"
      }
    }
  }

  enum MouseClickAction: Int, InitializingFromKey, CaseIterable {
    case none = 0
    case fullscreen
    case pause
    case hideOSC
    case togglePIP
    case abLoop
    case resetSpeed

    static var defaultValue = MouseClickAction.none

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var description: String {
      switch self {
      case .none: "none"
      case .fullscreen: "fullscreen"
      case .pause: "pause"
      case .hideOSC: "hideOSC"
      case .togglePIP: "togglePIP"
      case .abLoop: "abLoop"
      case .resetSpeed: "resetSpeed"
      }
    }
  }

  enum ScrollAction: Int, InitializingFromKey, CaseIterable {
    case volume = 0
    case seek = 1
    case none = 2
    // case passToMpv = 3
    case playbackSpeed = 4

    static var defaultValue = ScrollAction.volume

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var description: String {
      switch self {
      case .volume: "volume"
      case .seek: "seek"
      case .none: "none"
      case .playbackSpeed: "playbackSpeed"
      }
    }
  }

  enum PinchAction: Int, InitializingFromKey, CaseIterable {
    case windowSize = 0
    case fullscreen
    case none

    static var defaultValue = PinchAction.windowSize

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var description: String {
      switch self {
      case .windowSize: "windowSize"
      case .fullscreen: "fullscreen"
      case .none: "none"
      }
    }
  }

  enum IINAAutoLoadAction: Int, InitializingFromKey, CaseIterable {
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

    var description: String {
      switch self {
      case .disabled: "disabled"
      case .mpvFuzzy: "mpvFuzzy"
      case .iina: "iina"
      }
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

    var description: String {
      switch self {
      case .no: "no"
      case .exact: "exact"
      case .fuzzy: "fuzzy"
      case .all: "all"
      }
    }
  }

  /// Enum values for the IINA settings that correspond to the `mpv`
  /// [sub-ass-override](https://mpv.io/manual/stable/#options-sub-ass-override) and
  /// [secondary-sub-ass-override](https://mpv.io/manual/stable/#options-secondary-sub-ass-override) options.
  ///- Important: In order to preserve backward compatibility with enum values stored in user's settings `scale` and `no`were
  ///     added to the end of the enumeration. This is why the constants are not ordered from least impactful to most impactful.
  enum SubOverrideLevel: Int, InitializingFromKey, CaseIterable {
    case yes = 0
    case force
    case strip
    case scale
    case no

    static var defaultValue = SubOverrideLevel.scale

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var description: String {
      switch self {
      case .yes: "yes"
      case .force : "force"
      case .strip: "strip"
      case .scale: "scale"
      case .no: "no"
      }
    }
  }

  enum SubAlignX: Int, InitializingFromKey, CaseIterable {
    case left = 0
    case center
    case right

    static var defaultValue = SubAlignX.center

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var description: String {
      switch self {
      case .left: "left"
      case .center: "center"
      case .right: "right"
      }
    }
  }

  enum SubAlignY: Int, InitializingFromKey, CaseIterable {
    case top = 0
    case center
    case bottom

    static var defaultValue = SubAlignY.bottom

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var description: String {
      switch self {
      case .top: "top"
      case .center: "center"
      case .bottom: "bottom"
      }
    }
  }

  enum RTSPTransportation: Int, InitializingFromKey, CaseIterable {
    case lavf = 0
    case tcp
    case udp
    case http

    static var defaultValue = RTSPTransportation.tcp

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var description: String {
      switch self {
      case .lavf: "lavf"
      case .tcp: "tcp"
      case .udp: "udp"
      case .http: "http"
      }
    }
  }

  enum ScreenshotFormat: Int, InitializingFromKey, CaseIterable {
    case png = 0
    case jpg
    case jpeg
    case webp
    case jxl

    static var defaultValue = ScreenshotFormat.png

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var description: String {
      switch self {
      case .png: "png"
      case .jpg: "jpg"
      case .jpeg: "jpeg"
      case .webp: "webp"
      case .jxl: "jxl"
      }
    }
  }

  enum HardwareDecoderOption: Int, InitializingFromKey, CaseIterable {
    case disabled = 0
    case auto
    case autoCopy

    static var defaultValue = HardwareDecoderOption.auto

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var description: String {
      switch self {
      case .disabled: "no"
      case .auto: "auto"
      case .autoCopy: "auto-copy"
      }
    }

    var localizedDescription: String {
      NSLocalizedString("hwdec." + description, comment: description)
    }
  }

  enum ToneMappingAlgorithmOption: Int, InitializingFromKey, CaseIterable {
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

    var description: String {
      switch self {
      case .auto: "auto"
      case .clip: "clip"
      case .mobius: "mobius"
      case .reinhard: "reinhard"
      case .hable: "hable"
      case .bt_2390: "bt.2390"
      case .gamma: "gamma"
      case .linear: "linear"
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

    var description: String {
      switch self {
      case .always: "always"
      case .onlyWhenOpen: "onlyWhenOpen"
      case .never: "never"
      }
    }
  }

  enum ResizeWindowOption: Int, InitializingFromKey, CaseIterable {
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
      case .fitScreen: -1
      case .videoSize05: 0.5
      case .videoSize10: 1
      case .videoSize15: 1.5
      case .videoSize20: 2
      }
    }

    var description: String { String(ratio) }
  }

  enum WindowBehaviorWhenPip: Int, InitializingFromKey, CaseIterable {
    case doNothing = 0
    case hide
    case minimize

    static var defaultValue = WindowBehaviorWhenPip.doNothing

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var description: String {
      switch self {
      case .doNothing: "doNothing"
      case .hide: "hide"
      case .minimize: "minimize"
      }
    }
  }

  enum ToolBarButton: Int, CustomStringConvertible {
    case settings = 0
    case playlist
    case pip
    case fullScreen
    case musicMode
    case subTrack
    case screenshot
    case plugins

    var description: String {
      switch self {
      case .settings: "settings"
      case .playlist: "playlist"
      case .pip: "pip"
      case .fullScreen: "fullScreen"
      case .musicMode: "musicMode"
      case .subTrack: "subTrack"
      case .screenshot: "screenshot"
      case .plugins: "plugins"
      }
    }

    private func makeSymbol(_ names: [String], _ fallbackImage: NSImage.Name) -> NSImage {
        guard #available(macOS 14.0, *) else { return NSImage(named: fallbackImage)! }
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        return NSImage.sf(names, withConfiguration: configuration)!
      }

    func image() -> NSImage {
      switch self {
      case .settings: return makeSymbol(["gearshape"], NSImage.actionTemplateName)
      case .playlist: return makeSymbol(["list.bullet.rectangle", "list.bullet"], "playlist")
      case .pip: return makeSymbol(["pip.enter"], "pip")
      case .fullScreen: return makeSymbol(["arrow.up.backward.and.arrow.down.forward.rectangle", "arrow.up.left.and.arrow.down.right"], "fullscreen")
      case .musicMode: return makeSymbol(["music.microphone"], "toggle-album-art")
      case .subTrack: return makeSymbol(["captions.bubble.fill"], "sub-track")
      case .screenshot: return makeSymbol(["camera.shutter.button"], "screenshot")
      case .plugins: return makeSymbol(["puzzlepiece.extension"], "plugin")
      }
    }

    func alternateImage() -> NSImage? {
      switch self {
      case .settings: return makeSymbol(["gearshape.fill"], NSImage.actionTemplateName)
      case .playlist: return makeSymbol(["list.bullet.rectangle.fill", "list.bullet"], "playlist")
      case .pip: return makeSymbol(["pip.exit"], "pip")
      case .fullScreen: return makeSymbol(["arrow.down.forward.and.arrow.up.backward.rectangle", "arrow.down.right.and.arrow.up.left"], "fullscreen")
      case .plugins: return makeSymbol(["puzzlepiece.extension.fill"], "plugin")
      default: return nil
      }
    }

    func localizedDescription() -> String {
      let key: String
      switch self {
      case .settings: key = "settings"
      case .playlist: key = "playlist"
      case .pip: key = "pip"
      case .fullScreen: key = "full_screen"
      case .musicMode: key = "music_mode"
      case .subTrack: key = "sub_track"
      case .screenshot: key = "screenshot"
      case .plugins: key = "plugins"
      }
      return NSLocalizedString("osc_toolbar.\(key)", comment: key)
    }

    // Width will be identical
    static let frameSize: CGFloat = 24
    // Reduced size for floating OSC with five buttons
    static let compactFrameWidth: CGFloat = 20

  }

  enum ReplayGainOption: Int, InitializingFromKey, CaseIterable {
    case no = 0
    case track
    case album

    static var defaultValue = ReplayGainOption.no

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var description: String {
      switch self {
      case .no: "no"
      case .track : "track"
      case .album: "album"
      }
    }
  }

  enum GaplessAudioOption: Int, InitializingFromKey, CaseIterable {
    case disabled = 0
    case weak
    case strong

    static var defaultValue = GaplessAudioOption.weak

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var localizedDescription: String {
      NSLocalizedString("gaplessAudio." + description, comment: description)
    }

    var description: String {
      switch self {
      case .disabled: "no"
      case .weak : "weak"
      case .strong: "yes"
      }
    }
  }

  enum DefaultRepeatMode: Int, InitializingFromKey, CaseIterable {
    case playlist = 0
    case file

    static var defaultValue = DefaultRepeatMode.playlist

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var description: String {
      switch self {
      case .playlist: "playlist"
      case .file : "file"
      }
    }
  }

  // MARK: - Getters

  static var unlockWindowAspectRatio: Bool {
    Preference.bool(for: .unlockWindowAspectRatio) || !Preference.bool(for: .edgeToEdgeVideo)
  }

  // MARK: - Defaults

  static let defaultPreference: [Preference.Key: Any] = [
    .receiveBetaUpdate: false,
    .actionAfterLaunch: ActionAfterLaunch.welcomeWindow.rawValue,
    .alwaysOpenInNewWindow: true,
    .groupSimultaneousOpensInPlaylist: false,
    .allowDuplicatePlayers: false,
    .enableCmdN: false,
    .recordPlaybackHistory: true,
    .recordRecentFiles: true,
    .trackAllFilesInRecentOpenMenu: true,
    .controlBarPositionHorizontal: Float(0.5),
    .controlBarPositionVertical: Float(0.1),
    .controlBarStickToCenter: true,
    .controlBarAutoHideTimeout: Float(2.5),
    .enableControlBarAutoHide: true,
    .controlBarToolbarButtons: [ToolBarButton.plugins.rawValue, ToolBarButton.pip.rawValue, ToolBarButton.playlist.rawValue, ToolBarButton.settings.rawValue],
    .oscPosition: OSCPosition.floating.rawValue,
    .disablePlaySliderScrolling: false,
    .disableVolumeSliderScrolling: false,
    .playlistWidth: 270,
    .prefetchPlaylistVideoDuration: true,
    .themeMaterial: Theme.dark.rawValue,
    .enableOSD: true,
    .disableOSDFileStartMsg: false,
    .disableOSDPauseResumeMsgs: false,
    .disableOSDSeekMsg: false,
    .disableOSDSpeedMsg: false,
    .osdAutoHideTimeout: Float(1),
    .osdTextSize: Float(20),
    .softVolume: 100,
    .arrowButtonAction: ArrowButtonAction.speed.rawValue,
    .pauseWhenOpen: false,
    .fullScreenWhenOpen: false,
    .useLegacyFullScreen: false,
    .showChapterPos: false,
    .resumeLastPosition: true,
    .preventScreenSaver: true,
    .allowScreenSaverForAudio: false,
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

    .autoRepeat: false,
    .defaultRepeatMode: DefaultRepeatMode.playlist.rawValue,

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
    .thumbnailWidth: 120,
    .autoSwitchToMusicMode: true,
    .musicModeShowPlaylist: false,
    .musicModeShowAlbumArt: true,
    .displayTimeAndBatteryInFullScreen: false,

    .windowBehaviorWhenPip: WindowBehaviorWhenPip.doNothing.rawValue,
    .pauseWhenPip: false,
    .togglePipByMinimizingWindow: false,
    .togglePipByMinimizingWindowForVideoOnly: false,
    .disableAnimations: false,
    .unlockWindowAspectRatio: false,
    .compactUI: false,
    .edgeToEdgeVideo: true,

    .videoThreads: 0,
    .hardwareDecoder: HardwareDecoderOption.auto.rawValue,
    .forceDedicatedGPU: false,
    .loadIccProfile: true,
    .enableHdrSupport: true,
    .enableToneMapping: false,
    .toneMappingTargetPeak: 0,
    .toneMappingAlgorithm: ToneMappingAlgorithmOption.defaultValue.rawValue,
    .audioDriverEnableAVFoundation: false,
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
    .replayGain: ReplayGainOption.no.rawValue,
    .replayGainPreamp: 0,
    .replayGainClip: false,
    .replayGainFallback: 0,
    .gaplessAudio: GaplessAudioOption.weak.rawValue,

    .subAutoLoadIINA: IINAAutoLoadAction.iina.rawValue,
    .subAutoLoadPriorityString: "",
    .subAutoLoadSearchPath: "./*",
    .ignoreAssStyles: false,
    .subOverrideLevel: SubOverrideLevel.scale.rawValue,
    .secondarySubOverrideLevel: SubOverrideLevel.scale.rawValue,
    .subTextFont: Constants.String.mpvDefaultFont,
    .subTextSize: Float(55),
    .subTextColorString: NSColor.white.usingColorSpace(.deviceRGB)!.mpvColorString,
    .subBgColorString: NSColor.clear.usingColorSpace(.deviceRGB)!.mpvColorString,
    .subBold: false,
    .subItalic: false,
    .subBlur: Float(0),
    .subSpacing: Float(0),
    .subBorderSize: Float(3),
    .subBorderColorString: NSColor.black.usingColorSpace(.deviceRGB)!.mpvColorString,
    .subShadowSize: Float(0),
    .subShadowColorString: NSColor.clear.usingColorSpace(.deviceRGB)!.mpvColorString,
    .subAlignX: SubAlignX.center.rawValue,
    .subAlignY: SubAlignY.bottom.rawValue,
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
    .showBufferingThrobber: true,
    .showSeekingThrobber: true,
    .userAgent: "",
    .transportRTSPThrough: RTSPTransportation.tcp.rawValue,
    .ytdlEnabled: true,
    .ytdlSearchPath: "",
    .ytdlRawOptions: "",
    .httpProxy: "",

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
    .playbackSpeedScrollAmount: 3,
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

    .enableRecentDocumentsWorkaround: false,
    .recentDocuments: [Any](),

    .enableFFmpegImageDecoder: true,
    .enableHdrWorkaround: false,
    .enableNowPlayingArtwork: true,
    .enableDisplayIdle: true,
    .enableWrongScreenWorkaround: true
  ]


  static private let ud = UserDefaults.standard

  static func object(for key: Key) -> Any? { ud.object(forKey: key.rawValue) }

  static func array(for key: Key) -> [Any]? { ud.array(forKey: key.rawValue) }

  static func url(for key: Key) -> URL? { ud.url(forKey: key.rawValue) }

  static func dictionary(for key: Key) -> [String : Any]? { ud.dictionary(forKey: key.rawValue) }

  static func string(for key: Key) -> String? { ud.string(forKey: key.rawValue) }

  static func stringArray(for key: Key) -> [String]? { ud.stringArray(forKey: key.rawValue) }

  static func data(for key: Key) -> Data? { ud.data(forKey: key.rawValue) }

  static func bool(for key: Key) -> Bool { ud.bool(forKey: key.rawValue) }

  static func integer(for key: Key) -> Int { ud.integer(forKey: key.rawValue) }

  static func float(for key: Key) -> Float { ud.float(forKey: key.rawValue) }

  static func double(for key: Key) -> Double { ud.double(forKey: key.rawValue) }

  static func value(for key: Key) -> Any? { ud.value(forKey: key.rawValue) }

  static func set(_ value: Bool, for key: Key) { ud.set(value, forKey: key.rawValue) }

  static func set(_ value: Int, for key: Key) { ud.set(value, forKey: key.rawValue) }

  static func set(_ value: String, for key: Key) { ud.set(value, forKey: key.rawValue) }

  static func set(_ value: Float, for key: Key) { ud.set(value, forKey: key.rawValue) }

  static func set(_ value: Double, for key: Key) { ud.set(value, forKey: key.rawValue) }

  static func set(_ value: URL, for key: Key) { ud.set(value, forKey: key.rawValue) }

  static func set(_ value: Any?, for key: Key) { ud.set(value, forKey: key.rawValue) }

  static func `enum`<T: InitializingFromKey>(for key: Key) -> T {
    T.init(key: key) ?? T.defaultValue
  }

  // MARK: - Logging

  /// Log the value of settings that have been changed from their default value.
  ///
  /// These log messages are intended to be used by developers, not the user, so not all settings that have been changed are logged,
  /// ones not of interest to developers are not logged:
  /// - assrtToken Sensitive information
  /// - controlBarPositionHorizontal Not of interest, frequently changed
  /// - controlBarPositionVertical Not of interest, frequently changed
  /// - musicModeShowAlbumArt Not of interest
  /// - musicModeShowPlaylist Not of interest
  /// - openSubUsername Sensitive information
  /// - playlistWidth Not of interest
  /// - recentDocuments Sensitive information, not of interest, maybe large
  /// - savedAudioFilters Not of interest, maybe large
  /// - savedVideoFilters Not of interest, maybe large
  /// - softVolume Not of interest, frequently changed
  /// - watchProperties Not of interest, maybe large
  ///
  /// Although some values of settings can be determined from log messages emitted by `MPVController` it is easier for
  /// developers to have a concentrated list logged at startup.
  /// - Important: To determine if a setting has changed this method converts the current value of the setting as well as the default
  ///     value for the setting to [AnyHashable](https://developer.apple.com/documentation/swift/anyhashable)
  ///     and then compares the hash values. This filters out many settings that are still set to their default values. _However_ the
  ///     hash values can differ even when the setting is set to the default value. For example, if the user directly sets an IINA setting
  ///     using the [defaults](https://support.apple.com/guide/terminal/edit-property-lists-apda49a1bb2-577e-4721-8f25-ffc0836f6997/mac)
  ///     command like so:
  ///     ```bash
  ///     defaults write com.colliderli.iina enableNowPlayingArtwork true
  ///     ```
  ///     Instead of:
  ///     ```bash
  ///     defaults write com.colliderli.iina enableNowPlayingArtwork -bool true
  ///     ```
  ///     The type of the value will be `NSTaggedPointerString` instead of `__NSCFBoolean` and the hash values will differ
  ///     even when set to the default value. For this reason there is an additional check once the value has been converted to the
  ///     appropriate type and can be directly compared to the default value.
  static func logSettings() {
    guard Logger.isEmitting(.debug) else { return }
    // See the list in this method's documentation comment for why these settings are not logged.
    let doNotLog: [Key] = [.assrtToken, .controlBarPositionHorizontal, .controlBarPositionVertical,
      .musicModeShowAlbumArt, .musicModeShowPlaylist, .openSubUsername, .playlistWidth,
      .recentDocuments, .savedAudioFilters, .savedVideoFilters, .softVolume, .watchProperties]
    // There isn't an enumeration of the settings, so we use the keys in the dictionary containing
    // the defaults. Filter the list to remove the keys we do not want to log and then sort the keys
    // so the log messages are ordered for easier reading.
    let keys = Preference.defaultPreference.keys.filter( { !doNotLog.contains($0) } )
      .sorted(by: { $0.rawValue < $1.rawValue })
    log("Partial list of settings changed from their default values:")
    for key in keys {
      guard let defaultValue = Preference.defaultPreference[key] else {
        // Internal error. Nil is not a valid default value.
        log("Default for \(key) is nil", level: .error)
        continue
      }
      guard let value = Preference.value(for: key) else {
        // Internal error. All settings must have defaults.
        log("Value for \(key) is nil", level: .error)
        continue
      }
      // Only the value of recentDocuments which is of type Array<Any> cannot be cast to
      // AnyHashable. As that setting is not logged we do not bother to exclude that key.
      guard let hashableDefault = defaultValue as? AnyHashable else {
        log("Default for \(key) is of type \(type(of: defaultValue)) and cannot be cast to AnyHashable",
            level: .error)
        continue
      }
      guard let hashableValue = value as? AnyHashable else {
        log("Value for \(key) is of type \(type(of: value)) and cannot be cast to AnyHashable",
            level: .error)
        continue
      }
      // NOTE that if the hash does not match may not mean the setting is not set to the default.
      // See the discussion in this method's documentation comment. This check is still useful as it
      // avoids the work to convert the value and its default to their respective type and then into
      // a string.
      guard hashableValue.hashValue != hashableDefault.hashValue else { continue }
      // The values of many settings are not stored in a human friendly representation. The values
      // must be converted to their respective types and then converted to a string.
      let defaultAsString: String
      let valueAsString: String
      // Other than the first entry the cases in the switch are ordered based on the name of the
      // type of the value.
      switch key {
      case .assrtToken, .openSubUsername:
        // These keys should have been filtered above, so this code should never be executed. This
        // code makes sure that if a change to the code causes these keys to be logged the value
        // will be hidden.
        defaultAsString = ""
        valueAsString = "<private>"
      case .actionAfterLaunch:
        defaultAsString = String(describing: ActionAfterLaunch.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as ActionAfterLaunch)
      case .arrowButtonAction:
        defaultAsString = String(describing: ArrowButtonAction.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as ArrowButtonAction)
      case .allowScreenSaverForAudio,
           .alwaysFloatOnTop,
           .alwaysOpenInNewWindow,
           .alwaysShowOnTopIcon,
           .audioDriverEnableAVFoundation,
           .autoRepeat,
           .autoSearchOnlineSub,
           .autoSwitchToMusicMode,
           .blackOutMonitor,
           .controlBarStickToCenter,
           .disableAnimations,
           .disableOSDFileStartMsg,
           .disableOSDPauseResumeMsgs,
           .disableOSDSeekMsg,
           .disableOSDSpeedMsg,
           .disablePlaySliderScrolling,
           .disableVolumeSliderScrolling,
           .displayInLetterBox,
           .displayKeyBindingRawValues,
           .displayTimeAndBatteryInFullScreen,
           .enableAdvancedSettings,
           .enableCache,
           .enableCmdN,
           .enableControlBarAutoHide,
           .enableDisplayIdle,
           .enableFFmpegImageDecoder,
           .enableHdrSupport,
           .enableHdrWorkaround,
           .enableInitialVolume,
           .enableLogging,
           .enableNowPlayingArtwork,
           .enableOSD,
           .enableRecentDocumentsWorkaround,
           .enableThumbnailForRemoteFiles,
           .enableThumbnailPreview,
           .enableToneMapping,
           .enableWrongScreenWorkaround,
           .followGlobalSeekTypeWhenAdjustSlider,
           .forceDedicatedGPU,
           .fullScreenWhenOpen,
           .ignoreAssStyles,
           .iinaEnablePluginSystem,
           .keepOpenOnFileEnd,
           .loadIccProfile,
           .musicModeShowAlbumArt,
           .musicModeShowPlaylist,
           .pauseWhenGoesToSleep,
           .pauseWhenInactive,
           .pauseWhenLeavingFullScreen,
           .pauseWhenMinimized,
           .pauseWhenOpen,
           .pauseWhenPip,
           .playlistAutoAdd,
           .playlistAutoPlayNext,
           .playlistShowMetadata,
           .playlistShowMetadataInMusicMode,
           .playWhenEnteringFullScreen,
           .prefetchPlaylistVideoDuration,
           .preventScreenSaver,
           .quitWhenNoOpenedWindow,
           .receiveBetaUpdate,
           .recordPlaybackHistory,
           .recordRecentFiles,
           .replayGainClip,
           .resumeLastPosition,
           .scaleRemainingTime,
           .screenshotCopyToClipboard,
           .screenshotIncludeSubtitle,
           .screenshotSaveToFile,
           .screenshotShowPreview,
           .showBufferingThrobber,
           .showChapterPos,
           .showRemainingTime,
           .showSeekingThrobber,
           .spdifAC3,
           .spdifDTS,
           .spdifDTSHD,
           .subBold,
           .subItalic,
           .subScaleWithWindow,
           .togglePipByMinimizingWindow,
           .togglePipByMinimizingWindowForVideoOnly,
           .touchbarShowRemainingTime,
           .trackAllFilesInRecentOpenMenu,
           .useAppleRemote,
           .useLegacyFullScreen,
           .useMediaKeys,
           .useMpvOsd,
           .usePhysicalResolution,
           .useUserDefinedConfDir,
           .videoViewAcceptsFirstMouse,
           .ytdlEnabled:
        guard let defaultAsBool = defaultValue as? Bool else {
          // Should not occur. Internal error.
          log("Default for \(key) is of type \(type(of: value)) and cannot be cast to Bool",
              level: .error)
          continue
        }
        defaultAsString = String(defaultAsBool)
        valueAsString = String(Preference.bool(for: key))
      case .defaultRepeatMode:
        defaultAsString = String(describing: DefaultRepeatMode.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as DefaultRepeatMode)
      case .controlBarAutoHideTimeout,
           .controlBarPositionHorizontal,
           .controlBarPositionVertical,
           .osdAutoHideTimeout,
           .osdTextSize,
           .subBlur,
           .subBorderSize,
           .subMarginX,
           .subMarginY,
           .subPos,
           .subShadowSize,
           .subSpacing,
           .subTextSize:
        guard let defaultAsFloat = defaultValue as? Float else {
          // Should not occur. Internal error.
          log("Default for \(key) is of type \(type(of: value)) and cannot be cast to Float",
              level: .error)
          continue
        }
        defaultAsString = String(defaultAsFloat)
        valueAsString = String(Preference.float(for: key))
      case .gaplessAudio:
        defaultAsString = String(describing: GaplessAudioOption.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as GaplessAudioOption)
      case .hardwareDecoder:
        defaultAsString = String(describing: HardwareDecoderOption.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as HardwareDecoderOption)
      case .subAutoLoadIINA:
        defaultAsString = String(describing: IINAAutoLoadAction.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as IINAAutoLoadAction)
      case .logLevel:
        defaultAsString = String(describing: Logger.Level.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as Logger.Level)
      case .doubleClickAction,
           .forceTouchAction,
           .middleClickAction,
           .rightClickAction,
           .singleClickAction:
        defaultAsString = String(describing: MouseClickAction.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as MouseClickAction)
      case .oscPosition:
        defaultAsString = String(describing: OSCPosition.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as OSCPosition)
      case .pinchAction:
        defaultAsString = String(describing: PinchAction.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as PinchAction)
      case .replayGain:
        defaultAsString = String(describing: ReplayGainOption.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as ReplayGainOption)
      case .resizeWindowOption:
        defaultAsString = String(describing: ResizeWindowOption.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as ResizeWindowOption)
      case .resizeWindowTiming:
        defaultAsString = String(describing: ResizeWindowTiming.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as ResizeWindowTiming)
      case .transportRTSPThrough:
        defaultAsString = String(describing: RTSPTransportation.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as RTSPTransportation)
      case .screenshotFormat:
        defaultAsString = String(describing: ScreenshotFormat.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as ScreenshotFormat)
      case .horizontalScrollAction, .verticalScrollAction:
        defaultAsString = String(describing: ScrollAction.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as ScrollAction)
      case .useExactSeek:
        defaultAsString = String(describing: SeekOption.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as SeekOption)
      case.userOptions:
        defaultAsString = "[]"
        guard let valueAsArray = value as? [[String]] else {
          // Should not occur. Internal error.
          log("Default for \(key) is of type \(type(of: value)) and cannot be cast to [[String]]",
              level: .error)
          continue
        }
        valueAsString = valueAsArray.reduce("[", { $0 + $1.joined(separator: " = ") }) + "]"
      case .subAlignX:
        defaultAsString = String(describing: SubAlignX.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as SubAlignX)
      case .subAlignY:
        defaultAsString = String(describing: SubAlignY.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as SubAlignY)
      case .secondarySubOverrideLevel, .subOverrideLevel:
        defaultAsString = String(describing: SubOverrideLevel.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as SubOverrideLevel)
      case .themeMaterial:
        defaultAsString = String(describing: Theme.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as Theme)
      case .toneMappingAlgorithm:
        defaultAsString = String(describing: ToneMappingAlgorithmOption.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as ToneMappingAlgorithmOption)
      case .controlBarToolbarButtons:
        // The value is an array of ToolBarButton enum values stored as integers.
        guard let defaultAsArray = defaultValue as? [Int] else {
          // Should not occur. Internal error.
          log("Default for \(key) is of type \(type(of: value)) and cannot be cast to [Int]",
              level: .error)
          continue
        }
        defaultAsString = "[" + defaultAsArray.compactMap({
          guard let button = ToolBarButton.init(rawValue: $0) else { return "unknown(\($0))" }
          return String(describing: button)
        }).joined(separator: ", ") + "]"
        guard let valueAsArray = value as? [Int] else {
          // Should not occur. Internal error.
          log("Value for \(key) is of type \(type(of: value)) and cannot be cast to [Int]",
              level: .error)
          continue
        }
        valueAsString = "[" + valueAsArray.compactMap({
          guard let button = ToolBarButton.init(rawValue: $0) else { return "unknown(\($0))" }
          return String(describing: button)
        }).joined(separator: ", ") + "]"
      case .windowBehaviorWhenPip:
        defaultAsString = String(describing: WindowBehaviorWhenPip.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as WindowBehaviorWhenPip)
      default:
        // The remaining settings have values that are integers or strings and can be directly
        // converted to strings.
        defaultAsString = String(describing: defaultValue)
        valueAsString = String(describing: value)
      }
      // Now that the value and the default have both been converted to their human readable form
      // we can deterministically check if the setting has been changed from its default.
      guard valueAsString != defaultAsString else { continue }
      // To make the output easier to read we don't include the default value of boolean settings as
      // it is obviously the opposite of the current value of the setting. Defaults that are empty
      // strings or arrays are also not included to reduce clutter.
      switch defaultAsString {
      case "", "false", "true", "[]":
        log("\(key.rawValue) = \(valueAsString)")
      default:
        log("\(key.rawValue) = \(valueAsString) (default: \(defaultAsString))")
      }
    }
  }

  private static let subsystem = Logger.makeSubsystem("settings", ["gearshape"])

  /// Log a message using the `settings` logger subsystem.
  ///
  /// This is a wrapper function that merely avoids the need to include the `settings` subsystem in calls to the logger.
  /// - Important: As settings control the logger use of logging by this class _must not_ occur during class initialization.
  /// - Parameters:
  ///   - message: A closure that when executed gives the message to log.
  ///   - level: The log level of the message.
  private static func log(_ message: @autoclosure () -> String, level: Logger.Level = .debug) {
    Logger.log(message, level: level, subsystem: subsystem)
  }
}
