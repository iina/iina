//
//  VR2DController.swift
//  iina
//
//  Per-player state for VR reprojection: what the source is, where the viewer
//  is looking, and whether the whole thing is switched on.
//
//  Everything here is touched from the main thread. The render thread only ever
//  reads a `Snapshot`, taken under a lock, so panning never has to wait for a
//  frame and a frame never has to wait for a drag.
//

import Cocoa

final class VR2DController {

  /// What the render thread needs, copied out under a lock.
  struct Snapshot {
    var isActive = false
    /// Size of the offscreen buffer mpv should render into.
    var videoWidth = 0
    var videoHeight = 0
    var params = VR2DRenderer.Params(source: VR2DSource(), view: VR2DView(), eye: .left)
  }

  private unowned let player: PlayerCore
  private let lock = Lock()
  private var published = Snapshot()

  private lazy var subsystem = Logger.makeSubsystem("vr2d\(player.playerNumber)", ["view.3d"])

  // MARK: - State (main thread only)

  private(set) var isEnabled = false
  private(set) var detection = VR2DDetection()
  /// The source as it will be rendered — detection's answer, plus any manual
  /// override the user has made for this file.
  private(set) var source = VR2DSource()
  private(set) var view = VR2DView()
  private(set) var eye: VR2DEye = .left

  private var videoWidth = 0
  private var videoHeight = 0
  /// What `video-timing-offset` was before reprojection took it to zero.
  private var savedVideoTimingOffset: Double?
  /// What `sub-visibility` was before reprojection took subtitle drawing over.
  private var savedSubVisibility: Bool?
  /// Whether the user wants subtitles shown, once mpv's own flag is no longer
  /// able to carry that meaning.
  private var subtitlesVisible = true
  private var subtitleText = ""
  /// Warn once per file, not once per video-reconfig.
  private var hasWarnedAboutFilter = false

  init(player: PlayerCore) {
    self.player = player
  }

  // MARK: - Reading

  func snapshot() -> Snapshot {
    return lock.withLock { published }
  }

  /// Size of the video view in points, which is what the frustum is fitted to.
  private var surfaceSize: CGSize {
    guard player.mainWindow.loaded else { return CGSize(width: 16, height: 9) }
    let size = player.mainWindow.videoView.frame.size
    guard size.width > 0, size.height > 0 else { return CGSize(width: 16, height: 9) }
    return size
  }

  // MARK: - File lifecycle

  /// Run detection for the file that just loaded and turn reprojection on if
  /// the evidence is strong enough.
  func fileLoaded() {
    hasWarnedAboutFilter = false
    refreshVideoSize()

    let info = player.vr2dSourceInfo()
    guard info.width > 0, info.height > 0 else { return }

    let preferredEye: Preference.VR2DEyeOption = Preference.enum(for: .vr2dEye)
    eye = preferredEye == .right ? .right : .left

    let url = player.info.currentURL?.absoluteString ?? ""
    detection = VR2DDetect.detect(url: url, width: info.width, height: info.height,
                                  stereoIn: info.stereoIn,
                                  aggressive: Preference.bool(for: .vr2dAggressiveDetection))
    source = detection.source

    let shouldEnable = Preference.bool(for: .vr2dAutoDetect) && detection.auto
    Logger.log("Detected \(detection.summary); strong: \(detection.strong), weak: \(detection.weak)" +
               "; auto-enable \(shouldEnable)", level: .verbose, subsystem: subsystem)

    if shouldEnable {
      setEnabled(true, announce: true)
    } else {
      setEnabled(false, announce: false)
    }

#if DEBUG
    VR2DSelfTest.runIfRequested(for: player)
    VR2DSelfTest.runInputChecksIfRequested(for: player)
#endif
  }

#if DEBUG
  /// Force a complete state, bypassing detection and the clamps, so a render
  /// can be compared pixel for pixel against a reference. See `VR2DSelfTest`.
  func applyForSelfTest(source: VR2DSource, view: VR2DView, eye: VR2DEye) {
    isEnabled = true
    self.source = source
    self.view = view
    self.eye = eye
    publish()
  }
#endif

