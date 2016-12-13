//
//  MPVController.swift
//  mpvx
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

// Global functions

protocol MPVEventDelegate {
  func onMPVEvent(_ event: MPVEvent)
}

class MPVController: NSObject {
  // The mpv_handle
  var mpv: OpaquePointer!
  // The mpv client name
  var mpvClientName: UnsafePointer<Int8>!
  lazy var queue: DispatchQueue! = DispatchQueue(label: "mpvx")
  var playerCore: PlayerCore = PlayerCore.shared
  
  var needRecordSeekTime: Bool = false
  var recordedSeekStartTime: CFTimeInterval = 0
  var recordedSeekTimeListener: ((Double) -> Void)?
  
  let observeProperties: [String: mpv_format] = [
    MPVProperty.trackListCount: MPV_FORMAT_INT64,
    MPVProperty.chapterListCount: MPV_FORMAT_INT64,
    MPVOption.PlaybackControl.pause: MPV_FORMAT_FLAG,
    MPVOption.Video.deinterlace: MPV_FORMAT_FLAG,
    MPVOption.Audio.mute: MPV_FORMAT_FLAG,
    MPVOption.Audio.volume: MPV_FORMAT_DOUBLE,
    MPVOption.Audio.audioDelay: MPV_FORMAT_DOUBLE,
    MPVOption.PlaybackControl.speed: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.subDelay: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.subScale: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.subPos: MPV_FORMAT_DOUBLE,
    MPVOption.Equalizer.contrast: MPV_FORMAT_DOUBLE,
    MPVOption.Equalizer.brightness: MPV_FORMAT_DOUBLE,
    MPVOption.Equalizer.gamma: MPV_FORMAT_DOUBLE,
    MPVOption.Equalizer.hue: MPV_FORMAT_DOUBLE,
    MPVOption.Equalizer.saturation: MPV_FORMAT_DOUBLE
  ]
  
  /**
   Init the mpv context
   */
  func mpvInit() {
    // Create a new mpv instance and an associated client API handle to control the mpv instance.
    mpv = mpv_create()
    
    // Get the name of this client handle.
    mpvClientName = mpv_client_name(mpv)
    
    let yes_str = "yes"
    let no_str = "no"
    
    // Set options that can be override by user's config
    
    // disable internal OSD
    e(mpv_set_option_string(mpv, MPVOption.OSD.osdLevel, "0"))
    
    let screenshotPath = playerCore.ud.string(forKey: Preference.Key.screenshotFolder)!
    let absoluteScreenshotPath = NSString(string: screenshotPath).expandingTildeInPath
    e(mpv_set_option_string(mpv, MPVOption.Screenshot.screenshotDirectory, absoluteScreenshotPath))
    
    let screenshotFormat = playerCore.ud.string(forKey: Preference.Key.screenshotFormat)!
    e(mpv_set_option_string(mpv, MPVOption.Screenshot.screenshotFormat, screenshotFormat))
    
    let screenshotTemplate = playerCore.ud.string(forKey: Preference.Key.screenshotTemplate)!
    e(mpv_set_option_string(mpv, MPVOption.Screenshot.screenshotTemplate, screenshotTemplate))
    
    let useMediaKeys = playerCore.ud.bool(forKey: Preference.Key.useMediaKeys)
    e(mpv_set_option_string(mpv, MPVOption.Input.inputMediaKeys, useMediaKeys ? yes_str : no_str))
    
    // User default settings
    let volume = playerCore.ud.integer(forKey: Preference.Key.softVolume)
    e(mpv_set_option_string(mpv, MPVOption.Audio.volume, "\(volume)"))
    
    // Load user's config file.
    // e(mpv_load_config_file(mpv, ""))
    
    // Set options. Should be called before initialization.
    e(mpv_set_option_string(mpv, MPVOption.Input.inputMediaKeys, "yes"))
    e(mpv_set_option_string(mpv, MPVOption.Video.vo, "opengl-cb"))
    e(mpv_set_option_string(mpv, MPVOption.Video.hwdecPreload, "auto"))
    
    // Load external scripts
    let scriptPath = Bundle.main.path(forResource: "autoload", ofType: "lua", inDirectory: "scripts")!
    e(mpv_set_option_string(mpv, MPVOption.ProgramBehavior.script, scriptPath))
    
    let inputConfPath = Bundle.main.path(forResource: "input", ofType: "conf", inDirectory: "config")!
    e(mpv_set_option_string(mpv, MPVOption.Input.inputConf, inputConfPath))
    
    // Receive log messages at warn level.
    e(mpv_request_log_messages(mpv, "warn"))
    
    // Request tick event.
    // e(mpv_request_event(mpv, MPV_EVENT_TICK, 1))
    
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
    e(mpv_initialize(mpv))
  }
  
