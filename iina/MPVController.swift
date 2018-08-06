//
//  MPVController.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import Foundation

fileprivate typealias PK = Preference.Key

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


// Global functions

protocol MPVEventDelegate {
  func onMPVEvent(_ event: MPVEvent)
}

class MPVController: NSObject {
  // The mpv_handle
  var mpv: OpaquePointer!

  var mpvClientName: UnsafePointer<CChar>!
  var mpvVersion: String!

  lazy var queue = DispatchQueue(label: "com.colliderli.iina.controller", qos: .userInitiated)

  unowned let player: PlayerCore

  var needRecordSeekTime: Bool = false
  var recordedSeekStartTime: CFTimeInterval = 0
  var recordedSeekTimeListener: ((Double) -> Void)?

  var receivedEndFileWhileLoading: Bool = false

  var fileLoaded: Bool = false

  let observeProperties: [String: mpv_format] = [
    MPVProperty.trackListCount: MPV_FORMAT_INT64,
    MPVProperty.vf: MPV_FORMAT_NONE,
    MPVProperty.af: MPV_FORMAT_NONE,
    MPVOption.TrackSelection.vid: MPV_FORMAT_INT64,
    MPVOption.TrackSelection.aid: MPV_FORMAT_INT64,
    MPVOption.TrackSelection.sid: MPV_FORMAT_INT64,
    MPVOption.PlaybackControl.pause: MPV_FORMAT_FLAG,
    MPVProperty.chapter: MPV_FORMAT_INT64,
    MPVOption.Video.deinterlace: MPV_FORMAT_FLAG,
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
    MPVProperty.mediaTitle: MPV_FORMAT_STRING
  ]

  init(playerCore: PlayerCore) {
    self.player = playerCore
    super.init()
  }

  deinit {
    ObjcUtils.silenced {
      self.optionObservers.forEach { (k, _) in
        UserDefaults.standard.removeObserver(self, forKeyPath: k)
      }
    }
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
    let useMpvOsd = Preference.bool(for: .useMpvOsd)
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

    // - General

    setUserOption(PK.screenshotFolder, type: .other, forName: MPVOption.Screenshot.screenshotDirectory) { key in
      let screenshotPath = Preference.string(for: key)!
      return NSString(string: screenshotPath).expandingTildeInPath
    }

    setUserOption(PK.screenshotFormat, type: .other, forName: MPVOption.Screenshot.screenshotFormat) { key in
      let v = Preference.integer(for: key)
      return Preference.ScreenshotFormat(rawValue: v)?.string
    }

    setUserOption(PK.screenshotTemplate, type: .string, forName: MPVOption.Screenshot.screenshotTemplate)

    if #available(macOS 10.13, *) {
      chkErr(mpv_set_option_string(mpv, MPVOption.Input.inputMediaKeys, no_str))
    } else {
      setUserOption(PK.useMediaKeys, type: .bool, forName: MPVOption.Input.inputMediaKeys)
    }
    setUserOption(PK.useAppleRemote, type: .bool, forName: MPVOption.Input.inputAppleremote)

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
    setUserOption(PK.resumeLastPosition, type: .bool, forName: MPVOption.ProgramBehavior.savePositionOnQuit)
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

    setUserOption(PK.defaultCacheSize, type: .int, forName: MPVOption.Cache.cacheDefault)
    setUserOption(PK.cacheBufferSize, type: .int, forName: MPVOption.Cache.cacheBackbuffer)
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
    if Preference.bool(for: .useUserDefinedConfDir) {
      if var userConfDir = Preference.string(for: .userDefinedConfDir) {
        userConfDir = NSString(string: userConfDir).standardizingPath
        mpv_set_option_string(mpv, "config", "yes")
        let status = mpv_set_option_string(mpv, MPVOption.ProgramBehavior.configDir, userConfDir)
        if status < 0 {
          Utility.showAlert("extra_option.config_folder", arguments: [userConfDir])
        }
      }
    }

    // Set user defined options.
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

    // Observe propoties.
    observeProperties.forEach { (k, v) in
      mpv_observe_property(mpv, 0, k, v)
    }

    // Initialize an uninitialized mpv instance. If the mpv instance is already running, an error is retuned.
    chkErr(mpv_initialize(mpv))

    // Set options that can be override by user's config. mpv will log user config when initialize,
    // so we put them here.
    chkErr(mpv_set_property_string(mpv, MPVOption.Video.vo, "opengl-cb"))
    chkErr(mpv_set_property_string(mpv, MPVOption.Window.keepaspect, "no"))
    chkErr(mpv_set_property_string(mpv, MPVOption.Video.openglHwdecInterop, "auto"))

