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


fileprivate func mpvGetOpenGL(_ ctx: UnsafeMutableRawPointer?, _ name: UnsafePointer<Int8>?) -> UnsafeMutableRawPointer? {
  let symbolName: CFString = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingASCII);
  guard let addr = CFBundleGetFunctionPointerForName(CFBundleGetBundleWithIdentifier(CFStringCreateCopy(kCFAllocatorDefault, "com.apple.opengl" as CFString!)), symbolName) else {
    Utility.fatal("Cannot get OpenGL function pointer!")
    return nil
  }
  return addr
}

fileprivate func mpvUpdateCallback(_ ctx: UnsafeMutableRawPointer?) {
  let layer = unsafeBitCast(ctx, to: ViewLayer.self)
  layer.mpvGLQueue.async {
    layer.display()
  }
}



class ViewLayer: CAOpenGLLayer {

  weak var videoView: VideoView!

  lazy var mpvGLQueue: DispatchQueue = DispatchQueue(label: "com.colliderli.iina.mpvgl")

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

  func initMpvStuff() {
    // Initialize the mpv OpenGL state.
    mpv_opengl_cb_init_gl(videoView.mpvGLContext, nil, mpvGetOpenGL, nil)
    // Set the callback that notifies you when a new video frame is available, or requires a redraw.
    mpv_opengl_cb_set_update_callback(videoView.mpvGLContext, mpvUpdateCallback, mutableRawPointerOf(obj: self))
  }

  override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {

    let attributes: [CGLPixelFormatAttribute] = [
      kCGLPFADoubleBuffer,
      kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
      kCGLPFAAccelerated,
      kCGLPFAAllowOfflineRenderers,
      _CGLPixelFormatAttribute(rawValue: 0)
    ]

    var pix: CGLPixelFormatObj?
    var npix: GLint = 0

    CGLChoosePixelFormat(attributes, &pix, &npix)

    return pix!
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
    return true
  }

  override func draw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj, forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) {

    CGLLockContext(ctx)
    CGLSetCurrentContext(ctx)

    glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

    var i: GLint = 0
    glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &i)
    var dims: [GLint] = [0, 0, 0, 0]
    glGetIntegerv(GLenum(GL_VIEWPORT), &dims);

    if let context = videoView.mpvGLContext {
      mpv_opengl_cb_draw(context, i, dims[2], -dims[3])
      //print("draw")
      ignoreGLError()
    } else {
      glClearColor(0, 0, 0, 1)
      glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
    }
    glFlush()

    CGLUnlockContext(ctx)
  }

  func draw() {
    display()
  }

  override func display() {
    super.display()
    CATransaction.flush()
  }

  // MARK: Utils

  /** Check OpenGL error (for debug only). */
  func gle() {
    let e = glGetError()
    Swift.print(arc4random())
    switch e {
    case GLenum(GL_NO_ERROR):
      break
    case GLenum(GL_OUT_OF_MEMORY):
      Swift.print("GL_OUT_OF_MEMORY")
      break
    case GLenum(GL_INVALID_ENUM):
      Swift.print("GL_INVALID_ENUM")
      break
    case GLenum(GL_INVALID_VALUE):
      Swift.print("GL_INVALID_VALUE")
      break
    case GLenum(GL_INVALID_OPERATION):
      Swift.print("GL_INVALID_OPERATION")
      break
    case GLenum(GL_INVALID_FRAMEBUFFER_OPERATION):
      Swift.print("GL_INVALID_FRAMEBUFFER_OPERATION")
      break
    case GLenum(GL_STACK_UNDERFLOW):
      Swift.print("GL_STACK_UNDERFLOW")
      break
    case GLenum(GL_STACK_OVERFLOW):
      Swift.print("GL_STACK_OVERFLOW")
      break
    default:
      break
    }
  }

  func ignoreGLError() {
    glGetError()
  }

}
