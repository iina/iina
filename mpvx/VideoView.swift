//
//  VideoView.swift
//  mpvx
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

func mpvGLUpdate(_ ctx: UnsafeMutablePointer<Void>?) -> Void {
  let videoView = unsafeBitCast(ctx, to: VideoView.self)
  videoView.glQueue.async {
    videoView.drawFrame()
  }
}

class VideoView: NSOpenGLView {
  
  // The mpv opengl context
  var mpvGLContext: OpaquePointer! {
    didSet {
      // Initialize the mpv OpenGL state.
      mpv_opengl_cb_init_gl(mpvGLContext, nil, getGLProcAddress, nil)
      // Set the callback that notifies you when a new video frame is available, or requires a redraw.
      mpv_opengl_cb_set_update_callback(mpvGLContext, mpvGLUpdate, UnsafeMutablePointer<Void>(unsafeAddress(of: self)));
    }
  }
  
  var renderContext: NSOpenGLContext!
  
  // The queue for drawing
  // If draw in main thread, it will block UI such as resizing
  lazy var glQueue: DispatchQueue = DispatchQueue(label: "mpvx.gl", attributes: .serial)
  
  var videoSize: NSSize? {
    didSet {
      prepareVideoFrameBuffer(videoSize!)
      setUpDisplayLink()
      startDisplayLink()
    }
  }
  
  var displayLink: CVDisplayLink?
  
  var texture: GLuint = GLuint()
  var fbo: GLuint = GLuint()
  
  override var mouseDownCanMoveWindow: Bool {
    return true
  }
  
  override var isOpaque: Bool {
    return true
  }
  
  // MARK: - Constructor
  
  override init(frame: CGRect) {
    let attributes: [NSOpenGLPixelFormatAttribute] = [
      UInt32(NSOpenGLPFADoubleBuffer),
      UInt32(NSOpenGLPFAAccelerated),
      0
    ]
    let pixelFormat = NSOpenGLPixelFormat(attributes: attributes)!
    super.init(frame: frame, pixelFormat: pixelFormat)!
    // set up another context for offscreen render thread
    renderContext = NSOpenGLContext(format: pixelFormat, share: openGLContext!)!
    
    autoresizingMask = [.viewWidthSizable, .viewHeightSizable]
    wantsBestResolutionOpenGLSurface = true
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    // uninit mpv gl
    mpv_opengl_cb_set_update_callback(mpvGLContext, nil, nil)
    mpv_opengl_cb_uninit_gl(mpvGLContext)
    // delete framebuffer
    glDeleteTextures(1, &texture);
    glDeleteFramebuffersEXT(1, &fbo);
  }
  
  // MARK: - Preparation
  
  override func prepareOpenGL() {
    var swapInt = GLint(1)
    openGLContext!.setValues(&swapInt, for: NSOpenGLCPSwapInterval)
  }
  
  func prepareVideoFrameBuffer(_ size: NSSize) {
    openGLContext!.makeCurrentContext()
    // create frame buffer
    glGenFramebuffersEXT(GLsizei(1), &fbo)
    glBindFramebufferEXT(GLenum(GL_FRAMEBUFFER_EXT), fbo);
    // create texture
    glGenTextures(1, &texture);
    glBindTexture(GLenum(GL_TEXTURE_2D), texture);
    // bing texture
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR);
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR);
    glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA8, GLsizei(size.width), GLsizei(size.height), 0, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil);
    glFramebufferTexture2DEXT(GLenum(GL_FRAMEBUFFER_EXT), GLenum(GL_COLOR_ATTACHMENT0_EXT),
                              GLenum(GL_TEXTURE_2D), texture, 0);
    // check whether frame buffer is completed
    let status = glCheckFramebufferStatusEXT(GLenum(GL_FRAMEBUFFER_EXT));
    Utility.assert(status == GLenum(GL_FRAMEBUFFER_COMPLETE_EXT), "Frame buffer check failed!")
    // bind back to main framebuffer (may not necessary)
    glBindTexture(GLenum(GL_TEXTURE_2D), 0);
    glBindFramebufferEXT(GLenum(GL_FRAMEBUFFER_EXT), 0);
  }
  
  /**
   Set up display link.
   */
  func setUpDisplayLink() {
    // The callback function
    func displayLinkCallback(
      _ displayLink: CVDisplayLink, _ inNow: UnsafePointer<CVTimeStamp>,
      _ inOutputTime: UnsafePointer<CVTimeStamp>,
      _ flagsIn: CVOptionFlags,
      _ flagsOut: UnsafeMutablePointer<CVOptionFlags>,
      _ context: UnsafeMutablePointer<Void>?) -> CVReturn {
      
      let videoView = unsafeBitCast(context, to: VideoView.self)
      videoView.drawVideo()
      return kCVReturnSuccess
    }
    //
    CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
    if let link = displayLink {
      checkCVReturn(CVDisplayLinkSetOutputCallback(link, displayLinkCallback, UnsafeMutablePointer<Void>(unsafeAddress(of: self))))
    } else {
      Utility.fatal("Failed to create display link")
    }
    if let context = self.openGLContext?.cglContextObj, format = self.pixelFormat?.cglPixelFormatObj {
      checkCVReturn(CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(displayLink!, context, format))
    } else {
      Utility.fatal("Failed to set display with nil opengl context")
    }
  }
  
  func startDisplayLink() {
    CVDisplayLinkStart(displayLink!)
  }
  
  // MARK: - Drawing
  
  /**
   Draw offscreen to framebuffer.
   */
  func drawFrame() {
    renderContext.lock()
    renderContext.makeCurrentContext()
    if let context = self.mpvGLContext {
      mpv_opengl_cb_draw(context, Int32(fbo), Int32(videoSize!.width), -(Int32)(videoSize!.height))
    } else {
      glClearColor(0, 0, 0, 0)
      glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
    }
    renderContext.update()
    renderContext.flushBuffer()
    // report flip to mpv
    if let context = self.mpvGLContext {
      mpv_opengl_cb_report_flip( context, 0 );
    }
    renderContext.unlock()
  }
  
  /**
   Draw the video to view from framebuffer.
   */
  func drawVideo() {
    openGLContext?.lock()
    openGLContext?.makeCurrentContext()
    
    glEnable(GLenum(GL_TEXTURE_2D))
    glBindFramebufferEXT(GLenum(GL_FRAMEBUFFER_EXT), 0);
    glBindTexture(GLenum(GL_TEXTURE_2D), texture);
    glBegin(GLenum(GL_QUADS));
    
    glTexCoord2f(0, 0);    glVertex2f(-1, -1);
    glTexCoord2f(0, 1);    glVertex2f(-1, 1);
    glTexCoord2f(1, 1);    glVertex2f( 1, 1);
    glTexCoord2f(1, 0);    glVertex2f( 1, -1);
    
    glEnd();
    glDisable(GLenum(GL_TEXTURE_2D))
    openGLContext?.flushBuffer()
    openGLContext?.unlock()
  }
  
  /**
   This function is mainly called when bound changes, e.g. resize window
   */
  override func draw(_ dirtyRect: NSRect) {
    drawVideo()
  }
  
  // MARK: - Utils
  
  /**
   Check the CVReturn value.
   */
  func checkCVReturn(_ value: CVReturn) {
    if value != kCVReturnSuccess {
      Utility.fatal("CVReturn not success: \(value)")
    }
  }

}