  /// The decoded video changed shape, so the offscreen buffer has to follow and
  /// the view may need re-clamping.
  func videoGeometryChanged() {
    refreshVideoSize()
    clampAndPublish()
    // A CPU reprojection filter changes the frame size, so this is exactly when
    // one shows up — and it is added after the file loads, which is why the
    // check cannot only happen when reprojection is switched on.
    if isEnabled { warnAboutConflictingFilter() }
  }

  private func refreshVideoSize() {
    // The offscreen buffer is the size mpv itself would render at, so that mpv
    // fills it exactly: same aspect means no letterboxing, and native size
    // means no downscaling before the shader gets to sample.
    let width = player.info.displayWidth ?? 0
    let height = player.info.displayHeight ?? 0
    if width <= 0 || height <= 0 {
      // On the first file-loaded event IINA has zeroed these and is still
      // waiting for a video-reconfig; mpv already knows.
      return refreshVideoSizeFromMpv()
    }
    guard width > 0, height > 0 else { return }
    videoWidth = width
    videoHeight = height
  }

  /// mpv knows the size before IINA has recorded it, which is the case on the
  /// first file-loaded event.
  private func refreshVideoSizeFromMpv() {
    let size = player.vr2dDisplaySize()
    guard size.width > 0, size.height > 0 else { return }
    videoWidth = size.width
    videoHeight = size.height
  }

  // MARK: - Enabling

  func setEnabled(_ enabled: Bool, announce: Bool = true) {
    guard enabled != isEnabled else { return }
    isEnabled = enabled
    applyVideoTiming()
    applySubtitleHandling()
    if enabled {
      resetView()
    }
    clampAndPublish()
    if announce {
      player.sendOSD(.custom(enabled
        ? String(format: NSLocalizedString("osd.vr2d_on", comment: "VR2D on - %@"),
                 VR2DDetect.summarize(source))
        : NSLocalizedString("osd.vr2d_off", comment: "VR2D off")))
    }
    if enabled { warnAboutConflictingFilter() }
  }

  /// The VR2D *plugin* does the same job with a CPU filter, and if it is still
  /// installed and enabled it reprojects the frame before this ever sees it —
  /// the picture comes out reprojected twice and the panning is as slow as the
  /// plugin's, which looks exactly like this fork not working.
  ///
  /// Detected from the filter chain rather than from a plugin name, so it also
  /// catches the same mistake made with any other reprojecting filter.
  private func warnAboutConflictingFilter() {
    guard !hasWarnedAboutFilter else { return }
    guard let filters = player.vr2dVideoFilters(), !filters.isEmpty else { return }
    let lowercased = filters.lowercased()
    guard lowercased.contains("v360") || lowercased.contains("vr2d") else { return }

    hasWarnedAboutFilter = true
    Logger.log("A video filter is already reprojecting this frame (vf=\(filters)). " +
               "The VR2D plugin must be turned off for this build to help.",
               level: .warning, subsystem: subsystem)
    player.sendOSD(.custom(NSLocalizedString("osd.vr2d_filter_conflict",
                                            comment: "A filter is already reprojecting")),
                   forcedTimeout: 5)
  }

  func toggle() {
    setEnabled(!isEnabled)
  }

  // MARK: - Subtitles

  /// `true` while subtitles are being drawn over the flattened picture instead
  /// of composited into it by mpv.
  private(set) var isDrawingSubtitles = false

