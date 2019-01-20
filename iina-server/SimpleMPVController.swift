//
//  SimpleMPVController.swift
//  iina-server
//
//  Created by Collider LI on 19/2/2019.
//  Copyright © 2019 lhc. All rights reserved.
//

import Foundation

class SimpleMPVController {
  var mpv: OpaquePointer!
  var mpvRenderContext: OpaquePointer?

  var renderContext: VirtualRenderContext?
  var socket: LocalHostSocket?

  var filePath: String?

  lazy var queue = DispatchQueue(label: "com.colliderli.iina.server", qos: .userInitiated)

  var cleanupLock = NSLock()

  var renderContextAvailable = false

  func startSocket() {
    socket = LocalHostSocket()
    socket?.controller = self
    socket?.run()
  }

  func start() {
    mpv = mpv_create()
    chkErr(mpv_set_option_string(mpv, MPVOption.OSD.osdLevel, "0"))

    chkErr(mpv_initialize(mpv))

    chkErr(mpv_set_property_string(mpv, "volume", "50"))

    chkErr(mpv_set_property_string(mpv, MPVOption.Video.vo, "libmpv"))
    chkErr(mpv_set_property_string(mpv, MPVOption.Window.keepaspect, "yes"))
    chkErr(mpv_set_property_string(mpv, MPVOption.Video.gpuHwdecInterop, "auto"))

    chkErr(mpv_request_log_messages(mpv, "debug"))

    mpv_set_wakeup_callback(mpv, { (ctx) in
      let mpvController = unsafeBitCast(ctx, to: SimpleMPVController.self)
      mpvController.readEvents()
    }, mutableRawPointerOf(obj: self))
  }

  func prepareContext(size: VirtualRenderContext.Size) {
    renderContext = VirtualRenderContext(size: size, mpvController: self)
    renderContext!.prepareVideoFrameBuffer()
  }

  func mpvInitRendering() {
    guard let mpv = mpv else {
      fatalError("mpvInitRendering() should be called after mpv handle being initialized!")
    }
    cleanupLock.lock()
    let apiType = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String)
    var openGLInitParams = mpv_opengl_init_params(get_proc_address: mpvGetOpenGLFunc,
                                                  get_proc_address_ctx: nil,
                                                  extra_exts: nil)
    var params = [
      mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiType),
      mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: &openGLInitParams),
      mpv_render_param()
    ]
    mpv_render_context_create(&mpvRenderContext, mpv, &params)
    mpv_render_context_set_update_callback(mpvRenderContext!, mpvUpdateCallback, mutableRawPointerOf(obj: renderContext!))
    renderContextAvailable = true
    cleanupLock.unlock()
  }

  func mpvUninitRendering() {
    guard let mpvRenderContext = mpvRenderContext else { return }
    self.cleanupLock.lock()
    mpv_render_context_set_update_callback(mpvRenderContext, nil, nil)
    mpv_render_context_free(mpvRenderContext)
    self.cleanupLock.unlock()
  }

  func mpvReportSwap() {
    guard let mpvRenderContext = mpvRenderContext else { return }
    mpv_render_context_report_swap(mpvRenderContext)
  }

  func loadFile() {
    guard let path = filePath else { return }
    command(.loadfile, args: [path])
  }

  func cleanup() {
    print("clean start \(self.renderContextAvailable)")
    print("<")
    guard self.renderContextAvailable else {
      self.cleanupLock.unlock()
      print("no need to clean")
      return
    }
    self.renderContextAvailable = false
    self.socket!.stop()
    self.command(.stop)
    self.mpvUninitRendering()
    currentConnection = nil
    renderSemaphore.signal()
    print(">")
    print("clean end")
  }

  // MARK: - Control

  @discardableResult
  func command(_ command: MPVCommand, args: [String?] = []) -> Int32 {
    guard mpv != nil else { return -1 }
    var strArgs = args
    strArgs.insert(command.rawValue, at: 0)
    strArgs.append(nil)
    var cargs = strArgs.map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
    let returnValue = mpv_command(mpv, &cargs)
    for ptr in cargs { free(UnsafeMutablePointer(mutating: ptr)) }
    return returnValue
  }

  private func readEvents() {
    queue.async {
      while self.mpv != nil {
        let event = mpv_wait_event(self.mpv, 0)
        if event?.pointee.event_id == MPV_EVENT_NONE {
          break
        }
        self.handleEvent(event)
      }
    }
  }

  private func handleEvent(_ event: UnsafePointer<mpv_event>!) {
    let eventId = event.pointee.event_id
    let eventName = String(cString: mpv_event_name(eventId))
    if eventId == MPV_EVENT_LOG_MESSAGE {
      let dataOpaquePtr = OpaquePointer(event.pointee.data)
      let msg = UnsafeMutablePointer<mpv_event_log_message>(dataOpaquePtr)
      let prefix = String(cString: (msg?.pointee.prefix)!)
      let level = String(cString: (msg?.pointee.level)!)
      let text = String(cString: (msg?.pointee.text)!)
      // print("[\(prefix)] \(level): \(text)", terminator: "")
    } else {
      // print("event: [\(eventName)]")
    }
  }
}

fileprivate func mpvGetOpenGLFunc(_ ctx: UnsafeMutableRawPointer?, _ name: UnsafePointer<Int8>?) -> UnsafeMutableRawPointer? {
  let symbolName: CFString = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingASCII);
  guard let addr = CFBundleGetFunctionPointerForName(CFBundleGetBundleWithIdentifier(CFStringCreateCopy(kCFAllocatorDefault, "com.apple.opengl" as CFString)), symbolName) else {
    fatalError("Cannot get OpenGL function pointer!")
  }
  return addr
}

fileprivate func mpvUpdateCallback(_ ctx: UnsafeMutableRawPointer?) {
  let context = unsafeBitCast(ctx, to: VirtualRenderContext.self)
  context.queue.async {
    context.drawFrame()
  }
}


fileprivate func chkErr(_ status: Int32!) {
  guard status < 0 else { return }
  DispatchQueue.main.async {
    print("mpv API error: \"\(String(cString: mpv_error_string(status)))\", Return value: \(status!).")
  }
}

fileprivate func rawPointerOf<T : AnyObject>(obj : T) -> UnsafeRawPointer {
  return UnsafeRawPointer(Unmanaged.passUnretained(obj).toOpaque())
}

fileprivate func mutableRawPointerOf<T : AnyObject>(obj : T) -> UnsafeMutableRawPointer {
  return UnsafeMutableRawPointer(Unmanaged.passUnretained(obj).toOpaque())
}
