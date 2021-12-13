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

  lazy var mpvGLQueue = DispatchQueue(label: "com.colliderli.iina.mpvgl", qos: .userInteractive)
  var blocked = false

  private var fbo: GLint = 1

  private var needsMPVRender = false
  private var forceRender = false

  override init() {
    super.init()

    isOpaque = true
    isAsynchronous = false

    autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
  }

  override init(layer: Any) {
    let previousLayer = layer as! ViewLayer

    videoView = previousLayer.videoView

    super.init()
    isOpaque = true
    isAsynchronous = false

    autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
    var attributeList: [CGLPixelFormatAttribute] = [
      kCGLPFADoubleBuffer,
      kCGLPFAAllowOfflineRenderers,
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

  override func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj {
    let ctx = super.copyCGLContext(forPixelFormat: pf)

    var i: GLint = 1
    CGLSetParameter(ctx, kCGLCPSwapInterval, &i)

    CGLEnable(ctx, kCGLCEMPEngine)

    CGLSetCurrentContext(ctx)
    return ctx
  }

  // MARK: Draw

  override func canDraw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj, forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) -> Bool {
    if forceRender { return true }

    videoView.uninitLock.lock()
    let result = videoView.player.mpv!.shouldRenderUpdateFrame()
    videoView.uninitLock.unlock()

    return result
  }

  override func draw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj, forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) {
    let mpv = videoView.player.mpv!
    needsMPVRender = false

    videoView.uninitLock.lock()

    guard !videoView.isUninited else {
      videoView.uninitLock.unlock()
      return
    }

    CGLLockContext(ctx)
    CGLSetCurrentContext(ctx)

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
          mpv_render_context_render(context, &params);
          ignoreGLError()
        }
      } else {
        glClearColor(0, 0, 0, 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
      }
    }
    glFlush()

    CGLUnlockContext(ctx)
    videoView.uninitLock.unlock()
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
    needsMPVRender = true
    if forced { forceRender = true }
    display()
    if forced {
      forceRender = false
      return
    }
    if needsMPVRender {
      videoView.uninitLock.lock()
      // draw(inCGLContext:) is not called, needs a skip render
      if !videoView.isUninited, let context = videoView.player.mpv?.mpvRenderContext {
        var skip: CInt = 1
        withUnsafeMutablePointer(to: &skip) { skip in
          var params: [mpv_render_param] = [
            mpv_render_param(type: MPV_RENDER_PARAM_SKIP_RENDERING, data: .init(skip)),
            mpv_render_param()
          ]
          mpv_render_context_render(context, &params);
        }
      }
      videoView.uninitLock.unlock()
      needsMPVRender = false
    }
  }

  override func display() {
    super.display()
    CATransaction.flush()
  }

  // MARK: Utils

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
