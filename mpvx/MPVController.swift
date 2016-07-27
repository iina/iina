//
//  MPVController.swift
//  mpvx
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

// Global functions

func getGLProcAddress(ctx: UnsafeMutablePointer<Void>?, name: UnsafePointer<Int8>?) -> UnsafeMutablePointer<Void>? {
  let symbolName: CFString = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingASCII);
  let addr = CFBundleGetFunctionPointerForName(CFBundleGetBundleWithIdentifier(CFStringCreateCopy(kCFAllocatorDefault, "com.apple.opengl")), symbolName);
  return addr;
}

func wakeup(_ ctx: UnsafeMutablePointer<Void>?) {
  let mpvController = unsafeBitCast(ctx, to: MPVController.self)
  mpvController.readEvents()
}

protocol MPVEventDelegate {
  func onMPVEvent(_ event: MPVEvent)
}

class MPVController: NSObject {
  // The mpv_handle
  var mpv: OpaquePointer!
  // The mpv client name
  var mpvClientName: UnsafePointer<Int8>!
  lazy var queue: DispatchQueue! = DispatchQueue(label: "mpvx", attributes: .serial)
  var playerController: PlayerController!
  
  init(playerController: PlayerController) {
    self.playerController = playerController
  }
  
  /**
   Init the mpv context
   */
  func mpvInit() {
    // Create a new mpv instance and an associated client API handle to control the mpv instance.
    mpv = mpv_create()
    
    // Get the name of this client handle.
    mpvClientName = mpv_client_name(mpv)
    
    // Load user's config file.
    // e(mpv_load_config_file(mpv, ""))
    
    // Set options. Should be called before initialization.
    e(mpv_set_option_string(mpv, MPVOption.Input.inputMediaKeys, "yes"))
    e(mpv_set_option_string(mpv, MPVOption.Video.vo, "opengl-cb"))
    e(mpv_set_option_string(mpv, MPVOption.Video.hwdecPreload, "auto"))
    
    // Receive log messages at warn level.
    e(mpv_request_log_messages(mpv, "warn"))
    
    // Request tick event.
    // e(mpv_request_event(mpv, MPV_EVENT_TICK, 1))
    
    // Set a custom function that should be called when there are new events.
    mpv_set_wakeup_callback(self.mpv, wakeup, UnsafeMutablePointer(unsafeAddress(of: self)))
    
    //
    // mpv_observe_property(mpv, 0, "track-list", MPV_FORMAT_NODE_ARRAY)
    
    // Initialize an uninitialized mpv instance. If the mpv instance is already running, an error is retuned.
    e(mpv_initialize(mpv))
  }
  
  func mpvInitCB() -> UnsafeMutablePointer<Void> {
    // Get opengl-cb context.
    let mpvGL = mpv_get_sub_api(mpv, MPV_SUB_API_OPENGL_CB)!;
    // Ask delegate (actually VideoView) to setup openGL context.
//    self.delegate!.setUpMpvGLContext(mpvGL)
    return mpvGL
  }
  
  // Basically send quit to mpv
  func mpvQuit() {
    mpv_suspend(mpv)
    mpvCommand([MPVCommand.quit, nil])
  }
  
  func mpvSuspend() {
    mpv_suspend(mpv)
  }
  
  func mpvResume() {
    mpv_resume(mpv)
  }
  
  // MARK: Command & property
  
  // Send arbitrary mpv command.
  func mpvCommand(_ args: [String?]) {
    var cargs = args.map { $0.flatMap { UnsafePointer<Int8>(strdup($0)) } }
    self.e(mpv_command(self.mpv, &cargs))
    for ptr in cargs { free(UnsafeMutablePointer(ptr)) }
  }
  
  // Set property
  func mpvSetFlagProperty(_ name: String, _ flag: Bool) {
    var data: Int = flag ? 1 : 0
    mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
  }
  
  func mpvSetIntProperty(_ name: String, _ value: Int64) {
    var data = value
    mpv_set_property(mpv, name, MPV_FORMAT_INT64, &data)
  }
  
  func mpvGetIntProperty(_ name: String) -> Int {
    var data = Int64()
    mpv_get_property(mpv, name, MPV_FORMAT_INT64, &data)
    return Int(data)
  }
  
  func mpvGetFlagProperty(_ name: String) -> Bool {
    var data = Int64()
    mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &data)
    return data > 0
  }
  
  // MARK: - Events
  
  // Read event and handle it async
  func readEvents() {
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
  func handleEvent(_ event: UnsafePointer<mpv_event>!) {
    let eventId = event.pointee.event_id
    switch eventId {
    case MPV_EVENT_SHUTDOWN:
      mpv_detach_destroy(mpv)
      mpv = nil
      Utility.log("MPV event: shutdown")
      
    case MPV_EVENT_LOG_MESSAGE:
      let msg = UnsafeMutablePointer<mpv_event_log_message>(event.pointee.data)
      let prefix = String(cString: (msg?.pointee.prefix)!)
      let level = String(cString: (msg?.pointee.level)!)
      let text = String(cString: (msg?.pointee.text)!)
      Utility.log("MPV log: [\(prefix)] \(level): \(text)")
      
    case MPV_EVENT_PROPERTY_CHANGE:
      if let property = UnsafePointer<mpv_event_property>(event.pointee.data)?.pointee {
        let propertyName = String(property.name)
        switch propertyName {
        case MPVProperty.videoParams:
          onVideoParamsChange(UnsafePointer<mpv_node_list>(property.data))
        case MPVProperty.mute:
          playerController.syncUI(.MuteButton)
        default:
          Utility.log("MPV property changed (unhandled): \(propertyName)")
        }
      }
      
    case MPV_EVENT_AUDIO_RECONFIG:
      break
      
    case MPV_EVENT_VIDEO_RECONFIG:
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
      playerController.syncUI(.Time)
      
    case MPV_EVENT_PLAYBACK_RESTART:
      playerController.syncUI(.Time)
      
    case MPV_EVENT_PAUSE, MPV_EVENT_UNPAUSE:
      playerController.syncUI(.PlayButton)
      
    default:
      let eventName = String(cString: mpv_event_name(eventId))
      Utility.log("MPV event (unhandled): \(eventName)")
    }
  }
  
  func onVideoParamsChange (_ data: UnsafePointer<mpv_node_list>) {
    //let params = data.pointee
    //params.keys.
  }
  
  func onFileLoaded() {
    mpvSuspend()
    // Get video size and set the initial window size
    let width = mpvGetIntProperty(MPVProperty.width)
    let height = mpvGetIntProperty(MPVProperty.height)
    let duration = mpvGetIntProperty(MPVProperty.duration)
    let pos = mpvGetIntProperty(MPVProperty.timePos)
    playerController.info.videoHeight = height
    playerController.info.videoWidth = width
    playerController.info.videoDuration = VideoTime(duration)
    playerController.info.videoPosition = VideoTime(pos)
    playerController.fileLoaded()
  }
  
  func onTrackChanged() {
    playerController.mainWindow.updateTitle()
  }
  
  
  // MARK: Utils
  
  /**
   Utility function for checking mpv api error
   */
  func e(_ status: Int32!) {
    if status < 0 {
      Utility.showAlert(message: "Cannot start MPV!")
      Utility.fatal("MPV API error: \(String(cString: mpv_error_string(status)))")
    }
  }
  
  
  
}
