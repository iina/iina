//
//  VideoView.swift
//  mpvx
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

func glupdate(_ ctx: UnsafeMutablePointer<Void>?) -> Void {
  
  let videoView = unsafeBitCast(ctx, to: VideoView.self)
  
//  DispatchQueue.main.async {
//      videoView.needsDisplay = true
//  }
  
  // This workaround avoids glitches when resizng window.
  // The reason is unknown to me
  if videoView.isInResize {
    if (videoView.notdrawnFrame >= 1) {
      videoView.isInResize = false
      videoView.glQueue.async {
        videoView.drawRect()
      }
    } else {
      videoView.notdrawnFrame += 1
    }
  } else {
    videoView.glQueue.async {
      videoView.drawRect()
    }
  }
//  DispatchQueue.main.async {
//    videoView.needsDisplay = true
//  }
}

class VideoView: NSOpenGLView {
  
  // The mpv opengl context
  var mpvGLContext: OpaquePointer! {
    didSet {
      // Initialize the mpv OpenGL state.
      mpv_opengl_cb_init_gl(mpvGLContext, nil, getGLProcAddress, nil)
      
      // Set the callback that notifies you when a new video frame is available, or requires a redraw.
      mpv_opengl_cb_set_update_callback(mpvGLContext, glupdate, UnsafeMutablePointer<Void>(unsafeAddress(of: self)));
    }
  }
  
  // The queue for drawing
  // If draw in main thread, it will block UI such as resizing
  lazy var glQueue: DispatchQueue = DispatchQueue(label: "mpvx.gl", attributes: .serial)
  
  // Lock for drawing
  lazy var lock: Lock = Lock()
  
  var isInResize: Bool = false
  var notdrawnFrame: Int = 0
  
  override var mouseDownCanMoveWindow: Bool {
    return true
  }
  
  // Constructor
  override init(frame: CGRect) {
    let attributes: [NSOpenGLPixelFormatAttribute] = [
      UInt32(NSOpenGLPFADoubleBuffer),
      UInt32(NSOpenGLPFAAccelerated),
      0
    ]
    super.init(frame: frame, pixelFormat: NSOpenGLPixelFormat(attributes: attributes))!
    autoresizingMask = [.viewWidthSizable, .viewHeightSizable]
    var swapInt = GLint(1)
    wantsBestResolutionOpenGLSurface = true
    openGLContext?.setValues(&swapInt, for: NSOpenGLCPSwapInterval)
    openGLContext?.makeCurrentContext()
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    // Uninit mpv gl
    mpv_opengl_cb_set_update_callback(mpvGLContext, nil, nil)
    mpv_opengl_cb_uninit_gl(mpvGLContext)
  }
  
  override var isOpaque: Bool {
    return true
  }
  
  // The drawing function
  func drawRect() {
//    DispatchQueue.main.async {
//      self.needsDisplay = true
//    }
    lock.lock()
    if let context = self.mpvGLContext {
      openGLContext?.makeCurrentContext()
      mpv_opengl_cb_draw(context, 0, Int32(self.bounds.size.width), -(Int32)(self.bounds.size.height))
    } else {
      glClearColor(0, 0, 0, 0)
      glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
    }
    openGLContext?.flushBuffer()
    if let context = self.mpvGLContext {
      mpv_opengl_cb_report_flip( context, 0 );
    }
    notdrawnFrame = 0
    lock.unlock()
  }
  
  // This method is only called when resizing
  override func draw(_ dirtyRect: NSRect) {
    drawRect()
  }

  
}