    // get version
    mpvVersion = getString(MPVProperty.mpvVersion)
  }

  func mpvInitCB() -> UnsafeMutableRawPointer {
    // Get opengl-cb context.
    let mpvGL = mpv_get_sub_api(mpv, MPV_SUB_API_OPENGL_CB)!;

    return mpvGL
  }

  // Basically send quit to mpv
  func mpvQuit() {
    command(.quit)
  }

  // MARK: - Command & property

  // Send arbitrary mpv command.
  func command(_ command: MPVCommand, args: [String?] = [], checkError: Bool = true, returnValueCallback: ((Int32) -> Void)? = nil) {
    guard mpv != nil else { return }
    if args.count > 0 && args.last == nil {
      Logger.fatal("Command do not need a nil suffix")
    }
    var strArgs = args
    strArgs.insert(command.rawValue, at: 0)
    strArgs.append(nil)
    var cargs = strArgs.map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
    let returnValue = mpv_command(self.mpv, &cargs)
    for ptr in cargs { free(UnsafeMutablePointer(mutating: ptr)) }
    if checkError {
      chkErr(returnValue)
    } else if let cb = returnValueCallback {
      cb(returnValue)
    }
  }

  func command(rawString: String) -> Int32 {
    return mpv_command_string(mpv, rawString)
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
    return parsed!
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

  // Handle the event
  private func handleEvent(_ event: UnsafePointer<mpv_event>!) {
    let eventId = event.pointee.event_id

    switch eventId {
    case MPV_EVENT_SHUTDOWN:
      let quitByMPV = !player.isMpvTerminated
      if quitByMPV {
        NSApp.terminate(nil)
      } else {
        mpv_detach_destroy(mpv)
        mpv = nil
      }

    case MPV_EVENT_LOG_MESSAGE:
      let dataOpaquePtr = OpaquePointer(event.pointee.data)
      let msg = UnsafeMutablePointer<mpv_event_log_message>(dataOpaquePtr)
      let prefix = String(cString: (msg?.pointee.prefix)!)
      let level = String(cString: (msg?.pointee.level)!)
      let text = String(cString: (msg?.pointee.text)!)
      Logger.log("mpv log: [\(prefix)] \(level): \(text)", level: .warning, subsystem: .general, appendNewlineAtTheEnd: false)

    case MPV_EVENT_PROPERTY_CHANGE:
      let dataOpaquePtr = OpaquePointer(event.pointee.data)
      if let property = UnsafePointer<mpv_event_property>(dataOpaquePtr)?.pointee {
        let propertyName = String(cString: property.name)
        handlePropertyChange(propertyName, property)
      }

    case MPV_EVENT_AUDIO_RECONFIG:
      break

    case MPV_EVENT_VIDEO_RECONFIG:
      onVideoReconfig()
      break

    case MPV_EVENT_START_FILE:
      player.info.isIdle = false
      guard getString(MPVProperty.path) != nil else { break }
      player.fileStarted()
      let url = player.info.currentURL
      let message = player.info.isNetworkResource ? url?.absoluteString : url?.lastPathComponent
      player.sendOSD(.fileStart(message ?? "-"))

    case MPV_EVENT_FILE_LOADED:
      onFileLoaded()

    case MPV_EVENT_SEEK:
      player.info.isSeeking = true
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
      if needRecordSeekTime {
        recordedSeekTimeListener?(CACurrentMediaTime() - recordedSeekStartTime)
        recordedSeekTimeListener = nil
      }
      player.playbackRestarted()
      player.syncUI(.time)

    case MPV_EVENT_END_FILE:
      // if receive end-file when loading file, might be error
      // wait for idle
      if player.info.fileLoading {
        receivedEndFileWhileLoading = true
      } else {
        player.info.shouldAutoLoadFiles = false
      }
      break

    case MPV_EVENT_IDLE:
      if receivedEndFileWhileLoading && player.info.fileLoading {
        player.errorOpeningFileAndCloseMainWindow()
        player.info.fileLoading = false
        player.info.currentURL = nil
        player.info.isNetworkResource = false
      }
      player.info.isIdle = true
      if fileLoaded {
        fileLoaded = false
        player.closeMainWindow()
      }
      receivedEndFileWhileLoading = false
      break

    default:
      // let eventName = String(cString: mpv_event_name(eventId))
      // Utility.log("mpv event (unhandled): \(eventName)")
      break
    }
  }

  private func onVideoParamsChange (_ data: UnsafePointer<mpv_node_list>) {
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
      player.info.cachedVideoDurationAndProgress[filename]?.duration = duration
    }
    player.info.videoPosition = VideoTime(pos)
    player.fileLoaded()
    fileLoaded = true
    // mpvResume()
    if !Preference.bool(for: .pauseWhenOpen) {
      setFlag(MPVOption.PlaybackControl.pause, false)
    }
    player.syncUI(.playlist)
  }

  private func onVideoReconfig() {
    // If loading file, video reconfig can return 0 width and height
    if player.info.fileLoading {
      return
    }
    var dwidth = getInt(MPVProperty.dwidth)
    var dheight = getInt(MPVProperty.dheight)
    if player.info.rotation == 90 || player.info.rotation == 270 {
      swap(&dwidth, &dheight)
    }
    if dwidth != player.info.displayWidth! || dheight != player.info.displayHeight! {
      // filter the last video-reconfig event before quit
      if dwidth == 0 && dheight == 0 && getFlag(MPVProperty.coreIdle) { return }
      // video size changed
      player.info.displayWidth = dwidth
      player.info.displayHeight = dheight
      player.notifyMainWindowVideoSizeChanged()
    }
  }

  // MARK: - Property listeners

  private func handlePropertyChange(_ name: String, _ property: mpv_event_property) {

    var needReloadQuickSettingsView = false

    switch name {

    case MPVProperty.videoParams:
      needReloadQuickSettingsView = true
      onVideoParamsChange(UnsafePointer<mpv_node_list>(OpaquePointer(property.data)))

    case MPVOption.TrackSelection.vid:
      needReloadQuickSettingsView = true
      let data = getInt(MPVOption.TrackSelection.vid)
      player.info.vid = Int(data)
      player.getTrackInfo()
      let currTrack = player.info.currentTrack(.video) ?? .noneVideoTrack
      player.sendOSD(.track(currTrack))

    case MPVOption.TrackSelection.aid:
      needReloadQuickSettingsView = true
      let data = getInt(MPVOption.TrackSelection.aid)
      player.info.aid = Int(data)
      player.getTrackInfo()
      let currTrack = player.info.currentTrack(.audio) ?? .noneAudioTrack
      DispatchQueue.main.sync {
        player.mainWindow?.muteButton.isEnabled = (player.info.aid != 0)
        player.mainWindow?.volumeSlider.isEnabled = (player.info.aid != 0)
      }
      player.sendOSD(.track(currTrack))

    case MPVOption.TrackSelection.sid:
      needReloadQuickSettingsView = true
      let data = getInt(MPVOption.TrackSelection.sid)
      player.info.sid = Int(data)
      player.getTrackInfo()
      let currTrack = player.info.currentTrack(.sub) ?? .noneSubTrack
      player.sendOSD(.track(currTrack))

    case MPVOption.PlaybackControl.pause:
      if let data = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
        if player.info.isPaused != data {
          player.sendOSD(data ? .pause : .resume)
          player.info.isPaused = data
        }
        if player.mainWindow.isWindowLoaded {
          if Preference.bool(for: .alwaysFloatOnTop) {
            DispatchQueue.main.async {
              self.player.mainWindow.setWindowFloatingOnTop(!data)
            }
          }
        }
      }
      player.syncUI(.playButton)

    case MPVProperty.chapter:
      player.syncUI(.time)
      player.syncUI(.chapterList)

    case MPVOption.PlaybackControl.speed:
      needReloadQuickSettingsView = true
      if let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
        player.info.playSpeed = data
        player.sendOSD(.speed(data))
      }

    case MPVOption.Video.deinterlace:
      needReloadQuickSettingsView = true
      if let data = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
        // this property will fire a change event at file start
        if player.info.deinterlace != data {
          player.sendOSD(.deinterlace(data))
          player.info.deinterlace = data
        }
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

    case MPVProperty.trackListCount:
      player.trackListChanged()
      player.postNotification(.iinaTracklistChanged)

    case MPVProperty.vf:
      needReloadQuickSettingsView = true
      player.postNotification(.iinaVFChanged)

    case MPVProperty.af:
      player.postNotification(.iinaAFChanged)

    case MPVOption.Window.fullscreen:
      guard player.mainWindow.isWindowLoaded else { break }
      let fs = getFlag(MPVOption.Window.fullscreen)
      if fs != player.mainWindow.isInFullScreen {
        DispatchQueue.main.async {
          self.player.mainWindow.toggleWindowFullScreen()
        }
      }

    case MPVOption.Window.ontop:
      guard player.mainWindow.isWindowLoaded else { break }
      let ontop = getFlag(MPVOption.Window.ontop)
      if ontop != player.mainWindow.isOntop {
        DispatchQueue.main.async {
          self.player.mainWindow.isOntop = ontop
          self.player.mainWindow.setWindowFloatingOnTop(ontop)
        }
      }

    case MPVOption.Window.windowScale:
      guard player.mainWindow.isWindowLoaded else { break }
      let windowScale = getDouble(MPVOption.Window.windowScale)
      if fabs(windowScale - player.info.cachedWindowScale) > 10e-10 {
        DispatchQueue.main.async {
          self.player.mainWindow.setWindowScale(windowScale)
        }
      }

    case MPVProperty.mediaTitle:
      player.postNotification(.iinaMediaTitleChanged)

    default:
      // Utility.log("MPV property changed (unhandled): \(name)")
      break
    }

    if (needReloadQuickSettingsView) {
      DispatchQueue.main.async {
        self.player.mainWindow.quickSettingView.reload()
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
