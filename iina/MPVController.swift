//
//  MPVController.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa
import Foundation

fileprivate typealias PK = Preference.Key

fileprivate let yes_str = "yes"
fileprivate let no_str = "no"

// Global functions

protocol MPVEventDelegate {
  func onMPVEvent(_ event: MPVEvent)
}

class MPVController: NSObject {
  // The mpv_handle
  var mpv: OpaquePointer!

  var mpvClientName: UnsafePointer<Int8>!
  var mpvVersion: String!

  lazy var queue: DispatchQueue! = DispatchQueue(label: "com.colliderli.iina.controller")

  var playerCore: PlayerCore = PlayerCore.shared
  let ud: UserDefaults = UserDefaults.standard

  var needRecordSeekTime: Bool = false
  var recordedSeekStartTime: CFTimeInterval = 0
  var recordedSeekTimeListener: ((Double) -> Void)?

  var receivedEndFileWhileLoading: Bool = false

  let observeProperties: [String: mpv_format] = [
    MPVProperty.trackListCount: MPV_FORMAT_INT64,
    MPVProperty.vf: MPV_FORMAT_NONE,
    MPVProperty.af: MPV_FORMAT_NONE,
    MPVOption.PlaybackControl.pause: MPV_FORMAT_FLAG,
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
    MPVOption.Equalizer.saturation: MPV_FORMAT_INT64
  ]

