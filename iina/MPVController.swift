//
//  MPVController.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import JavaScriptCore
import VideoToolbox

fileprivate let yes_str = "yes"
fileprivate let no_str = "no"

/// Change this variable to adjust mpv log level.
///
/// Available levels:
/// |  Level  | Output  |
/// | --- | --- |
/// | no  | complete silence |
/// | fatal | fatal messages only |
/// | error | error messages |
/// | warn  | warning messages |
/// | info | informational message |
/// | status | status messages (default) |
/// | v | verbose messages |
/// | debug | debug messages |
/// | trace | very noisy debug messages |
/// - Important: The mpv event system uses an event queue of limited size. If events are not read quickly enough the queue can
///     overflow resulting in events being dropped. Loss of events can trigger severe malfunctions. IINA's ability to include mpv log
///     messages in the IINA log file relies up the mpv `MPV_EVENT_LOG_MESSAGE` event. There is a danger that mpv will emit log
///     messages at a rate that exceeds IINA's ability to empty the event queue before it overflows. For this reason IINA intentionally
///     limits the mpv log level to `warn`. If you change the level to debug a problem be aware that the event queue could overflow
///     and drop events resulting in odd behavior.
fileprivate let MPVLogLevel = "warn"
fileprivate let logLevelMap: [String: Logger.Level] = ["fatal": .error,
                                                       "error": .error,
                                                       "warn": .warning,
                                                       "info": .debug,
                                                       "v": .verbose,
                                                       "debug": .debug,
                                                       "trace": .verbose]

// FIXME: should be moved to a separated file
struct MPVHookValue {
  typealias Block = (@escaping () -> Void) -> Void

  var id: String?
  var isJavascript: Bool
  var block: Block?
  var jsBlock: JSManagedValue!
  var context: JSContext!

  init(withIdentifier id: String, jsContext context: JSContext, jsBlock block: JSValue, owner: JavascriptAPIMpv) {
    self.id = id
    self.isJavascript = true
    self.jsBlock = JSManagedValue(value: block)
    self.context = context
    context.virtualMachine.addManagedReference(self.jsBlock, withOwner: owner)
  }

  init(withBlock block: @escaping Block) {
    self.isJavascript = false
    self.block = block
  }

  func call(withNextBlock next: @escaping () -> Void) {
    if isJavascript {
      let block: @convention(block) () -> Void = { next() }
      guard let callback = jsBlock.value else {
        next()
        return
      }
      callback.call(withArguments: [JSValue(object: block, in: context)!])
      if callback.forProperty("constructor")?.forProperty("name")?.toString() != "AsyncFunction" {
        next()
      }
    } else {
      block!(next)
    }
  }
}

// Global functions

class MPVController: NSObject {
  struct UserData {
    static let screenshot: UInt64 = 1000000
  }

  // The mpv_handle
  var mpv: OpaquePointer!
  var mpvRenderContext: OpaquePointer?

  private var openGLContext: CGLContextObj! = nil

  /// [DispatchQueue](https://developer.apple.com/documentation/dispatch/dispatchqueue) for reading `mpv`
  /// events.
  /// - Important: The mpv event system uses an event queue of limited size. If events are not read quickly enough with
  ///     `mpv_wait_event` the queue can overflow resulting in events being dropped. IINA can recover from the loss of some
  ///     types of mpv events, but certain mpv events are critical. If a critical event is discarded IINA will experience severe
  ///     malfunctions. For this reason this queue _must only_ be used for reading events. This also means processing of events
  ///     _must not be performed_ using this queue unless the work required can _always_ be accomplished _quickly_. Otherwise
  ///     processing _must be_ queued to another dispatch queue.
  /// - Important: To avoid using locking to prevent data races the convention is that processing involving data used by the UI is
  ///     never performed while running on this queue's thread and instead is queued for processing by the main thread .
  private lazy var queue = DispatchQueue(label: "com.colliderli.iina.controller",
                                         qos: .userInitiated)

  unowned let player: PlayerCore

  var needRecordSeekTime: Bool = false
  var recordedSeekStartTime: CFTimeInterval = 0
  var recordedSeekTimeListener: ((Double) -> Void)?

  @Atomic private var hooks: [UInt64: MPVHookValue] = [:]
  private var hookCounter: UInt64 = 1

  let observeProperties: [String: mpv_format] = [
    MPVProperty.trackList: MPV_FORMAT_NONE,
    MPVProperty.vf: MPV_FORMAT_NONE,
    MPVProperty.af: MPV_FORMAT_NONE,
    MPVProperty.audioDeviceList: MPV_FORMAT_NONE,
    MPVOption.TrackSelection.vid: MPV_FORMAT_INT64,
    MPVOption.TrackSelection.aid: MPV_FORMAT_INT64,
    MPVOption.TrackSelection.sid: MPV_FORMAT_INT64,
    MPVOption.Subtitles.secondarySid: MPV_FORMAT_INT64,
    MPVOption.PlaybackControl.pause: MPV_FORMAT_FLAG,
    MPVOption.PlaybackControl.loopPlaylist: MPV_FORMAT_STRING,
    MPVOption.PlaybackControl.loopFile: MPV_FORMAT_STRING,
    MPVProperty.chapter: MPV_FORMAT_INT64,
    MPVOption.Video.deinterlace: MPV_FORMAT_FLAG,
    MPVOption.Video.hwdec: MPV_FORMAT_STRING,
    MPVOption.Video.videoRotate: MPV_FORMAT_INT64,
    MPVOption.Audio.mute: MPV_FORMAT_FLAG,
    MPVOption.Audio.volume: MPV_FORMAT_DOUBLE,
    MPVOption.Audio.audioDelay: MPV_FORMAT_DOUBLE,
    MPVOption.PlaybackControl.speed: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.secondarySubDelay: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.secondarySubPos: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.secondarySubVisibility: MPV_FORMAT_FLAG,
    MPVOption.Subtitles.subDelay: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.subPos: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.subScale: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.subVisibility: MPV_FORMAT_FLAG,
    MPVOption.Equalizer.contrast: MPV_FORMAT_INT64,
    MPVOption.Equalizer.brightness: MPV_FORMAT_INT64,
    MPVOption.Equalizer.gamma: MPV_FORMAT_INT64,
    MPVOption.Equalizer.hue: MPV_FORMAT_INT64,
    MPVOption.Equalizer.saturation: MPV_FORMAT_INT64,
    MPVOption.Window.fullscreen: MPV_FORMAT_FLAG,
    MPVOption.Window.ontop: MPV_FORMAT_FLAG,
    MPVOption.Window.windowScale: MPV_FORMAT_DOUBLE,
    MPVProperty.mediaTitle: MPV_FORMAT_STRING,
    MPVProperty.videoParamsRotate: MPV_FORMAT_INT64,
    MPVProperty.videoParamsPrimaries: MPV_FORMAT_STRING,
    MPVProperty.videoParamsGamma: MPV_FORMAT_STRING,
    MPVProperty.idleActive: MPV_FORMAT_FLAG,
    MPVProperty.currentAo: MPV_FORMAT_STRING
  ]

  /// Map from mpv codec name to core media video codec types.
  ///
  /// This map only contains the mpv codecs `adjustCodecWhiteList` can remove from the mpv `hwdec-codecs` option.
  /// If any codec types are added then `HardwareDecodeCapabilities` will need to be updated to support them.
  private let mpvCodecToCodecTypes: [String: [CMVideoCodecType]] = [
    "av1": [kCMVideoCodecType_AV1],
    "prores": [kCMVideoCodecType_AppleProRes422, kCMVideoCodecType_AppleProRes422HQ,
               kCMVideoCodecType_AppleProRes422LT, kCMVideoCodecType_AppleProRes422Proxy,
               kCMVideoCodecType_AppleProRes4444, kCMVideoCodecType_AppleProRes4444XQ,
               kCMVideoCodecType_AppleProResRAW, kCMVideoCodecType_AppleProResRAWHQ],
    "vp9": [kCMVideoCodecType_VP9]
  ]

  private let subsystem: Logger.Subsystem

  /// Creates a `MPVController` object.
  /// - Parameters:
  ///   - playerCore: The player this `MPVController` will be associated with.
  init(playerCore: PlayerCore) {
    self.player = playerCore
    subsystem = Logger.makeSubsystem("mpv\(player.playerNumber)", ["building.columns"])
    super.init()
  }

  deinit {
    removeOptionObservers()
  }

  /// Remove codecs from the hardware decoding white list that this Mac does not support.
  ///
  /// As explained in [HWAccelIntro](https://trac.ffmpeg.org/wiki/HWAccelIntro),  [FFmpeg](https://ffmpeg.org/)
  /// will automatically fall back to software decoding. _However_ when it does so `FFmpeg` emits an error level log message
  /// referring to "Failed setup". This has confused users debugging problems. To eliminate the overhead of setting up for hardware
  /// decoding only to have it fail, this method removes codecs from the mpv
  /// [hwdec-codecs](https://mpv.io/manual/stable/#options-hwdec-codecs) option that are known to not have
  /// hardware decoding support on this Mac. This is not comprehensive. This method only covers the recent codecs whose support
  /// for hardware decoding varies among Macs. This merely reduces the dependence upon the FFmpeg fallback to software decoding
  /// feature in some cases.
  /// - ToDo: **REMOVE** workaround for FFmpeg not supporting AV1 hardware decoding when upgrading to a FFmpeg version
  ///         that supports it.
  private func adjustCodecWhiteList() {
    // Allow the user to override this behavior.
    guard !userOptionsContains(MPVOption.Video.hwdecCodecs) else {
      log("""
        Option \(MPVOption.Video.hwdecCodecs) has been set in advanced settings, \
        will not adjust white list
        """)
      return
    }
    guard let whitelist = getString(MPVOption.Video.hwdecCodecs) else {
      // Internal error. Make certain this method is called after mpv_initialize which sets the
      // default value.
      log("Failed to obtain the value of option \(MPVOption.Video.hwdecCodecs)", level: .error)
      return
    }
    log("Hardware decoding whitelist (\(MPVOption.Video.hwdecCodecs)) is set to \(whitelist)")
    var adjusted: [String] = []
    var needsAdjustment = false
    codecLoop: for codec in whitelist.components(separatedBy: ",") {
      guard let codecTypes = mpvCodecToCodecTypes[codec] else {
        // Not a codec this method supports removing. Retain it in the option value.
        adjusted.append(codec)
        continue
      }
      // The mpv codec name can map to multiple codec types. If hardware decoding is supported for
      // any of them retain the codec in the option value.
      for codecType in codecTypes {
        if HardwareDecodeCapabilities.shared.isSupported(codecType) {
          if codecType == kCMVideoCodecType_AV1 {
            // WORKAROUND missing support for AV1 hardware decoding.
            // This Mac supports AV1 hardware decoding, but the version of FFmpeg IINA is using does
            // not. FFmpeg will try to use hardware decoding, which will fail. FFmpeg will then fall
            // back to software decoding. When FFmpeg does this it logs the warning message "Error
            // while decoding frame (hardware decoding)!" which is alarming to users. Prevent this
            // by removing AV1 from the codecs whitelist.
            needsAdjustment = true
            log("FFmpeg does not support av1 hardware decoding")
            continue codecLoop
          }
          adjusted.append(codec)
          continue codecLoop
        }
      }
      needsAdjustment = true
      log("This Mac does not support \(codec) hardware decoding")
    }
    // Only set the option if a change is needed to avoid logging when nothing has changed.
    if needsAdjustment {
      chkErr(setOptionString(MPVOption.Video.hwdecCodecs, adjusted.joined(separator: ",")))
    }
  }

