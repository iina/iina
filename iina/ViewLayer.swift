//
//  ViewLayer.swift
//  iina
//
//  Created by lhc on 27/1/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa
import OpenGL.GL
import OpenGL.GL3

class ViewLayer: CAOpenGLLayer {

  weak var videoView: VideoView!

  let mpvGLQueue = DispatchQueue(label: "com.colliderli.iina.mpvgl", qos: .userInteractive)
  @Atomic var blocked = false

  private let cglContext: CGLContextObj
  private let cglPixelFormat: CGLPixelFormatObj

  /// Lock to single thread calls to `display`.
  private let displayLock: NSLocking

  private var fbo: GLint = 1

  private var needsMPVRender = false
  private var forceRender = false

  /// Returns an initialized `ViewLayer` object.
  ///
  /// For the display lock a recursive lock is needed because the call to `CATransaction.flush()` in `display` calls
  /// `display_if_needed` which will then call `display` if layout is needed. See the discussion in PR
  /// [#5029](https://github.com/iina/iina/pull/5029).
  override init() {
    cglPixelFormat = ViewLayer.createPixelFormat()
    cglContext = ViewLayer.createContext(cglPixelFormat)
    displayLock = NSRecursiveLock()
    super.init()

    isOpaque = true
    isAsynchronous = false

    autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
  }

  /// Returns an initialized shadow copy of the given layer with custom instance variables copied from `layer`.
  ///
  /// This initializer will be used when `MainWindowController.windowDidChangeBackingProperties` changes
  /// [contentsScale](https://developer.apple.com/documentation/quartzcore/calayer/1410746-contentsscale).
  /// To trigger this start IINA playing on an external monitor with a different scale factor with a MacBook in closed clamshell mode then
  /// unplug the external monitor.
  /// - Parameter layer: The layer from which custom fields should be copied.
  override init(layer: Any) {
    let previousLayer = layer as! ViewLayer
    cglPixelFormat = previousLayer.cglPixelFormat
    cglContext = previousLayer.cglContext
    displayLock = previousLayer.displayLock
    super.init(layer: layer)
    isOpaque = previousLayer.isOpaque
    isAsynchronous = previousLayer.isAsynchronous
    autoresizingMask = previousLayer.autoresizingMask
    videoView = previousLayer.videoView
  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj { cglPixelFormat }

  override func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj { cglContext }

  // MARK: - Draw

  override func canDraw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj,
                        forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) -> Bool {
    videoView.$isUninited.withLock() { isUninited in
      guard !isUninited else { return false }
      if forceRender { return true }
      return videoView.player.mpv.shouldRenderUpdateFrame()
    }
  }

