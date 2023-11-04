//
//  MPVController.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import JavaScriptCore

fileprivate let yes_str = "yes"
fileprivate let no_str = "no"

/** Change this variable to adjust mpv log level */
/*
 "no"    - disable absolutely all messages
 "fatal" - critical/aborting errors
 "error" - simple errors
 "warn"  - possible problems
 "info"  - informational message
 "v"     - noisy informational message
 "debug" - very noisy technical information
 "trace" - extremely noisy
 */
fileprivate let MPVLogLevel = "warn"
fileprivate let mpvSubsystem = Logger.makeSubsystem("mpv")
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

protocol MPVEventDelegate {
  func onMPVEvent(_ event: MPVEvent)
}

class MPVController: NSObject {
  struct UserData {
    static let screenshot: UInt64 = 1000000
  }

  // The mpv_handle
  var mpv: OpaquePointer!
  var mpvRenderContext: OpaquePointer?

  private var openGLContext: CGLContextObj! = nil

  var mpvClientName: UnsafePointer<CChar>!
  var mpvVersion: String!

  lazy var queue = DispatchQueue(label: "com.colliderli.iina.controller", qos: .userInitiated)

  unowned let player: PlayerCore

  var needRecordSeekTime: Bool = false
  var recordedSeekStartTime: CFTimeInterval = 0
  var recordedSeekTimeListener: ((Double) -> Void)?

  var receivedEndFileWhileLoading: Bool = false

  var fileLoaded: Bool = false

  private var hooks: [UInt64: MPVHookValue] = [:]
  private var hookCounter: UInt64 = 1

  let observeProperties: [String: mpv_format] = [
    MPVProperty.trackList: MPV_FORMAT_NONE,
    MPVProperty.vf: MPV_FORMAT_NONE,
    MPVProperty.af: MPV_FORMAT_NONE,
    MPVOption.TrackSelection.vid: MPV_FORMAT_INT64,
    MPVOption.TrackSelection.aid: MPV_FORMAT_INT64,
    MPVOption.TrackSelection.sid: MPV_FORMAT_INT64,
    MPVOption.Subtitles.secondarySid: MPV_FORMAT_INT64,
    MPVOption.PlaybackControl.pause: MPV_FORMAT_FLAG,
    MPVOption.PlaybackControl.loopPlaylist: MPV_FORMAT_STRING,
    MPVProperty.chapter: MPV_FORMAT_INT64,
    MPVOption.Video.deinterlace: MPV_FORMAT_FLAG,
    MPVOption.Video.hwdec: MPV_FORMAT_STRING,
    MPVOption.Video.videoRotate: MPV_FORMAT_INT64,
    MPVOption.Audio.mute: MPV_FORMAT_FLAG,
    MPVOption.Audio.volume: MPV_FORMAT_DOUBLE,
    MPVOption.Audio.audioDelay: MPV_FORMAT_DOUBLE,
    MPVOption.PlaybackControl.speed: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.subDelay: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.subScale: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.subPos: MPV_FORMAT_DOUBLE,
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
    MPVProperty.idleActive: MPV_FORMAT_FLAG
  ]

  init(playerCore: PlayerCore) {
    self.player = playerCore
    super.init()
  }

  deinit {
    removeOptionObservers()
  }