  /// Determine if this Mac has an Apple Silicon chip.
  /// - Returns: `true` if running on a Mac with an Apple Silicon chip, `false` otherwise.
  private func runningOnAppleSilicon() -> Bool {
    var sysinfo = utsname()
    let result = uname(&sysinfo)
    guard result == EXIT_SUCCESS else {
      log("uname failed returning \(result)", level: .error)
      return false
    }
    let data = Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN))
    guard let machine = String(bytes: data, encoding: .ascii) else {
      log("Failed to construct string for sysinfo.machine", level: .error)
      return false
    }
    return machine.starts(with: "arm64")
  }

  /// Apply a workaround for issue [#4486](https://github.com/iina/iina/issues/4486), if needed.
  ///
  /// On Macs with an Intel chip VP9 hardware acceleration is causing a hang in
  ///[VTDecompressionSessionWaitForAsynchronousFrames](https://developer.apple.com/documentation/videotoolbox/1536066-vtdecompressionsessionwaitforasy).
  /// This has been reproduced with FFmpeg and has been reported in ticket [9599](https://trac.ffmpeg.org/ticket/9599).
  ///
  /// The workaround removes VP9 from the value of the mpv [hwdec-codecs](https://mpv.io/manual/master/#options-hwdec-codecs) option,
  /// the list of codecs eligible for hardware acceleration.
  private func applyHardwareAccelerationWorkaround() {
    // The problem is not reproducible under Apple Silicon.
    guard !runningOnAppleSilicon() else {
      log("Running on Apple Silicon, not applying FFmpeg 9599 workaround")
      return
    }
    // Allow the user to override this behavior.
    guard !userOptionsContains(MPVOption.Video.hwdecCodecs) else {
      log("""
        Option \(MPVOption.Video.hwdecCodecs) has been set in advanced settings, \
        not applying FFmpeg 9599 workaround
        """)
      return
    }
    guard let whitelist = getString(MPVOption.Video.hwdecCodecs) else {
      // Internal error. Make certain this method is called after mpv_initialize which sets the
      // default value.
      log("Failed to obtain the value of option \(MPVOption.Video.hwdecCodecs)", level: .error)
      return
    }
    var adjusted: [String] = []
    var needsWorkaround = false
    codecLoop: for codec in whitelist.components(separatedBy: ",") {
      guard codec == "vp9" else {
        adjusted.append(codec)
        continue
      }
      needsWorkaround = true
    }
    if needsWorkaround {
      log("Disabling hardware acceleration for VP9 encoded videos to workaround FFmpeg 9599")
      chkErr(setOptionString(MPVOption.Video.hwdecCodecs, adjusted.joined(separator: ",")))
    }
  }

  /**
   Init the mpv context, set options
   */
  func mpvInit() {
    // Create a new mpv instance and an associated client API handle to control the mpv instance.
    mpv = mpv_create()

    // Record explicit mpv.conf keys BEFORE any forced option is set, so the
    // sentinel can be consulted by the userOptionsContains-style guards below.
    // See SPEC requirement 2 and PLAN Phase 2.
    MPVSentinel.recordFromConfigFiles()

    // User default settings

    if Preference.bool(for: .enableInitialVolume) {
      setUserOption(PK.initialVolume, type: .int, forName: MPVOption.Audio.volume, sync: false,
                    level: .verbose)
    } else {
      setUserOption(PK.softVolume, type: .int, forName: MPVOption.Audio.volume, sync: false,
                    level: .verbose)
    }

    // - Advanced

    // disable internal OSD
    let useMpvOsd = Preference.bool(for: .enableAdvancedSettings) && Preference.bool(for: .useMpvOsd)
    if !useMpvOsd {
      // Skip the override when the user has explicitly set osd-level in
      // mpv.conf (see SPEC requirement 2 / PLAN Phase 2).
      if !MPVSentinel.wasSetInConfig(MPVOption.OSD.osdLevel) {
        chkErr(setOptionString(MPVOption.OSD.osdLevel, "0", level: .verbose))
      }
    } else {
      player.displayOSD = false
    }

    // log
    if Logger.enabled {
      let path = Logger.logDirectory.appendingPathComponent("mpv.log").path
      chkErr(setOptionString(MPVOption.ProgramBehavior.logFile, path, level: .verbose))
    }

    // - General

    let setScreenshotPath = { (key: Preference.Key) -> String in
      let screenshotPath = Preference.string(for: .screenshotFolder)!
      return Preference.bool(for: .screenshotSaveToFile) ?
        NSString(string: screenshotPath).expandingTildeInPath :
        Utility.screenshotCacheURL.path
    }

    setUserOption(PK.screenshotFolder, type: .other, forName: MPVOption.Screenshot.screenshotDir,
                  level: .verbose, transformer: setScreenshotPath)
    setUserOption(PK.screenshotSaveToFile, type: .other, forName: MPVOption.Screenshot.screenshotDir,
                  level: .verbose, transformer: setScreenshotPath)

    setUserOption(PK.screenshotFormat, type: .other, forName: MPVOption.Screenshot.screenshotFormat,
                  verboseIfDefault: true) { key in
      let format: Preference.ScreenshotFormat = Preference.enum(for: key)
      // Workaround for mpv issue  #15107, HDR screenshots are unimplemented (gpu/gpu-next).
      // If the screenshot format is set to JPEG XL then set the screenshot-sw option to yes. This
      // causes the screenshot to be rendered by software instead of the VO. If a HDR video is being
      // displayed in HDR then the resulting screenshot will be HDR.
      self.chkErr(self.setOptionFlag(MPVOption.Screenshot.screenshotSw, format == .jxl,
                                     verboseIfDefault: true))
      return String(describing: format)
    }

    setUserOption(PK.screenshotTemplate, type: .string,
                  forName: MPVOption.Screenshot.screenshotTemplate)

    // SPEC ui-driven-mpv-options Phase 3: screenshot quality/format options
    // wired with skipIfDefault: false so curated defaults are always applied.
    setUserOption(PK.screenshotJpegQuality, type: .int,
                  forName: MPVOption.Screenshot.screenshotJpegQuality, skipIfDefault: false)
    setUserOption(PK.screenshotJpegSourceChroma, type: .bool,
                  forName: MPVOption.Screenshot.screenshotJpegSourceChroma, skipIfDefault: false)
    setUserOption(PK.screenshotPngCompression, type: .int,
                  forName: MPVOption.Screenshot.screenshotPngCompression, skipIfDefault: false)
    setUserOption(PK.screenshotWebpLossless, type: .bool,
                  forName: MPVOption.Screenshot.screenshotWebpLossless, skipIfDefault: false)
    setUserOption(PK.screenshotWebpQuality, type: .int,
                  forName: MPVOption.Screenshot.screenshotWebpQuality, skipIfDefault: false)
    setUserOption(PK.screenshotJxlDistance, type: .int,
                  forName: MPVOption.Screenshot.screenshotJxlDistance, skipIfDefault: false)
    setUserOption(PK.screenshotJxlEffort, type: .int,
                  forName: MPVOption.Screenshot.screenshotJxlEffort, skipIfDefault: false)
    setUserOption(PK.screenshotHighBitDepth, type: .bool,
                  forName: MPVOption.Screenshot.screenshotHighBitDepth, skipIfDefault: false)

    // SPEC ui-driven-mpv-options Phase 3: replaced the hard-forced
    // input-media-keys=no with a setUserOption call so the value is
    // user-configurable through IINA preferences. IINA uses the MediaPlayer
    // Framework for media keys; mpv's own input-media-keys is disabled by
    // default (curated value: no).
    setUserOption(PK.inputMediaKeys, type: .bool, forName: MPVOption.Input.inputMediaKeys,
                  skipIfDefault: false)

    setUserOption(PK.keepOpenOnFileEnd, type: .other, forName: MPVOption.Window.keepOpen,
                  level: .verbose) { key in
      let keepOpen = Preference.bool(for: PK.keepOpenOnFileEnd)
      let keepOpenPl = !Preference.bool(for: PK.playlistAutoPlayNext)
      return keepOpenPl ? "always" : (keepOpen ? "yes" : "no")
    }

    setUserOption(PK.playlistAutoPlayNext, type: .other, forName: MPVOption.Window.keepOpen,
                  level: .verbose) { key in
      let keepOpen = Preference.bool(for: PK.keepOpenOnFileEnd)
      let keepOpenPl = !Preference.bool(for: PK.playlistAutoPlayNext)
      return keepOpenPl ? "always" : (keepOpen ? "yes" : "no")
    }

    // Skip the override when the user has explicitly set
    // watch-later-directory in mpv.conf (see SPEC requirement 2 /
    // PLAN Phase 2).
    if !MPVSentinel.wasSetInConfig("watch-later-directory") {
      chkErr(setOptionString("watch-later-directory", Utility.watchLaterURL.path, level: .verbose))
    }
    // SPEC ui-driven-mpv-options Phase 3: decoupled save-position-on-quit
    // from resumeLastPosition. The legacy resumeLastPosition key now only
    // controls resume-playback (line below). savePositionOnQuit is a new
    // key with curated default false (= no), matching mpv.conf.
    setUserOption(PK.savePositionOnQuit, type: .bool, forName: MPVOption.WatchLater.savePositionOnQuit,
                  skipIfDefault: false)
    setUserOption(PK.resumeLastPosition, type: .bool, forName: MPVOption.WatchLater.resumePlayback,
                  verboseIfDefault: true)

    setUserOption(.initialWindowSizePosition, type: .string, forName: MPVOption.Window.geometry,
                  level: .verbose)

    // SPEC ui-driven-mpv-options Phase 3: force-window as a user-configurable
    // preference. NOT set pre-init here: force-window=immediate (the curated
    // default) makes mpv spawn the VO thread during mpv_initialize, but
    // vo=libmpv requires IINA's render context which doesn't exist until
    // PlayerCore.initVideo() calls mpvInitRendering(). Setting it here
    // produces "vo/libmpv: No render context set" and a fatal -4 later.
    // PlayerCore.openFile() sets force-window=yes, then initVideo() upgrades
    // it to immediate AFTER the render context exists. Both PlayerCore calls
    // are guarded by MPVSentinel + userOptionsContains so a user who has
    // explicitly set force-window in mpv.conf / Additional mpv options keeps
    // their value.

    // - Codec

    setUserOption(PK.videoThreads, type: .int, forName: MPVOption.Video.vdLavcThreads,
                  verboseIfDefault: true)
    setUserOption(PK.audioThreads, type: .int, forName: MPVOption.Audio.adLavcThreads,
                  verboseIfDefault: true)

    setUserOption(PK.hardwareDecoder, type: .other, forName: MPVOption.Video.hwdec,
                  verboseIfDefault: true) { key in
      return String(describing: Preference.enum(for: key) as Preference.HardwareDecoderOption)
    }

    setUserOption(PK.audioLanguage, type: .string, forName: MPVOption.TrackSelection.alang,
                  level: .verbose)
    setUserOption(PK.maxVolume, type: .int, forName: MPVOption.Audio.volumeMax, level: .verbose)

    var spdif: [String] = []
    if Preference.bool(for: PK.spdifAC3) { spdif.append("ac3") }
    if Preference.bool(for: PK.spdifDTS){ spdif.append("dts") }
    if Preference.bool(for: PK.spdifDTSHD) { spdif.append("dts-hd") }
    chkErr(setOptionString(MPVOption.Audio.audioSpdif, spdif.joined(separator: ","),
                           verboseIfDefault: true))

    setUserOption(PK.audioDevice, type: .string, forName: MPVOption.Audio.audioDevice,
                  verboseIfDefault: true)

    setUserOption(PK.replayGain, type: .other, forName: MPVOption.Audio.replaygain,
                  verboseIfDefault: true) { key in
      return String(describing: Preference.enum(for: key) as Preference.ReplayGainOption)
    }
    setUserOption(PK.replayGainPreamp, type: .float, forName: MPVOption.Audio.replaygainPreamp,
                  verboseIfDefault: true)
    setUserOption(PK.replayGainClip, type: .bool, forName: MPVOption.Audio.replaygainClip,
                  verboseIfDefault: true)
    setUserOption(PK.replayGainFallback, type: .float, forName: MPVOption.Audio.replaygainFallback,
                  verboseIfDefault: true)

    setUserOption(PK.gaplessAudio, type: .other, forName: MPVOption.Audio.gaplessAudio,
                  verboseIfDefault: true) { key in
      return String(describing: Preference.enum(for: key) as Preference.GaplessAudioOption)
    }

    // - Sub

    // SPEC ui-driven-mpv-options Phase 3: replaced the hard-forced
    // sub-auto=no with a setUserOption call so the value is
    // user-configurable through IINA preferences. Curated default is "fuzzy".
    setUserOption(PK.subAuto, type: .string, forName: MPVOption.Subtitles.subAuto,
                  skipIfDefault: false)
    chkErr(setOptionalOptionString(MPVOption.Subtitles.subCodepage,
                                   Preference.string(for: .defaultEncoding), verboseIfDefault: true))
    player.info.subEncoding = Preference.string(for: .defaultEncoding)

    let subOverrideHandler: OptionObserverInfo.Transformer = { key in
      String(describing: Preference.enum(for: key) as Preference.SubOverrideLevel)
    }
    setUserOption(PK.subOverrideLevel, type: .other, forName: MPVOption.Subtitles.subAssOverride,
                  verboseIfDefault: true, transformer: subOverrideHandler)
    setUserOption(PK.secondarySubOverrideLevel, type: .other,
                  forName: MPVOption.Subtitles.secondarySubAssOverride, verboseIfDefault: true,
                  transformer: subOverrideHandler)

    setUserOption(PK.subTextFont, type: .string, forName: MPVOption.Subtitles.subFont,
                  verboseIfDefault: true)
    setUserOption(PK.subTextSize, type: .float, forName: MPVOption.Subtitles.subFontSize,
                  verboseIfDefault: true)

    setUserOption(PK.subTextColorString, type: .color, forName: MPVOption.Subtitles.subColor,
                  verboseIfDefault: true)
    setUserOption(PK.subBgColorString, type: .color, forName: MPVOption.Subtitles.subBackColor,
                  verboseIfDefault: true)

    setUserOption(PK.subBold, type: .bool, forName: MPVOption.Subtitles.subBold,
                  verboseIfDefault: true)
    setUserOption(PK.subItalic, type: .bool, forName: MPVOption.Subtitles.subItalic,
                  verboseIfDefault: true)

    setUserOption(PK.subBlur, type: .float, forName: MPVOption.Subtitles.subBlur,
                  verboseIfDefault: true)
    setUserOption(PK.subSpacing, type: .float, forName: MPVOption.Subtitles.subSpacing,
                  verboseIfDefault: true)

    setUserOption(PK.subBorderSize, type: .float, forName: MPVOption.Subtitles.subBorderSize,
                  verboseIfDefault: true)
    setUserOption(PK.subBorderColorString, type: .color, forName: MPVOption.Subtitles.subBorderColor,
                  verboseIfDefault: true)

    setUserOption(PK.subShadowSize, type: .float, forName: MPVOption.Subtitles.subShadowOffset,
                  verboseIfDefault: true)
    setUserOption(PK.subShadowColorString, type: .color, forName: MPVOption.Subtitles.subShadowColor,
                  verboseIfDefault: true)

    setUserOption(PK.subAlignX, type: .other, forName: MPVOption.Subtitles.subAlignX,
                  verboseIfDefault: true) { key in
      return String(describing: Preference.enum(for: key) as Preference.SubAlignX)
    }

    setUserOption(PK.subAlignY, type: .other, forName: MPVOption.Subtitles.subAlignY,
                  verboseIfDefault: true) { key in
      return String(describing: Preference.enum(for: key) as Preference.SubAlignY)
    }

    setUserOption(PK.subMarginX, type: .int, forName: MPVOption.Subtitles.subMarginX,
                  verboseIfDefault: true)
    setUserOption(PK.subMarginY, type: .int, forName: MPVOption.Subtitles.subMarginY,
                  verboseIfDefault: true)

    setUserOption(PK.subPos, type: .float, forName: MPVOption.Subtitles.subPos, verboseIfDefault: true)

    setUserOption(PK.subLang, type: .string, forName: MPVOption.TrackSelection.slang, level: .verbose)

    setUserOption(PK.displayInLetterBox, type: .bool, forName: MPVOption.Subtitles.subUseMargins,
                  verboseIfDefault: true)
    setUserOption(PK.displayInLetterBox, type: .bool, forName: MPVOption.Subtitles.subAssForceMargins,
                  verboseIfDefault: true)

    setUserOption(PK.subScaleWithWindow, type: .bool, forName: MPVOption.Subtitles.subScaleByWindow,
                  verboseIfDefault: true)

    // - Network / cache settings

    setUserOption(PK.enableCache, type: .other, forName: MPVOption.Cache.cache,
                  verboseIfDefault: true) { key in
      return Preference.bool(for: key) ? nil : "no"
    }

    setUserOption(PK.defaultCacheSize, type: .other, forName: MPVOption.Demuxer.demuxerMaxBytes,
                  verboseIfDefault: true) { key in
      return "\(Preference.integer(for: key))KiB"
    }
    setUserOption(PK.secPrefech, type: .int, forName: MPVOption.Cache.cacheSecs, verboseIfDefault: true)

    setUserOption(PK.userAgent, type: .other, forName: MPVOption.Network.userAgent,
                  verboseIfDefault: true) { key in
      let ua = Preference.string(for: key)!
      return ua.isEmpty ? nil : ua
    }

    setUserOption(PK.transportRTSPThrough, type: .other, forName: MPVOption.Network.rtspTransport,
                  verboseIfDefault: true) { key in
      return String(describing: Preference.enum(for: .transportRTSPThrough) as
                    Preference.RTSPTransportation)
    }

    setUserOption(PK.ytdlEnabled, type: .other, forName: MPVOption.ProgramBehavior.ytdl,
                  verboseIfDefault: true) { key in
      let v = Preference.bool(for: .ytdlEnabled)
      if JavascriptPlugin.hasYTDL {
        return "no"
      }
      return v ? "yes" : "no"
    }
    // SPEC:Phase-3 intended the `-append` form so an IINA-side value
    // ADDS to whatever the user's `mpv.conf` already configured. But the
    // libmpv IINA ships (mpv 0.38.0) does NOT have `ytdl-raw-options-
    // append` — only `ytdl-raw-options` (verified via
    // `strings libmpv.2.dylib | grep ytdl`, Phase 7). Using `-append`
    // returned MPV_ERROR_OPTION_NOT_FOUND (-5) and surfaced an
    // `alert.mpv_error` to the user. We use plain `ytdl-raw-options`
    // (overwrite semantics); for a single entry the end state is
    // identical, and the user's `mpv.conf` line
    // `ytdl-raw-options-append = cookies-from-browser=edge` is already
    // silently ignored by mpv 0.38.0 (unknown option at parse time).
    // `Preference.Key.ytdlRawOptions` name and type are unchanged.
    setUserOption(PK.ytdlRawOptions, type: .string, forName: MPVOption.ProgramBehavior.ytdlRawOptions,
                  verboseIfDefault: true)
    // see SPEC:Phase-2 — reset-on-next-file is intentionally not guarded by
    // MPVSentinel; the user's value (if any) is allowed to override only
    // through the "Additional mpv options" preference, not via mpv.conf.
    chkErr(setOptionString(MPVOption.ProgramBehavior.resetOnNextFile,
            "\(MPVOption.PlaybackControl.abLoopA),\(MPVOption.PlaybackControl.abLoopB)", level: .verbose))

    setUserOption(PK.audioDriverEnableAVFoundation, type: .other, forName: MPVOption.Audio.ao,
                  verboseIfDefault: true) { key in
      Preference.bool(for: key) ? "avfoundation" : "coreaudio"
    }

    // SPEC:Phase-7 — wire the previously-unwired mpv options. All use
    // verboseIfDefault so an empty/zero IINA preference is a no-op: mpv's
    // own default (or the user's mpv.conf value) applies.

    // GPURendererOptions (scale / colour / HDR)
    setUserOption(PK.scale, type: .other, forName: MPVOption.GPURendererOptions.scale,
                  verboseIfDefault: true) { key in
      let v: Preference.ScaleOption = Preference.enum(for: key)
      return v == .default ? nil : String(describing: v)
    }
    setUserOption(PK.cscale, type: .other, forName: MPVOption.GPURendererOptions.cscale,
                  verboseIfDefault: true) { key in
      let v: Preference.ScaleOption = Preference.enum(for: key)
      return v == .default ? nil : String(describing: v)
    }
    setUserOption(PK.dscale, type: .other, forName: MPVOption.GPURendererOptions.dscale,
                  verboseIfDefault: true) { key in
      let v: Preference.ScaleOption = Preference.enum(for: key)
      return v == .default ? nil : String(describing: v)
    }
    setUserOption(PK.scaleAntiring, type: .float, forName: MPVOption.GPURendererOptions.scaleAntiring, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.correctDownscaling, type: .bool, forName: MPVOption.GPURendererOptions.correctDownscaling, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.linearDownscaling, type: .bool, forName: MPVOption.GPURendererOptions.linearDownscaling, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.sigmoidUpscaling, type: .bool, forName: MPVOption.GPURendererOptions.sigmoidUpscaling, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.dither, type: .other, forName: MPVOption.GPURendererOptions.dither,
                  verboseIfDefault: true) { key in
      let v: Preference.DitherOption = Preference.enum(for: key)
      return v == .default ? nil : String(describing: v)
    }
    setUserOption(PK.hdrComputePeak, type: .bool, forName: MPVOption.GPURendererOptions.hdrComputePeak, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.hdrPeakPercentile, type: .float, forName: MPVOption.GPURendererOptions.hdrPeakPercentile, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.hdrContrastRecovery, type: .float, forName: MPVOption.GPURendererOptions.hdrContrastRecovery, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.libplaceboOpts, type: .string, forName: MPVOption.GPURendererOptions.libplaceboOpts, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.iccForceContrast, type: .int, forName: MPVOption.GPURendererOptions.iccForceContrast, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.gpuContext, type: .string, forName: MPVOption.GPURendererOptions.gpuContext, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.targetColorspaceHint, type: .bool, forName: MPVOption.GPURendererOptions.targetColorspaceHint, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.targetTrc, type: .other, forName: MPVOption.GPURendererOptions.targetTrc,
                  verboseIfDefault: true) { key in
      let v: Preference.TargetTrcOption = Preference.enum(for: key)
      return v == .default ? nil : String(describing: v)
    }
    setUserOption(PK.targetPeak, type: .float, forName: MPVOption.GPURendererOptions.targetPeak, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.blendSubtitles, type: .bool, forName: MPVOption.GPURendererOptions.blendSubtitles, verboseIfDefault: true, skipIfDefault: true)

    // Codec (decoder)
    setUserOption(PK.vdLavcDr, type: .bool, forName: MPVOption.Video.vdLavcDr, verboseIfDefault: true, skipIfDefault: true)
    // SPEC:Phase-7 revert. The Phase 3 "correction 1" was WRONG — mpv
    // 0.38.0 (the libmpv IINA ships) has `vd-lavc-software-fallback`
    // as the option name; `hwdec-software-fallback` was added in a
    // later mpv version and returns MPV_ERROR_OPTION_NOT_FOUND (-5) on
    // 0.38.0, surfacing as `alert.mpv_error`. The user's mpv.conf
    // `vd-lavc-software-fallback=60` was never a typo — it was always
    // the real name. Reverted to the pre-Phase-3 wiring: `vdLavcSoftwareFallback`
    // key + `MPVOption.Video.vdLavcSoftwareFallback` constant (string
    // `"vd-lavc-software-fallback"`), default 60.
    setUserOption(PK.vdLavcSoftwareFallback, type: .int,
                  forName: MPVOption.Video.vdLavcSoftwareFallback, skipIfDefault: false)

    // OSD
    setUserOption(PK.osdOnSeek, type: .string, forName: MPVOption.OSD.osdOnSeek, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.osdBarH, type: .int, forName: MPVOption.OSD.osdBarH, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.osdBarBorderSize, type: .float, forName: MPVOption.OSD.osdBarBorderSize, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.osdBorderSize, type: .float, forName: MPVOption.OSD.osdBorderSize, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.osdFontSize, type: .int, forName: MPVOption.OSD.osdFontSize, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.osdFractions, type: .bool, forName: MPVOption.OSD.osdFractions, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.osdPlayingMsg, type: .string, forName: MPVOption.OSD.osdPlayingMsg, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.osdDuration, type: .int, forName: MPVOption.OSD.osdDuration, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.osdPlayingMsgDuration, type: .int, forName: MPVOption.OSD.osdPlayingMsgDuration, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.osc, type: .other, forName: MPVOption.OSD.osc,
                  verboseIfDefault: true) { key in
      let v: Preference.OscOption = Preference.enum(for: key)
      return v == .default ? nil : String(describing: v)
    }

    // Audio
    setUserOption(PK.adLavcDownmix, type: .bool, forName: MPVOption.Audio.adLavcDownmix, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.audioChannels, type: .other, forName: MPVOption.Audio.audioChannels,
                  verboseIfDefault: true) { key in
      let v: Preference.AudioChannelsOption = Preference.enum(for: key)
      return v == .default ? nil : String(describing: v)
    }
    setUserOption(PK.audioFileAuto, type: .other, forName: MPVOption.Audio.audioFileAuto,
                  verboseIfDefault: true) { key in
      let v: Preference.AudioFileAutoOption = Preference.enum(for: key)
      return v == .default ? nil : String(describing: v)
    }

    // Subtitle
    setUserOption(PK.subFilePaths, type: .string, forName: MPVOption.Subtitles.subFilePaths, verboseIfDefault: true, skipIfDefault: true)

    // Demuxer
    setUserOption(PK.demuxerLavfFormat, type: .string, forName: MPVOption.Demuxer.demuxerLavfFormat, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.forceSeekable, type: .bool, forName: MPVOption.Demuxer.forceSeekable, verboseIfDefault: true, skipIfDefault: true)

    // Window / playback
    setUserOption(PK.border, type: .bool, forName: MPVOption.Window.border, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.hidpiWindowScale, type: .bool, forName: MPVOption.Window.hidpiWindowScale, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.autofitLarger, type: .string, forName: MPVOption.Window.autofitLarger, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.cursorAutohide, type: .string, forName: MPVOption.Window.cursorAutohide, verboseIfDefault: true, skipIfDefault: true)
    setUserOption(PK.imageDisplayDuration, type: .string, forName: MPVOption.Window.imageDisplayDuration, verboseIfDefault: true, skipIfDefault: true)

    // Set user defined conf dir.
    // If the user has configured a custom mpv config-dir via Preferences →
    // Advanced (the "Use config directory" escape hatch, ui-driven-mpv-options
    // SPEC requirement 5), apply it now. The default is empty (no bundled
    // config-dir is shipped); users who want to bring their own mpv.conf
    // directory set this manually.
    if let rawUserConfDir = Preference.string(for: .userDefinedConfDir),
       !rawUserConfDir.isEmpty {
      let userConfDir = NSString(string: rawUserConfDir).standardizingPath
      setConfigDir(path: userConfDir)
    }

    // Set user defined options.
    if Preference.bool(for: .enableAdvancedSettings) {
      if let userOptions = Preference.value(for: .userOptions) as? [[String]] {
        if !userOptions.isEmpty {
          log("Setting \(userOptions.count) user configured mpv option values")
          userOptions.forEach { op in
            let status = setOptionString(op[0], op[1])
            if status < 0 {
              Utility.showAlert("extra_option.error", arguments:
                                  [op[0], op[1], status], disableMenus: true)
            }
          }
          log("Set \(userOptions.count) user configured mpv option values")
        }
      } else {
        Utility.showAlert("extra_option.cannot_read", disableMenus: true)
      }
    }

    // Load external scripts

    // Load keybindings. This is still required for mpv to handle media keys or apple remote.
    let userConfigs = PrefKeyBindingViewController.userConfigs
    var inputConfPath =  PrefKeyBindingViewController.defaultConfigs["IINA Default"]
    if let confFromUd = Preference.string(for: .currentInputConfigName) {
      if let currentConfigFilePath = Utility.getFilePath(Configs: userConfigs, forConfig: confFromUd, showAlert: false) {
        inputConfPath = currentConfigFilePath
      }
    }
    // SPEC:Phase-8 — merge the IINA-side editor's input.conf with the user's
    // mpv/input.conf so both IINA custom bindings and the user's script-binding
    // / @click / @press / @release modifiers take effect.
    let userInputConf = Utility.materializedMPVConfigDirURL.appendingPathComponent("input.conf")
    let mergedURL = Utility.writeMergedInputConf(
      iinaConfPath: inputConfPath,
      userConfPath: userInputConf.path,
      destinationDir: Utility.appSupportDirUrl
    )
    chkErr(setOptionalOptionString(MPVOption.Input.inputConf,
                                  mergedURL?.path ?? inputConfPath, level: .verbose))

    // Receive log messages at warn level.
    chkErr(mpv_request_log_messages(mpv, MPVLogLevel))

    // Request tick event.
    // chkErr(mpv_request_event(mpv, MPV_EVENT_TICK, 1))

    // Set a custom function that should be called when there are new events.
    mpv_set_wakeup_callback(self.mpv, { (ctx) in
      let mpvController = unsafeBitCast(ctx, to: MPVController.self)
      mpvController.readEvents()
      }, mutableRawPointerOf(obj: self))

    // Observe properties.
    observeProperties.forEach { (k, v) in
      mpv_observe_property(mpv, 0, k, v)
    }

    // vo=libmpv MUST be set before mpv_initialize. force-window=immediate
    // (the default, applied above via PK.forceWindow) causes mpv to spawn the
    // VO thread during mpv_initialize. If vo is still at its default ("gpu")
    // at that point, the VO thread probes Vulkan (`displayvk`) and crashes in
    // libmpv builds with Vulkan enabled (EXC_BAD_ACCESS in mppl_log_create,
    // backtrace: vo_thread -> preinit -> ra_ctx_create -> display_init ->
    // mpvk_init -> mppl_log_create). Setting vo=libmpv pre-init makes the VO
    // thread use IINA's render API instead. See SPEC requirement 2.
    if !MPVSentinel.wasSetInConfig(MPVOption.Video.vo) {
      chkErr(setOptionString(MPVOption.Video.vo, "libmpv", level: .verbose))
    }

    // Initialize an uninitialized mpv instance. If the mpv instance is already running, an error is returned.
    chkErr(mpv_initialize(mpv))

    // The option watch-later-options is not available until after the mpv instance is initialized.
    // Workaround for mpv issue #14417, watch-later-options missing secondary subtitle delay and sid.
    // Allow the user to override this workaround by setting this mpv option in advanced settings.
    if !userOptionsContains(MPVOption.WatchLater.watchLaterOptions),
       var watchLaterOptions = getString(MPVOption.WatchLater.watchLaterOptions) {

      // In mpv 0.38.0 the default value for the watch-later-options property contains the options
      // sid and sub-delay, but not the corresponding options for the secondary subtitle. This
      // inconsistency is likely to confuse users, so insure the secondary options are also saved in
      // watch later files. Issue #14417 has been fixed, so this workaround will not be needed after
      // the next mpv upgrade.
      var needsUpdate = false
      if watchLaterOptions.contains(MPVOption.TrackSelection.sid),
         !watchLaterOptions.contains(MPVOption.Subtitles.secondarySid) {
        log("Adding \(MPVOption.Subtitles.secondarySid) to \(MPVOption.WatchLater.watchLaterOptions)")
        watchLaterOptions += "," + MPVOption.Subtitles.secondarySid
        needsUpdate = true
      }
      if watchLaterOptions.contains(MPVOption.Subtitles.subDelay),
         !watchLaterOptions.contains(MPVOption.Subtitles.secondarySubDelay) {
        log("Adding \(MPVOption.Subtitles.secondarySubDelay) to \(MPVOption.WatchLater.watchLaterOptions)")
        watchLaterOptions += "," + MPVOption.Subtitles.secondarySubDelay
        needsUpdate = true
      }
      if needsUpdate {
        chkErr(setOptionString(MPVOption.WatchLater.watchLaterOptions, watchLaterOptions, level: .verbose))
      }
    }
    if let watchLaterOptions = getString(MPVOption.WatchLater.watchLaterOptions) {
      let sorted = watchLaterOptions.components(separatedBy: ",").sorted().joined(separator: ",")
      log("Options mpv is configured to save in watch later files: \(sorted)")
    }

    // Must be called after mpv_initialize which sets the default value for hwdec-codecs.
    adjustCodecWhiteList()
    applyHardwareAccelerationWorkaround()

    // Set options that can be override by user's config. mpv will log user config when initialize,
    // so we put them here. Each forced option is gated on MPVSentinel so a
    // user who has explicitly set the key in mpv.conf keeps their value
    // instead of being clobbered. See SPEC requirement 2 / PLAN Phase 2.
    // NOTE: vo=libmpv is set PRE-init above (before mpv_initialize) because
    // force-window=immediate spawns the VO thread during init.
    if !MPVSentinel.wasSetInConfig(MPVOption.Window.keepaspect) {
      chkErr(setOptionString(MPVOption.Window.keepaspect, "yes", level: .verbose))
    }
    if !MPVSentinel.wasSetInConfig(MPVOption.Video.gpuHwdecInterop) {
      chkErr(setOptionString(MPVOption.Video.gpuHwdecInterop, "auto", level: .verbose))
    }
  }

  /// Sync mpv's effective option values back into IINA's UserDefaults so
  /// the Settings UI reflects what the user's `mpv.conf` actually resolved.
  /// Only writes when the IINA preference is still at its empty/default
  /// value — user-set IINA preferences always win over mpv.conf.
  /// Called by `PlayerCore.openFile` after the file load command so mpv
  /// is fully initialized. Idempotent. See SPEC requirement 6.
  func syncMPVConfigToPreferences() {
    // String options: only sync if IINA pref is empty.
    let stringPairs: [(Preference.Key, String)] = [
      (.libplaceboOpts, MPVOption.GPURendererOptions.libplaceboOpts),
      (.gpuContext, MPVOption.GPURendererOptions.gpuContext),
      (.osdOnSeek, MPVOption.OSD.osdOnSeek),
      (.osdPlayingMsg, MPVOption.OSD.osdPlayingMsg),
      (.subFilePaths, MPVOption.Subtitles.subFilePaths),
      (.demuxerLavfFormat, MPVOption.Demuxer.demuxerLavfFormat),
      (.autofitLarger, MPVOption.Window.autofitLarger),
      (.cursorAutohide, MPVOption.Window.cursorAutohide),
      (.imageDisplayDuration, MPVOption.Window.imageDisplayDuration),
    ]
    for (prefKey, mpvName) in stringPairs {
      let current = Preference.string(for: prefKey) ?? ""
      if current.isEmpty {
        if let mpvValue = getString(mpvName), !mpvValue.isEmpty {
          // Don't write mpv's internal sentinel values like "<no>".
          if !mpvValue.hasPrefix("<") {
            Preference.set(mpvValue, for: prefKey)
            log("Synced \(mpvName)=\(mpvValue) from mpv.conf to IINA preference")
          }
        }
      }
    }

    // Int options: only sync if IINA pref is 0 (our default).
    let intPairs: [(Preference.Key, String)] = [
      (.iccForceContrast, MPVOption.GPURendererOptions.iccForceContrast),
      (.vdLavcSoftwareFallback, MPVOption.Video.vdLavcSoftwareFallback),
      (.osdBarH, MPVOption.OSD.osdBarH),
      (.osdFontSize, MPVOption.OSD.osdFontSize),
      (.osdDuration, MPVOption.OSD.osdDuration),
      (.osdPlayingMsgDuration, MPVOption.OSD.osdPlayingMsgDuration),
    ]
    for (prefKey, mpvName) in intPairs {
      if Preference.integer(for: prefKey) == 0 {
        let mpvValue = getInt(mpvName)
        if mpvValue != 0 {
          Preference.set(mpvValue, for: prefKey)
          log("Synced \(mpvName)=\(mpvValue) from mpv.conf to IINA preference")
        }
      }
    }

    // Float options: only sync if IINA pref is 0 (our default).
    let floatPairs: [(Preference.Key, String)] = [
      (.scaleAntiring, MPVOption.GPURendererOptions.scaleAntiring),
      (.hdrPeakPercentile, MPVOption.GPURendererOptions.hdrPeakPercentile),
      (.hdrContrastRecovery, MPVOption.GPURendererOptions.hdrContrastRecovery),
      (.targetPeak, MPVOption.GPURendererOptions.targetPeak),
      (.osdBarBorderSize, MPVOption.OSD.osdBarBorderSize),
      (.osdBorderSize, MPVOption.OSD.osdBorderSize),
    ]
    for (prefKey, mpvName) in floatPairs {
      if Preference.float(for: prefKey) == 0 {
        let mpvValue = getDouble(mpvName)
        if mpvValue != 0 {
          Preference.set(Float(mpvValue), for: prefKey)
          log("Synced \(mpvName)=\(mpvValue) from mpv.conf to IINA preference")
        }
      }
    }

    // Bool options: only sync if IINA pref is false (our default) and mpv is true.
    // We don't sync false→false or true→false to avoid surprising the user.
    let boolPairs: [(Preference.Key, String)] = [
      (.correctDownscaling, MPVOption.GPURendererOptions.correctDownscaling),
      (.linearDownscaling, MPVOption.GPURendererOptions.linearDownscaling),
      (.sigmoidUpscaling, MPVOption.GPURendererOptions.sigmoidUpscaling),
      (.hdrComputePeak, MPVOption.GPURendererOptions.hdrComputePeak),
      (.targetColorspaceHint, MPVOption.GPURendererOptions.targetColorspaceHint),
      (.blendSubtitles, MPVOption.GPURendererOptions.blendSubtitles),
      (.vdLavcDr, MPVOption.Video.vdLavcDr),
      (.osdFractions, MPVOption.OSD.osdFractions),
      (.adLavcDownmix, MPVOption.Audio.adLavcDownmix),
      (.forceSeekable, MPVOption.Demuxer.forceSeekable),
      (.border, MPVOption.Window.border),
      (.hidpiWindowScale, MPVOption.Window.hidpiWindowScale),
    ]
    for (prefKey, mpvName) in boolPairs {
      if !Preference.bool(for: prefKey) {
        if getFlag(mpvName) {
          Preference.set(true, for: prefKey)
          log("Synced \(mpvName)=yes from mpv.conf to IINA preference")
        }
      }
    }
  }

  /// Initialize the `mpv` renderer.
  ///
  /// This method creates and initializes the `mpv` renderer and sets the callback that `mpv` calls when a new video frame is available.
  ///
  /// - Note: Advanced control must be enabled for the screenshot command to work when the window flag is used. See issue
  ///         [#4822](https://github.com/iina/iina/issues/4822) for details.
  func mpvInitRendering() {
    guard let mpv = mpv else {
      fatalError("mpvInitRendering() should be called after mpv handle being initialized!")
    }
    let apiType = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String)
    var openGLInitParams = mpv_opengl_init_params(get_proc_address: mpvGetOpenGLFunc,
                                                  get_proc_address_ctx: nil)
    withUnsafeMutablePointer(to: &openGLInitParams) { openGLInitParams in
      var advanced: CInt = 1
      withUnsafeMutablePointer(to: &advanced) { advanced in
        var params = [
          mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiType),
          mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: openGLInitParams),
          mpv_render_param(type: MPV_RENDER_PARAM_ADVANCED_CONTROL, data: advanced),
          mpv_render_param()
        ]
        chkErr(mpv_render_context_create(&mpvRenderContext, mpv, &params))
      }
      openGLContext = CGLGetCurrentContext()
      mpv_render_context_set_update_callback(mpvRenderContext!, mpvUpdateCallback, mutableRawPointerOf(obj: player.mainWindow.videoView.videoLayer))
    }
  }

  /// Lock the OpenGL context associated with the mpv renderer and set it to be the current context for this thread.
  ///
  /// This method is needed to meet this requirement from `mpv/render.h`:
  ///
  /// If the OpenGL backend is used, for all functions the OpenGL context must be "current" in the calling thread, and it must be the
  /// same OpenGL context as the `mpv_render_context` was created with. Otherwise, undefined behavior will occur.
  ///
  /// - Reference: [mpv render.h](https://github.com/mpv-player/mpv/blob/master/libmpv/render.h)
  /// - Reference: [Concurrency and OpenGL](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/OpenGL-MacProgGuide/opengl_threading/opengl_threading.html)
  /// - Reference: [OpenGL Context](https://www.khronos.org/opengl/wiki/OpenGL_Context)
  /// - Attention: Do not forget to unlock the OpenGL context by calling `unlockOpenGLContext`
  func lockAndSetOpenGLContext() {
    CGLLockContext(openGLContext)
    CGLSetCurrentContext(openGLContext)
  }

  /// Unlock the OpenGL context associated with the mpv renderer.
  func unlockOpenGLContext() {
    CGLUnlockContext(openGLContext)
  }

  func mpvUninitRendering() {
    guard let mpvRenderContext = mpvRenderContext else { return }
    mpv_render_context_set_update_callback(mpvRenderContext, nil, nil)
    mpv_render_context_free(mpvRenderContext)
    self.mpvRenderContext = nil
    mpv_destroy(mpv)
    mpv = nil
  }

  func mpvReportSwap() {
    guard let mpvRenderContext = mpvRenderContext else { return }
    mpv_render_context_report_swap(mpvRenderContext)
  }

  func shouldRenderUpdateFrame() -> Bool {
    guard let mpvRenderContext = mpvRenderContext else { return false }
    let flags: UInt64 = mpv_render_context_update(mpvRenderContext)
    return flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) > 0
  }

  /// Remove observers for IINA preferences and mpv properties.
  /// - Important: Observers **must** be removed before sending a `quit` command to mpv. Accessing a mpv core after it
  ///     has shutdown is not permitted by mpv and can trigger a crash. During shutdown mpv will emit property change events,
  ///     thus it is critical that observers be removed, otherwise they may access the core and trigger a crash.
  func removeObservers() {
    // Remove observers for IINA preferences. Must not attempt to change a mpv setting in response
    // to an IINA preference change while mpv is shutting down.
    removeOptionObservers()
    // Remove observers for mpv properties. Because 0 was passed for reply_userdata when registering
    // mpv property observers all observers can be removed in one call.
    mpv_unobserve_property(mpv, 0)
  }

  /// Remove observers for IINA preferences.
  private func removeOptionObservers() {
    ObjcUtils.silenced {
      self.optionObservers.forEach { (k, _) in
        UserDefaults.standard.removeObserver(self, forKeyPath: k)
      }
    }
  }

  /// Shutdown this mpv controller.
  func mpvQuit() {
    // Remove observers for IINA preference. Must not attempt to change a mpv setting
    // in response to an IINA preference change while mpv is shutting down.
    removeOptionObservers()
    // Remove observers for mpv properties. Because 0 was passed for reply_userdata when
    // registering mpv property observers all observers can be removed in one call.
    mpv_unobserve_property(mpv, 0)
    // Start mpv quitting. Even though this command is being sent using the synchronous
    // command API the quit command is special and will be executed by mpv asynchronously.
    command(.quit, level: .verbose)
  }

  // MARK: - Command & property

  private func makeCArgs(_ command: MPVCommand, _ args: [String?]) -> [String?] {
    if args.count > 0 && args.last == nil {
      Logger.fatal("Command do not need a nil suffix")
    }
    var strArgs = args
    strArgs.insert(command.rawValue, at: 0)
    strArgs.append(nil)
    return strArgs
  }

  // Send arbitrary mpv command.
  func command(_ command: MPVCommand, args: [String?] = [], checkError: Bool = true,
               level: Logger.Level = .debug, returnValueCallback: ((Int32) -> Void)? = nil) {
    guard mpv != nil else { return }
    log("Run command: \(command.rawValue) \(args.compactMap{$0}.joined(separator: " "))", level: level)
    var cargs = makeCArgs(command, args).map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
    defer {
      for ptr in cargs {
        if (ptr != nil) {
          free(UnsafeMutablePointer(mutating: ptr!))
        }
      }
    }
    let returnValue = mpv_command(self.mpv, &cargs)
    if checkError {
      chkErr(returnValue)
    } else if let cb = returnValueCallback {
      cb(returnValue)
    }
  }

  func command(rawString: String, level: Logger.Level = .debug) -> Int32 {
    log("Run command: \(rawString)", level: level)
    return mpv_command_string(mpv, rawString)
  }

  func asyncCommand(_ command: MPVCommand, args: [String?] = [], checkError: Bool = true,
                    replyUserdata: UInt64, level: Logger.Level = .debug) {
    guard mpv != nil else { return }
    log("Asynchronously run command: \(command.rawValue) \(args.compactMap{$0}.joined(separator: " "))",
        level: level)
    var cargs = makeCArgs(command, args).map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
    defer {
      for ptr in cargs {
        if (ptr != nil) {
          free(UnsafeMutablePointer(mutating: ptr!))
        }
      }
    }
    let returnValue = mpv_command_async(self.mpv, replyUserdata, &cargs)
    if checkError {
      chkErr(returnValue)
    }
  }

  func observe(property: String, format: mpv_format = MPV_FORMAT_DOUBLE) {
    mpv_observe_property(mpv, 0, property, format)
  }

  // Set property
  func setFlag(_ name: String, _ flag: Bool, level: Logger.Level = .debug) {
    log("Set property: \(name)=\(flag)", level: level)
    var data: Int32 = flag ? 1 : 0
    mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
  }

  func setInt(_ name: String, _ value: Int, level: Logger.Level = .debug) {
    log("Set property: \(name)=\(value)", level: level)
    var data = Int64(value)
    mpv_set_property(mpv, name, MPV_FORMAT_INT64, &data)
  }

  func setDouble(_ name: String, _ value: Double, level: Logger.Level = .debug) {
    log("Set property: \(name)=\(value)", level: level)
    var data = value
    mpv_set_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
  }

  @discardableResult
  func setString(_ name: String, _ value: String, level: Logger.Level = .debug) -> Int32 {
    log("Set property: \(name)=\(value)", level: level)
    return mpv_set_property_string(mpv, name, value)
  }

  func getEnum<T: MPVOptionValue>(_ name: String) -> T {
    guard let value = getString(name) else {
      return T.defaultValue
    }
    return T.init(rawValue: value) ?? T.defaultValue
  }

  func getInt(_ name: String) -> Int {
    var data = Int64()
    mpv_get_property(mpv, name, MPV_FORMAT_INT64, &data)
    return Int(data)
  }

  func getDouble(_ name: String) -> Double {
    var data = Double()
    mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
    return data
  }

  func getFlag(_ name: String) -> Bool {
    var data = Int32()
    mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &data)
    return data > 0
  }

  func getString(_ name: String) -> String? {
    let cstr = mpv_get_property_string(mpv, name)
    let str: String? = cstr == nil ? nil : String(cString: cstr!)
    mpv_free(cstr)
    return str
  }

  /// Cached value of mpv's `osd-font` option, read once after `mpv_initialize`
  /// resolves the user's `mpv.conf`. Used by `MainWindowController` to resolve
  /// IINA's native OSD label font. Returns `nil` if the option is at mpv's
  /// default (unset). See SPEC `mpv-config-driven-refactor` Phase 6.
  private var _cachedOsdFont: String?
  /// Set to `true` once `_cachedOsdFont` has been populated.
  private var osdFontCached = false
  var osdFontFromMpv: String? {
    if !osdFontCached {
      _cachedOsdFont = getString(MPVOption.OSD.osdFont)
      osdFontCached = true
    }
    return _cachedOsdFont
  }

  /** Get filter. only "af" or "vf" is supported for name */
  func getFilters(_ name: String) -> [MPVFilter] {
    Logger.ensure(name == MPVProperty.vf || name == MPVProperty.af, "getFilters() do not support \(name)!")

    var result: [MPVFilter] = []
    var node = mpv_node()
    mpv_get_property(mpv, name, MPV_FORMAT_NODE, &node)
    guard let filters = (try? MPVNode.parse(node)!) as? [[String: Any?]] else { return result }
    filters.forEach { f in
      let filter = MPVFilter(name: f["name"] as! String,
                             label: f["label"] as? String,
                             params: f["params"] as? [String: String])
      result.append(filter)
    }
    mpv_free_node_contents(&node)
    return result
  }

  /// Remove the audio or video filter at the given index in the list of filters.
  ///
  /// Previously IINA removed filters using the mpv `af remove` and `vf remove` commands described in the
  /// [Input Commands that are Possibly Subject to Change](https://mpv.io/manual/stable/#input-commands-that-are-possibly-subject-to-change)
  /// section of the mpv manual. The behavior of the remove command is described in the [video-filters](https://mpv.io/manual/stable/#video-filters)
  /// section of the manual under the entry for `--vf-remove-filter`.
  ///
  /// When searching for the filter to be deleted the remove command takes into consideration the order of filter parameters. The
  /// expectation is that the application using the mpv client will provide the filter to the remove command in the same way it was
  /// added. However IINA doe not always know how a filter was added. Filters can be added to mpv outside of IINA therefore it is not
  /// possible for IINA to know how filters were added. IINA obtains the filter list from mpv using `mpv_get_property`. The
  /// `mpv_node` tree returned for a filter list stores the filter parameters in a `MPV_FORMAT_NODE_MAP`. The key value pairs in a
  /// `MPV_FORMAT_NODE_MAP` are in **random** order. As a result sometimes the order of filter parameters in the filter string
  /// representation given by IINA to the mpv remove command would not match the order of parameters given when the filter was
  /// added to mpv and the remove command would fail to remove the filter. This was reported in
  /// [IINA issue #3620 Audio filters with same name cannot be removed](https://github.com/iina/iina/issues/3620).
  ///
  /// The issue of `mpv_get_property` returning filter parameters in random order even though the remove command is sensitive to
  /// filter parameter order was raised with the mpv project in
  /// [mpv issue #9841 mpv_get_property returns filter params in unordered map breaking remove](https://github.com/mpv-player/mpv/issues/9841)
  /// The response from the mpv project confirmed that the parameters in a `MPV_FORMAT_NODE_MAP` **must** be considered to
  /// be in random order even if they appear to be ordered. The recommended methods for removing filters is to use labels, which
  /// IINA does for filters it creates or removing based on position in the filter list. This method supports removal based on the
  /// position within the list of filters.
  ///
  /// The recommended implementation is to get the entire list of filters using `mpv_get_property`, remove the filter from the
  /// `mpv_node` tree returned by that method and then set the list of filters using `mpv_set_property`. This is the approach
  /// used by this method.
  /// - Parameter name: The kind of filter identified by the mpv property name, `MPVProperty.af` or `MPVProperty.vf`.
  /// - Parameter index: Index of the filter to be removed.
  /// - Returns: `true` if the filter was successfully removed, `false` if the filter was not removed.
  func removeFilter(_ name: String, _ index: Int) -> Bool {
    Logger.ensure(name == MPVProperty.vf || name == MPVProperty.af, "removeFilter() does not support \(name)!")

    // Get the current list of filters from mpv as a mpv_node tree.
    var oldNode = mpv_node()
    defer { mpv_free_node_contents(&oldNode) }
    mpv_get_property(mpv, name, MPV_FORMAT_NODE, &oldNode)

    let oldList = oldNode.u.list!.pointee

    // If the user uses mpv's JSON-based IPC protocol to make changes to mpv's filters behind IINA's
    // back then there is a very small window of vulnerability where the list of filters displayed
    // by IINA may be stale and therefore the index to remove may be invalid. IINA listens for
    // changes to mpv's filter properties and updates the filters displayed when changes occur, so
    // it is unlikely in practice that this method will be called with an invalid index, but we will
    // validate the index nonetheless to insure this code does not trigger a crash.
    guard index < oldList.num else {
      log("Found \(oldList.num) \(name) filters, index of filter to remove (\(index)) is invalid",
          level: .error)
      return false
    }

    // The documentation for mpv_node states:
    // "If mpv writes this struct (e.g. via mpv_get_property()), you must not change the data."
    // So the approach taken is to create new top level node objects as those need to be modified in
    // order to remove the filter, and reuse the lower level node objects representing the filters.
    // First we create a new node list that is one entry smaller than the current list of filters.
    let newNum = oldList.num - 1
    let newValues = UnsafeMutablePointer<mpv_node>.allocate(capacity: Int(newNum))
    defer {
      newValues.deinitialize(count: Int(newNum))
      newValues.deallocate()
    }
    var newList = mpv_node_list()
    newList.num = newNum
    newList.values = newValues

    // Make the new list of values point to the same values in the old list, skipping the entry to
    // be removed.
    var newValuesPtr = newValues
    var oldValuesPtr = oldList.values!
    for i in 0 ..< oldList.num {
      if i != index {
        newValuesPtr.pointee = oldValuesPtr.pointee
        newValuesPtr = newValuesPtr.successor()
      }
      oldValuesPtr = oldValuesPtr.successor()
    }

    // Add the new list to a new node.
    let newListPtr = UnsafeMutablePointer<mpv_node_list>.allocate(capacity: 1)
    defer {
      newListPtr.deinitialize(count: 1)
      newListPtr.deallocate()
    }
    newListPtr.pointee = newList
    var newNode = mpv_node()
    newNode.format = MPV_FORMAT_NODE_ARRAY
    newNode.u.list = newListPtr

    // Set the list of filters using the new node that leaves out the filter to be removed.
    log("Set property: \(name)=<a mpv node>")
    mpv_set_property(mpv, name, MPV_FORMAT_NODE, &newNode)
    return true
  }

  /** Set filter. only "af" or "vf" is supported for name */
  func setFilters(_ name: String, filters: [MPVFilter]) {
    Logger.ensure(name == MPVProperty.vf || name == MPVProperty.af, "setFilters() do not support \(name)!")
    let cmd = name == MPVProperty.vf ? MPVCommand.vf : MPVCommand.af

    let str = filters.map { $0.stringFormat }.joined(separator: ",")
    command(cmd, args: ["set", str], checkError: false) { returnValue in
      if returnValue < 0 {
        Utility.showAlert("filter.incorrect")
        // reload data in filter setting window
        self.player.postNotification(.iinaVFChanged)
      }
    }
  }

  func getNode(_ name: String) -> Any? {
    var node = mpv_node()
    mpv_get_property(mpv, name, MPV_FORMAT_NODE, &node)
    let parsed = try? MPVNode.parse(node)
    mpv_free_node_contents(&node)
    return parsed
  }

  func setNode(_ name: String, _ value: Any) {
    guard var node = try? MPVNode.create(value) else {
      log("setNode: cannot encode value for \(name)", level: .error)
      return
    }
    log("Set property: \(name)=<a mpv node>")
    mpv_set_property(mpv, name, MPV_FORMAT_NODE, &node)
    MPVNode.free(node)
  }

  /// Returns the given node map value as an `Int`.
  ///
  /// This method is intended to be used when extracting values from a `MPV_FORMAT_NODE_MAP` `mpv_node` that contains
  /// mixed types.
  /// - Note: Zero is returned for `nil` values to match the behavior of `getInt`.
  /// - Parameter value:Value from a mpv node map.
  /// - Returns: The given value converted to an `Int`.
  static func nodeValueAsInt(_ value: Any?) -> Int {
    guard let asInt64 = value as? Int64 else { return 0 }
    return Int(asInt64)
  }

  // MARK: - Hooks

  func addHook(_ name: MPVHook, priority: Int32 = 0, hook: MPVHookValue) {
    $hooks.withLock {
      mpv_hook_add(mpv, hookCounter, name.rawValue, priority)
      $0[hookCounter] = hook
      hookCounter += 1
    }
  }

  func removeHooks(withIdentifier id: String) {
    $hooks.withLock { hooks in
      hooks.filter { (k, v) in v.isJavascript && v.id == id }.keys.forEach { hooks.removeValue(forKey: $0) }
    }
  }

  // MARK: - Events

  // Read event and handle it async
  private func readEvents() {
    queue.async {
      while ((self.mpv) != nil) {
        let event = mpv_wait_event(self.mpv, 0)!
        let eventId = event.pointee.event_id
        // Do not deal with mpv-event-none
        if eventId == MPV_EVENT_NONE {
          break
        }
        self.handleEvent(event)
        // Must stop reading events once the mpv core is shutdown.
        if eventId == MPV_EVENT_SHUTDOWN {
          break
        }
      }
    }
  }

  // Handle the event
  private func handleEvent(_ event: UnsafePointer<mpv_event>) {
    let eventId = event.pointee.event_id

    switch eventId {
    case MPV_EVENT_SHUTDOWN:
      DispatchQueue.main.async {
        self.player.mpvHasShutdown()
      }

    case MPV_EVENT_LOG_MESSAGE:
      let dataOpaquePtr = OpaquePointer(event.pointee.data)
      let msg = UnsafeMutablePointer<mpv_event_log_message>(dataOpaquePtr)
      let prefix = String(cString: (msg?.pointee.prefix)!)
      let level = String(cString: (msg?.pointee.level)!)
      let text = String(cString: (msg?.pointee.text)!).trimmingCharacters(in: .newlines)
      log("[\(prefix)] \(level): \(text)", level: logLevelMap[level] ?? .verbose)

    case MPV_EVENT_HOOK:
      let userData = event.pointee.reply_userdata
      let hookEvent = event.pointee.data.bindMemory(to: mpv_event_hook.self, capacity: 1).pointee
      let hookID = hookEvent.id
      guard let hook = $hooks.withLock({ $0[userData] }) else {
        // Hook not found, probably because it's from an unloaded plugin.
        // Still need to call hook_continue otherwise it will stuck.
        log("Hook \(hookID) not found", level: .warning)
        mpv_hook_continue(self.mpv, hookID)
        break
      }
      hook.call {
        mpv_hook_continue(self.mpv, hookID)
      }

    case MPV_EVENT_PROPERTY_CHANGE:
      let dataOpaquePtr = OpaquePointer(event.pointee.data)
      if let property = UnsafePointer<mpv_event_property>(dataOpaquePtr)?.pointee {
        let propertyName = String(cString: property.name)
        handlePropertyChange(propertyName, property)
      }

    case MPV_EVENT_AUDIO_RECONFIG: break

    case MPV_EVENT_VIDEO_RECONFIG:
      DispatchQueue.main.async { self.player.onVideoReconfig() }

    case MPV_EVENT_START_FILE:
      guard let path = getString(MPVProperty.path) else { break }
      DispatchQueue.main.async { [self] in
        player.info.state = .starting
        player.fileStarted(path: path)
        let url = player.info.currentURL
        let message = player.info.isNetworkResource ? url?.absoluteString : url?.lastPathComponent
        player.sendOSD(.fileStart(message ?? "-"))
      }

    case MPV_EVENT_FILE_LOADED:
      DispatchQueue.main.async { self.player.fileLoaded() }

    case MPV_EVENT_SEEK:
      DispatchQueue.main.async { [self] in
        player.info.isSeeking = true
        // When playback is paused the display link may be shutdown in order to not waste energy.
        // It must be running when seeking to avoid slowdowns caused by mpv waiting for IINA to call
        // mpv_render_report_swap.
        player.mainWindow.videoView.displayActive()
        if needRecordSeekTime {
          recordedSeekStartTime = CACurrentMediaTime()
        }
        player.syncUI(.time)
        let osdText = (player.info.videoPosition?.stringRepresentation ?? Constants.String.videoTimePlaceholder) + " / " +
        (player.info.videoDuration?.stringRepresentation ?? Constants.String.videoTimePlaceholder)
        let percentage = (player.info.videoPosition / player.info.videoDuration) ?? 1
        player.sendOSD(.seek(osdText, percentage))
      }

    case MPV_EVENT_PLAYBACK_RESTART:
      DispatchQueue.main.async { [self] in
        player.info.isSeeking = false
        // When playback is paused the display link may be shutdown in order to not waste energy.
        // The display link will be restarted while seeking. If playback is paused shut it down
        // again.
        if player.info.state == .paused {
          player.mainWindow.videoView.displayIdle()
        }
        if needRecordSeekTime {
          recordedSeekTimeListener?(CACurrentMediaTime() - recordedSeekStartTime)
          recordedSeekTimeListener = nil
        }
        player.playbackRestarted()
        player.syncUI(.time)
      }

    case MPV_EVENT_END_FILE:
      let reason = event.pointee.data.load(as: mpv_end_file_reason.self)
      let dueToStopCommand = reason == MPV_END_FILE_REASON_STOP
      // When the IINA "Pause" setting is enabled under "When media is opened" IINA must tell mpv to
      // pause playback ASAP. Events are delivered asynchronously. If the IINA
      // "Play next item automatically" setting is enabled mpv will currently be loading the next
      // item in the playlist and will immediately start playing it as soon as loading completes.
      // Thus there is a race condition as to whether IINA can pause playback before mpv starts
      // playing the media. This is more likely to happen with audio files that can be quickly
      // loaded. As handling this does not require accessing IINA state not protected by locks and
      // only available to the main thread along with the requirement to pause playback ASAP we will
      // not leave this to the PlayerCore function and handle this now before calling fileEnded.
      if !dueToStopCommand, Preference.bool(for: .pauseWhenOpen) {
        setFlag(MPVOption.PlaybackControl.pause, true, level: .verbose)
        // Normally a log message is emitted before calling mpv, but in this case, due to the race
        // condition, playback must be paused as soon as possible, so logging is done afterward.
        log("Pausing playback because \"pause when media is opened\" is enabled")
      }
      DispatchQueue.main.async { self.player.fileEnded(dueToStopCommand) }

    case MPV_EVENT_COMMAND_REPLY:
      let reply = event.pointee.reply_userdata
      if reply == MPVController.UserData.screenshot {
        let code = event.pointee.error
        guard code >= 0 else {
          let error = String(cString: mpv_error_string(code))
          log("Cannot take a screenshot, mpv API error: \(error), Return value: \(code)", level: .error)
          // Unfortunately the mpv API does not provide any details on the failure. The error
          // code returned maps to "error running command", so all the alert can report is
          // that we cannot take a screenshot.
          DispatchQueue.main.async {
            Utility.showAlert("screenshot.error_taking")
          }
          return
        }
        DispatchQueue.main.async { self.player.screenshotCallback() }
      }

    case MPV_EVENT_QUEUE_OVERFLOW:
      // The mpv event system uses an event queue of limited size. If events are not read quickly
      // enough the queue can overflow resulting in events being dropped. This event indicates the
      // ringbuffer overflowed and at least one event was dropped. IINA can recover from the loss of
      // some types of mpv events, but certain mpv events are critical. If a critical event is
      // discarded IINA will experience severe malfunctions. For this reason most of the work of
      // processing an event is dispatched to other queues so that MPVController can move on to
      // reading the next event. This event indicates something went wrong and IINA failed to read
      // events fast enough. As IINA has been ignoring this event we don't know if this has been
      // occurring. For now log this as an error. May want to switch to an alert in the future.
      log("Critical failure, mpv events lost, queue overflowed", level: .error)

    case MPV_EVENT_CLIENT_MESSAGE:
      // mpv's `script-message` command is delivered via the C API as
      // MPV_EVENT_CLIENT_MESSAGE. The first argument (args[0]) is the
      // message name used for dispatch; args[1...] are the payload.
      // See SPEC requirement 9 and PLAN Phase 4.
      let dataOpaquePtr = OpaquePointer(event.pointee.data)
      if let msg = UnsafeMutablePointer<mpv_event_client_message>(dataOpaquePtr)?.pointee {
        let numArgs = Int(msg.num_args)
        let allArgs: [String] = (0..<numArgs).compactMap { i in
          guard let cStr = msg.args[i] else { return nil }
          return String(cString: cStr)
        }
        guard allArgs.count >= 1 else { break }
        let name = allArgs[0]
        let payload = Array(allArgs.dropFirst())
        // The event loop runs on the controller background queue.
        // NotificationCenter subscribers may touch UI, so dispatch to main.
        DispatchQueue.main.async {
          MpvScriptMessageCenter.shared.handle(name: name, args: payload)
        }
      }

    default: break
      // let eventName = String(cString: mpv_event_name(eventId))
      // Utility.log("mpv event (unhandled): \(eventName)")
    }

    // This code is running in the com.colliderli.iina.controller dispatch queue. We must not run
    // plugins from a task in this queue. Accessing EventController data from a thread in this queue
    // results in data races that can cause a crash. See issue 3986.
    DispatchQueue.main.async { [self] in
      let eventName = "mpv.\(String(cString: mpv_event_name(eventId)))"
      player.events.emit(.init(eventName))
    }
  }

  // MARK: - Property listeners

  private func handlePropertyChange(_ name: String, _ property: mpv_event_property) {

    switch name {

    case MPVProperty.audioDeviceList:
      DispatchQueue.main.async { self.player.audioDeviceListChanged() }

    case MPVProperty.videoParams:
      DispatchQueue.main.async { self.player.needReloadQuickSettingsView() }

    case MPVProperty.videoParamsRotate:
      guard let rotation = UnsafePointer<Int>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVProperty.videoParamsRotate, property.format)
        break
      }
      DispatchQueue.main.async { self.player.mainWindow.rotation = rotation }

    case MPVProperty.videoParamsPrimaries:
      fallthrough;

    case MPVProperty.videoParamsGamma:
      DispatchQueue.main.async { self.player.refreshEdrMode() }

    case MPVOption.TrackSelection.vid:
      DispatchQueue.main.async { self.player.vidChanged() }

    case MPVOption.TrackSelection.aid:
      DispatchQueue.main.async { self.player.aidChanged() }

    case MPVOption.TrackSelection.sid:
      DispatchQueue.main.async { self.player.sidChanged() }

    case MPVOption.Subtitles.secondarySid:
      DispatchQueue.main.async { self.player.secondarySidChanged() }

    case MPVOption.PlaybackControl.pause:
      guard let paused = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.PlaybackControl.pause, property.format)
        break
      }
      DispatchQueue.main.async { self.player.pauseChanged(paused) }

    case MPVProperty.chapter:
      DispatchQueue.main.async { self.player.chapterChanged() }

    case MPVOption.PlaybackControl.speed:
      guard let speed = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.PlaybackControl.speed, property.format)
        break
      }
      DispatchQueue.main.async { self.player.speedChanged(speed) }

    case MPVOption.PlaybackControl.loopPlaylist, MPVOption.PlaybackControl.loopFile:
      DispatchQueue.main.async { [self] in
        let loopMode = player.getLoopMode()
        switch loopMode {
        case .file:
          player.sendOSD(.fileLoop)
        case .playlist:
          player.sendOSD(.playlistLoop)
        default:
          player.sendOSD(.noLoop)
        }
        player.syncUI(.loop)
      }

    case MPVOption.Video.deinterlace:
      guard let data = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Video.deinterlace, property.format)
        break
      }
      DispatchQueue.main.async { [self] in
        // this property will fire a change event at file start
        if player.info.deinterlace != data {
          player.info.deinterlace = data
          player.sendOSD(.deinterlace(data))
        }
        player.needReloadQuickSettingsView()
      }

    case MPVOption.Video.hwdec:
      let data = String(cString: property.data.assumingMemoryBound(to: UnsafePointer<UInt8>.self).pointee)
      DispatchQueue.main.async { [self] in
        if player.info.hwdec != data {
          player.info.hwdec = data
          player.sendOSD(.hwdec(player.info.hwdecEnabled))
        }
        player.needReloadQuickSettingsView()
      }

    case MPVOption.Video.videoRotate:
      guard let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Video.videoRotate, property.format)
        break
      }
      let intData = Int(data)
      DispatchQueue.main.async { self.player.info.rotation = intData }

    case MPVOption.Audio.mute:
      guard let data = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Audio.mute, property.format)
        break
      }
      DispatchQueue.main.async { [self] in
        player.syncUI(.volume)
        player.info.isMuted = data
        player.sendOSD(data ? OSDMessage.mute : OSDMessage.unMute)
      }

    case MPVOption.Audio.volume:
      guard let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Audio.volume, property.format)
        break
      }
      DispatchQueue.main.async { [self] in
        player.info.volume = data
        player.syncUI(.volume)
        player.sendOSD(.volume(data))
      }

    case MPVOption.Audio.audioDelay:
      guard let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Audio.audioDelay, property.format)
        break
      }
      DispatchQueue.main.async { [self] in
        player.info.audioDelay = data
        player.sendOSD(.audioDelay(data))
        player.needReloadQuickSettingsView()
      }

    case MPVOption.Subtitles.subVisibility:
      if let visible = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
        DispatchQueue.main.async {
          self.player.subVisibilityChanged(visible)
        }
      }

    case MPVOption.Subtitles.secondarySubVisibility:
      if let visible = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
        DispatchQueue.main.async {
          self.player.secondSubVisibilityChanged(visible)
        }
      }

    case MPVOption.Subtitles.secondarySubDelay:
      fallthrough
    case MPVOption.Subtitles.subDelay:
      guard let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(name, property.format)
        break
      }
      guard name == MPVOption.Subtitles.subDelay else {
        DispatchQueue.main.async { self.player.secondarySubDelayChanged(data) }
        break
      }
      DispatchQueue.main.async { self.player.subDelayChanged(data) }

    case MPVOption.Subtitles.subScale:
      guard let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Subtitles.subScale, property.format)
        break
      }
      DispatchQueue.main.async { self.player.subScaleChanged(data) }

    case MPVOption.Subtitles.secondarySubPos:
      fallthrough
    case MPVOption.Subtitles.subPos:
      guard let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(name, property.format)
        break
      }
      guard name == MPVOption.Subtitles.subPos else {
        DispatchQueue.main.async { self.player.secondarySubPosChanged(data) }
        break
      }
      DispatchQueue.main.async { self.player.subPosChanged(data) }

    case MPVOption.Equalizer.contrast:
      guard let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Equalizer.contrast, property.format)
        break
      }
      let intData = Int(data)
      DispatchQueue.main.async { [self] in
        player.info.contrast = intData
        player.sendOSD(.contrast(intData))
        player.needReloadQuickSettingsView()
      }

    case MPVOption.Equalizer.hue:
      guard let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Equalizer.hue, property.format)
        break
      }
      let intData = Int(data)
      DispatchQueue.main.async { [self] in
        player.info.hue = intData
        player.sendOSD(.hue(intData))
        player.needReloadQuickSettingsView()
      }

    case MPVOption.Equalizer.brightness:
      guard let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Equalizer.brightness, property.format)
        break
      }
      let intData = Int(data)
      DispatchQueue.main.async { [self] in
        player.info.brightness = intData
        player.sendOSD(.brightness(intData))
        player.needReloadQuickSettingsView()
      }

    case MPVOption.Equalizer.gamma:
      guard let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Equalizer.gamma, property.format)
        break
      }
      let intData = Int(data)
      DispatchQueue.main.async { [self] in
        player.info.gamma = intData
        player.sendOSD(.gamma(intData))
        player.needReloadQuickSettingsView()
      }

    case MPVOption.Equalizer.saturation:
      guard let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Equalizer.saturation, property.format)
        break
      }
      let intData = Int(data)
      DispatchQueue.main.async { [self] in
        player.info.saturation = intData
        player.sendOSD(.saturation(intData))
        player.needReloadQuickSettingsView()
      }

    // following properties may change before file loaded

    case MPVProperty.playlistCount:
      DispatchQueue.main.async { self.player.postNotification(.iinaPlaylistChanged) }

    case MPVProperty.trackList:
      DispatchQueue.main.async { self.player.trackListChanged() }

    case MPVProperty.vf:
      DispatchQueue.main.async { [self] in
        player.vfChanged()
        player.needReloadQuickSettingsView()
      }

    case MPVProperty.af:
      DispatchQueue.main.async { self.player.afChanged() }

    case MPVOption.Window.fullscreen:
      DispatchQueue.main.async { self.player.fullscreenChanged() }

    case MPVOption.Window.ontop:
      DispatchQueue.main.async { self.player.ontopChanged() }

    case MPVOption.Window.windowScale:
      DispatchQueue.main.async { self.player.windowScaleChanged() }

    case MPVProperty.mediaTitle:
      DispatchQueue.main.async { self.player.mediaTitleChanged() }

    case MPVProperty.idleActive:
      guard let idleActive = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVProperty.idleActive, property.format)
        break
      }
      guard idleActive else { break }
      DispatchQueue.main.async { self.player.idleActiveChanged() }

    case MPVProperty.currentAo:
      DispatchQueue.main.async { self.player.currentAoChanged() }

    default:
      // Utility.log("MPV property changed (unhandled): \(name)")
      break
    }

    // This code is running in the com.colliderli.iina.controller dispatch queue. We must not run
    // plugins from a task in this queue. Accessing EventController data from a thread in this queue
    // results in data races that can cause a crash. See issue 3986.
    DispatchQueue.main.async { [self] in
      let eventName = EventController.Name("mpv.\(name).changed")
      if player.events.hasListener(for: eventName) {
        // FIXME: better convert to JSValue before passing to call()
        let data: Any
        switch property.format {
        case MPV_FORMAT_FLAG:
          data = property.data.bindMemory(to: Bool.self, capacity: 1).pointee
        case MPV_FORMAT_INT64:
          data = property.data.bindMemory(to: Int64.self, capacity: 1).pointee
        case MPV_FORMAT_DOUBLE:
          data = property.data.bindMemory(to: Double.self, capacity: 1).pointee
        case MPV_FORMAT_STRING:
          data = property.data.bindMemory(to: String.self, capacity: 1).pointee
        default:
          data = 0
        }
        player.events.emit(eventName, data: data)
      }
    }
  }

  // MARK: - User Options

  private enum UserOptionType {
    case bool, int, float, string, color, other
  }

  private struct OptionObserverInfo {
    typealias Transformer = (Preference.Key) -> String?

    var prefKey: Preference.Key
    var optionName: String
    var valueType: UserOptionType
    /** input a pref key and return the option value (as string) */
    var transformer: Transformer?

    init(_ prefKey: Preference.Key, _ optionName: String, _ valueType: UserOptionType, _ transformer: Transformer?) {
      self.prefKey = prefKey
      self.optionName = optionName
      self.valueType = valueType
      self.transformer = transformer
    }
  }

  private var optionObservers: [String: [OptionObserverInfo]] = [:]

  private func setOptionFlag(_ name: String, _ flag: Bool, level: Logger.Level = .debug,
                             verboseIfDefault: Bool = false) -> Int32 {
    let value = flag ? yes_str : no_str
    return setOptionString(name, value, level: level, verboseIfDefault: verboseIfDefault)
  }

  private func setOptionFloat(_ name: String, _ value: Float, level: Logger.Level = .debug,
                              verboseIfDefault: Bool = false) -> Int32 {
    let levelToUse: Logger.Level = {
      guard verboseIfDefault, let defaultValue = MPVOptionDefaults.shared.getDouble(name),
            abs(Double(value).distance(to: defaultValue)) <= Double.leastNonzeroMagnitude else {
        return level
      }
      return .verbose
    }()
    log("Set option: \(name)=\(value)", level: levelToUse)
    var data = Double(value)
    return mpv_set_option(mpv, name, MPV_FORMAT_DOUBLE, &data)
  }

  private func setOptionInt(_ name: String, _ value: Int, level: Logger.Level = .debug,
                            verboseIfDefault: Bool = false) -> Int32 {
    let levelToUse: Logger.Level = verboseIfDefault &&
      MPVOptionDefaults.shared.getInt(name) == value ? .verbose  : level
    log("Set option: \(name)=\(value)", level: levelToUse)
    var data = Int64(value)
    return mpv_set_option(mpv, name, MPV_FORMAT_INT64, &data)
  }

  @discardableResult
  private func setOptionString(_ name: String, _ value: String, level: Logger.Level = .debug,
                               verboseIfDefault: Bool = false) -> Int32 {
    let levelToUse: Logger.Level = verboseIfDefault &&
      MPVOptionDefaults.shared.getString(name) == value ? .verbose  : level
    log("Set option: \(name)=\(value)", level: levelToUse)
    return mpv_set_option_string(mpv, name, value)
  }

  /// Apply mpv's `config-dir` (and the related `config`, `load-auto-profiles`,
  /// `load-scripts` toggles) to the given path. The two `load-*` toggles are
  /// the mpv defaults, but pinning them here removes ambiguity about whether
  /// the bundled `scripts/` and `[profile]` sections will be honoured at
  /// runtime. See SPEC requirement 1 and PLAN Phase 1.
  private func setConfigDir(path: String) {
    chkErr(setOptionString("config", "yes", level: .verbose))
    chkErr(setOptionString(MPVOption.ProgramBehavior.loadAutoProfiles, "yes", level: .verbose))
    chkErr(setOptionString(MPVOption.ProgramBehavior.loadScripts, "yes", level: .verbose))
    let status = setOptionString(MPVOption.ProgramBehavior.configDir, path)
    if status < 0 {
      Utility.showAlert("extra_option.config_folder", arguments: [path], disableMenus: true)
    }
  }

  private func setOptionalOptionColor(_ name: String, _ value: String?,
                                       level: Logger.Level = .debug,
                                       verboseIfDefault: Bool = false) -> Int32 {
    guard let value = value else { return 0 }
    let levelToUse: Logger.Level = {
      // The default value for options of type color is currently returned by mpv in the alternative
      // string format that specifies component values in hex. Must convert to the form that uses
      // floating point to be able to compare the strings.
      guard verboseIfDefault, let defaultValue = MPVOptionDefaults.shared.getString(name),
            hexColorToFloat(defaultValue) == value else {
        return level
      }
      return .verbose
    }()
    return setOptionString(name, value, level: levelToUse)
  }

  private func setOptionalOptionString(_ name: String, _ value: String?, level: Logger.Level = .debug,
                                       verboseIfDefault: Bool = false) -> Int32 {
    guard let value = value, !value.isEmpty else { return 0 }
    return setOptionString(name, value, level: level, verboseIfDefault: verboseIfDefault)
  }

  /// Set the given mpv option to the value of the given IINA setting.
  ///
  /// To reduce the amount of logging that occurs when `MPVController` initializes a mpv core this method provides a
  /// `verboseIfDefault` parameter. If this parameter is set to `true` then the value to set the mpv option to is compared to the
  /// default value for the mpv option and if the values match then the value of the `level` parameter will be ignored and the
  /// message will be logged using the `verbose` level.
  /// - Parameters:
  ///   - key: Key for the IINA setting.
  ///   - type: Type of the value of the mpv option.
  ///   - name: Name of the mpv option.
  ///   - sync: Whether to add an observer for the IINA setting that updates the mpv option when the IINA setting changes.
  ///   - level: Log level to use when logging the setting of the option.
  ///   - verboseIfDefault: Whether to use log level `verbose` if the value matches the default for the mpv option.
  ///   - transformer: Optional transformer that changes the IINA setting value to be usable as the mpv option value.
  private func setUserOption(_ key: Preference.Key, type: UserOptionType, forName name: String,
                             sync: Bool = true, level: Logger.Level = .debug,
                             verboseIfDefault: Bool = false,
                             skipIfDefault: Bool = false,
                             transformer: OptionObserverInfo.Transformer? = nil) {
    var code: Int32 = 0

    let keyRawValue = key.rawValue

    switch type {
    case .int:
      let value = Preference.integer(for: key)
      if !(skipIfDefault && value == 0) {
        code = setOptionInt(name, value, level: level,
                            verboseIfDefault: verboseIfDefault)
      }

    case .float:
      let value = Preference.float(for: key)
      if !(skipIfDefault && value == 0) {
        code = setOptionFloat(name, value, level: level,
                              verboseIfDefault: verboseIfDefault)
      }

    case .bool:
      let value = Preference.bool(for: key)
      if !(skipIfDefault && !value) {
        code = setOptionFlag(name, value, level: level,
                             verboseIfDefault: verboseIfDefault)
      }

    case .string:
      code = setOptionalOptionString(name, Preference.string(for: key), level: level,
                                     verboseIfDefault: verboseIfDefault)

    case .color:
      let value = Preference.string(for: key)
      code = setOptionalOptionColor(name, value, level: level, verboseIfDefault: verboseIfDefault)
      // Random error here (perhaps a Swift or mpv one), so set it twice
      // 「没有什么是 set 不了的；如果有，那就 set 两次」
      if code < 0 {
        code = setOptionalOptionColor(name, value, level: level, verboseIfDefault: verboseIfDefault)
      }

    case .other:
      guard let tr = transformer else {
        log("setUserOption: no transformer!", level: .error)
        return
      }
      if let value = tr(key) {
        code = setOptionString(name, value, level: level, verboseIfDefault: verboseIfDefault)
      } else {
        code = 0
      }
    }

    if code < 0 {
      Utility.showAlert("mpv_error", arguments: [String(cString: mpv_error_string(code)), "\(code)", name],
                        disableMenus: true)
    }

    if sync {
      UserDefaults.standard.addObserver(self, forKeyPath: keyRawValue, options: [.new, .old], context: nil)
      if optionObservers[keyRawValue] == nil {
        optionObservers[keyRawValue] = []
      }
      optionObservers[keyRawValue]!.append(OptionObserverInfo(key, name, type, transformer))
    }
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard !(change?[NSKeyValueChangeKey.oldKey] is NSNull) else { return }

    guard let keyPath = keyPath else { return }
    guard let infos = optionObservers[keyPath] else { return }

    for info in infos {
      switch info.valueType {
      case .int:
        let value = Preference.integer(for: info.prefKey)
        setInt(info.optionName, value)

      case .float:
        let value = Preference.float(for: info.prefKey)
        setDouble(info.optionName, Double(value))

      case .bool:
        let value = Preference.bool(for: info.prefKey)
        setFlag(info.optionName, value)

      case .string:
        if let value = Preference.string(for: info.prefKey), !value.isEmpty {
          setString(info.optionName, value)
        }

      case .color:
        if let value = Preference.string(for: info.prefKey) {
          setString(info.optionName, value)
        }

      case .other:
        guard let tr = info.transformer else {
          log("setUserOption: no transformer!", level: .error)
          return
        }
        if let value = tr(info.prefKey) {
          setString(info.optionName, value)
        }
      }
    }
  }

  // MARK: - Utils

  /**
   Utility function for checking mpv api error
   */
  private func chkErr(_ status: Int32!) {
    guard status < 0 else { return }
    DispatchQueue.main.async {
      Logger.fatal("mpv API error: \"\(String(cString: mpv_error_string(status)))\", Return value: \(status!).")
    }
  }

  private func log(_ message: @autoclosure () -> String, level: Logger.Level = .debug) {
    Logger.log(message, level: level, subsystem: subsystem)
  }

  /// Log an error when a `mpv` property change event can't be processed because a property value could not be converted to the
  /// expected type.
  ///
  /// A [MPV_EVENT_PROPERTY_CHANGE](https://mpv.io/manual/stable/#command-interface-mpv-event-property-change)
  /// event contains the new value of the property. If that value could not be converted to the expected type then this method is called
  /// to log the problem.
  ///
  /// _However_ the situation is not that simple. The documentation for [mpv_observe_property](https://github.com/mpv-player/mpv/blob/023d02c9504e308ba5a295cd1846f2508b3dd9c2/libmpv/client.h#L1192-L1195)
  /// contains the following warning:
  ///
  /// "if a property is unavailable or retrieving it caused an error, `MPV_FORMAT_NONE` will be set in `mpv_event_property`, even
  /// if the format parameter was set to a different value. In this case, the `mpv_event_property.data` field is invalid"
  ///
  /// With mpv 0.35.0 we are receiving some property change events for the video-params/rotate property that do not contain the
  /// property value. This happens when the core starts before a file is loaded and when the core is stopping. At some point this needs
  /// to be investigated. For now we suppress logging an error for this known case.
  /// - Parameter property: Name of the property whose value changed.
  /// - Parameter format: Format of the value contained in the property change event.
  private func logPropertyValueError(_ property: String, _ format: mpv_format) {
    guard property != MPVProperty.videoParamsRotate || format != MPV_FORMAT_NONE else { return }
    log("""
      Value of property \(property) in the property change event could not be converted from
      \(format) to the expected type
      """, level: .error)
  }

  /// Convert the given mpv color string containing color components specified in hex to floating point.
  ///
  /// Normally color is specified in the form r/g/b, where each color component is specified as number in the range 0.0 to 1.0. It's also
  /// possible to specify the transparency by using r/g/b/a, where the alpha value 0 means fully transparent, and 1.0 means opaque.
  /// If the alpha component is not given, the color is 100% opaque. Alternatively, the color can be specified as a RGB hex triplet in the
  /// form #RRGGBB, where each 2-digit group expresses a color value in the range 0 (00) to 255 (FF). Alpha is given with #AARRGGBB.
  /// This method converts from the hex based alternative form to the floating point form.
  /// - Parameter color: Color with components specified in hex.
  /// - Returns: Color with components specified in floating point.
  private func hexColorToFloat(_ color: String) -> String {
    guard color.starts(with: "#"), color.count == 7 || color.count == 9 else {
      log("Invalid mpv hex color string: \(color)", level: .error)
      return color
    }
    var components: [String] = []
    for offset in stride(from: 1, to: color.count, by: 2) {
      let range = color.index(color.startIndex, offsetBy: offset)...color.index(color.startIndex, offsetBy: offset + 1)
      let value = Double(Int(color[range], radix: 16)!)
      components.append(String(value / 255))
    }
    guard components.count == 4 else {
      return components.joined(separator: "/")
    }
    // The alpha component comes first in the hex based form, last in the floating point form.
    let alpha = components[0]
    components.remove(at: 0)
    return "\(components.joined(separator: "/"))/\(alpha)"
  }

  /// Searches the list of user configured `mpv` options and returns `true` if the given option is present.
  /// - Parameter option: Option to look for.
  /// - Returns: `true` if the `mpv` option is found, `false` otherwise.
  /// SPEC ui-driven-mpv-options Phase 3: changed from private to internal
  /// so PlayerCore can guard the force-window hardcode with this check.
  func userOptionsContains(_ option: String) -> Bool {
    guard Preference.bool(for: .enableAdvancedSettings),
          let userOptions = Preference.value(for: .userOptions) as? [[String]] else { return false }
    return userOptions.contains { $0[0] == option }
  }
}

fileprivate func mpvGetOpenGLFunc(_ ctx: UnsafeMutableRawPointer?, _ name: UnsafePointer<Int8>?) -> UnsafeMutableRawPointer? {
  let symbolName: CFString = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingASCII);
  guard let addr = CFBundleGetFunctionPointerForName(CFBundleGetBundleWithIdentifier(CFStringCreateCopy(kCFAllocatorDefault, "com.apple.opengl" as CFString)), symbolName) else {
    Logger.fatal("Cannot get OpenGL function pointer!")
  }
  return addr
}

fileprivate func mpvUpdateCallback(_ ctx: UnsafeMutableRawPointer?) {
  let layer = bridge(ptr: ctx!) as ViewLayer
  layer.update()
}