  override func draw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj,
                     forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) {
    videoView.$isUninited.withLock() { isUninited in
      guard !isUninited else { return }

      let mpv = videoView.player.mpv!
      needsMPVRender = false

      glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

      var i: GLint = 0
      glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &i)
      var dims: [GLint] = [0, 0, 0, 0]
      glGetIntegerv(GLenum(GL_VIEWPORT), &dims);

      var flip: CInt = 1

      withUnsafeMutablePointer(to: &flip) { flip in
        if let context = mpv.mpvRenderContext {
          fbo = i != 0 ? i : fbo

          var data = mpv_opengl_fbo(fbo: Int32(fbo),
                                    w: Int32(dims[2]),
                                    h: Int32(dims[3]),
                                    internal_format: 0)
          withUnsafeMutablePointer(to: &data) { data in
            var params: [mpv_render_param] = [
              mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: .init(data)),
              mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: .init(flip)),
              mpv_render_param()
            ]
            mpv_render_context_render(context, &params)
            ignoreGLError()
          }
        } else {
          glClearColor(0, 0, 0, 1)
          glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        }
      }
      glFlush()
    }
  }

  func suspend() {
    blocked = true
    mpvGLQueue.suspend()
  }

  func resume() {
    blocked = false
    draw(forced: true)
    mpvGLQueue.resume()
  }

  func draw(forced: Bool = false) {
    videoView.$isUninited.withLock() { isUninited in
      // The properties forceRender and needsMPVRender are always accessed while holding isUninited's
      // lock. This avoids the need for separate locks to avoid data races with these flags. No need
      // to check isUninited at this point.
      needsMPVRender = true
      if forced { forceRender = true }
    }

    // Must not call display while holding isUninited's lock as that method will attempt to acquire
    // the lock and our locks do not support recursion.
    display()
  }

  override func display() {
    displayLock.lock()
    defer { displayLock.unlock() }

    super.display()
    CATransaction.flush()

    // Must lock the OpenGL context before calling mpv render methods. Can't wait until we have
    // checked the flags to see if a skip renderer is needed because the OpenGL context must always
    // be locked before locking the isUninited lock to avoid deadlocks. The flags can't be checked
    // without locking isUninited to avoid data races.
    videoView.player.mpv.lockAndSetOpenGLContext()
    defer { videoView.player.mpv.unlockOpenGLContext() }
    videoView.$isUninited.withLock() { isUninited in
      guard !isUninited else { return }

      guard !forceRender else {
        forceRender = false
        return
      }
      guard needsMPVRender else { return }

      // Neither canDraw nor draw(inCGLContext:) were called by AppKit, needs a skip render.
      // This can happen when IINA is playing in another space, as might occur when just playing
      // audio. See issue #5025.
      if let renderContext = videoView.player.mpv.mpvRenderContext,
         videoView.player.mpv.shouldRenderUpdateFrame() {
        var skip: CInt = 1
        withUnsafeMutablePointer(to: &skip) { skip in
          var params: [mpv_render_param] = [
            mpv_render_param(type: MPV_RENDER_PARAM_SKIP_RENDERING, data: .init(skip)),
            mpv_render_param()
          ]
          mpv_render_context_render(renderContext, &params)
        }
      }
      needsMPVRender = false
    }
  }

  // MARK: - Core OpenGL Context and Pixel Format

  private static func createContext(_ pixelFormat: CGLPixelFormatObj) -> CGLContextObj {
    var ctx: CGLContextObj?
    CGLCreateContext(pixelFormat, nil, &ctx)

    guard let ctx = ctx else {
      Logger.fatal("Cannot create OpenGL context")
    }

    // Sync to vertical retrace.
    var i: GLint = 1
    CGLSetParameter(ctx, kCGLCPSwapInterval, &i)

    // Enable multi-threaded GL engine.
    CGLEnable(ctx, kCGLCEMPEngine)

    CGLSetCurrentContext(ctx)
    return ctx
  }

  private static func createPixelFormat() -> CGLPixelFormatObj {
    var attributeList: [CGLPixelFormatAttribute] = [
      kCGLPFADoubleBuffer,
      kCGLPFAAllowOfflineRenderers,
      kCGLPFAColorFloat,
      kCGLPFAColorSize, CGLPixelFormatAttribute(64),
      kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
      kCGLPFAAccelerated,
    ]

    if (!Preference.bool(for: .forceDedicatedGPU)) {
      attributeList.append(kCGLPFASupportsAutomaticGraphicsSwitching)
    }

    var pix: CGLPixelFormatObj?
    var npix: GLint = 0

    for index in (0..<attributeList.count).reversed() {
      let attributes = Array(
        attributeList[0...index] + [_CGLPixelFormatAttribute(rawValue: 0)]
      )
      CGLChoosePixelFormat(attributes, &pix, &npix)
      if let pix = pix {
        Logger.log("Created OpenGL pixel format with \(attributes)", level: .debug)
        return pix
      }
    }

    Logger.fatal("Cannot create OpenGL pixel format!")
  }

  // MARK: - Utils

  /** Check OpenGL error (for debug only). */
  func gle() {
    let e = glGetError()
    print(arc4random())
    switch e {
    case GLenum(GL_NO_ERROR):
      break
    case GLenum(GL_OUT_OF_MEMORY):
      print("GL_OUT_OF_MEMORY")
      break
    case GLenum(GL_INVALID_ENUM):
      print("GL_INVALID_ENUM")
      break
    case GLenum(GL_INVALID_VALUE):
      print("GL_INVALID_VALUE")
      break
    case GLenum(GL_INVALID_OPERATION):
      print("GL_INVALID_OPERATION")
      break
    case GLenum(GL_INVALID_FRAMEBUFFER_OPERATION):
      print("GL_INVALID_FRAMEBUFFER_OPERATION")
      break
    case GLenum(GL_STACK_UNDERFLOW):
      print("GL_STACK_UNDERFLOW")
      break
    case GLenum(GL_STACK_OVERFLOW):
      print("GL_STACK_OVERFLOW")
      break
    default:
      break
    }
  }

  func ignoreGLError() {
    glGetError()
  }
}