  /**
   Init the mpv context, set options
   */
  func mpvInit() {
    // Create a new mpv instance and an associated client API handle to control the mpv instance.
    mpv = mpv_create()

    // Get the name of this client handle.
    mpvClientName = mpv_client_name(mpv)

    // User default settings

    setUserOption(PK.softVolume, type: .int, forName: MPVOption.Audio.volume, sync: false)

    // - Advanced

    // disable internal OSD
    let useMpvOsd = ud.bool(forKey: PK.useMpvOsd)
    if !useMpvOsd {
      chkErr(mpv_set_option_string(mpv, MPVOption.OSD.osdLevel, "0"))
    } else {
      playerCore.displayOSD = false
    }

    // log
    let enableLog = ud.bool(forKey: PK.enableLogging)
    if enableLog {
      let date = Date()
      let calendar = NSCalendar.current
      let y = calendar.component(.year, from: date)
      let m = calendar.component(.month, from: date)
      let d = calendar.component(.day, from: date)
      let h = calendar.component(.hour, from: date)
      let mm = calendar.component(.minute, from: date)
      let s = calendar.component(.second, from: date)
      let token = Utility.ShortCodeGenerator.getCode(length: 6)
      let logFileName = "\(y)-\(m)-\(d)-\(h)-\(mm)-\(s)_\(token).log"
      let path = Utility.logDirURL.appendingPathComponent(logFileName).path
      chkErr(mpv_set_option_string(mpv, MPVOption.ProgramBehavior.logFile, path))
    }

    // - General

    setUserOption(PK.screenshotFolder, type: .other, forName: MPVOption.Screenshot.screenshotDirectory) { key in
      let screenshotPath = UserDefaults.standard.string(forKey: key)!
      return NSString(string: screenshotPath).expandingTildeInPath
    }

    setUserOption(PK.screenshotFormat, type: .other, forName: MPVOption.Screenshot.screenshotFormat) { key in
      let v = UserDefaults.standard.integer(forKey: key)
      return Preference.ScreenshotFormat(rawValue: v)?.string
    }

    setUserOption(PK.screenshotTemplate, type: .string, forName: MPVOption.Screenshot.screenshotTemplate)

    setUserOption(PK.useMediaKeys, type: .bool, forName: MPVOption.Input.inputMediaKeys)

    // - Codec

    setUserOption(PK.videoThreads, type: .int, forName: MPVOption.Video.vdLavcThreads)
    setUserOption(PK.audioThreads, type: .int, forName: MPVOption.Audio.adLavcThreads)

    setUserOption(PK.useHardwareDecoding, type: .bool, forName: MPVOption.Video.hwdec)

    setUserOption(PK.audioLanguage, type: .string, forName: MPVOption.TrackSelection.alang)

    // - Sub

    setUserOption(PK.subAutoLoad, type: .other, forName: MPVOption.Subtitles.subAuto) { key in
      let v = UserDefaults.standard.integer(forKey: key)
      return Preference.AutoLoadAction(rawValue: v)?.string
    }

    setUserOption(PK.ignoreAssStyles, type: .other, forName: MPVOption.Subtitles.subAssStyleOverride) { key in
      let v = UserDefaults.standard.bool(forKey: key)
      return v ? "force" : "yes"
    }

    setUserOption(PK.subTextFont, type: .string, forName: MPVOption.Subtitles.subFont)
    setUserOption(PK.subTextSize, type: .int, forName: MPVOption.Subtitles.subFontSize)

    setUserOption(PK.subTextColor, type: .color, forName: MPVOption.Subtitles.subColor)
    setUserOption(PK.subBgColor, type: .color, forName: MPVOption.Subtitles.subBackColor)

    setUserOption(PK.subBold, type: .bool, forName: MPVOption.Subtitles.subBold)
    setUserOption(PK.subItalic, type: .bool, forName: MPVOption.Subtitles.subItalic)

    setUserOption(PK.subBorderSize, type: .int, forName: MPVOption.Subtitles.subBorderSize)
    setUserOption(PK.subBorderColor, type: .color, forName: MPVOption.Subtitles.subBorderColor)

    setUserOption(PK.subShadowSize, type: .int, forName: MPVOption.Subtitles.subShadowOffset)
    setUserOption(PK.subShadowColor, type: .color, forName: MPVOption.Subtitles.subShadowColor)

    setUserOption(PK.subAlignX, type: .other, forName: MPVOption.Subtitles.subAlignX) { key in
      let v = UserDefaults.standard.integer(forKey: key)
      return Preference.SubAlign(rawValue: v)?.stringForX
    }

    setUserOption(PK.subAlignY, type: .other, forName: MPVOption.Subtitles.subAlignY) { key in
      let v = UserDefaults.standard.integer(forKey: key)
      return Preference.SubAlign(rawValue: v)?.stringForY
    }

    setUserOption(PK.subMarginX, type: .int, forName: MPVOption.Subtitles.subMarginX)
    setUserOption(PK.subMarginY, type: .int, forName: MPVOption.Subtitles.subMarginY)

    setUserOption(PK.subLang, type: .string, forName: MPVOption.TrackSelection.slang)

    // - Network / cache settings

    setUserOption(PK.enableCache, type: .other, forName: MPVOption.Cache.cache) { key in
      let v = UserDefaults.standard.bool(forKey: key)
      return v ? nil : "no"
    }

    setUserOption(PK.defaultCacheSize, type: .int, forName: MPVOption.Cache.cacheDefault)
    setUserOption(PK.cacheBufferSize, type: .int, forName: MPVOption.Cache.cacheBackbuffer)
    setUserOption(PK.secPrefech, type: .int, forName: MPVOption.Cache.cacheSecs)

    setUserOption(PK.userAgent, type: .other, forName: MPVOption.Network.userAgent) { key in
      let ua = UserDefaults.standard.string(forKey: key)!
      return ua.isEmpty ? nil : ua
    }

    setUserOption(PK.transportRTSPThrough, type: .other, forName: MPVOption.Network.rtspTransport) { key in
      let v = UserDefaults.standard.integer(forKey: key)
      return Preference.RTSPTransportation(rawValue: v)!.string
    }

    // Set user defined conf dir.
    if ud.bool(forKey: PK.useUserDefinedConfDir) {
      if var userConfDir = ud.string(forKey: PK.userDefinedConfDir) {
        userConfDir = NSString(string: userConfDir).standardizingPath
        mpv_set_option_string(mpv, "config", "yes")
        let status = mpv_set_option_string(mpv, MPVOption.ProgramBehavior.configDir, userConfDir)
        if status < 0 {
          Utility.showAlert(message: "Error setting config directory \"\(userConfDir)\".")
        }
      }
    }

    // Set user defined options.
    if let userOptions = ud.value(forKey: PK.userOptions) as? [[String]] {
      userOptions.forEach { op in
        let status = mpv_set_option_string(mpv, op[0], op[1])
        if status < 0 {
          Utility.showAlert(message: "Error setting option --\(op[0])=\(op[1]) with return value \(status). Pleaase check your settings.")
        }
      }
    } else {
      Utility.showAlert(message: "Cannot read user defined options.")
    }

    // Set options that can be override by user's config.
    chkErr(mpv_set_option_string(mpv, MPVOption.Input.inputMediaKeys, "yes"))
    chkErr(mpv_set_option_string(mpv, MPVOption.Video.vo, "opengl-cb"))
    chkErr(mpv_set_option_string(mpv, MPVOption.Video.hwdecPreload, "auto"))

    // Load external scripts
    let scriptPath = Bundle.main.path(forResource: "autoload", ofType: "lua", inDirectory: "scripts")!
    chkErr(mpv_set_option_string(mpv, MPVOption.ProgramBehavior.script, scriptPath))

    let inputConfPath = Bundle.main.path(forResource: "input", ofType: "conf", inDirectory: "config")!
    chkErr(mpv_set_option_string(mpv, MPVOption.Input.inputConf, inputConfPath))

    // Receive log messages at warn level.
    chkErr(mpv_request_log_messages(mpv, "warn"))

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

  // MARK: Command & property

  // Send arbitrary mpv command.
  func command(_ command: MPVCommand, args: [String?] = [], checkError: Bool = true, returnValueCallback: ((Int32) -> Void)? = nil) {
    if args.count > 0 && args.last == nil {
      Utility.fatal("Command do not need a nil suffix")
      return
    }

    var strArgs = args
    strArgs.insert(command.rawValue, at: 0)
    strArgs.append(nil)
    var cargs = strArgs.map { $0.flatMap { UnsafePointer<Int8>(strdup($0)) } }
    let returnValue = mpv_command(self.mpv, &cargs)
    for ptr in cargs { free(UnsafeMutablePointer(mutating: ptr)) }
    if checkError {
      chkErr(returnValue)
    } else if let cb = returnValueCallback {
      cb(returnValue)
    }
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
    Utility.assert(name == MPVProperty.vf || name == MPVProperty.af, "getFilters() do not support \(name)!")

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
    Utility.assert(name == MPVProperty.vf || name == MPVProperty.af, "setFilters() do not support \(name)!")
    let cmd = name == MPVProperty.vf ? MPVCommand.vf : MPVCommand.af

    let str = filters.map { $0.stringFormat }.joined(separator: ",")
    command(cmd, args: ["set", str], checkError: false) { returnValue in
      if returnValue < 0 {
        Utility.showAlert(message: "Error occured when setting filters. Please check your parameter format.")
        // reload data in filter setting window
        NotificationCenter.default.post(Notification(name: Constants.Noti.vfChanged))
      }
    }
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
      mpv_detach_destroy(mpv)
      mpv = nil
      Utility.log("MPV event: shutdown")

    case MPV_EVENT_LOG_MESSAGE:
      let dataOpaquePtr = OpaquePointer(event.pointee.data)
      let msg = UnsafeMutablePointer<mpv_event_log_message>(dataOpaquePtr)
      let prefix = String(cString: (msg?.pointee.prefix)!)
      let level = String(cString: (msg?.pointee.level)!)
      let text = String(cString: (msg?.pointee.text)!)
      Utility.log("MPV log: [\(prefix)] \(level): \(text)")

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

    case MPV_EVENT_METADATA_UPDATE:
      break

    case MPV_EVENT_START_FILE:
      playerCore.fileStarted()

    case MPV_EVENT_FILE_LOADED:
      onFileLoaded()

    case MPV_EVENT_TRACKS_CHANGED:
      onTrackChanged()

    case MPV_EVENT_SEEK:
      playerCore.info.isSeeking = true
      if needRecordSeekTime {
        recordedSeekStartTime = CACurrentMediaTime()
      }
      playerCore.syncUI(.time)

    case MPV_EVENT_PLAYBACK_RESTART:
      playerCore.info.isSeeking = false
      if needRecordSeekTime {
        recordedSeekTimeListener?(CACurrentMediaTime() - recordedSeekStartTime)
        recordedSeekTimeListener = nil
      }
      playerCore.syncUI(.time)

    case MPV_EVENT_PAUSE, MPV_EVENT_UNPAUSE:
      // deprecated
      break

    case MPV_EVENT_END_FILE:
      // if receive end-file when loading file, might be error
      // wait for idle
      if playerCore.info.fileLoading {
        receivedEndFileWhileLoading = true
      }
      break

    case MPV_EVENT_IDLE:
      if receivedEndFileWhileLoading && playerCore.info.fileLoading {
        playerCore.errorOpeningFileAndCloseMainWindow()
        playerCore.info.fileLoading = false
        playerCore.info.currentURL = nil
        playerCore.info.isNetworkResource = false
      }
      receivedEndFileWhileLoading = false
      break

    case MPV_EVENT_CHAPTER_CHANGE:
      playerCore.syncUI(.time)
      playerCore.syncUI(.chapterList)

    default:
      let eventName = String(cString: mpv_event_name(eventId))
      Utility.log("MPV event (unhandled): \(eventName)")
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
    let dwidth = getInt(MPVProperty.dwidth)
    let dheight = getInt(MPVProperty.dheight)
    let duration = getInt(MPVProperty.duration)
    let pos = getInt(MPVProperty.timePos)
    playerCore.info.videoHeight = height
    playerCore.info.videoWidth = width
    playerCore.info.displayWidth = dwidth == 0 ? width : dwidth
    playerCore.info.displayHeight = dheight == 0 ? height : dheight
    playerCore.info.videoDuration = VideoTime(duration)
    playerCore.info.videoPosition = VideoTime(pos)
    let filename = getString(MPVProperty.filename)
    playerCore.info.currentURL = URL(fileURLWithPath: filename ?? "")
    playerCore.fileLoaded()
    // mpvResume()
    if !ud.bool(forKey: PK.pauseWhenOpen) {
      setFlag(MPVOption.PlaybackControl.pause, false)
    }
    playerCore.syncUI(.playlist)
  }

  private func onTrackChanged() {

  }

  private func onVideoReconfig() {
    // If loading file, video reconfig can return 0 width and height
    if playerCore.info.fileLoading {
      return
    }
    var dwidth = getInt(MPVProperty.dwidth)
    var dheight = getInt(MPVProperty.dheight)
    if playerCore.info.rotation == 90 || playerCore.info.rotation == 270 {
      Utility.swap(&dwidth, &dheight)
    }
    // according to client api doc, check whether changed
    if playerCore.info.displayWidth! == 0 && playerCore.info.displayHeight! == 0 {
      playerCore.info.displayWidth = dwidth
      playerCore.info.displayHeight = dheight
      return
    }
    if dwidth != playerCore.info.displayWidth! || dheight != playerCore.info.displayHeight! {
      // video size changed
      playerCore.info.displayWidth = dwidth
      playerCore.info.displayHeight = dheight
      // mpvSuspend()
      playerCore.notifyMainWindowVideoSizeChanged()
      // mpvResume()
    }
  }

  // MARK: - Property listeners

  private func handlePropertyChange(_ name: String, _ property: mpv_event_property) {
    switch name {

    case MPVProperty.videoParams:
      onVideoParamsChange(UnsafePointer<mpv_node_list>(OpaquePointer(property.data)))

    case MPVOption.PlaybackControl.pause:
      if let data = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
        if playerCore.info.isPaused != data {
          playerCore.sendOSD(data ? .pause : .resume)
          playerCore.info.isPaused = data
        }
      }
      playerCore.syncUI(.playButton)

    case MPVOption.Video.deinterlace:
      if let data = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
        // this property will fire a change event at file start
        if playerCore.info.deinterlace != data {
          playerCore.sendOSD(.deinterlace(data))
          playerCore.info.deinterlace = data
        }
      }

    case MPVOption.Audio.mute:
      playerCore.syncUI(.muteButton)
      if let data = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
        playerCore.info.isMuted = data
        playerCore.sendOSD(data ? OSDMessage.mute : OSDMessage.unMute)
      }

