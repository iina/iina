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

let glVersions: [CGLOpenGLProfile] = [
    kCGLOGLPVersion_3_2_Core,
    kCGLOGLPVersion_Legacy
]

let glFormatBase: [CGLPixelFormatAttribute] = [
    kCGLPFAOpenGLProfile,
    kCGLPFAAccelerated,
    kCGLPFADoubleBuffer
]

let glFormatSoftwareBase: [CGLPixelFormatAttribute] = [
    kCGLPFAOpenGLProfile,
    kCGLPFARendererID,
    CGLPixelFormatAttribute(UInt32(kCGLRendererGenericFloatID)),
    kCGLPFADoubleBuffer
]

let glFormatOptional: [[CGLPixelFormatAttribute]] = [
    [kCGLPFABackingStore],
    [kCGLPFAAllowOfflineRenderers]
]

let glFormat10Bit: [CGLPixelFormatAttribute] = [
    kCGLPFAColorSize,
    _CGLPixelFormatAttribute(rawValue: 64),
    kCGLPFAColorFloat
]

let glFormatAutoGPU: [CGLPixelFormatAttribute] = [
    kCGLPFASupportsAutomaticGraphicsSwitching
]

let attributeLookUp: [UInt32: String] = [
    kCGLOGLPVersion_3_2_Core.rawValue: "kCGLOGLPVersion_3_2_Core",
    kCGLOGLPVersion_Legacy.rawValue: "kCGLOGLPVersion_Legacy",
    kCGLPFAOpenGLProfile.rawValue: "kCGLPFAOpenGLProfile",
    UInt32(kCGLRendererGenericFloatID): "kCGLRendererGenericFloatID",
    kCGLPFARendererID.rawValue: "kCGLPFARendererID",
    kCGLPFAAccelerated.rawValue: "kCGLPFAAccelerated",
    kCGLPFADoubleBuffer.rawValue: "kCGLPFADoubleBuffer",
    kCGLPFABackingStore.rawValue: "kCGLPFABackingStore",
    kCGLPFAColorSize.rawValue: "kCGLPFAColorSize",
    kCGLPFAColorFloat.rawValue: "kCGLPFAColorFloat",
    kCGLPFAAllowOfflineRenderers.rawValue: "kCGLPFAAllowOfflineRenderers",
    kCGLPFASupportsAutomaticGraphicsSwitching.rawValue: "kCGLPFASupportsAutomaticGraphicsSwitching"
]

/// OpenGL layer for `VideoView`.
///
/// This class is structured to make it easier to compare it to the reference implementation in the mpv player. Methods and statements
/// are in the same order as found in the mpv source. However there are differences that cause the implementation to not match up. For
/// example IINA draws using a background thread whereas mpv uses the main thread. For this reason the locking differs as IINA has to
/// coordinate access to data that is shared between the main thread and the background thread.
class ViewLayer: CAOpenGLLayer {

  private weak var videoView: VideoView!

  let mpvGLQueue = DispatchQueue(label: "com.colliderli.iina.mpvgl", qos: .userInteractive)
  @Atomic var blocked = false

