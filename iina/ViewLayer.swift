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
/// example IINA draws using a background thread whereas mpv uses the main thread. When IINA tested drawing on the main thread
/// the sliding animation to show and hide the side panels was _very_ slugish and moving the floating OSC was jerky.
class ViewLayer: CAOpenGLLayer {

  private weak var videoView: VideoView!

  private let mpvGLQueue = DispatchQueue(label: "com.colliderli.iina.mpvgl", qos: .userInteractive)

  private var bufferDepth: GLint = 8

  private let cglContext: CGLContextObj
  private let cglPixelFormat: CGLPixelFormatObj

  /// Lock to single thread calls to `display`.
  private let displayLock: NSLocking

  private var fbo: GLint = 1

  /// Lock used to allow the main thread priority access to `displayLock`.
  private var mainThreadPriorityLock = MainThreadPriorityLock()

  /// When `true` the frame needs to be rendered.
  @Atomic private var needsFlip = false

  /// When `true` drawing will proceed even if mpv indicates nothing needs to be done.
  @Atomic private var forceDraw = false

  /// Indicates whether the view is being rendered as part of a live resizing operation.
  ///
  /// This flag is used to manage setting of the
  /// [isAsynchronous](https://developer.apple.com/documentation/quartzcore/caopengllayer/isasynchronous)
  /// property. When `isAsynchronous` is `true` [canDraw](https://developer.apple.com/documentation/quartzcore/caopengllayer/candraw(incglcontext:pixelformat:forlayertime:displaytime:))
  /// is called periodically to determine if the OpenGL content should be updated. This is used when the window is being resized. When [windowDidEndLiveResize](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowdidendliveresize(_:))
  /// is called it is important to not set `isAsynchronous` to `false` until a draw has occurred. Setting this flag to `false`
  /// will cause `canDraw` to set `isAsynchronous` to `false` only once another drawing is in process. This reduces the
  /// likelihood of seeing a very short momentary black screen when exiting full screen mode.
  @Atomic var inLiveResize: Bool = false {
    didSet {
      if inLiveResize {
        isAsynchronous = true
      }
      update(force: true)
    }
  }

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
    inLiveResize = previousLayer.inLiveResize
    isAsynchronous = previousLayer.isAsynchronous
    Logger.log("Created view layer shadow copy")
  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Draw

