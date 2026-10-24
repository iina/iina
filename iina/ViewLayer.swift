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

  // Preserve the native PiP transaction while it updates the hosted surface.
  @Atomic var isHostedInPIP = false

  @Atomic var isAnimatingWindowResize = false {
    didSet {
      if isAnimatingWindowResize && !isInCropTransition { isAsynchronous = true }
      update(force: true)
    }
  }

  @Atomic private var fullscreenTransition = (generation: 0, active: false, finishing: false)
  @Atomic private var fullscreenDisplayQueued = false

  private var isInFullscreenTransition: Bool { fullscreenTransition.active }

  @Atomic private var isDrawingGeometryHandoff = false
  @Atomic var isInCropTransition = false {
    didSet {
      // CA's automatic GL timer locks the context before canDraw can reject a
      // preparation frame. Keep crop drawing on mpvGLQueue so that timer cannot
      // starve main while the native renderer waits for video presentation time.
      if isInCropTransition { isAsynchronous = false }
      else if inLiveResize || isAnimatingWindowResize || isInFullscreenTransition { isAsynchronous = true }
    }
  }
  @Atomic private var isPreparingCropFrame = false
  @Atomic private var skippedEmptyCropFrame = false

  @Atomic private var lastRenderedPixelSize: CGSize? = nil

  private var pixelSize: CGSize {
    CGSize(width: (bounds.width * contentsScale).rounded(),
           height: (bounds.height * contentsScale).rounded())
  }

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
      if inLiveResize && !isInCropTransition {
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
    // when resized but mpv hasn't rendered a new frame,
    // the old content's aspect ratio should be preserved.
    contentsGravity = .resizeAspectFill
    needsDisplayOnBoundsChange = true
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
    bufferDepth = previousLayer.bufferDepth
    super.init(layer: layer)
    autoresizingMask = previousLayer.autoresizingMask
    backgroundColor = previousLayer.backgroundColor
    wantsExtendedDynamicRangeContent = previousLayer.wantsExtendedDynamicRangeContent
    contentsFormat = previousLayer.contentsFormat
    // Ownership belongs to the shared surface, including its shadow copies.
    _isHostedInPIP = previousLayer._isHostedInPIP
    _isAnimatingWindowResize = previousLayer._isAnimatingWindowResize
    _fullscreenTransition = previousLayer._fullscreenTransition
    _fullscreenDisplayQueued = previousLayer._fullscreenDisplayQueued
    _lastRenderedPixelSize = previousLayer._lastRenderedPixelSize
    _isDrawingGeometryHandoff = previousLayer._isDrawingGeometryHandoff
    _isInCropTransition = previousLayer._isInCropTransition
    _isPreparingCropFrame = previousLayer._isPreparingCropFrame
    _skippedEmptyCropFrame = previousLayer._skippedEmptyCropFrame
    cropFrameState = previousLayer.cropFrameState
    _forceDraw = previousLayer._forceDraw
    _needsFlip = previousLayer._needsFlip
    snapshotState = previousLayer.snapshotState
    needsDisplayOnBoundsChange = true
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
    guard !((inLiveResize || isAnimatingWindowResize || isInFullscreenTransition) && Thread.isMainThread && !isDrawingGeometryHandoff) else { return false }
    return videoView.$isUninited.withReadLock() { isUninited in
      guard !isUninited else { return false }
      if !inLiveResize && !isAnimatingWindowResize && !isInFullscreenTransition {
        isAsynchronous = false
      }
      let size = pixelSize
      guard size.width > 0, size.height > 0 else { return false }
      if isPreparingCropFrame { return false }
      if isInCropTransition || isHostedInPIP {
        guard let context = videoView.player.mpv.mpvRenderContext else { return false }
        // Reconfiguration forgets mpv's current frame before a replacement is
        // queued. A forced render then draws its empty dummy frame. Keep the
        // native backing surface until an actual video/redraw frame is present.
        _ = mpv_render_context_update(context)
        var info = mpv_render_frame_info()
        withUnsafeMutablePointer(to: &info) { pointer in
          _ = mpv_render_context_get_info(context, mpv_render_param(type: MPV_RENDER_PARAM_NEXT_FRAME_INFO, data: pointer))
        }
        let ready = info.flags & UInt64(MPV_RENDER_FRAME_INFO_PRESENT.rawValue) != 0
        if !ready && isInCropTransition {
          skippedEmptyCropFrame = true
          return false
        }
        // A new timed frame can arrive after display()'s preflight, including
        // while a synchronous geometry handoff owns the drawable. Recheck once
        // CA has acquired the current GL context, before render can wait while
        // holding the compositor's transaction. Keep atomic handoffs synchronous.
        if ready, !isDrawingGeometryHandoff,
           deferCropDisplay(until: info.target_time, now: mpv_get_time_ns(videoView.player.mpv.mpv)) {
          skippedEmptyCropFrame = true
          return false
        }
        if isInCropTransition { return true }
      }
      // Core Animation can resize a paused surface without an mpv update; render in display(), never layout.
      return forceDraw || lastRenderedPixelSize != size || videoView.player.mpv.shouldRenderUpdateFrame()
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
              lastRenderedPixelSize = CGSize(width: Int(dims[2]), height: Int(dims[3]))
              ignoreGLError()
            }
          }
        } else {
          glClearColor(0, 0, 0, 1)
          glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        }
      }
      glFlush()
      let frameHandlers = takeCropFrameHandlers()
      if !frameHandlers.isEmpty { DispatchQueue.main.async { frameHandlers.forEach { $0(true) } } }

      let handlers = takeSnapshotHandlers()
      if !handlers.isEmpty {
        let image = framebufferSnapshot(width: Int(dims[2]), height: Int(dims[3]))
        handlers.forEach { $0(image) }
      }
    }
  }

  private final class CropFrameState {
    let lock = Lock()
    var handlers: [(Bool) -> Void] = []
    var preparationHandlers: [(Bool) -> Void] = []
    var displayDeadline: Int64?
    var displayGeneration = 0
    var closed = false
  }
  private var cropFrameState = CropFrameState()

  private func takeCropFrameHandlers() -> [(Bool) -> Void] {
    cropFrameState.lock.withLock {
      let handlers = cropFrameState.handlers
      cropFrameState.handlers.removeAll()
      return handlers
    }
  }

  func afterNextCropFrame(_ completion: @escaping (Bool) -> Void) {
    let queued = cropFrameState.lock.withLock {
      guard !cropFrameState.closed else { return false }
      cropFrameState.handlers.append(completion)
      return true
    }
    if queued { update(force: true) } else { completion(false) }
  }

  private func takePreparedCropFrameHandlers() -> [(Bool) -> Void] {
    cropFrameState.lock.withLock {
      let handlers = cropFrameState.preparationHandlers
      cropFrameState.preparationHandlers.removeAll()
      return handlers
    }
  }

  func afterNextPreparedCropFrame(_ completion: @escaping (Bool) -> Void) {
    let queued = cropFrameState.lock.withLock {
      guard !cropFrameState.closed else { return false }
      cropFrameState.preparationHandlers.append(completion)
      return true
    }
    if queued { update(force: true) } else { completion(false) }
  }

  func cancelCropFrameRequests(close: Bool = false) {
    cropFrameState.lock.withLock {
      if close { cropFrameState.closed = true }
      cropFrameState.displayDeadline = nil
      cropFrameState.displayGeneration += 1
    }
    let handlers = takeCropFrameHandlers() + takePreparedCropFrameHandlers()
    if !handlers.isEmpty { DispatchQueue.main.async { handlers.forEach { $0(false) } } }
  }

  // MARK: - Snapshot

  private final class SnapshotState {
    let lock = Lock()
    var handlers: [(NSImage?) -> Void] = []
    var closed = false
  }
  private var snapshotState = SnapshotState()

  private func takeSnapshotHandlers() -> [(NSImage?) -> Void] {
    snapshotState.lock.withLock {
      let handlers = snapshotState.handlers
      snapshotState.handlers.removeAll()
      return handlers
    }
  }

  func cancelSnapshots() {
    cancelCropFrameRequests(close: true)
    let handlers = snapshotState.lock.withLock {
      snapshotState.closed = true
      let handlers = snapshotState.handlers
      snapshotState.handlers.removeAll()
      return handlers
    }
    handlers.forEach { $0(nil) }
  }

  /// Capture the next rendered frame as an `NSImage`. Forces a redraw so this works while paused.
  func captureSnapshot() async -> NSImage? {
    await withCheckedContinuation { continuation in
      // Concurrent Live Text requests share one native readback.
      let shouldDraw: Bool? = snapshotState.lock.withLock {
        guard !snapshotState.closed else { return nil }
        let needsDraw = snapshotState.handlers.isEmpty
        snapshotState.handlers.append { image in
          continuation.resume(returning: image)
        }
        return needsDraw
      }
      if shouldDraw == true { update(force: true) }
      else if shouldDraw == nil { continuation.resume(returning: nil) }
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

    // Wait for mpv's presentation deadline before opening a CA transaction or
    // locking the drawable. Waiting inside render() holds those resources and
    // makes compositor/window movement advance at the video's frame rate.
    if !Thread.isMainThread && deferCropDisplayUntilFrameTime() { return }

    if Thread.isMainThread, !isHostedInPIP, !isDrawingGeometryHandoff,
       inLiveResize || isAnimatingWindowResize || isInFullscreenTransition {
      scheduleFullscreenDisplay()
      return
    }

    // May need to block other threads to allow the main thread to lock displayLock.
    mainThreadPriorityLock.beforeLocking()
    displayLock.lock()
    defer { displayLock.unlock() }
    mainThreadPriorityLock.afterLocked()
    defer { completeFullscreenTransitionIfReady() }

    let isUpdate = needsFlip
    skippedEmptyCropFrame = false

    if Thread.isMainThread {
      super.display()
    } else {
      // When not on the main thread use an explicit transaction.
      CATransaction.begin()
      super.display()
      CATransaction.commit()
    }

    // Never flush native PiP's main-thread transaction: bounds and surface must publish together.
    if !isDrawingGeometryHandoff && (!Thread.isMainThread || !isHostedInPIP) {
      CATransaction.flush()
    }

    // canDraw can decline an empty crop frame or one whose presentation time
    // is still in the future. Leave it queued for the next draw; skip-rendering
    // here would consume it without publishing or completing presentation waiters.
    if skippedEmptyCropFrame { return }
    guard isUpdate && needsFlip else { return }

    // Must lock the OpenGL context before calling mpv render methods. The OpenGL context must
    // always be locked before locking the isUninited lock to avoid deadlocks.
    videoView.player.mpv.lockAndSetOpenGLContext()
    defer { videoView.player.mpv.unlockOpenGLContext() }
    videoView.$isUninited.withReadLock() { isUninited in
      guard !isUninited else { return }

      if isInCropTransition && !isPreparingCropFrame { cancelCropFrameRequests() }
      // Neither canDraw nor draw(inCGLContext:) were called by AppKit, needs a skip render.
      // This can happen when IINA is playing in another space, as might occur when just playing
      // audio. See issue #5025.
      if let renderContext = videoView.player.mpv.mpvRenderContext {
        let preparing = isPreparingCropFrame
        let hasFrame: Bool
        if preparing {
          _ = mpv_render_context_update(renderContext)
          var info = mpv_render_frame_info()
          withUnsafeMutablePointer(to: &info) { pointer in
            _ = mpv_render_context_get_info(renderContext,
              mpv_render_param(type: MPV_RENDER_PARAM_NEXT_FRAME_INFO, data: pointer))
          }
          hasFrame = info.flags & UInt64(MPV_RENDER_FRAME_INFO_PRESENT.rawValue) != 0
        } else { hasFrame = videoView.player.mpv.shouldRenderUpdateFrame() }
        guard hasFrame else { return }
        var skip: CInt = 1
        withUnsafeMutablePointer(to: &skip) { skip in
          var params: [mpv_render_param] = [
            mpv_render_param(type: MPV_RENDER_PARAM_SKIP_RENDERING, data: .init(skip)),
            mpv_render_param()
          ]
          mpv_render_context_render(renderContext, &params)
        }
        if preparing {
          // The normal renderer now owns a real current frame from the prepared
          // graph. Main can change the viewport and redraw that frame atomically.
          let handlers = takePreparedCropFrameHandlers()
          if !handlers.isEmpty { DispatchQueue.main.async { handlers.forEach { $0(true) } } }
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

  private func deferCropDisplayUntilFrameTime() -> Bool {
    guard isInCropTransition || isHostedInPIP else { return false }
    let mpv = videoView.player.mpv!
    mpv.lockAndSetOpenGLContext()
    defer { mpv.unlockOpenGLContext() }
    return videoView.$isUninited.withReadLock { isUninited in
      guard !isUninited, let context = mpv.mpvRenderContext else { return false }
      _ = mpv_render_context_update(context)
      var frame = mpv_render_frame_info()
      withUnsafeMutablePointer(to: &frame) { pointer in
        _ = mpv_render_context_get_info(context,
          mpv_render_param(type: MPV_RENDER_PARAM_NEXT_FRAME_INFO, data: pointer))
      }
      guard frame.flags & UInt64(MPV_RENDER_FRAME_INFO_PRESENT.rawValue) != 0 else { return false }
      // Bundled mpv 0.41 returns the native nanosecond pts here despite the
      // header's older microsecond description. Its ns clock is render-safe.
      // Keep the original A/V timing; move only the wait outside the drawable.
      return deferCropDisplay(until: frame.target_time, now: mpv_get_time_ns(mpv.mpv))
    }
  }

  private func deferCropDisplay(until target: Int64, now: Int64) -> Bool {
    guard target > now else { return false }
    let generation: Int? = cropFrameState.lock.withLock {
      guard !cropFrameState.closed, cropFrameState.displayDeadline != target else { return nil }
      cropFrameState.displayDeadline = target
      cropFrameState.displayGeneration += 1
      return cropFrameState.displayGeneration
    }
    if let generation {
      mpvGLQueue.asyncAfter(deadline: .now() + Double(target - now) / 1_000_000_000) { [weak self] in
        guard let self else { return }
        let current = self.cropFrameState.lock.withLock {
          guard !self.cropFrameState.closed, self.cropFrameState.displayGeneration == generation else { return false }
          self.cropFrameState.displayDeadline = nil
          return true
        }
        if current { self.update(force: false) }
      }
    }
    return true
  }

  func beginFullscreenTransition() {
    dispatchPrecondition(condition: .onQueue(.main))
    $fullscreenTransition.withLock { state in
      state.generation += 1
      state.active = true
      state.finishing = false
    }
    contentsGravity = .resizeAspectFill
    isAsynchronous = true
    update(force: true)
  }

  func endFullscreenTransition(cancelled: Bool = false) {
    dispatchPrecondition(condition: .onQueue(.main))
    $fullscreenTransition.withLock { state in
      state.finishing = !cancelled
      if cancelled {
        state.generation += 1
        state.active = false
      }
    }
    contentsGravity = cancelled ? .resizeAspectFill : .resizeAspect
  }

  private func scheduleFullscreenDisplay() {
    let scheduled = $fullscreenDisplayQueued.withLock { queued in
      guard !queued else { return false }
      queued = true
      return true
    }
    guard scheduled else { return }
    mpvGLQueue.async { [self] in
      fullscreenDisplayQueued = false
      forceDraw = true
      needsFlip = true
      display()
    }
  }

  private func completeFullscreenTransitionIfReady() {
    let state = fullscreenTransition
    guard state.active, state.finishing, lastRenderedPixelSize == pixelSize else { return }
    DispatchQueue.main.async { [weak videoView] in
      guard let owner = videoView?.videoLayer,
            owner.lastRenderedPixelSize == owner.pixelSize else { return }
      owner.$fullscreenTransition.withLock { current in
        guard current.generation == state.generation, current.active, current.finishing else { return }
        current.active = false
        current.finishing = false
      }
    }
  }

  /// A new native host can allocate a fresh surface even at the same pixel size.
  func invalidatePIPDisplay() {
    dispatchPrecondition(condition: .onQueue(.main))
    lastRenderedPixelSize = nil
    setNeedsDisplay()
  }

  /// Only PiP host/geometry handoffs render on main; regular playback stays on mpvGLQueue.
  func displayForPIPHandoff() {
    dispatchPrecondition(condition: .onQueue(.main))
    mainThreadPriorityLock.beforeLocking()
    displayLock.lock()
    defer { displayLock.unlock() }
    mainThreadPriorityLock.afterLocked()
    isDrawingGeometryHandoff = true
    let wasAsynchronous = isAsynchronous
    isAsynchronous = false
    defer {
      isDrawingGeometryHandoff = false
      isAsynchronous = wasAsynchronous
    }
    // Hold display()'s lock so a queued playback update cannot consume the forced draw first.
    forceDraw = true
    needsFlip = true
    display()
  }

  /// Keep the normal native backing while mpv drains an old filter graph. Ready
  /// frames are consumed without presentation until source size and VO geometry
  /// agree; playback and audio keep advancing. No additional video surface exists.
  func setCropFramePreparation(_ preparing: Bool) {
    dispatchPrecondition(condition: .onQueue(.main))
    mainThreadPriorityLock.beforeLocking()
    displayLock.lock()
    mainThreadPriorityLock.afterLocked()
    isPreparingCropFrame = preparing
    displayLock.unlock()
    update(force: true)
  }

  /// Window layout and its native projection are one presentation update. AppKit
  /// may request a resized drawable inside setFrame; defer that draw until all VO
  /// options describe the same viewport.
  func withCropFrameUpdate(_ body: () -> Void) {
    dispatchPrecondition(condition: .onQueue(.main))
    mainThreadPriorityLock.beforeLocking()
    displayLock.lock()
    mainThreadPriorityLock.afterLocked()
    let preparing = isPreparingCropFrame
    isPreparingCropFrame = true
    body()
    isPreparingCropFrame = preparing
    displayLock.unlock()
    if !preparing { update(force: true) }
  }

  /// Publish the final native viewport in the same transaction as editor layout.
  /// Regular playback continues on mpvGLQueue; only this geometry boundary draws
  /// synchronously, so restoring native layout cannot expose an old-sized FBO.
  func displayForCropHandoff(allowCachedFrame: Bool = false) {
    dispatchPrecondition(condition: .onQueue(.main))
    mainThreadPriorityLock.beforeLocking()
    displayLock.lock()
    defer { displayLock.unlock() }
    mainThreadPriorityLock.afterLocked()
    isDrawingGeometryHandoff = true
    let wasCropping = isInCropTransition
    if allowCachedFrame { isInCropTransition = false }
    // Changing crop ownership can enable CA's resize timer. This one draw must
    // remain synchronous with its geometry, including when a cached current
    // frame is used after mpv's prepared-frame notification.
    isAsynchronous = false
    defer { isDrawingGeometryHandoff = false; isInCropTransition = wasCropping }
    forceDraw = true
    needsFlip = true
    display()
  }

  /// Keep a newly cropped texture from reaching the compositor under the old
  /// source transform. A nested commit alone leaves AppKit's implicit root
  /// transaction pending; no background draw may publish until it is flushed.
  func withCropFrameHandoff(_ updateLayout: () -> Void) {
    dispatchPrecondition(condition: .onQueue(.main))
    mainThreadPriorityLock.beforeLocking()
    displayLock.lock()
    defer { displayLock.unlock() }
    mainThreadPriorityLock.afterLocked()
    isPreparingCropFrame = true
    isAsynchronous = false
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    updateLayout()
    isPreparingCropFrame = false
    displayForCropHandoff(allowCachedFrame: true)
    CATransaction.commit()
    CATransaction.flush()
  }

  private func framebufferSnapshot(width: Int, height: Int) -> NSImage? {
    let bytesPerRow = width * 4
    var pixels = Data(count: height * bytesPerRow)

    // Save and restore the read framebuffer binding so we don't disturb AppKit/mpv state.
    var prevReadFBO: GLint = 0
    glGetIntegerv(GLenum(GL_READ_FRAMEBUFFER_BINDING), &prevReadFBO)
    defer { glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), GLuint(prevReadFBO)) }

    // The layer renders into an FBO (captured as `fbo`), not the default framebuffer,
    // so we must bind that FBO as the read target and use GL_COLOR_ATTACHMENT0 — not GL_BACK.
    glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), GLuint(fbo))
    glReadBuffer(GLenum(GL_COLOR_ATTACHMENT0))
    glPixelStorei(GLenum(GL_PACK_ALIGNMENT), 1)

    pixels.withUnsafeMutableBytes { buf in
      guard let base = buf.baseAddress else { return }
      glReadPixels(0, 0, GLsizei(width), GLsizei(height),
                   GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), base)

      // OpenGL origin is bottom-left; CGImage expects top-left. Flip rows in place.
      var temp = [UInt8](repeating: 0, count: bytesPerRow)
      temp.withUnsafeMutableBufferPointer { tempBuf in
        let tmp = UnsafeMutableRawPointer(tempBuf.baseAddress!)
        for i in 0..<(height / 2) {
          let top = base.advanced(by: i * bytesPerRow)
          let bot = base.advanced(by: (height - 1 - i) * bytesPerRow)
          memcpy(tmp, top, bytesPerRow)
          memcpy(top, bot, bytesPerRow)
          memcpy(bot, tmp, bytesPerRow)
        }
      }
    }

    guard let provider = CGDataProvider(data: pixels as CFData) else { return nil }
    guard let cgImage = CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: bytesPerRow,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    ) else { return nil }

    return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
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
    let subsystem = Logger.makeSubsystem("layer\(player.playerNumber)", ["square.2.layers.3d.bottom.filled"])
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

    guard let ctx else {
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

#if USE_ICC_PROFILE_AUTO // See VideoView.setICCProfile.
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
#endif // USE_ICC_PROFILE_AUTO

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