  /// Determine if this Mac has an Apple Silicon chip.
  /// - Returns: `true` if running on a Mac with an Apple Silicon chip, `false` otherwise.
  private func runningOnAppleSilicon() -> Bool {
    // Old versions of macOS do not support Apple Silicon.
    if #unavailable(macOS 11.0) {
      return false
    }
    var sysinfo = utsname()
    let result = uname(&sysinfo)
    guard result == EXIT_SUCCESS else {
      Logger.log("uname failed returning \(result)", level: .error)
      return false
    }
    let data = Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN))
    guard let machine = String(bytes: data, encoding: .ascii) else {
      Logger.log("Failed to construct string for sysinfo.machine", level: .error)
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
      Logger.log("Running on Apple Silicon, not applying FFmpeg 9599 workaround")
      return
    }
    // Do not apply the workaround if the user has configured a value for the hwdec-codecs option in
    // IINA's advanced settings. This code is only needed to avoid emitting confusing log messages
    // as the user's settings are applied after this and would overwrite the workaround, but without
    // this check the log would indicate VP9 hardware acceleration is disabled, which may or may not
    // be true.
    if Preference.bool(for: .enableAdvancedSettings),
        let userOptions = Preference.value(for: .userOptions) as? [[String]] {
      for op in userOptions {
        guard op[0] != MPVOption.Video.hwdecCodecs else {
          Logger.log("""
Option \(MPVOption.Video.hwdecCodecs) has been set in advanced settings, \
not applying FFmpeg 9599 workaround
""")
          return
        }
      }
    }
    // Apply the workaround.
    Logger.log("Disabling hardware acceleration for VP9 encoded videos to workaround FFmpeg 9599")
    let value = "h264,vc1,hevc,vp8,av1,prores"
    mpv_set_option_string(mpv, MPVOption.Video.hwdecCodecs, value)
    Logger.log("Option \(MPVOption.Video.hwdecCodecs) has been set to: \(value)")
  }

  /**
   Init the mpv context, set options
   */
  func mpvInit() {
    // Create a new mpv instance and an associated client API handle to control the mpv instance.
    mpv = mpv_create()

    // Get the name of this client handle.
    mpvClientName = mpv_client_name(mpv)

    // User default settings

    if Preference.bool(for: .enableInitialVolume) {
      setUserOption(PK.initialVolume, type: .int, forName: MPVOption.Audio.volume, sync: false)
    } else {
      setUserOption(PK.softVolume, type: .int, forName: MPVOption.Audio.volume, sync: false)
    }

    // - Advanced

    // disable internal OSD
    let useMpvOsd = Preference.bool(for: .enableAdvancedSettings) && Preference.bool(for: .useMpvOsd)
    if !useMpvOsd {
      chkErr(mpv_set_option_string(mpv, MPVOption.OSD.osdLevel, "0"))
    } else {
      player.displayOSD = false
    }

    // log
    if Logger.enabled {
      let path = Logger.logDirectory.appendingPathComponent("mpv.log").path
      chkErr(mpv_set_option_string(mpv, MPVOption.ProgramBehavior.logFile, path))
    }

    applyHardwareAccelerationWorkaround()

    // - General

    let setScreenshotPath = { (key: Preference.Key) -> String in
      let screenshotPath = Preference.string(for: .screenshotFolder)!
      return Preference.bool(for: .screenshotSaveToFile) ?
        NSString(string: screenshotPath).expandingTildeInPath :
        Utility.screenshotCacheURL.path
    }

    setUserOption(PK.screenshotFolder, type: .other, forName: MPVOption.Screenshot.screenshotDirectory, transformer: setScreenshotPath)
    setUserOption(PK.screenshotSaveToFile, type: .other, forName: MPVOption.Screenshot.screenshotDirectory, transformer: setScreenshotPath)

    setUserOption(PK.screenshotFormat, type: .other, forName: MPVOption.Screenshot.screenshotFormat) { key in
      let v = Preference.integer(for: key)
      return Preference.ScreenshotFormat(rawValue: v)?.string
    }

    setUserOption(PK.screenshotTemplate, type: .string, forName: MPVOption.Screenshot.screenshotTemplate)

    // Disable mpv's media key system as it now uses the MediaPlayer Framework.
    // Dropped media key support in 10.11 and 10.12.
    chkErr(mpv_set_option_string(mpv, MPVOption.Input.inputMediaKeys, no_str))

    setUserOption(PK.keepOpenOnFileEnd, type: .other, forName: MPVOption.Window.keepOpen) { key in
      let keepOpen = Preference.bool(for: PK.keepOpenOnFileEnd)
      let keepOpenPl = !Preference.bool(for: PK.playlistAutoPlayNext)
      return keepOpenPl ? "always" : (keepOpen ? "yes" : "no")
    }

    setUserOption(PK.playlistAutoPlayNext, type: .other, forName: MPVOption.Window.keepOpen) { key in
      let keepOpen = Preference.bool(for: PK.keepOpenOnFileEnd)
      let keepOpenPl = !Preference.bool(for: PK.playlistAutoPlayNext)
      return keepOpenPl ? "always" : (keepOpen ? "yes" : "no")
    }

    chkErr(mpv_set_option_string(mpv, "watch-later-directory", Utility.watchLaterURL.path))
    setUserOption(PK.resumeLastPosition, type: .bool, forName: MPVOption.WatchLater.savePositionOnQuit)
    setUserOption(PK.resumeLastPosition, type: .bool, forName: "resume-playback")

    setUserOption(.initialWindowSizePosition, type: .string, forName: MPVOption.Window.geometry)

    // - Codec

    setUserOption(PK.videoThreads, type: .int, forName: MPVOption.Video.vdLavcThreads)
    setUserOption(PK.audioThreads, type: .int, forName: MPVOption.Audio.adLavcThreads)

    setUserOption(PK.hardwareDecoder, type: .other, forName: MPVOption.Video.hwdec) { key in
      let value = Preference.integer(for: key)
      return Preference.HardwareDecoderOption(rawValue: value)?.mpvString ?? "auto"
    }

    setUserOption(PK.audioLanguage, type: .string, forName: MPVOption.TrackSelection.alang)
    setUserOption(PK.maxVolume, type: .int, forName: MPVOption.Audio.volumeMax)

    var spdif: [String] = []
    if Preference.bool(for: PK.spdifAC3) { spdif.append("ac3") }
    if Preference.bool(for: PK.spdifDTS){ spdif.append("dts") }
    if Preference.bool(for: PK.spdifDTSHD) { spdif.append("dts-hd") }
    setString(MPVOption.Audio.audioSpdif, spdif.joined(separator: ","))

    setUserOption(PK.audioDevice, type: .string, forName: MPVOption.Audio.audioDevice)

    // - Sub

    chkErr(mpv_set_option_string(mpv, MPVOption.Subtitles.subAuto, "no"))
    chkErr(mpv_set_option_string(mpv, MPVOption.Subtitles.subCodepage, Preference.string(for: .defaultEncoding)))
    player.info.subEncoding = Preference.string(for: .defaultEncoding)

    let subOverrideHandler: OptionObserverInfo.Transformer = { key in
      let v = Preference.bool(for: .ignoreAssStyles)
      let level: Preference.SubOverrideLevel = Preference.enum(for: .subOverrideLevel)
      return v ? level.string : "yes"
    }

    setUserOption(PK.ignoreAssStyles, type: .other, forName: MPVOption.Subtitles.subAssOverride, transformer: subOverrideHandler)
    setUserOption(PK.subOverrideLevel, type: .other, forName: MPVOption.Subtitles.subAssOverride, transformer: subOverrideHandler)

    setUserOption(PK.subTextFont, type: .string, forName: MPVOption.Subtitles.subFont)
    setUserOption(PK.subTextSize, type: .int, forName: MPVOption.Subtitles.subFontSize)

    setUserOption(PK.subTextColor, type: .color, forName: MPVOption.Subtitles.subColor)
    setUserOption(PK.subBgColor, type: .color, forName: MPVOption.Subtitles.subBackColor)

    setUserOption(PK.subBold, type: .bool, forName: MPVOption.Subtitles.subBold)
    setUserOption(PK.subItalic, type: .bool, forName: MPVOption.Subtitles.subItalic)

    setUserOption(PK.subBlur, type: .float, forName: MPVOption.Subtitles.subBlur)
    setUserOption(PK.subSpacing, type: .float, forName: MPVOption.Subtitles.subSpacing)

    setUserOption(PK.subBorderSize, type: .int, forName: MPVOption.Subtitles.subBorderSize)
    setUserOption(PK.subBorderColor, type: .color, forName: MPVOption.Subtitles.subBorderColor)

    setUserOption(PK.subShadowSize, type: .int, forName: MPVOption.Subtitles.subShadowOffset)
    setUserOption(PK.subShadowColor, type: .color, forName: MPVOption.Subtitles.subShadowColor)

    setUserOption(PK.subAlignX, type: .other, forName: MPVOption.Subtitles.subAlignX) { key in
      let v = Preference.integer(for: key)
      return Preference.SubAlign(rawValue: v)?.stringForX
    }

    setUserOption(PK.subAlignY, type: .other, forName: MPVOption.Subtitles.subAlignY) { key in
      let v = Preference.integer(for: key)
      return Preference.SubAlign(rawValue: v)?.stringForY
    }

    setUserOption(PK.subMarginX, type: .int, forName: MPVOption.Subtitles.subMarginX)
    setUserOption(PK.subMarginY, type: .int, forName: MPVOption.Subtitles.subMarginY)

    setUserOption(PK.subPos, type: .int, forName: MPVOption.Subtitles.subPos)

    setUserOption(PK.subLang, type: .string, forName: MPVOption.TrackSelection.slang)

    setUserOption(PK.displayInLetterBox, type: .bool, forName: MPVOption.Subtitles.subUseMargins)
    setUserOption(PK.displayInLetterBox, type: .bool, forName: MPVOption.Subtitles.subAssForceMargins)

    setUserOption(PK.subScaleWithWindow, type: .bool, forName: MPVOption.Subtitles.subScaleByWindow)

    // - Network / cache settings

    setUserOption(PK.enableCache, type: .other, forName: MPVOption.Cache.cache) { key in
      return Preference.bool(for: key) ? nil : "no"
    }

    setUserOption(PK.defaultCacheSize, type: .other, forName: MPVOption.Demuxer.demuxerMaxBytes) { key in
      return "\(Preference.integer(for: key))KiB"
    }
    setUserOption(PK.secPrefech, type: .int, forName: MPVOption.Cache.cacheSecs)

    setUserOption(PK.userAgent, type: .other, forName: MPVOption.Network.userAgent) { key in
      let ua = Preference.string(for: key)!
      return ua.isEmpty ? nil : ua
    }

    setUserOption(PK.transportRTSPThrough, type: .other, forName: MPVOption.Network.rtspTransport) { key in
      let v: Preference.RTSPTransportation = Preference.enum(for: .transportRTSPThrough)
      return v.string
    }

    setUserOption(PK.ytdlEnabled, type: .bool, forName: MPVOption.ProgramBehavior.ytdl)
    setUserOption(PK.ytdlRawOptions, type: .string, forName: MPVOption.ProgramBehavior.ytdlRawOptions)
    chkErr(mpv_set_option_string(mpv, MPVOption.ProgramBehavior.resetOnNextFile,
            "\(MPVOption.PlaybackControl.abLoopA),\(MPVOption.PlaybackControl.abLoopB)"))

    // Set user defined conf dir.
    if Preference.bool(for: .enableAdvancedSettings),
       Preference.bool(for: .useUserDefinedConfDir),
       var userConfDir = Preference.string(for: .userDefinedConfDir) {
      userConfDir = NSString(string: userConfDir).standardizingPath
      mpv_set_option_string(mpv, "config", "yes")
      let status = mpv_set_option_string(mpv, MPVOption.ProgramBehavior.configDir, userConfDir)
      if status < 0 {
        Utility.showAlert("extra_option.config_folder", arguments: [userConfDir])
      }
    }

    // Set user defined options.
    if Preference.bool(for: .enableAdvancedSettings) {
      if let userOptions = Preference.value(for: .userOptions) as? [[String]] {
        userOptions.forEach { op in
          let status = mpv_set_option_string(mpv, op[0], op[1])
          if status < 0 {
            Utility.showAlert("extra_option.error", arguments:
              [op[0], op[1], status])
          }
        }
      } else {
        Utility.showAlert("extra_option.cannot_read")
      }
    }

    // Load external scripts

    // Load keybindings. This is still required for mpv to handle media keys or apple remote.
    let userConfigs = Preference.dictionary(for: .inputConfigs)
    var inputConfPath =  PrefKeyBindingViewController.defaultConfigs["IINA Default"]
    if let confFromUd = Preference.string(for: .currentInputConfigName) {
      if let currentConfigFilePath = Utility.getFilePath(Configs: userConfigs, forConfig: confFromUd, showAlert: false) {
        inputConfPath = currentConfigFilePath
      }
    }
    chkErr(mpv_set_option_string(mpv, MPVOption.Input.inputConf, inputConfPath))

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

    // Initialize an uninitialized mpv instance. If the mpv instance is already running, an error is returned.
    chkErr(mpv_initialize(mpv))

    // Set options that can be override by user's config. mpv will log user config when initialize,
    // so we put them here.
    chkErr(mpv_set_property_string(mpv, MPVOption.Video.vo, "libmpv"))
    chkErr(mpv_set_property_string(mpv, MPVOption.Window.keepaspect, "no"))
    chkErr(mpv_set_property_string(mpv, MPVOption.Video.gpuHwdecInterop, "auto"))

    // get version
    mpvVersion = getString(MPVProperty.mpvVersion)
  }

  func mpvInitRendering() {
    guard let mpv = mpv else {
      fatalError("mpvInitRendering() should be called after mpv handle being initialized!")
    }
    let apiType = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String)
    var openGLInitParams = mpv_opengl_init_params(get_proc_address: mpvGetOpenGLFunc,
                                                  get_proc_address_ctx: nil)
    withUnsafeMutablePointer(to: &openGLInitParams) { openGLInitParams in
      // var advanced: CInt = 1
      var params = [
        mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiType),
        mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: openGLInitParams),
        // mpv_render_param(type: MPV_RENDER_PARAM_ADVANCED_CONTROL, data: &advanced),
        mpv_render_param()
      ]
      mpv_render_context_create(&mpvRenderContext, mpv, &params)
      openGLContext = CGLGetCurrentContext()
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
    lockAndSetOpenGLContext()
    defer { unlockOpenGLContext() }
    mpv_render_context_free(mpvRenderContext)
  }

  func mpvReportSwap() {
    guard let mpvRenderContext = mpvRenderContext else { return }
    mpv_render_context_report_swap(mpvRenderContext)
  }

  func shouldRenderUpdateFrame() -> Bool {
    guard let mpvRenderContext = mpvRenderContext else { return false }
    guard !player.isStopping && !player.isShuttingDown else { return false }
    let flags: UInt64 = mpv_render_context_update(mpvRenderContext)
    return flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) > 0
  }

  /// Remove registered observers for IINA preferences.
  private func removeOptionObservers() {
    // Remove observers for IINA preferences.
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
    command(.quit)
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
  func command(_ command: MPVCommand, args: [String?] = [], checkError: Bool = true, returnValueCallback: ((Int32) -> Void)? = nil) {
    guard mpv != nil else { return }
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

  func command(rawString: String) -> Int32 {
    return mpv_command_string(mpv, rawString)
  }

  func asyncCommand(_ command: MPVCommand, args: [String?] = [], checkError: Bool = true, replyUserdata: UInt64) {
    guard mpv != nil else { return }
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
  func setFlag(_ name: String, _ flag: Bool) {
    var data: Int = flag ? 1 : 0
    mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
  }

  func setInt(_ name: String, _ value: Int) {
    var data = Int64(value)
    mpv_set_property(mpv, name, MPV_FORMAT_INT64, &data)
  }

  func setDouble(_ name: String, _ value: Double) {
    var data = value
    mpv_set_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
  }

  func setFlagAsync(_ name: String, _ flag: Bool) {
    var data: Int = flag ? 1 : 0
    mpv_set_property_async(mpv, 0, name, MPV_FORMAT_FLAG, &data)
  }

  func setIntAsync(_ name: String, _ value: Int) {
    var data = Int64(value)
    mpv_set_property_async(mpv, 0, name, MPV_FORMAT_INT64, &data)
  }

  func setDoubleAsync(_ name: String, _ value: Double) {
    var data = value
    mpv_set_property_async(mpv, 0, name, MPV_FORMAT_DOUBLE, &data)
  }

  func setString(_ name: String, _ value: String) {
    mpv_set_property_string(mpv, name, value)
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
    var data = Int64()
    mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &data)
    return data > 0
  }

  func getString(_ name: String) -> String? {
    let cstr = mpv_get_property_string(mpv, name)
    let str: String? = cstr == nil ? nil : String(cString: cstr!)
    mpv_free(cstr)
    return str
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
      Logger.log("Found \(oldList.num) \(name) filters, index of filter to remove (\(index)) is invalid",
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
      Logger.log("setNode: cannot encode value for \(name)", level: .error)
      return
    }
    mpv_set_property(mpv, name, MPV_FORMAT_NODE, &node)
    MPVNode.free(node)
  }

  // MARK: - Hooks

  func addHook(_ name: MPVHook, priority: Int32 = 0, hook: MPVHookValue) {
    mpv_hook_add(mpv, hookCounter, name.rawValue, priority)
    hooks[hookCounter] = hook
    hookCounter += 1
  }

  func removeHooks(withIdentifier id: String) {
    hooks.filter { (k, v) in v.isJavascript && v.id == id }.keys.forEach { hooks.removeValue(forKey: $0) }
  }

  // MARK: - Events

  // Read event and handle it async
  private func readEvents() {
    queue.async {
      while ((self.mpv) != nil) {
        let event = mpv_wait_event(self.mpv, 0)
        // Do not deal with mpv-event-none
        if event?.pointee.event_id == MPV_EVENT_NONE {
          break
        }
        self.handleEvent(event)
      }
    }
  }

  /// Tell Cocoa to terminate the application.
  ///
  /// - Note: This code must be in a method that can be a target of a selector in order to support macOS 10.11.
  ///     The `perform` method in `RunLoop` that accepts a closure was introduced in macOS 10.12. If IINA drops
  ///     support for 10.11 then the code in this method can be moved to the closure in `handleEvent and this
  ///     method can then be removed.`
  @objc
  internal func terminateApplication() {
    NSApp.terminate(nil)
  }

  // Handle the event
  private func handleEvent(_ event: UnsafePointer<mpv_event>!) {
    let eventId = event.pointee.event_id

    switch eventId {
    case MPV_EVENT_SHUTDOWN:
      let quitByMPV = !player.isShuttingDown
      if quitByMPV {
        // This happens when the user presses "q" in a player window and the quit command is sent
        // directly to mpv. The user could also use mpv's IPC interface to send the quit command to
        // mpv. Must not attempt to change a mpv setting in response to an IINA preference change
        // now that mpv has shut down. This is not needed when IINA sends the quit command to mpv
        // as in that case the observers are removed before the quit command is sent.
        removeOptionObservers()
        // Submit the following task synchronously to ensure it is done before application
        // termination is started.
        DispatchQueue.main.sync {
          self.player.mpvHasShutdown(isMPVInitiated: true)
        }
        // Initiate application termination. AppKit requires this be done from the main thread,
        // however the main dispatch queue must not be used to avoid blocking the queue as per
        // instructions from Apple.
        if #available(macOS 10.12, *) {
          RunLoop.main.perform(inModes: [.common]) {
            self.terminateApplication()
          }
        } else {
          RunLoop.main.perform(#selector(self.terminateApplication), target: self,
                               argument: nil, order: Int.min, modes: [.common])
        }
      } else {
        mpv_destroy(mpv)
        mpv = nil
        DispatchQueue.main.async {
          self.player.mpvHasShutdown()
        }
      }

    case MPV_EVENT_LOG_MESSAGE:
      let dataOpaquePtr = OpaquePointer(event.pointee.data)
      let msg = UnsafeMutablePointer<mpv_event_log_message>(dataOpaquePtr)
      let prefix = String(cString: (msg?.pointee.prefix)!)
      let level = String(cString: (msg?.pointee.level)!)
      let text = String(cString: (msg?.pointee.text)!).trimmingCharacters(in: .newlines)
      Logger.log("[\(prefix)] \(level): \(text)", level: logLevelMap[level] ?? .verbose, subsystem: mpvSubsystem)

    case MPV_EVENT_HOOK:
      let userData = event.pointee.reply_userdata
      let hookEvent = event.pointee.data.bindMemory(to: mpv_event_hook.self, capacity: 1).pointee
      let hookID = hookEvent.id
      if let hook = hooks[userData] {
        hook.call {
          mpv_hook_continue(self.mpv, hookID)
        }
      }

    case MPV_EVENT_PROPERTY_CHANGE:
      let dataOpaquePtr = OpaquePointer(event.pointee.data)
      if let property = UnsafePointer<mpv_event_property>(dataOpaquePtr)?.pointee {
        let propertyName = String(cString: property.name)
        handlePropertyChange(propertyName, property)
      }

    case MPV_EVENT_AUDIO_RECONFIG: break

    case MPV_EVENT_VIDEO_RECONFIG:
      player.onVideoReconfig()

    case MPV_EVENT_START_FILE:
      player.info.isIdle = false
      guard let path = getString(MPVProperty.path) else { break }
      player.fileStarted(path: path)
      let url = player.info.currentURL
      let message = player.info.isNetworkResource ? url?.absoluteString : url?.lastPathComponent
      player.sendOSD(.fileStart(message ?? "-"))

    case MPV_EVENT_FILE_LOADED:
      onFileLoaded()

    case MPV_EVENT_SEEK:
      player.info.isSeeking = true
      DispatchQueue.main.sync {
        // When playback is paused the display link may be shutdown in order to not waste energy.
        // It must be running when seeking to avoid slowdowns caused by mpv waiting for IINA to call
        // mpv_render_report_swap.
        player.mainWindow.videoView.displayActive()
      }
      if needRecordSeekTime {
        recordedSeekStartTime = CACurrentMediaTime()
      }
      player.syncUI(.time)
      let osdText = (player.info.videoPosition?.stringRepresentation ?? Constants.String.videoTimePlaceholder) + " / " +
        (player.info.videoDuration?.stringRepresentation ?? Constants.String.videoTimePlaceholder)
      let percentage = (player.info.videoPosition / player.info.videoDuration) ?? 1
      player.sendOSD(.seek(osdText, percentage))

    case MPV_EVENT_PLAYBACK_RESTART:
      player.info.isIdle = false
      player.info.isSeeking = false
      DispatchQueue.main.sync {
        // When playback is paused the display link may be shutdown in order to not waste energy.
        // The display link will be restarted while seeking. If playback is paused shut it down
        // again.
        if player.info.isPaused {
          player.mainWindow.videoView.displayIdle()
        }
      }
      if needRecordSeekTime {
        recordedSeekTimeListener?(CACurrentMediaTime() - recordedSeekStartTime)
        recordedSeekTimeListener = nil
      }
      player.playbackRestarted()
      player.syncUI(.time)

    case MPV_EVENT_END_FILE:
      // if receive end-file when loading file, might be error
      // wait for idle
      let reason = event!.pointee.data.load(as: mpv_end_file_reason.self)
      if player.info.fileLoading {
        if reason != MPV_END_FILE_REASON_STOP {
          receivedEndFileWhileLoading = true
        }
      } else {
        player.info.shouldAutoLoadFiles = false
      }
      if reason == MPV_END_FILE_REASON_STOP {
        DispatchQueue.main.async {
          self.player.playbackStopped()
        }
      }

    case MPV_EVENT_COMMAND_REPLY:
      let reply = event.pointee.reply_userdata
      if reply == MPVController.UserData.screenshot {
        let code = event.pointee.error
        guard code >= 0 else {
          let error = String(cString: mpv_error_string(code))
          Logger.log("Cannot take a screenshot, mpv API error: \(error), Return value: \(code)", level: .error)
          // Unfortunately the mpv API does not provide any details on the failure. The error
          // code returned maps to "error running command", so all the alert can report is
          // that we cannot take a screenshot.
          DispatchQueue.main.async {
            Utility.showAlert("screenshot.error_taking")
          }
          return
        }
        player.screenshotCallback()
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

  private func onVideoParamsChange(_ data: UnsafePointer<mpv_node_list>) {
    //let params = data.pointee
    //params.keys.
  }

  private func onFileLoaded() {
    // mpvSuspend()
    setFlag(MPVOption.PlaybackControl.pause, true)
    // Get video size and set the initial window size
    let width = getInt(MPVProperty.width)
    let height = getInt(MPVProperty.height)
    let duration = getDouble(MPVProperty.duration)
    let pos = getDouble(MPVProperty.timePos)
    player.info.videoHeight = height
    player.info.videoWidth = width
    player.info.displayWidth = 0
    player.info.displayHeight = 0
    player.info.videoDuration = VideoTime(duration)
    if let filename = getString(MPVProperty.path) {
      self.player.info.setCachedVideoDuration(filename, duration)
    }
    player.info.videoPosition = VideoTime(pos)
    player.fileLoaded()
    fileLoaded = true
    // mpvResume()
    if !(player.info.justOpenedFile && Preference.bool(for: .pauseWhenOpen)) {
      setFlag(MPVOption.PlaybackControl.pause, false)
    }
    player.syncUI(.playlist)
  }

  // MARK: - Property listeners

  private func handlePropertyChange(_ name: String, _ property: mpv_event_property) {

    var needReloadQuickSettingsView = false

    switch name {

    case MPVProperty.videoParams:
      needReloadQuickSettingsView = true
      onVideoParamsChange(UnsafePointer<mpv_node_list>(OpaquePointer(property.data)))

    case MPVProperty.videoParamsRotate:
      if let rotation = UnsafePointer<Int>(OpaquePointer(property.data))?.pointee {
        player.mainWindow.rotation = rotation
      }

    case MPVProperty.videoParamsPrimaries:
      fallthrough;

    case MPVProperty.videoParamsGamma:
      if #available(macOS 10.15, *) {
        player.refreshEdrMode()
      }

    case MPVOption.TrackSelection.vid:
      player.vidChanged()

    case MPVOption.TrackSelection.aid:
      player.aidChanged()

    case MPVOption.TrackSelection.sid:
      player.sidChanged()

    case MPVOption.Subtitles.secondarySid:
      player.secondarySidChanged()

    case MPVOption.PlaybackControl.pause:
      if let paused = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
        if player.info.isPaused != paused {
          player.sendOSD(paused ? .pause : .resume)
          DispatchQueue.main.sync {
            player.info.isPaused = paused
            // Follow energy efficiency best practices and ensure IINA is absolutely idle when the
            // video is paused to avoid wasting energy with needless processing. If paused shutdown
            // the timer that synchronizes the UI and the high priority display link thread.
            if paused {
              player.invalidateTimer()
              player.mainWindow.videoView.displayIdle()
            } else {
              player.mainWindow.videoView.displayActive()
              player.createSyncUITimer()
            }
          }
        }
        if player.mainWindow.loaded && Preference.bool(for: .alwaysFloatOnTop) {
          DispatchQueue.main.async {
            self.player.mainWindow.setWindowFloatingOnTop(!paused)
          }
        }
      }
      player.syncUI(.playButton)

    case MPVProperty.chapter:
      player.info.chapter = Int(getInt(MPVProperty.chapter))
      player.syncUI(.time)
      player.syncUI(.chapterList)
      player.postNotification(.iinaMediaTitleChanged)

    case MPVOption.PlaybackControl.speed:
      needReloadQuickSettingsView = true
      if let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
        player.info.playSpeed = data
        player.sendOSD(.speed(data))
      }

    case MPVOption.PlaybackControl.loopPlaylist:
      player.syncUI(.playlistLoop)

    case MPVOption.Video.deinterlace:
      needReloadQuickSettingsView = true
      if let data = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
        // this property will fire a change event at file start
        if player.info.deinterlace != data {
          player.info.deinterlace = data
          player.sendOSD(.deinterlace(data))
        }
      }

    case MPVOption.Video.hwdec:
      needReloadQuickSettingsView = true
      let data = String(cString: property.data.assumingMemoryBound(to: UnsafePointer<UInt8>.self).pointee)
      if player.info.hwdec != data {
        player.info.hwdec = data
        player.sendOSD(.hwdec(player.info.hwdecEnabled))
      }

    case MPVOption.Video.videoRotate:
      if let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee {
      let intData = Int(data)
        player.info.rotation = intData
      }

    case MPVOption.Audio.mute:
      player.syncUI(.muteButton)
      if let data = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
        player.info.isMuted = data
        player.sendOSD(data ? OSDMessage.mute : OSDMessage.unMute)
      }

    case MPVOption.Audio.volume:
      if let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
        player.info.volume = data
        player.syncUI(.volume)
        player.sendOSD(.volume(Int(data)))
      }

    case MPVOption.Audio.audioDelay:
      needReloadQuickSettingsView = true
      if let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
        player.info.audioDelay = data
        player.sendOSD(.audioDelay(data))
      }

    case MPVOption.Subtitles.subDelay:
      needReloadQuickSettingsView = true
      if let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
        player.info.subDelay = data
        player.sendOSD(.subDelay(data))
      }

    case MPVOption.Subtitles.subScale:
      needReloadQuickSettingsView = true
      if let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
        let displayValue = data >= 1 ? data : -1/data
        let truncated = round(displayValue * 100) / 100
        player.sendOSD(.subScale(truncated))
      }

    case MPVOption.Subtitles.subPos:
      needReloadQuickSettingsView = true
      if let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
        player.sendOSD(.subPos(data))
      }

    case MPVOption.Equalizer.contrast:
      needReloadQuickSettingsView = true
      if let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee {
        let intData = Int(data)
        player.info.contrast = intData
        player.sendOSD(.contrast(intData))
      }

    case MPVOption.Equalizer.hue:
      needReloadQuickSettingsView = true
      if let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee {
        let intData = Int(data)
        player.info.hue = intData
        player.sendOSD(.hue(intData))
      }

    case MPVOption.Equalizer.brightness:
      needReloadQuickSettingsView = true
      if let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee {
        let intData = Int(data)
        player.info.brightness = intData
        player.sendOSD(.brightness(intData))
      }

    case MPVOption.Equalizer.gamma:
      needReloadQuickSettingsView = true
      if let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee {
        let intData = Int(data)
        player.info.gamma = intData
        player.sendOSD(.gamma(intData))
      }

    case MPVOption.Equalizer.saturation:
      needReloadQuickSettingsView = true
      if let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee {
        let intData = Int(data)
        player.info.saturation = intData
        player.sendOSD(.saturation(intData))
      }

    // following properties may change before file loaded

    case MPVProperty.playlistCount:
      player.postNotification(.iinaPlaylistChanged)

    case MPVProperty.trackList:
      player.trackListChanged()

    case MPVProperty.vf:
      needReloadQuickSettingsView = true
      player.vfChanged()

    case MPVProperty.af:
      player.afChanged()

    case MPVOption.Window.fullscreen:
      guard player.mainWindow.loaded else { break }
      let fs = getFlag(MPVOption.Window.fullscreen)
      if fs != player.mainWindow.fsState.isFullscreen {
        DispatchQueue.main.async(execute: self.player.mainWindow.toggleWindowFullScreen)
      }

    case MPVOption.Window.ontop:
      guard player.mainWindow.loaded else { break }
      let ontop = getFlag(MPVOption.Window.ontop)
      if ontop != player.mainWindow.isOntop {
        DispatchQueue.main.async {
          self.player.mainWindow.setWindowFloatingOnTop(ontop)
        }
      }

    case MPVOption.Window.windowScale:
      guard player.mainWindow.loaded else { break }
      let windowScale = getDouble(MPVOption.Window.windowScale)
      if fabs(windowScale - player.info.cachedWindowScale) > 10e-10 {
        DispatchQueue.main.async {
          self.player.mainWindow.setWindowScale(windowScale)
        }
      }

    case MPVProperty.mediaTitle:
      player.mediaTitleChanged()

    case MPVProperty.idleActive:
      if let idleActive = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee, idleActive {
        if receivedEndFileWhileLoading && player.info.fileLoading {
          player.errorOpeningFileAndCloseMainWindow()
          player.info.fileLoading = false
          player.info.currentURL = nil
          player.info.isNetworkResource = false
        }
        player.info.isIdle = true
        if fileLoaded {
          fileLoaded = false
          player.closeWindow()
        }
        receivedEndFileWhileLoading = false
      }

    default:
      // Utility.log("MPV property changed (unhandled): \(name)")
      break
    }

    if needReloadQuickSettingsView {
      player.needReloadQuickSettingsView()
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

  private func setUserOption(_ key: Preference.Key, type: UserOptionType, forName name: String, sync: Bool = true, transformer: OptionObserverInfo.Transformer? = nil) {
    var code: Int32 = 0

    let keyRawValue = key.rawValue

    switch type {
    case .int:
      let value = Preference.integer(for: key)
      var i = Int64(value)
      code = mpv_set_option(mpv, name, MPV_FORMAT_INT64, &i)

    case .float:
      let value = Preference.float(for: key)
      var d = Double(value)
      code = mpv_set_option(mpv, name, MPV_FORMAT_DOUBLE, &d)

    case .bool:
      let value = Preference.bool(for: key)
      code = mpv_set_option_string(mpv, name, value ? yes_str : no_str)

    case .string:
      let value = Preference.string(for: key)
      code = mpv_set_option_string(mpv, name, value)

    case .color:
      let value = Preference.mpvColor(for: key)
      code = mpv_set_option_string(mpv, name, value)
      // Random error here (perhaps a Swift or mpv one), so set it twice
      // 「没有什么是 set 不了的；如果有，那就 set 两次」
      if code < 0 {
        code = mpv_set_option_string(mpv, name, value)
      }

    case .other:
      guard let tr = transformer else {
        Logger.log("setUserOption: no transformer!", level: .error)
        return
      }
      if let value = tr(key) {
        code = mpv_set_option_string(mpv, name, value)
      } else {
        code = 0
      }
    }

    if code < 0 {
      Utility.showAlert("mpv_error", arguments: [String(cString: mpv_error_string(code)), "\(code)", name])
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
        if let value = Preference.string(for: info.prefKey) {
          setString(info.optionName, value)
        }

      case .color:
        if let value = Preference.mpvColor(for: info.prefKey) {
          setString(info.optionName, value)
        }

      case .other:
        guard let tr = info.transformer else {
          Logger.log("setUserOption: no transformer!", level: .error)
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
}

fileprivate func mpvGetOpenGLFunc(_ ctx: UnsafeMutableRawPointer?, _ name: UnsafePointer<Int8>?) -> UnsafeMutableRawPointer? {
  let symbolName: CFString = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingASCII);
  guard let addr = CFBundleGetFunctionPointerForName(CFBundleGetBundleWithIdentifier(CFStringCreateCopy(kCFAllocatorDefault, "com.apple.opengl" as CFString)), symbolName) else {
    Logger.fatal("Cannot get OpenGL function pointer!")
  }
  return addr
}