  /// Take subtitle drawing away from mpv while reprojection is on.
  ///
  /// mpv composites subtitles into the same framebuffer as the video and the
  /// render API cannot separate them, so they would be warped onto the sphere
  /// with the picture. `VR2DSubtitleView` draws them flat over the top instead,
  /// and mpv's `sub-visibility` is held off so it stops drawing its own.
  ///
  /// Because that flag is also how the user shows and hides subtitles,
  /// `PlayerCore.toggleSubVisibility` is routed here while this is in effect —
  /// otherwise turning subtitles back on would turn the warped ones back on.
  ///
  /// Picture-based subtitles have no text to re-draw, so mpv keeps them and
  /// they stay warped: better warped than absent.
  private func applySubtitleHandling() {
    guard player.mainWindow.loaded else { return }
    let shouldDraw = isEnabled && !subtitleText.isEmpty

    if shouldDraw, !isDrawingSubtitles {
      savedSubVisibility = player.vr2dSetSubtitleRendering(false)
      subtitlesVisible = savedSubVisibility ?? true
      isDrawingSubtitles = true
    } else if !shouldDraw, isDrawingSubtitles {
      isDrawingSubtitles = false
      if let saved = savedSubVisibility {
        player.vr2dSetSubtitleRendering(saved)
        savedSubVisibility = nil
      }
    }

    let view = player.mainWindow.vr2dSubtitleView
    view.player = player
    view.text = (isDrawingSubtitles && subtitlesVisible) ? subtitleText : ""
  }

  /// Show or hide the flattened subtitles, standing in for mpv's own flag.
  func setSubtitlesVisible(_ visible: Bool) {
    subtitlesVisible = visible
    applySubtitleHandling()
  }

  /// A subtitle setting changed, so whatever is on screen has to be restyled.
  func subtitleStyleChanged() {
    guard player.mainWindow.loaded else { return }
    player.mainWindow.vr2dSubtitleView.render()
  }

  func subtitleTextChanged(_ text: String) {
    subtitleText = text
    applySubtitleHandling()
  }

  /// Stop mpv rendering ahead of time while looking around is possible.
  ///
  /// mpv normally renders a frame early and waits inside its render call until
  /// the frame is due. That wait occupies the one thread that can talk to
  /// OpenGL, so a pan cannot be drawn until it finishes — panning ends up
  /// running at the video's frame rate rather than the display's. Rendering
  /// with no headroom costs a little scheduling slack and buys immediate
  /// response; the previous value goes back when reprojection is switched off.
  private func applyVideoTiming() {
    if isEnabled {
      let previous = player.vr2dSetVideoTimingOffset(0)
      if savedVideoTimingOffset == nil { savedVideoTimingOffset = previous }
    } else if let saved = savedVideoTimingOffset {
      player.vr2dSetVideoTimingOffset(saved)
      savedVideoTimingOffset = nil
    }
  }

  // MARK: - Looking around

  func resetView() {
    let size = surfaceSize
    let horizontal = Preference.double(for: .vr2dStartHorizontalFov)
    view = VR2DView(yaw: 0, pitch: 0,
                    fov: VR2DGeometry.diagonalFromHorizontal(horizontal, size.width, size.height))
    clampAndPublish()
  }

  /// Pan by a drag in points. Dragging right swings the view left, so the
  /// picture tracks the cursor.
  func pan(dx: CGFloat, dy: CGFloat) {
    let size = surfaceSize
    var sensitivity = Preference.double(for: .vr2dDragSensitivity)
    if Preference.bool(for: .vr2dInvertDrag) { sensitivity = -sensitivity }
    view = VR2DGeometry.applyDrag(view, dx: Double(dx), dy: Double(dy),
                                  width: size.width, height: size.height, sensitivity: sensitivity)
    clampAndPublish()
  }

  /// Pan by a fixed number of degrees, for the keyboard.
  func panBy(yaw: Double, pitch: Double) {
    view = VR2DGeometry.applyPanStep(view, dxDeg: yaw, dyDeg: pitch)
    clampAndPublish()
  }

  func zoom(notches: Double) {
    view = VR2DGeometry.applyZoom(view, notches: notches)
    clampAndPublish()
  }