  func mpvInitCB() -> UnsafeMutableRawPointer {
    // Get opengl-cb context.
    let mpvGL = mpv_get_sub_api(mpv, MPV_SUB_API_OPENGL_CB)!;
    // Ask delegate (actually VideoView) to setup openGL context.
//    self.delegate!.setUpMpvGLContext(mpvGL)
    return mpvGL
  }
  
  // Basically send quit to mpv
  func mpvQuit() {
    // mpv_suspend(mpv)
    command([MPVCommand.quit, nil])
  }
  
  // MARK: Command & property
  
  // Send arbitrary mpv command.
  func command(_ args: [String?]) {
    var cargs = args.map { $0.flatMap { UnsafePointer<Int8>(strdup($0)) } }
    self.e(mpv_command(self.mpv, &cargs))
    for ptr in cargs { free(UnsafeMutablePointer(mutating: ptr)) }
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
      break
      
    case MPV_EVENT_FILE_LOADED:
      onFileLoaded()
      
    case MPV_EVENT_TRACKS_CHANGED:
      onTrackChanged()
      
    case MPV_EVENT_SEEK:
      if needRecordSeekTime {
        recordedSeekStartTime = CACurrentMediaTime()
      }
      playerCore.syncUI(.time)
      
    case MPV_EVENT_PLAYBACK_RESTART:
      if needRecordSeekTime {
        recordedSeekTimeListener?(CACurrentMediaTime() - recordedSeekStartTime)
        recordedSeekTimeListener = nil
      }
      playerCore.syncUI(.time)
      
    case MPV_EVENT_PAUSE, MPV_EVENT_UNPAUSE:
      playerCore.syncUI(.playButton)
      
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
    if !playerCore.ud.bool(forKey: Preference.Key.pauseWhenOpen) {
      setFlag(MPVOption.PlaybackControl.pause, false)
    }
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
        playerCore.sendOSD(data ? .pause : .resume)
      }
      
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
      if let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
        playerCore.sendOSD(.contrast(data))
      }
      
    case MPVOption.Equalizer.hue:
      if let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
        playerCore.sendOSD(.hue(data))
      }
      
    case MPVOption.Equalizer.brightness:
      if let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
        playerCore.sendOSD(.brightness(data))
      }
      
    case MPVOption.Equalizer.gamma:
      if let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
        playerCore.sendOSD(.gamma(data))
      }
      
    case MPVOption.Equalizer.saturation:
      if let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
        playerCore.sendOSD(.saturation(data))
      }
    
    // following properties may change before file loaded
      
    case MPVProperty.playlistCount:
      NotificationCenter.default.post(Notification(name: Constants.Noti.playlistChanged))
      
    case MPVProperty.trackListCount:
      NotificationCenter.default.post(Notification(name: Constants.Noti.tracklistChanged))
      
    // ignore following
      
      
    default:
      Utility.log("MPV property changed (unhandled): \(name)")
    }
  }
  
  
  // MARK: - Utils
  
  /**
   Utility function for checking mpv api error
   */
  private func e(_ status: Int32!) {
    if status < 0 {
      Utility.fatal("MPV API error: \"\(String(cString: mpv_error_string(status)))\", Return value: \(status!).")
    }
  }
  
  
  
}