    case MPVOption.Audio.volume:
      if let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
        playerCore.info.volume = Int(data)
        playerCore.sendOSD(.volume(Int(data)))
      }

    case MPVOption.Audio.audioDelay:
      if let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
        playerCore.info.audioDelay = data
        playerCore.sendOSD(.audioDelay(data))
      }

    case MPVOption.Subtitles.subDelay:
      if let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
        playerCore.info.subDelay = data
        playerCore.sendOSD(.subDelay(data))
      }

    case MPVOption.Subtitles.subScale:
      if let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
        let displayValue = data >= 1 ? data : -1/data
        let truncated = round(displayValue * 100) / 100
        playerCore.sendOSD(.subScale(truncated))
      }

    case MPVOption.Subtitles.subPos:
      if let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
        playerCore.sendOSD(.subPos(data))
      }

    case MPVOption.PlaybackControl.speed:
      if let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
        let displaySpeed = Utility.toDisplaySpeed(fromRealSpeed: data)
        playerCore.sendOSD(.speed(displaySpeed))
      }

    case MPVOption.Equalizer.contrast:
      if let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee {
        let intData = Int(data)
        playerCore.info.contrast = intData
        playerCore.sendOSD(.contrast(intData))
      }

    case MPVOption.Equalizer.hue:
      if let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee {
        let intData = Int(data)
        playerCore.info.hue = intData
        playerCore.sendOSD(.hue(intData))
      }

    case MPVOption.Equalizer.brightness:
      if let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee {
        let intData = Int(data)
        playerCore.info.brightness = intData
        playerCore.sendOSD(.brightness(intData))
      }

    case MPVOption.Equalizer.gamma:
      if let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee {
        let intData = Int(data)
        playerCore.info.gamma = intData
        playerCore.sendOSD(.gamma(intData))
      }

    case MPVOption.Equalizer.saturation:
      if let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee {
        let intData = Int(data)
        playerCore.info.saturation = intData
        playerCore.sendOSD(.saturation(intData))
      }

    // following properties may change before file loaded

    case MPVProperty.playlistCount:
      NotificationCenter.default.post(Notification(name: Constants.Noti.playlistChanged))

    case MPVProperty.trackListCount:
      NotificationCenter.default.post(Notification(name: Constants.Noti.tracklistChanged))

    case MPVProperty.vf:
      NotificationCenter.default.post(Notification(name: Constants.Noti.vfChanged))

    case MPVProperty.af:
      NotificationCenter.default.post(Notification(name: Constants.Noti.afChanged))

    // ignore following


    default:
      Utility.log("MPV property changed (unhandled): \(name)")
    }
  }

  // MARK: - User Options


  private enum UserOptionType {
    case bool, int, float, string, color, other
  }

  private struct OptionObserverInfo {
    typealias Transformer = (String) -> String?

    var prefKey: String
    var optionName: String
    var valueType: UserOptionType
    /** input a pref key and return the option value (as string) */
    var transformer: Transformer?

    init(_ prefKey: String, _ optionName: String, _ valueType: UserOptionType, _ transformer: Transformer?) {
      self.prefKey = prefKey
      self.optionName = optionName
      self.valueType = valueType
      self.transformer = transformer
    }
  }

  private var optionObservers: [String: OptionObserverInfo] = [:]

  private func setUserOption(_ key: String, type: UserOptionType, forName name: String, sync: Bool = true, transformer: OptionObserverInfo.Transformer? = nil) {
    let code: Int32

    switch type {
    case .int:
      let value = ud.integer(forKey: key)
      var i = Int64(value)
      code = mpv_set_option(mpv, name, MPV_FORMAT_INT64, &i)

    case .float:
      let value = ud.float(forKey: key)
      var d = Double(value)
      code = mpv_set_option(mpv, name, MPV_FORMAT_DOUBLE, &d)

    case .bool:
      let value = ud.bool(forKey: key)
      code = mpv_set_option_string(mpv, name, value ? yes_str : no_str)

    case .string:
      let value = ud.string(forKey: key)
      code = mpv_set_option_string(mpv, name, value)

    case .color:
      let value = ud.mpvColor(forKey: key)
      code = mpv_set_option_string(mpv, name, value)

    case .other:
      guard let tr = transformer else {
        Utility.log("setUserOption: no transformer!")
        return
      }
      if let value = tr(key) {
        code = mpv_set_option_string(mpv, name, value)
      } else {
        code = 0
      }
    }

    if code < 0 {
      Utility.showAlert(message: "Error \(String(cString: mpv_error_string(code))) (\(code)) when setting user option \(name).")
    }

    if sync {
      ud.addObserver(self, forKeyPath: key, options: [.new, .old], context: nil)
      optionObservers[key] = OptionObserverInfo(key, name, type, transformer)
    }
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard !(change?[NSKeyValueChangeKey.oldKey] is NSNull) else { return }

    guard let keyPath = keyPath else { return }
    guard let info = optionObservers[keyPath] else { return }

    switch info.valueType {
    case .int:
      let value = ud.integer(forKey: info.prefKey)
      setInt(info.optionName, value)

    case .float:
      let value = ud.float(forKey: info.prefKey)
      setDouble(info.optionName, Double(value))

    case .bool:
      let value = ud.bool(forKey: info.prefKey)
      setFlag(info.optionName, value)

    case .string:
      if let value = ud.string(forKey: info.prefKey) {
        setString(info.optionName, value)
      }

    case .color:
      if let value = ud.mpvColor(forKey: info.prefKey) {
        setString(info.optionName, value)
      }

    case .other:
      guard let tr = info.transformer else {
        Utility.log("setUserOption: no transformer!")
        return
      }
      if let value = tr(info.prefKey) {
        setString(info.optionName, value)
      }
    }
  }

  // MARK: - Utils

  /**
   Utility function for checking mpv api error
   */
  private func chkErr(_ status: Int32!) {
    if status < 0 {
      Utility.fatal("MPV API error: \"\(String(cString: mpv_error_string(status)))\", Return value: \(status!).")
    }
  }


}