  // MARK: - Overrides

  /// Pick a projection from the menu. Choosing one turns reprojection on, the
  /// way choosing a crop turns cropping on; `nil` means whatever detection
  /// worked out.
  func selectProjection(_ projection: VR2DProjection?) {
    if !isEnabled { setEnabled(true, announce: false) }
    setProjection(projection)
  }

  /// Fisheye at a particular lens angle.
  func selectFisheye(fov: Double) {
    if !isEnabled { setEnabled(true, announce: false) }
    source.projection = .fisheye
    source.inHFov = fov
    source.inVFov = fov
    announceSource()
    clampAndPublish()
  }

  func setProjection(_ projection: VR2DProjection?) {
    guard let projection else {
      source.projection = detection.source.projection
      source.inHFov = detection.source.inHFov
      source.inVFov = detection.source.inVFov
      announceSource()
      clampAndPublish()
      return
    }
    source.projection = projection
    // Fisheye keeps whatever lens angle detection found; the others have a
    // coverage that follows from the projection itself.
    switch projection {
    case .halfEquirect:
      source.inHFov = 180
      source.inVFov = 180
    case .equirect, .eac:
      source.inHFov = 360
      source.inVFov = 180
    case .fisheye:
      let detected = detection.source
      let fov = detected.projection == .fisheye ? detected.inHFov : 180
      source.inHFov = fov
      source.inVFov = fov
    }
    announceSource()
    clampAndPublish()
  }

  func cycleLayout() {
    let order: [(VR2DLayout, Bool)] = [(.mono, false), (.sbs, false), (.sbs, true), (.tb, false), (.tb, true)]
    let current = order.firstIndex { $0.0 == source.layout && $0.1 == source.swapEyes } ?? 0
    let next = order[(current + 1) % order.count]
    setLayout(next.0, swapEyes: next.1)
  }

  func setLayout(_ layout: VR2DLayout?, swapEyes: Bool = false) {
    if let layout {
      source.layout = layout
      source.swapEyes = swapEyes
    } else {
      source.layout = detection.source.layout
      source.swapEyes = detection.source.swapEyes
    }
    announceSource()
    clampAndPublish()
  }

  func setEye(_ eye: VR2DEye) {
    self.eye = eye
    Preference.set((eye == .right ? Preference.VR2DEyeOption.right : .left).rawValue, for: .vr2dEye)
    publish()
    player.sendOSD(.custom(String(format: NSLocalizedString("osd.vr2d_eye", comment: "VR2D - %@ eye"),
                                 eye == .left
                                   ? NSLocalizedString("vr2d.eye.left", comment: "Left")
                                   : NSLocalizedString("vr2d.eye.right", comment: "Right"))))
  }

  func swapEye() {
    setEye(eye == .left ? .right : .left)
  }

  private func announceSource() {
    player.sendOSD(.custom(String(format: NSLocalizedString("osd.vr2d_source", comment: "VR2D - %@"),
                                 VR2DDetect.summarize(source))))
  }

  // MARK: - Publishing

  private func clampAndPublish() {
    let size = surfaceSize
    view = VR2DGeometry.clampView(view, source, size.width, size.height)
    publish()
  }

  /// Copy the state the render thread needs and ask for a redraw.
  ///
  /// The redraw is forced because the view can change while playback is paused,
  /// and mpv has no new frame to offer in that case — the whole point of doing
  /// this in the renderer is that the held frame can be re-projected.
  private func publish() {
    let snapshot = Snapshot(isActive: isEnabled && videoWidth > 0 && videoHeight > 0,
                            videoWidth: videoWidth,
                            videoHeight: videoHeight,
                            params: VR2DRenderer.Params(source: source, view: view, eye: eye))
    lock.withLock { published = snapshot }
    guard player.mainWindow.loaded else { return }
    player.mainWindow.videoView.videoLayer.update(force: true)
  }
}
