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
  
  /**
   Init the mpv context
   */
  func mpvInit() {
    // Create a new mpv instance and an associated client API handle to control the mpv instance.
    mpv = mpv_create()
    
    // Get the name of this client handle.
    mpvClientName = mpv_client_name(mpv)
    
    // Set options that can be override by user's config
    let screenshotPath = playerCore.ud.string(forKey: Preference.Key.screenshotFolder)!
    let absoluteScreenshotPath = NSString(string: screenshotPath).expandingTildeInPath
    e(mpv_set_option_string(mpv, MPVOption.Screenshot.screenshotDirectory, absoluteScreenshotPath))
    
    let screenshotFormat = playerCore.ud.string(forKey: Preference.Key.screenshotFormat)!
    e(mpv_set_option_string(mpv, MPVOption.Screenshot.screenshotFormat, screenshotFormat))
    
    let screenshotTemplate = playerCore.ud.string(forKey: Preference.Key.screenshotTemplate)!
    e(mpv_set_option_string(mpv, MPVOption.Screenshot.screenshotTemplate, screenshotTemplate))
    
    // Load user's config file.
    // e(mpv_load_config_file(mpv, ""))
    
    // Set options. Should be called before initialization.
    e(mpv_set_option_string(mpv, MPVOption.Input.inputMediaKeys, "yes"))
    e(mpv_set_option_string(mpv, MPVOption.Video.vo, "opengl-cb"))
    e(mpv_set_option_string(mpv, MPVOption.Video.hwdecPreload, "auto"))
    
    // Load external scripts
    e(mpv_set_option_string(mpv, MPVOption.ProgramBehavior.script, "/Users/admin/Project/mpvx/mpvx/tools/autoload.lua"))
    
    // Receive log messages at warn level.
    e(mpv_request_log_messages(mpv, "warn"))
    
    // Request tick event.
    // e(mpv_request_event(mpv, MPV_EVENT_TICK, 1))
    
    // Set a custom function that should be called when there are new events.
    mpv_set_wakeup_callback(self.mpv, { (ctx) in
      let mpvController = unsafeBitCast(ctx, to: MPVController.self)
      mpvController.readEvents()
      }, mutableRawPointerOf(obj: self))
    
    //
    // mpv_observe_property(mpv, 0, "track-list", MPV_FORMAT_NODE_ARRAY)
    
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
        switch propertyName {
        case MPVProperty.videoParams:
          onVideoParamsChange(UnsafePointer<mpv_node_list>(OpaquePointer(property.data)))
        case MPVOption.Audio.mute:
          playerCore.syncUI(.MuteButton)
        default:
          Utility.log("MPV property changed (unhandled): \(propertyName)")
        }
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
      playerCore.syncUI(.Time)
      
    case MPV_EVENT_PLAYBACK_RESTART:
      playerCore.syncUI(.Time)
      
    case MPV_EVENT_PAUSE, MPV_EVENT_UNPAUSE:
      playerCore.syncUI(.PlayButton)
      
    case MPV_EVENT_CHAPTER_CHANGE:
      playerCore.syncUI(.Time)
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
  
  
  // MARK: Utils
  
  /**
   Utility function for checking mpv api error
   */
  private func e(_ status: Int32!) {
    if status < 0 {
      Utility.showAlert(message: "Cannot start MPV!")
      Utility.fatal("MPV API error: \(String(cString: mpv_error_string(status)))")
    }
  }
  
  
  
}