  private var bufferDepth: GLint = 8

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
  /// - Parameter videoView: The view this layer will be associated with.
  init(_ videoView: VideoView) {
    self.videoView = videoView
    (cglPixelFormat, bufferDepth) = ViewLayer.createPixelFormat(videoView.player)
    cglContext = ViewLayer.createContext(cglPixelFormat)
    displayLock = NSRecursiveLock()
    super.init()
    autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    backgroundColor = NSColor.black.cgColor
    wantsExtendedDynamicRangeContent = true
    if bufferDepth > 8 {
      contentsFormat = .RGBA16Float
    }
    isAsynchronous = false
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
    videoView = previousLayer.videoView
    cglPixelFormat = previousLayer.cglPixelFormat
    cglContext = previousLayer.cglContext
    displayLock = previousLayer.displayLock
    super.init(layer: layer)
    autoresizingMask = previousLayer.autoresizingMask
    backgroundColor = previousLayer.backgroundColor
    wantsExtendedDynamicRangeContent = previousLayer.wantsExtendedDynamicRangeContent
    contentsFormat = previousLayer.contentsFormat
    isAsynchronous = previousLayer.isAsynchronous
  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

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
            withUnsafeMutablePointer(to: &bufferDepth) { bufferDepth in
              var params: [mpv_render_param] = [
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: .init(data)),
                mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: .init(flip)),
                mpv_render_param(type: MPV_RENDER_PARAM_DEPTH, data:.init(bufferDepth)),
                mpv_render_param()
              ]
              mpv_render_context_render(context, &params)
              ignoreGLError()
            }
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

  override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj { cglPixelFormat }

  override func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj { cglContext }

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

  // MARK: - Core OpenGL Context and Pixel Format

  private static func createPixelFormat(_ player: PlayerCore) -> (CGLPixelFormatObj, GLint) {
    var pix: CGLPixelFormatObj?
    var depth: GLint = 8
    var err: CGLError = CGLError(rawValue: 0)
    let swRender: CocoaCbSwRenderer = player.mpv.getEnum(MPVOption.GPURendererOptions.cocoaCbSwRenderer)

    if swRender != .yes {
      (pix, depth, err) = ViewLayer.findPixelFormat(player)
    }

    if (err != kCGLNoError || pix == nil) && swRender != .no {
      (pix, depth, err) = ViewLayer.findPixelFormat(player, software: true)
    }

    guard let pixelFormat = pix, err == kCGLNoError else {
      Logger.fatal("Cannot create OpenGL pixel format!")
    }

    return (pixelFormat, depth)
  }

  private static func findPixelFormat(_ player: PlayerCore, software: Bool = false) -> (CGLPixelFormatObj?, GLint, CGLError) {
    let subsystem = Logger.makeSubsystem("layer\(player.playerNumber)")
    var pix: CGLPixelFormatObj?
    var err: CGLError = CGLError(rawValue: 0)
    var npix: GLint = 0

    for ver in glVersions {
      var glBase = software ? glFormatSoftwareBase : glFormatBase
      glBase.insert(CGLPixelFormatAttribute(ver.rawValue), at: 1)

      var glFormat = [glBase]
      if player.mpv.getFlag(MPVOption.GPURendererOptions.cocoaCb10bitContext) {
        glFormat += [glFormat10Bit]
      }
      glFormat += glFormatOptional

      if !Preference.bool(for: .forceDedicatedGPU) {
        glFormat += [glFormatAutoGPU]
      }

      for index in stride(from: glFormat.count-1, through: 0, by: -1) {
        let format = glFormat.flatMap { $0 } + [_CGLPixelFormatAttribute(rawValue: 0)]
        err = CGLChoosePixelFormat(format, &pix, &npix)

        if err == kCGLBadAttribute || err == kCGLBadPixelFormat || pix == nil {
          glFormat.remove(at: index)
        } else {
          let attArray = format.map({ (value: _CGLPixelFormatAttribute) -> String in
            return attributeLookUp[value.rawValue] ?? String(value.rawValue)
          })

          Logger.log("Created CGL pixel format with attributes: " +
                     "\(attArray.joined(separator: ", "))", subsystem: subsystem)
          return (pix, glFormat.contains(glFormat10Bit) ? 16 : 8, err)
        }
      }
    }

    let errS = String(cString: CGLErrorString(err))
    Logger.log("Couldn't create a " + "\(software ? "software" : "hardware accelerated") " +
               "CGL pixel format: \(errS) (\(err.rawValue))", subsystem: subsystem)
    let swRenderer: CocoaCbSwRenderer = player.mpv.getEnum(MPVOption.GPURendererOptions.cocoaCbSwRenderer)
    if software == false && swRenderer == .auto {
      Logger.log("Falling back to software renderer", subsystem: subsystem)
    }

    return (pix, 8, err)
  }

  private static func createContext(_ pixelFormat: CGLPixelFormatObj) -> CGLContextObj {
    var ctx: CGLContextObj?
    CGLCreateContext(pixelFormat, nil, &ctx)

    guard let ctx = ctx else {
      Logger.fatal("Cannot create OpenGL context!")
    }

    // Sync to vertical retrace.
    var i: GLint = 1
    CGLSetParameter(ctx, kCGLCPSwapInterval, &i)

    // Enable multi-threaded GL engine.
    CGLEnable(ctx, kCGLCEMPEngine)

    CGLSetCurrentContext(ctx)
    return ctx
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