  override func canDraw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj,
                        forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) -> Bool {
    // When in live resize, skip all drawing calls on the main thread.
    // Setting isAsynchronous = true is enough to prevent jittering.
    guard !(inLiveResize && Thread.isMainThread) else { return false }
    return videoView.$isUninited.withReadLock() { isUninited in
      guard !isUninited else { return false }
      if !inLiveResize {
        isAsynchronous = false
      }
      return forceDraw || videoView.player.mpv.shouldRenderUpdateFrame()
    }
  }

  override func draw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj,
                     forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) {
    videoView.$isUninited.withReadLock() { isUninited in
      guard !isUninited else { return }

      needsFlip = false
      forceDraw = false

      let mpv = videoView.player.mpv!

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

  override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj { cglPixelFormat }

  override func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj { cglContext }

  /// Reload the content of this layer.
  /// - Important: Because this method is called by tasks on the `mpvGLQueue` an explicit
  ///     [CATransaction](https://developer.apple.com/documentation/quartzcore/catransaction) **must**
  ///     be used. Otherwise if `CA_ASSERT_MAIN_THREAD_TRANSACTIONS` is set to check for unintended UI operations on
  ///     something other than the main thread, IINA will crash with a SIGABRT reporting "an implicit transaction wasn't created on a
  ///     main thread". See issue [#5038](https://github.com/iina/iina/issues/5038).
  override func display() {

    // May need to block other threads to allow the main thread to lock displayLock.
    mainThreadPriorityLock.beforeLocking()
    displayLock.lock()
    defer { displayLock.unlock() }
    mainThreadPriorityLock.afterLocked()

    let isUpdate = needsFlip

    if Thread.isMainThread {
      super.display()
    } else {
      // When not on the main thread use an explicit transaction.
      CATransaction.begin()
      super.display()
      CATransaction.commit()
    }

    // The call to commit will not render the explicit transaction if it is nested in an implicit
    // transaction. This can happen when drawing is being forced after a change to the view such as
    // resizing. Must call flush to ensure any implicit transaction is flushed.
    CATransaction.flush()

    guard isUpdate && needsFlip else { return }

    // Must lock the OpenGL context before calling mpv render methods. The OpenGL context must
    // always be locked before locking the isUninited lock to avoid deadlocks.
    videoView.player.mpv.lockAndSetOpenGLContext()
    defer { videoView.player.mpv.unlockOpenGLContext() }
    videoView.$isUninited.withReadLock() { isUninited in
      guard !isUninited else { return }

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
    }
  }

  func update(force: Bool = false) {
    mpvGLQueue.async { [self] in
      if force { forceDraw = true }
      needsFlip = true
      display()
    }
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

  // MARK: - ICC Profile

  /// Set an ICC profile for use with the mpv [icc-profile-auto](https://mpv.io/manual/stable/#options-icc-profile-auto)
  /// option.
  ///
  /// This method fulfills the mpv requirement that applications using libmpv with the render API provide the ICC profile via
  /// `MPV_RENDER_PARAM_ICC_PROFILE` in order for the `--icc-profile-auto` option to work. The ICC profile data will not
  /// be used by mpv unless the option is enabled.
  ///
  /// The IINA `Load ICC profile` setting is tied to the `--icc-profile-auto` option. This allows users to override IINA using
  /// the [--icc-profile](https://mpv.io/manual/stable/#options-icc-profile) option.
  func setRenderICCProfile(_ profile: NSColorSpace) {
    // The OpenGL context must always be locked before locking the isUninited lock to avoid
    // deadlocks.
    videoView.player.mpv.lockAndSetOpenGLContext()
    defer { videoView.player.mpv.unlockOpenGLContext() }
    videoView.$isUninited.withReadLock() { isUninited in
      guard !isUninited else { return }

      guard let renderContext = videoView.player.mpv.mpvRenderContext else { return }
      guard var iccData = profile.iccProfileData else {
        let name = profile.localizedName ?? "unnamed"
        Logger.log("Color space \(name) does not contain ICC profile data", level: .warning)
        return
      }
      iccData.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
        guard let baseAddress = ptr.baseAddress, ptr.count > 0 else { return }

        let u8Ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
        var icc = mpv_byte_array(data: u8Ptr, size: ptr.count)
        withUnsafeMutableBytes(of: &icc) { (ptr: UnsafeMutableRawBufferPointer) in
          let params = mpv_render_param(type: MPV_RENDER_PARAM_ICC_PROFILE, data: ptr.baseAddress)
          mpv_render_context_set_parameter(renderContext, params)
        }
      }
    }
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

// MARK: - Main Thread Priority

/// Lock used to give the main thread priority access to another lock.
///
/// Testing revealed that the main thread encounters lock starvation while trying to acquire `displayLock` when the `mpvGLQueue`
/// thread is constantly locking and unlocking the lock during playback. This sometimes results in a severe hang causing the spinning
/// beach ball of death to be displayed. This lock uses a
/// [NSCondition](https://developer.apple.com/documentation/foundation/nscondition) to block other threads
/// when the main thread needs to lock a lock, giving the main thread a chance to acquire the lock.
private class MainThreadPriorityLock {

  private let lock = NSCondition()

  /// `True` when the main thread is waiting to lock a lock; `false` otherwise.
  private var needsLock = false

  /// All threads call this before attempting to lock a lock the main thread has trouble acquiring.
  ///
  /// When called by the main thread this function will record that the main thread is waiting for a lock. When called by other threads
  /// this function will block the thread if the main thread is waiting, allowing it to proceed once the main thread has locked the lock.
  func beforeLocking() {
    lock.lock()
    defer { lock.unlock() }
    guard Thread.isMainThread else {
      while needsLock { lock.wait() }
      return
    }
    needsLock = true
  }

  /// All threads call this after locking a lock the main thread has trouble acquiring.
  ///
  /// When called by the main thread this function will record that the main thread has the lock and will allow any blocked threads to
  /// proceed. When called by other threads this function does nothing. This avoids the caller only calling this when running on the
  /// main thread.
  func afterLocked() {
    guard Thread.isMainThread else { return }
    lock.lock()
    defer { lock.unlock() }
    needsLock = false
    lock.broadcast()
  }
}
