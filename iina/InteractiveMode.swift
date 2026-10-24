//
//  InteractiveMode.swift
//  iina
//
//  Created by Hechen Li on 2026-06-22.
//  Copyright © 2026 lhc. All rights reserved.
//

import Cocoa

fileprivate let ui = UIHelper.shared

// The native view always renders the complete source at its source aspect.
// Crop motion moves that view and its aperture together; mpv never receives
// per-tick geometry commands or a replacement video frame.
final class NativeCropVideoPresentation {
  private weak var view: NSView?
  private weak var container: NSView?
  private let beginLayout: () -> Void
  private let restoreLayout: () -> Void
  private let originalFrame: NSRect
  private var originalTransform: CATransform3D
  private let originalGravity: CALayerContentsGravity
  private let originalAutoresizingMask: CAAutoresizingMask
  private let originalScale: CGFloat
  private var originalMask: CALayer?
  private let aperture = CALayer()
  private let rotatedAperture = CAShapeLayer()
  private var pixelSize: NSSize
  private var isPresenting = false
  private var ownsLayout = false
  private var presentationFrame = NSRect.zero
  private var maximumRasterFrameSize: NSSize?
  private var lastPresentation: (frame: NSRect, clip: NSRect, rotation: CGFloat)?

  /// Resolve density before motion; the compositor can then zoom without
  /// magnifying an editor-sized raster or reallocating it on every tick.
  func prepareRaster(for frames: [NSRect]) {
    let sizes = frames.map(\.size).filter {
      $0.width.isFinite && $0.height.isFinite && $0.width > 0 && $0.height > 0
    }
    guard let first = sizes.first else { return }
    maximumRasterFrameSize = sizes.dropFirst().reduce(first) {
      NSSize(width: max($0.width, $1.width), height: max($0.height, $1.height))
    }
    if isPresenting, let lastPresentation {
      isPresenting = false
      present(frame: lastPresentation.frame, clip: lastPresentation.clip, rotation: lastPresentation.rotation)
    }
  }

  static func rasterScale(base: NSSize, maximum: NSSize, source: NSSize,
                          backingScale: CGFloat, legacyScale: CGFloat) -> CGFloat {
    guard [base.width, base.height, maximum.width, maximum.height,
           source.width, source.height, backingScale, legacyScale].allSatisfy({ $0.isFinite && $0 > 0 })
      else { return legacyScale.isFinite && legacyScale > 0 ? legacyScale : 1 }
    let demand = backingScale * max(1, maximum.width / base.width, maximum.height / base.height)
    // Both source axes matter for anamorphic video. Beyond source detail,
    // increasing this full-frame raster only spends memory on upscaled pixels.
    let detail = max(source.width / base.width, source.height / base.height)
    let areaLimit = max(CGFloat(3840 * 2160), base.width * base.height * legacyScale * legacyScale)
    let areaScale = sqrt(areaLimit / base.width / base.height)
    let edgeScale = max(legacyScale, 8192 / max(base.width, base.height))
    return max(legacyScale, min(demand, detail, areaScale, edgeScale))
  }

  private func rasterScale(for size: NSSize, view: NSView) -> CGFloat {
    let screenScale = view.window?.backingScaleFactor ?? originalScale
    let pixelLimit = max(pixelSize.width, pixelSize.height,
                         max(container?.bounds.width ?? 0, container?.bounds.height ?? 0) * screenScale)
    let legacy = min(screenScale, pixelLimit / max(size.width, size.height))
    guard let maximumRasterFrameSize else { return legacy }
    return Self.rasterScale(base: size, maximum: maximumRasterFrameSize, source: pixelSize,
                            backingScale: screenScale, legacyScale: legacy)
  }

  init(view: NSView, container: NSView, pixelSize: NSSize,
       beginLayout: @escaping () -> Void = {}, restoreLayout: @escaping () -> Void = {}) {
    self.view = view; self.container = container; self.pixelSize = pixelSize
    self.beginLayout = beginLayout; self.restoreLayout = restoreLayout
    originalFrame = view.frame
    originalTransform = view.layer?.transform ?? CATransform3DIdentity
    originalGravity = view.layer?.contentsGravity ?? .resizeAspectFill
    originalAutoresizingMask = view.layer?.autoresizingMask ?? []
    originalScale = view.layer?.contentsScale ?? 1
    originalMask = view.layer?.mask
    aperture.backgroundColor = NSColor.white.cgColor
    rotatedAperture.fillColor = NSColor.white.cgColor
  }

  func updateSourcePixels(_ size: NSSize) { pixelSize = size }

  func setRestoration(transform: CATransform3D, mask: CALayer?) {
    // Editor teardown may choose the final player geometry, but the live
    // transition keeps its transform/aperture until the new output is ready.
    originalTransform = transform
    originalMask = mask
  }

  func present(frame: NSRect, clip: NSRect, rotation: CGFloat = 0) {
    guard rotation.isFinite else { return }
    guard let view, container != nil, !frame.isEmpty, !clip.isEmpty,
          frame.width.isFinite, frame.height.isFinite else { return }
    guard let layer = view.layer else { return }
    lastPresentation = (frame, clip, rotation)
    if !isPresenting {
      isPresenting = true
      if !ownsLayout { beginLayout(); ownsLayout = true }
      // The window may resize while the source raster stays fixed. ViewLayer's
      // regular parent sizing must not compete with the crop transform.
      layer.autoresizingMask = []
      // Allocate a full-source surface once. Changing its bounds every tick
      // makes Core Animation wait for the native GL renderer during playback.
      // Only the compositor transform and aperture move after this boundary.
      let density = rasterScale(for: frame.size, view: view)
      let screenScale = view.window?.backingScaleFactor ?? originalScale
      let allocationScale = maximumRasterFrameSize == nil ? 1 : density / screenScale
      let allocation = NSRect(origin: frame.origin, size: NSSize(
        width: frame.width * allocationScale, height: frame.height * allocationScale))
      layer.transform = CATransform3DIdentity
      view.frame = allocation
      presentationFrame = allocation
      layer.contentsGravity = .resize
      layer.contentsScale = maximumRasterFrameSize == nil ? density : screenScale
    }
    if rotation != 0 {
      presentRotated(frame: frame, clip: clip, rotation: rotation, layer: layer)
      return
    }
    let base = presentationFrame
    let scaleX = frame.width / base.width, scaleY = frame.height / base.height
    var transform = CATransform3DMakeScale(scaleX, scaleY, 1)
    transform.m41 = frame.minX - base.minX + (frame.width - base.width) * layer.anchorPoint.x
    transform.m42 = frame.minY - base.minY + (frame.height - base.height) * layer.anchorPoint.y
    layer.transform = transform
    aperture.frame = NSRect(x: (clip.minX - frame.minX) / scaleX,
                            y: (clip.minY - frame.minY) / scaleY,
                            width: clip.width / scaleX, height: clip.height / scaleY)
      .intersection(view.bounds)
    layer.mask = aperture
  }

  private func presentRotated(frame: NSRect, clip: NSRect, rotation: CGFloat, layer: CALayer) {
    let bounds = layer.bounds
    guard bounds.width > 0, bounds.height > 0 else { return }
    let scaleX = frame.width / bounds.width, scaleY = frame.height / bounds.height
    let cosine = cos(rotation), sine = sin(rotation)
    // This maps raster coordinates into the container around the image center.
    // CALayer applies its transform around anchorPoint, so compensate for that
    // anchor separately instead of rotating around a possibly off-center pivot.
    let affine = CGAffineTransform(a: cosine * scaleX, b: sine * scaleX,
                                  c: -sine * scaleY, d: cosine * scaleY,
                                  tx: frame.midX - cosine * scaleX * bounds.midX + sine * scaleY * bounds.midY,
                                  ty: frame.midY - sine * scaleX * bounds.midX - cosine * scaleY * bounds.midY)
    let anchor = NSPoint(x: bounds.minX + bounds.width * layer.anchorPoint.x,
                         y: bounds.minY + bounds.height * layer.anchorPoint.y)
    var transform = CATransform3DMakeAffineTransform(affine)
    transform.m41 += affine.a * anchor.x + affine.c * anchor.y - layer.position.x
    transform.m42 += affine.b * anchor.x + affine.d * anchor.y - layer.position.y
    layer.transform = transform

    let inverse = affine.inverted()
    let corners = [NSPoint(x: clip.minX, y: clip.minY), NSPoint(x: clip.maxX, y: clip.minY),
                   NSPoint(x: clip.maxX, y: clip.maxY), NSPoint(x: clip.minX, y: clip.maxY)]
    let path = CGMutablePath()
    path.addLines(between: corners.map { $0.applying(inverse) })
    path.closeSubpath()
    rotatedAperture.frame = bounds
    rotatedAperture.bounds = bounds
    rotatedAperture.path = path
    layer.mask = rotatedAperture
  }

  func restore() {
    guard isPresenting else { return }
    isPresenting = false
    if let view, let layer = view.layer {
      if layer.mask === aperture || layer.mask === rotatedAperture {
        layer.mask = originalMask
        layer.transform = originalTransform
      }
      layer.contentsGravity = originalGravity
      layer.contentsScale = view.window?.backingScaleFactor ?? originalScale
      view.frame = originalFrame
      layer.autoresizingMask = originalAutoresizingMask
    }
    restoreLayout()
    ownsLayout = false
  }
}

/// Geometry only: the caller supplies the shared, already-eased window clock.
/// Rotation is in radians; positive compensation cancels mpv's clockwise turn.
enum VideoGeometryTransition {
  struct Sample {
    let frame: NSRect
    let rotation: CGFloat
  }

  /// Quarter-turn choices use the shortest signed degree delta; 180 ties turn clockwise.
  static func shortestQuarterTurnDelta(from: Int, to: Int) -> Int {
    let normalized = ((to % 360 - from % 360) % 360 + 360) % 360
    return normalized > 180 ? normalized - 360 : normalized
  }

  /// The new raster's unrotated frame whose compensated bounds reproduce the old image.
  static func startFrame(oldVisibleRect: NSRect, quarterTurnDelta: Int) -> NSRect {
    guard abs((quarterTurnDelta % 360) / 90) % 2 == 1 else { return oldVisibleRect }
    return NSRect(x: oldVisibleRect.midX - oldVisibleRect.height / 2,
                  y: oldVisibleRect.midY - oldVisibleRect.width / 2,
                  width: oldVisibleRect.height, height: oldVisibleRect.width)
  }

  static func sample(from start: NSRect, to target: NSRect, viewport: NSRect,
                     progress: CGFloat, initialRotation: CGFloat) -> Sample {
    guard progress.isFinite, initialRotation.isFinite,
          !start.isEmpty, !target.isEmpty, !viewport.isEmpty else {
      return Sample(frame: .zero, rotation: 0)
    }
    let progress = min(1, max(0, progress))
    let rotation = initialRotation * (1 - progress)
    let width = start.width + (target.width - start.width) * progress
    let height = start.height + (target.height - start.height) * progress
    let cosine = abs(cos(rotation)), sine = abs(sin(rotation))
    let rotatedWidth = cosine * width + sine * height
    let rotatedHeight = sine * width + cosine * height
    let fit = min(1, viewport.width / rotatedWidth, viewport.height / rotatedHeight)
    let halfWidth = rotatedWidth * fit / 2, halfHeight = rotatedHeight * fit / 2
    let centerX = min(viewport.maxX - halfWidth, max(viewport.minX + halfWidth,
      start.midX + (target.midX - start.midX) * progress))
    let centerY = min(viewport.maxY - halfHeight, max(viewport.minY + halfHeight,
      start.midY + (target.midY - start.midY) * progress))
    return Sample(frame: NSRect(x: centerX - width * fit / 2, y: centerY - height * fit / 2,
                               width: width * fit, height: height * fit), rotation: rotation)
  }
}

/// Delayed, cancellable feedback for a native operation. The owner chooses
/// whether readiness dismisses immediately or waits for a transparent breath.
final class DelayedPreparationFeedback {
  struct Token: Equatable {
    fileprivate let generation: UUID
    fileprivate init() { generation = UUID() }
  }
  enum FinishPolicy { case immediate, afterCurrentBreath }
  typealias Scheduler = (TimeInterval, @escaping () -> Void) -> Void

  static let activationDelay: TimeInterval = 0.5
  static let breathingDuration: TimeInterval = 1
  let layer = CALayer()
  private let vignette = CAGradientLayer()
  private let edge = CAGradientLayer()
  private let now: () -> CFTimeInterval
  private let schedule: Scheduler
  private let hasPresentation: (CALayer) -> Bool
  private(set) var isShowing = false
  private var token: Token?
  private var startedAt: CFTimeInterval?
  private var isPulsing = false
  private var completion: (() -> Void)?
  private var finishRequested = false

  init(namePrefix: String = "preparation", now: @escaping () -> CFTimeInterval = CACurrentMediaTime,
       schedule: @escaping Scheduler = { delay, action in
         DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
       }, hasPresentation: @escaping (CALayer) -> Bool = { $0.presentation() != nil }) {
    self.now = now
    self.schedule = schedule
    self.hasPresentation = hasPresentation
    layer.name = namePrefix + "Feedback"
    layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    layer.opacity = 0
    vignette.name = namePrefix + "Vignette"
    vignette.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    vignette.type = .radial
    vignette.startPoint = CGPoint(x: 0.5, y: 0.5)
    vignette.endPoint = CGPoint(x: 1, y: 1)
    vignette.colors = [0, 0, 0.12, 0.34, 0.52].map {
      NSColor.black.withAlphaComponent($0).cgColor
    }
    vignette.locations = [0, 0.16, 0.40, 0.70, 1]
    layer.addSublayer(vignette)
    // The same parent opacity drives both accents, including their endpoint.
    edge.name = namePrefix + "VignetteEdge"
    edge.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    edge.type = .radial
    edge.startPoint = vignette.startPoint
    edge.endPoint = vignette.endPoint
    edge.colors = [0, 0, 0.015, 0.08].map {
      NSColor.white.withAlphaComponent($0).cgColor
    }
    edge.locations = [0, 0.82, 0.94, 1]
    vignette.addSublayer(edge)
  }

  @discardableResult
  func begin(pulse: Bool) -> Token {
    // Also remove a previous cancellation's fade before starting the delay.
    end(animated: false)
    let token = Token()
    self.token = token
    isShowing = true
    schedule(Self.activationDelay) { [weak self] in self?.activate(pulse: pulse, token: token) }
    return token
  }

  private func activate(pulse: Bool, token: Token) {
    guard self.token == token, isShowing else { return }
    // An animation installed before the first backing-layer presentation can
    // be discarded. A fast operation must stay transparent even in this gap.
    guard hasPresentation(layer) else {
      schedule(1 / 60.0) { [weak self] in self?.activate(pulse: pulse, token: token) }
      return
    }
    let started = now()
    startedAt = started
    isPulsing = pulse
    let visibleOpacity = layer.presentation()?.opacity ?? layer.opacity
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.opacity = 1
    vignette.opacity = pulse ? 0 : 0.5
    vignette.removeAnimation(forKey: "breathing")
    if pulse {
      let breathing = CABasicAnimation(keyPath: "opacity")
      breathing.fromValue = Float(0)
      breathing.toValue = Float(0.7)
      breathing.duration = Self.breathingDuration / 2
      breathing.beginTime = vignette.convertTime(started, from: nil)
      breathing.autoreverses = true
      breathing.repeatCount = .infinity
      breathing.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      vignette.add(breathing, forKey: "breathing")
    } else {
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = visibleOpacity
      fade.toValue = Float(1)
      fade.duration = 0.15
      fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
      layer.add(fade, forKey: "visibility")
    }
    CATransaction.commit()
  }

  static func cycleEnd(startedAt: CFTimeInterval, readyAt: CFTimeInterval) -> CFTimeInterval {
    let cycles = max(1, ceil(max(0, readyAt - startedAt) / breathingDuration))
    return startedAt + cycles * breathingDuration
  }

  /// Accept one success continuation per active token. Cancellation/replacement
  /// suppresses that continuation; stale or duplicate finish requests return false.
  @discardableResult
  func finish(_ token: Token, policy: FinishPolicy, completion: @escaping () -> Void) -> Bool {
    guard self.token == token, !finishRequested else { return false }
    finishRequested = true
    guard policy == .afterCurrentBreath, let started = startedAt, isPulsing else {
      end(animated: false)
      completion()
      return true
    }
    self.completion = completion
    let current = now()
    let endpoint = Self.cycleEnd(startedAt: started, readyAt: current)
    // Keep the original animation clock and stop at its transparent endpoint.
    if let breathing = vignette.animation(forKey: "breathing")?.copy() as? CABasicAnimation {
      breathing.repeatCount = Float((endpoint - started) / Self.breathingDuration)
      vignette.add(breathing, forKey: "breathing")
    }
    schedule(max(0, endpoint - current)) { [weak self] in
      guard let self, self.token == token, self.isShowing else { return }
      let completion = self.completion
      self.end(animated: false)
      completion?()
    }
    return true
  }

  func cancel(_ token: Token, animated: Bool = true) {
    guard self.token == token else { return }
    end(animated: animated)
  }

  fileprivate func end(animated: Bool) {
    guard isShowing || !animated else { return }
    isShowing = false
    token = nil
    completion = nil
    finishRequested = false
    let elapsed = now() - (startedAt ?? now())
    let ramp = min(1, max(0, elapsed / 0.15))
    let visibleOpacity = layer.presentation()?.opacity ?? Float(1 - pow(1 - ramp, 3))
    startedAt = nil
    isPulsing = false
    let vignetteOpacity = vignette.presentation()?.opacity ?? vignette.opacity
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    vignette.opacity = vignetteOpacity
    vignette.removeAnimation(forKey: "breathing")
    layer.opacity = 0
    layer.removeAnimation(forKey: "visibility")
    if animated && visibleOpacity > 0 {
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = visibleOpacity
      fade.toValue = Float(0)
      fade.duration = 0.12
      fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
      layer.add(fade, forKey: "visibility")
    }
    CATransaction.commit()
  }
}

/// Transparent host for operations that do not already own an overlay layer.
final class PreparationFeedbackView: NSView {
  let feedback = DelayedPreparationFeedback()

  override init(frame: NSRect) {
    super.init(frame: frame)
    autoresizingMask = [.width, .height]
    wantsLayer = true
    layer?.masksToBounds = true
    feedback.layer.frame = bounds
    layer?.addSublayer(feedback.layer)
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class CropTransitionOverlay: NSView {
  struct PlayerFrame {
    let selection: NSRect
    let videoRect: NSRect
    let viewport: NSRect

    var sourceFrame: NSRect {
      let width = videoRect.width / selection.width
      let height = videoRect.height / selection.height
      return NSRect(x: videoRect.minX - selection.minX * width,
                    y: videoRect.minY - selection.minY * height, width: width, height: height)
    }

    var contentsRect: NSRect {
      NSRect(x: (videoRect.minX - viewport.minX) / viewport.width,
             y: (videoRect.minY - viewport.minY) / viewport.height,
             width: videoRect.width / viewport.width, height: videoRect.height / viewport.height)
    }
  }

  private let preparationFeedback = DelayedPreparationFeedback(namePrefix: "cropPreparation")
  private var preparationToken: DelayedPreparationFeedback.Token?
  var isShowingPreparationFeedback: Bool { preparationFeedback.isShowing }
  static let preparationFeedbackDelay = DelayedPreparationFeedback.activationDelay
  static let preparationBreathingDuration = DelayedPreparationFeedback.breathingDuration
  private let controls = CALayer()
  private let canvas = CALayer()
  private let dimming = CAShapeLayer()
  private let cropMask = CAShapeLayer()
  private let borderCanvas = CALayer()
  private let borderMask = CAShapeLayer()
  private let outline = CAShapeLayer()
  private let corners = CAShapeLayer()
  private var timer: Timer?
  private var animationDisplayLink: AnyObject?
  private var animationGeneration = 0
  private(set) var sourceSize = NSSize.zero
  private(set) var selection = NSRect.zero
  private(set) var imageFrame = NSRect.zero
  private var initialImage = NSRect.zero
  private var initialAperture = NSRect.zero
  private var initialSelection = NSRect.zero
  private var initialControls = NSRect.zero
  private var initialPlayerFrame: PlayerFrame?
  private(set) var nativeVideo: NativeCropVideoPresentation?
  private var isEditorEntry = false
  private var playerVideoFrames: (from: PlayerFrame, to: PlayerFrame)?
  var targetSelection = NSRect.zero
  var targetDisplaySize = NSSize.zero
  var targetFilterRect = NSRect.zero
  var expectedSourceSize = NSSize.zero
  var isPreparingSource = false
  var isCommitting = false
  var isAwaitingNativeFrame = false
  var nativeFrameWasRendered = false
  var pendingNativeFrameCompletion: (() -> Void)?
  var applyCrop: (() -> Void)?
  var sourceVideoSize = NSSize.zero
  var entryImageFrame = NSRect.zero
  var entryClip = NSRect.zero
  var entryControlsFrame = NSRect.zero
  var isPreparing = true
  var isFinishing = false
  var isTransforming = false
  var isPlayerTransition = false
  var wasAnimatingWindowResize = false
  var hasRenderedVideo = false
  var targetWindowFrame: NSRect?
  var waitsForOutput = false
  var mediaGeneration = 0
  var playerVideoFrame = NSRect.zero

  override init(frame: NSRect) {
    super.init(frame: frame)
    autoresizingMask = [.width, .height]
    wantsLayer = true
    layer?.masksToBounds = true
    preparationFeedback.layer.frame = bounds
    layer?.addSublayer(preparationFeedback.layer)
    layer?.addSublayer(controls)
    layer?.addSublayer(canvas)
    canvas.addSublayer(dimming)
    dimming.fillColor = NSColor.black.cgColor
    dimming.fillRule = .evenOdd
    canvas.mask = cropMask
    layer?.addSublayer(borderCanvas)
    borderCanvas.mask = borderMask
    for shape in [outline, corners] {
      shape.fillColor = nil
      shape.strokeColor = NSColor.white.cgColor
      borderCanvas.addSublayer(shape)
    }
    outline.lineWidth = 1
    corners.lineWidth = 3
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  deinit { stopAnimation() }

  override func hitTest(_ point: NSPoint) -> NSView? {
    bounds.contains(convert(point, from: superview)) ? self : nil
  }

  // Keep the crop API and layer identities stable while sharing the owner.
  func beginPreparationFeedback(pulse: Bool) {
    guard !isShowingPreparationFeedback else { return }
    preparationToken = preparationFeedback.begin(pulse: pulse)
  }

  static func preparationCycleEnd(startedAt: CFTimeInterval, readyAt: CFTimeInterval) -> CFTimeInterval {
    DelayedPreparationFeedback.cycleEnd(startedAt: startedAt, readyAt: readyAt)
  }

  func finishPreparationFeedback(completion: @escaping () -> Void) {
    guard let token = preparationToken else { completion(); return }
    preparationFeedback.finish(token, policy: .afterCurrentBreath) { [weak self] in
      if self?.preparationToken == token { self?.preparationToken = nil }
      completion()
    }
  }

  func endPreparationFeedback(animated: Bool = true) {
    preparationFeedback.end(animated: animated)
    preparationToken = nil
  }

  func useNativeVideo(_ view: NSView, in container: NSView, pixelSize: NSSize,
                      beginLayout: @escaping () -> Void = {}, restoreLayout: @escaping () -> Void = {}) {
    if nativeVideo == nil {
      nativeVideo = NativeCropVideoPresentation(view: view, container: container, pixelSize: pixelSize,
                                                beginLayout: beginLayout, restoreLayout: restoreLayout)
    } else { nativeVideo?.updateSourcePixels(pixelSize) }
  }

  func show(selection: NSRect, sourceSize: NSSize, initialFrame: NSRect,
            initialClip: NSRect, initialSelection: NSRect, controlsImage: NSImage?, controlsFrame: NSRect,
            entering: Bool = false) {
    isPlayerTransition = false
    isEditorEntry = entering
    canvas.mask = cropMask
    dimming.isHidden = false
    borderCanvas.isHidden = false
    controls.isHidden = false
    self.selection = selection
    self.sourceSize = sourceSize
    self.initialImage = initialFrame
    self.initialSelection = initialSelection
    initialAperture = NSRect(x: (initialClip.minX - initialFrame.minX) * sourceSize.width / initialFrame.width,
                            y: (initialClip.minY - initialFrame.minY) * sourceSize.height / initialFrame.height,
                            width: initialClip.width * sourceSize.width / initialFrame.width,
                            height: initialClip.height * sourceSize.height / initialFrame.height)
      .intersection(NSRect(origin: .zero, size: sourceSize))
    initialControls = controlsFrame
    controls.contents = controlsImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    controls.frame = controlsFrame
    layer?.backgroundColor = nil
    present(image: initialFrame, clip: initialClip, outlineSelection: initialSelection,
            outlineOpacity: 1, dimOpacity: 0.52)
  }

  func showPlayerFrame(frame: PlayerFrame? = nil) {
    imageFrame = bounds
    isPlayerTransition = true
    initialPlayerFrame = frame
    layer?.backgroundColor = nil
    canvas.mask = nil
    dimming.isHidden = true
    borderCanvas.isHidden = true
    controls.isHidden = true
  }

  func setPlayerTargetFrame(_ frame: PlayerFrame?, present: Bool = true) {
    if let from = initialPlayerFrame, let to = frame {
      playerVideoFrames = (from, to)
      nativeVideo?.prepareRaster(for: [from.sourceFrame, to.sourceFrame])
    }
    if present { presentPlayerTransition(progress: 0) }
  }

  func presentPlayerTransition(progress: CGFloat) {
    guard let from = playerVideoFrames?.from ?? initialPlayerFrame else { return }
    let to = playerVideoFrames?.to ?? from
    nativeVideo?.present(frame: Self.interpolate(from.sourceFrame, to.sourceFrame, progress),
                         clip: Self.interpolate(from.videoRect, to.videoRect, progress))
  }

  static func interpolate(_ from: NSRect, _ to: NSRect, _ progress: CGFloat) -> NSRect {
    NSRect(x: from.minX + (to.minX - from.minX) * progress,
           y: from.minY + (to.minY - from.minY) * progress,
           width: from.width + (to.width - from.width) * progress,
           height: from.height + (to.height - from.height) * progress)
  }

  static func fit(_ size: NSSize, in bounds: NSRect) -> NSRect {
    let scale = min(bounds.width / size.width, bounds.height / size.height)
    return NSRect(x: bounds.midX - size.width * scale / 2,
                  y: bounds.midY - size.height * scale / 2,
                  width: size.width * scale, height: size.height * scale)
  }

  func selectionFrame(in image: NSRect) -> NSRect {
    sourceFrame(selection, in: image)
  }

  private func sourceFrame(_ rect: NSRect, in image: NSRect) -> NSRect {
    NSRect(x: image.minX + rect.minX * image.width / sourceSize.width,
           y: image.minY + rect.minY * image.height / sourceSize.height,
           width: rect.width * image.width / sourceSize.width,
           height: rect.height * image.height / sourceSize.height)
  }

  func transformedImage(fitting target: NSRect) -> NSRect {
    let width = target.width * sourceSize.width / selection.width
    let height = target.height * sourceSize.height / selection.height
    return NSRect(x: target.minX - selection.minX * width / sourceSize.width,
                  y: target.minY - selection.minY * height / sourceSize.height,
                  width: width, height: height)
  }

  func presentTransition(to target: NSRect, progress: CGFloat, letterboxed: Bool = false,
                         outlineOpacity: CGFloat? = nil) {
    let image = Self.interpolate(initialImage, transformedImage(fitting: target), progress)
    let aperture = Self.interpolate(initialAperture, selection, progress)
    let outlineSelection = Self.interpolate(initialSelection, selection, progress)
    let destination = NSRect(x: bounds.midX - initialControls.width / 2,
                             y: -initialControls.height - 8,
                             width: initialControls.width, height: initialControls.height)
    controls.frame = Self.interpolate(initialControls, destination, progress)
    present(image: image, clip: sourceFrame(aperture, in: image), outlineSelection: outlineSelection,
            outlineOpacity: outlineOpacity ?? min(1, (1 - progress) * 4), dimOpacity: 0.52 * (1 - progress))
    let clip = sourceFrame(aperture, in: image)
    nativeVideo?.present(frame: image, clip: clip)
  }

  private func present(image: NSRect, clip: NSRect, outlineSelection: NSRect,
                       outlineOpacity: CGFloat, dimOpacity: CGFloat) {
    imageFrame = image
    canvas.frame = bounds
    cropMask.frame = bounds
    cropMask.path = CGPath(rect: clip, transform: nil)
    borderCanvas.frame = bounds
    borderMask.frame = bounds
    borderMask.path = CGPath(rect: clip.insetBy(dx: -3, dy: -3), transform: nil)
    let rect = sourceFrame(outlineSelection, in: image)
    let outside = CGMutablePath()
    outside.addRect(clip)
    let visibleSelection = rect.intersection(clip)
    if !visibleSelection.isEmpty { outside.addRect(visibleSelection) }
    dimming.path = outside
    dimming.opacity = Float(dimOpacity)
    outline.path = CGPath(rect: rect, transform: nil)
    outline.opacity = outlineSelection.isEmpty ? 0 : Float(outlineOpacity * 0.85)
    let path = CGMutablePath()
    let length = min(14, min(rect.width, rect.height) / 3)
    for (x, dx) in [(rect.minX, CGFloat(1)), (rect.maxX, CGFloat(-1))] {
      for (y, dy) in [(rect.minY, CGFloat(1)), (rect.maxY, CGFloat(-1))] {
        path.move(to: NSPoint(x: x, y: y + dy * length))
        path.addLine(to: NSPoint(x: x, y: y))
        path.addLine(to: NSPoint(x: x + dx * length, y: y))
      }
    }
    corners.path = path
    corners.opacity = outlineSelection.isEmpty ? 0 : Float(outlineOpacity)
  }

  enum AnimationCurve {
    case easeOut
    case smoothstep

    func progress(at time: Double) -> CGFloat {
      switch self {
      case .easeOut:
        return CGFloat(1 - pow(1 - time, 3))
      case .smoothstep:
        return CGFloat(time * time * (3 - 2 * time))
      }
    }
  }

  func animate(duration: TimeInterval, curve: AnimationCurve = .easeOut, startOnFirstTick: Bool = false,
               update: @escaping (CGFloat) -> Void,
               completion: @escaping () -> Void) {
    stopAnimation()
    let generation = animationGeneration
    var start: CFTimeInterval? = startOnFirstTick ? nil : CACurrentMediaTime()
    let advance: (Double) -> Void = { [weak self] time in
      guard let self, self.animationGeneration == generation else { return }
      let progress = curve.progress(at: time)
      // Window, editor UI and native projection use the same refresh target.
      // Leave their publication in AppKit's normal main-loop transaction.
      let actionsWereDisabled = CATransaction.disableActions()
      CATransaction.setDisableActions(true)
      update(progress)
      CATransaction.setDisableActions(actionsWereDisabled)
      if time >= 1, self.animationGeneration == generation {
        self.stopAnimation()
        completion()
      }
    }
    let tick: (CFTimeInterval) -> Void = { timestamp in
      if start == nil { start = timestamp }
      advance(min(1, max(0, (timestamp - start!) / duration)))
    }
    guard duration > 0 else { advance(1); return }
    if #available(macOS 14.0, *), let window, window.isVisible,
       let screen = window.screen, screen.maximumFramesPerSecond > 0 {
      let target = AnimationDisplayLinkTarget(tick: tick)
      let link = window.displayLink(target: target, selector: #selector(AnimationDisplayLinkTarget.advance(_:)))
      let maximum = Float(screen.maximumFramesPerSecond)
      link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximum), maximum: maximum, preferred: maximum)
      animationDisplayLink = link
      link.add(to: .main, forMode: .common)
      // A display link stops calling back when its window leaves all displays.
      // Complete at the original deadline even if it becomes occluded/detached.
      let watchdog = Timer(timeInterval: duration, repeats: startOnFirstTick) { _ in
        if startOnFirstTick {
          if let start {
            if CACurrentMediaTime() - start < duration { return }
          } else if window.isVisible, window.occlusionState.contains(.visible) {
            // An occupied main loop can delay the first refresh callback. It
            // belongs to preparation; preserve the full requested movement.
            return
          }
        }
        advance(1)
      }
      timer = watchdog
      RunLoop.main.add(watchdog, forMode: .common)
      return
    }
    let timer = Timer(timeInterval: 1 / 120.0, repeats: true) { _ in tick(CACurrentMediaTime()) }
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  @available(macOS 14.0, *)
  private final class AnimationDisplayLinkTarget: NSObject {
    private let tick: (CFTimeInterval) -> Void

    init(tick: @escaping (CFTimeInterval) -> Void) { self.tick = tick }

    @objc func advance(_ link: CADisplayLink) { tick(link.targetTimestamp) }
  }

  func stopAnimation() {
    animationGeneration += 1
    timer?.invalidate()
    timer = nil
    if #available(macOS 14.0, *) { (animationDisplayLink as? CADisplayLink)?.invalidate() }
    animationDisplayLink = nil
  }

  func releaseNativeVideo() {
    nativeVideo?.restore()
    nativeVideo = nil
  }
}

class InteractiveModeController: NSObject, NSTextFieldDelegate, NSPopoverDelegate {
  enum Mode {
    case crop, delogo
  }

  weak var mainWindow: MainWindowController!

  private var cropx = 0
  private var cropy = 0
  private var cropw = 0
  private var croph = 0
  private var presetAspects: [CGFloat] = []
  private var selectedPreset: Int?
  private var videoGeometry = CropVideoGeometry(sourceSize: .zero, displaySize: .zero, rotation: 0)
  private var originalCropFilter: MPVFilter?
  private var originalCropDescription = ""
  private var dimensionEditCenter: NSPoint?
  private var isUpdatingDimension = false
  private var controlBarWidth: NSLayoutConstraint?
  private var controlBarBottom: NSLayoutConstraint?
  private var pinchStartZoom: CGFloat?
  private var pinchAnchor: NSPoint?
  private var originalVideoTransform = CATransform3DIdentity
  private var originalVideoMask: CALayer?
  private var exitPreviewTransform: CropPreviewTransform?
  private let previewMask = CALayer()
  private var editorEventMonitor: Any?
  private var nativeMenuObservers: [NSObjectProtocol] = []
  private var trackingNativeMenus = Set<ObjectIdentifier>()
  private var isTrackingEditorMenu = false
  private var aspectPopover: NSPopover?
  private var entryOverlay: CropTransitionOverlay?
  var isEntering: Bool { entryOverlay != nil }

  private var readableCropString: String {
    "(\(cropx), \(cropy)) (\(cropw)\u{d7}\(croph))"
  }

  private var isFullFrameSelected: Bool {
    cropBoxView.selectedRect == NSRect(origin: .zero, size: cropBoxView.videoSize)
  }

  private(set) var isActive = false
  private(set) var currentMode: Mode?
  private var isPausedPriorToInteractiveMode = false

  private lazy var cropTargetLabel: NSTextField = {
    let label = NSTextField(labelWithString: "")
    label.font = .systemFont(ofSize: 11)
    label.textColor = .secondaryLabelColor
    label.lineBreakMode = .byTruncatingMiddle
    label.translatesAutoresizingMaskIntoConstraints = false
    label.widthAnchor.constraint(lessThanOrEqualToConstant: 110).isActive = true
    label.isHidden = true
    return label
  }()
  private lazy var widthInput = dimensionInput(label: "crop.width")
  private lazy var heightInput = dimensionInput(label: "crop.height")

  private func dimensionInput(label: String) -> NSTextField {
    let input = NSTextField()
    input.translatesAutoresizingMaskIntoConstraints = false
    input.bezelStyle = .roundedBezel
    input.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    input.alignment = .right
    input.delegate = self
    input.target = self
    input.action = #selector(dimensionInputAction)
    input.setAccessibilityLabel(ui.localized(label))
    input.widthAnchor.constraint(equalToConstant: 58).isActive = true
    return input
  }

  private lazy var aspectSelector: ScrollSelectionControl = {
    let selector = ScrollSelectionControl()
    selector.translatesAutoresizingMaskIntoConstraints = false
    selector.segmentCount = 1
    selector.trackingMode = .momentary
    selector.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    selector.shrinkDelay = 0.25
    selector.animatesDigits = true
    selector.setImage(NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil), forSegment: 0)
    selector.setLabel("—", forSegment: 0)
    selector.maximumWidth = 140
    selector.target = self
    selector.action = #selector(showAspectMenu)
    selector.switchSelection = { [weak self] direction in
      self?.switchAspect(direction: direction)
    }
    return selector
  }()

  private lazy var saveButton: NSButton = {
    let button = ui.button("crop.save", target: self, action: #selector(doneAction))
    button.keyEquivalent = "\r"
    return button
  }()

  private lazy var zoomControl: NSPopUpButton = {
    let control = CropZoomPopUpButton(frame: .zero, pullsDown: true)
    control.menuTrackingChanged = { [weak self] in self?.isTrackingEditorMenu = $0 }
    control.translatesAutoresizingMaskIntoConstraints = false
    control.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    control.addItem(withTitle: "100%")
    for percent in [100, 125, 150, 200, 300, 400, 800] {
      let title = percent == 100 ? ui.localized("crop.zoom_fit") : "\(percent)%"
      let item = NSMenuItem(title: title, action: #selector(zoomMenuAction), keyEquivalent: "")
      item.target = self
      item.tag = percent
      control.menu?.addItem(item)
    }
    control.setAccessibilityLabel(ui.localized("crop.zoom"))
    control.toolTip = ui.localized("crop.zoom")
    return control
  }()

  private lazy var controlBar: CropControlBar = {
    let widthLabel = NSTextField(labelWithString: "W")
    let heightLabel = NSTextField(labelWithString: "H")
    [widthLabel, heightLabel].forEach { $0.textColor = .secondaryLabelColor }
    let dimensions = ui.hStack(spacing: 6, cropTargetLabel, widthLabel, widthInput, heightLabel, heightInput)
    let resetButton = ui.button("crop.reset", target: self, action: #selector(resetAction))
    let cancelButton = ui.button("general.cancel", target: self, action: #selector(cancelAction))
    cancelButton.keyEquivalent = "\u{1b}"
    let buttons = ui.hStack(spacing: 8, cancelButton, saveButton)
    let keyViews: [NSView] = [cropBoxView, widthInput, heightInput, aspectSelector, resetButton, zoomControl, cancelButton, saveButton]
    for (index, view) in keyViews.enumerated() { view.nextKeyView = keyViews[(index + 1) % keyViews.count] }
    return CropControlBar(dimensions: dimensions, selector: aspectSelector,
                          reset: resetButton, zoom: zoomControl, buttons: buttons)
  }()

  private lazy var cropBoxView: CropBoxView = {
    let view = CropBoxView { [weak self] in self?.selectedRectUpdated() }
    view.previewUpdatedCallback = { [weak self] in self?.updatePreviewTransform() }
    return view
  }()

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow
    super.init()
  }

  deinit {
    removeEditorEventMonitor()
  }

  var canEnter: Bool {
    guard let mainWindow, mainWindow.loaded, let window = mainWindow.window else { return false }
    return !isActive && !mainWindow.isCropTransitionInProgress &&
      mainWindow.player.info.state.loaded && !mainWindow.player.isInMiniPlayer &&
      mainWindow.pipStatus == .notInPIP && !mainWindow.isFullscreenTransitionInProgress &&
      mainWindow.videoView.window === window && mainWindow.videoView.superview === mainWindow.videoViewContainer
  }

  func enter(mode: Mode, selectWholeVideoByDefault: Bool = false) {
    guard canEnter else { return }
    mainWindow.prepareVideoTransformWindowReference()
    reloadAspectPresets()
    let player = mainWindow.player
    videoGeometry = (mode == .crop ? player.scopedCropPreview?.geometry : nil) ?? player.interactiveVideoGeometry(uncropped: mode == .crop)
    guard videoGeometry.sourceSize.width > 0 && videoGeometry.sourceSize.height > 0 else {
      Utility.showAlert("no_video_track")
      return
    }
    let cropFilter = mode == .crop ? (player.scopedCropPreview?.filter ?? player.info.cropFilter) : nil
    let cropDescription = player.scopedCropPreview?.originalTrack.cropDescription ?? player.info.unsureCrop
    if mode == .crop, player.scopedCropPreview == nil, player.canAnimateCropSource, mainWindow.cropTransitionDuration(0.35) > 0 {
      prepareEntry(cropFilter: cropFilter, cropDescription: cropDescription,
                   selectWholeVideoByDefault: selectWholeVideoByDefault)
    } else {
      _ = beginEditing(mode: mode, cropFilter: cropFilter, cropDescription: cropDescription,
                       selectWholeVideoByDefault: selectWholeVideoByDefault)
    }
  }

  private func prepareEntry(cropFilter: MPVFilter?, cropDescription: String,
                            selectWholeVideoByDefault: Bool) {
    let main = mainWindow!
    main.window?.contentView?.layoutSubtreeIfNeeded()
    let overlay = CropTransitionOverlay(frame: main.videoViewContainer.bounds)
    overlay.wasAnimatingWindowResize = main.videoView.videoLayer.isAnimatingWindowResize
    main.videoView.videoLayer.isInCropTransition = true
    main.videoView.videoLayer.isAnimatingWindowResize = true
    let (width, height) = main.player.videoSizeForDisplay
    let frame = main.player.cropTransitionFrame(in: main.videoViewContainer.bounds)
    overlay.playerVideoFrame = CropTransitionOverlay.fit(NSSize(width: width, height: height), in: main.videoView.frame)
    overlay.mediaGeneration = main.player.info.trackSelectionGeneration
    overlay.waitsForOutput = cropFilter != nil
    let geometry = main.player.interactiveVideoGeometry(uncropped: true)
    overlay.expectedSourceSize = geometry.sourceSize
    overlay.showPlayerFrame(frame: frame)
    entryOverlay = overlay
    main.videoViewContainer.addSubview(overlay, positioned: .above, relativeTo: nil)
    overlay.beginPreparationFeedback(pulse: !AccessibilityPreferences.motionReductionEnabled)
    main.bindCropVideo(overlay, pixelSize: geometry.selectionSize)
    main.videoView.videoLayer.setCropFramePreparation(true)
    if cropFilter != nil {
      main.player.removeCropFilter()
      guard main.player.info.cropFilter == nil else { cancelEntryTransition(); return }
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    main.videoViewContainer.addSubview(overlay, positioned: .above, relativeTo: nil)
    let entered = beginEditing(mode: .crop, cropFilter: cropFilter, cropDescription: cropDescription,
                               selectWholeVideoByDefault: selectWholeVideoByDefault)
    main.videoViewContainer.addSubview(overlay, positioned: .above, relativeTo: nil)
    // The crop box is a sibling of VideoView. Resolve their parent constraints
    // before recording the editor viewport, including a reused crop box.
    main.videoViewContainer.layoutSubtreeIfNeeded()
    overlay.entryImageFrame = main.videoViewContainer.convert(cropBoxView.imageRect, from: cropBoxView)
    overlay.entryClip = main.videoViewContainer.convert(cropBoxView.previewRect, from: cropBoxView)
    overlay.entryControlsFrame = main.videoViewContainer.convert(controlBar.bounds, from: controlBar)
    beginNativeExitPresentation()
    CATransaction.commit()
    guard entered else { cancelEntryTransition(); return }
    overlay.isPreparing = false
    finishEntryTransition()
  }

  func finishEntryTransition(outputIsReady: Bool = false) {
    if let overlay = entryOverlay {
      if outputIsReady { overlay.nativeFrameWasRendered = true }
      mainWindow.finishPendingNativeCropFrame(overlay)
    }
    guard let overlay = entryOverlay, isActive, !overlay.isPreparing, !overlay.isFinishing else { return }
    let main = mainWindow!
    guard main.player.info.state.active,
          main.player.info.trackSelectionGeneration == overlay.mediaGeneration else { cancelEntryTransition(); return }
    let actual = NSSize(width: main.player.mpv.getInt(MPVProperty.videoOutParams + "/w"),
                        height: main.player.mpv.getInt(MPVProperty.videoOutParams + "/h"))
    guard !main.player.isRefreshingPausedCrop, actual == overlay.expectedSourceSize else { return }
    overlay.isFinishing = true
    let selection = cropBoxView.selectedRect
    let anchor = selection.isEmpty ? NSRect(origin: .zero, size: cropBoxView.videoSize) : selection
    controlBar.isHidden = false
    let controlsImage = controlBar.bitmapImageRepForCachingDisplay(in: controlBar.bounds).map { bitmap in
      controlBar.cacheDisplay(in: controlBar.bounds, to: bitmap)
      let image = NSImage(size: controlBar.bounds.size)
      image.addRepresentation(bitmap)
      return image
    }
    controlBar.isHidden = true
    main.afterNativeCropFrame(overlay, preparing: true,
                             outputIsReady: outputIsReady || !overlay.waitsForOutput) { [weak self, weak overlay] in
      guard let self, let overlay, entryOverlay === overlay else { return }
      main.videoView.videoLayer.withCropFrameHandoff {
        overlay.show(selection: anchor, sourceSize: self.cropBoxView.videoSize,
                     initialFrame: overlay.entryImageFrame,
                     initialClip: overlay.entryClip,
                     initialSelection: selection, controlsImage: controlsImage,
                     controlsFrame: overlay.entryControlsFrame, entering: true)
        overlay.nativeVideo?.prepareRaster(for: [overlay.entryImageFrame,
          overlay.transformedImage(fitting: overlay.playerVideoFrame)])
        overlay.presentTransition(to: overlay.playerVideoFrame, progress: 1, outlineOpacity: 0)
      }
      overlay.finishPreparationFeedback { [weak self, weak overlay] in
        guard let self, let overlay, entryOverlay === overlay else { return }
        overlay.animate(duration: main.cropTransitionDuration(0.35), update: { [weak self, weak overlay] progress in
          guard let self, let overlay, entryOverlay === overlay else { return }
          overlay.presentTransition(to: overlay.playerVideoFrame, progress: 1 - progress,
                                    outlineOpacity: max(0, (progress - 0.6) / 0.4))
        }) { [weak self, weak overlay] in
          guard let self, let overlay, entryOverlay === overlay else { return }
          cancelEntryTransition()
        }
      }
    }
  }

  func cancelEntryTransition() {
    let overlay = entryOverlay
    overlay?.stopAnimation()
    overlay?.endPreparationFeedback(animated: false)
    overlay?.pendingNativeFrameCompletion = nil
    if overlay != nil { mainWindow?.videoView.videoLayer.cancelCropFrameRequests() }
    if let overlay {
      let restoreLayout = {
        overlay.releaseNativeVideo()
        self.entryOverlay = nil
        // Publish the actual editor UI before retiring its animated counterpart.
        // withCropFrameHandoff flushes this boundary: revealing these siblings
        // afterwards would expose one frame with neither controls nor outline.
        self.controlBar.isHidden = false
        self.cropBoxView.isHidden = false
        if self.isActive { self.layoutEditor() }
        overlay.removeFromSuperview()
      }
      if isActive, mainWindow.player.info.state.active {
        mainWindow.videoView.videoLayer.withCropFrameHandoff(restoreLayout)
      } else {
        mainWindow.videoView.videoLayer.withCropFrameUpdate(restoreLayout)
        mainWindow.videoView.videoLayer.setCropFramePreparation(false)
      }
    }
    controlBar.isHidden = false
    cropBoxView.isHidden = false
    if let overlay {
      mainWindow?.videoView.videoLayer.isAnimatingWindowResize = overlay.wasAnimatingWindowResize
      mainWindow?.videoView.videoLayer.isInCropTransition = false
    }
    if !isActive { removeEditorEventMonitor() }
  }

  private func beginEditing(mode: Mode, cropFilter: MPVFilter?, cropDescription: String,
                            selectWholeVideoByDefault: Bool) -> Bool {
    guard let window = mainWindow.window else { return false }
    let player = mainWindow.player
    if cropFilter != nil && player.scopedCropPreview == nil {
      player.removeCropFilter()
      guard player.info.cropFilter == nil else { return false }
    }

    window.backgroundColor = .windowBackgroundColor
    mainWindow.standardWindowButtons.forEach { $0.isEnabled = false }
    isPausedPriorToInteractiveMode = player.info.state == .paused
    if mode == .delogo { player.pause() }
    isActive = true
    currentMode = mode
    originalVideoTransform = mainWindow.videoView.layer?.transform ?? CATransform3DIdentity
    originalVideoMask = mainWindow.videoView.layer?.mask
    cropBoxView.allowsZoom = mode == .crop
    zoomControl.isHidden = mode != .crop
    cropBoxView.resetPreview()
    mainWindow.oscFloatingView.cancelPositionAnimation()
    mainWindow.hideUI(force: true)
    mainWindow.hideOSD()
    mainWindow.liveText.clearAnalysis()
    originalCropFilter = cropFilter
    originalCropDescription = cropDescription

    cropTargetLabel.isHidden = player.scopedCropPreview == nil
    if let preview = player.scopedCropPreview {
      let track = player.info.videoTracks.first(where: { $0.id == preview.id })
      let position = player.info.orderedTrackList(.video).firstIndex { $0.id == preview.id }.map { $0 + 1 } ?? preview.id
      cropTargetLabel.stringValue = "#\(position) \(track?.title ?? "")"
      cropTargetLabel.toolTip = "#\(position) \(track?.readableString() ?? "")"
    }
    saveButton.title = ui.localized(mode == .crop ? "crop.save" : "general.done")
    mainWindow.videoViewContainer.addSubview(controlBar)
    let barWidth = controlBar.widthAnchor.constraint(equalToConstant: 1)
    barWidth.priority = .defaultLow
    controlBarWidth = barWidth
    let barBottom = controlBar.bottomAnchor.constraint(equalTo: mainWindow.videoViewContainer.bottomAnchor)
    controlBarBottom = barBottom
    NSLayoutConstraint.activate([
      controlBar.centerXAnchor.constraint(equalTo: mainWindow.videoViewContainer.centerXAnchor),
      barBottom,
      barWidth
    ])

    let shadow = NSShadow()
    shadow.shadowBlurRadius = 10
    shadow.shadowColor = .black.withAlphaComponent(0.5)
    mainWindow.videoView.shadow = shadow
    layoutEditor()

    mainWindow.videoViewContainer.addSubview(cropBoxView)
    cropBoxView.previewInset = 10
    NSLayoutConstraint.activate([
      cropBoxView.leadingAnchor.constraint(equalTo: mainWindow.videoView.leadingAnchor, constant: -10),
      cropBoxView.trailingAnchor.constraint(equalTo: mainWindow.videoView.trailingAnchor, constant: 10),
      cropBoxView.topAnchor.constraint(equalTo: mainWindow.videoView.topAnchor, constant: -10),
      cropBoxView.bottomAnchor.constraint(equalTo: mainWindow.videoView.bottomAnchor, constant: 10)
    ])
    cropBoxView.videoSize = videoGeometry.selectionSize
    let fullFrame = NSRect(origin: .zero, size: cropBoxView.videoSize)
    let selected = originalCropFilter.flatMap { selectionRect(for: $0) } ??
      (selectWholeVideoByDefault ? fullFrame : .zero)
    cropBoxView.setSelectedRect(to: selected)
    mainWindow.videoView.layoutSubtreeIfNeeded()
    updatePreviewTransform()
    window.makeFirstResponder(cropBoxView)
    player.postNotification(.iinaTrackSettingsChanged)
    if mode == .crop { installEditorEventMonitor() }
    return true
  }

  private func installEditorEventMonitor() {
    guard editorEventMonitor == nil else { return }
    for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
      nativeMenuObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
        guard let self, let menu = notification.object as? NSMenu else { return }
        let identity = ObjectIdentifier(menu)
        if notification.name == NSMenu.didBeginTrackingNotification {
          trackingNativeMenus.insert(identity)
        } else {
          trackingNativeMenus.remove(identity)
        }
      })
    }
    editorEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
      guard let self else { return event }
      return handleEditorEvent(event)
    }
  }

  private func removeEditorEventMonitor() {
    if let editorEventMonitor { NSEvent.removeMonitor(editorEventMonitor) }
    editorEventMonitor = nil
    nativeMenuObservers.forEach { NotificationCenter.default.removeObserver($0) }
    nativeMenuObservers.removeAll()
    trackingNativeMenus.removeAll()
  }

  func handleEditorEvent(_ event: NSEvent) -> NSEvent? {
    let parentModifierEvent = event.type == .flagsChanged && event.window == nil && mainWindow.window?.isKeyWindow == true
    guard event.window === mainWindow.window || parentModifierEvent else { return event }
    guard trackingNativeMenus.isEmpty else { return event }
    let cancelsTransition = event.type == .keyDown && event.keyCode == 53 && !event.isARepeat &&
      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
    if mainWindow.isCropTransitionInProgress, cancelsTransition {
      mainWindow.cancelCropExitTransition()
      if !isActive { return nil }
    }
    if isEntering { return event.modifierFlags.contains(.command) ? event : nil }
    guard isActive, currentMode == .crop else { return event }
    if mainWindow.isCropTransitionInProgress { return nil }
    guard !isTrackingEditorMenu else {
      // A transient popover can leave keyboard focus on its parent window.
      (aspectPopover?.contentViewController as? CropAspectPresetListController)?
        .setOptionHeld(event.modifierFlags.contains(.option))
      return event
    }
    guard event.type == .keyDown else { return event }
    guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
          [UInt16(53), 36, 76].contains(event.keyCode) else { return event }
    guard !event.isARepeat else { return nil }
    if event.keyCode == 53 {
      mainWindow.window?.makeFirstResponder(cropBoxView)
      if isFullFrameSelected {
        cancelAction(self)
      } else {
        resetAction(self)
      }
    } else if let input = [widthInput, heightInput].first(where: { $0.currentEditor() != nil }) {
      input.validateEditing()
      commitDimension(input)
      mainWindow.window?.makeFirstResponder(cropBoxView)
    } else {
      doneAction(self)
    }
    return nil
  }

  func resize() {
    guard isActive, !mainWindow.isCropTransitionInProgress else { return }
    layoutEditor()
  }

  private func layoutEditor() {
    mainWindow.window?.contentView?.layoutSubtreeIfNeeded()
    let containerSize = mainWindow.videoViewContainer.bounds.size
    let insets = CropEditorInsets(size: containerSize)
    controlBarBottom?.constant = -insets.bottom
    let maxSize = NSSize(width: max(1, containerSize.width - 2 * insets.side),
                        height: max(1, containerSize.height - insets.top - insets.gap - insets.bottom))
    let newSize = controlBar.arrange(availableSize: maxSize,
                                   previewAspect: videoGeometry.displaySize.width / videoGeometry.displaySize.height)
    controlBarWidth?.constant = controlBar.layoutWidth
    let horizontalPadding = (containerSize.width - newSize.width) / 2
    // Insets from the previous size must not constrain AppKit's next resize proposal.
    mainWindow.updateVideoViewConstraints([
      .top: insets.top, .bottom: containerSize.height - insets.top - newSize.height,
      .leading: horizontalPadding, .trailing: horizontalPadding
    ], priority: .defaultLow)
    mainWindow.videoViewContainer.layoutSubtreeIfNeeded()
    updatePreviewTransform()
    mainWindow.forceDraw("interactive cropping")
  }

  func handleMagnifyGesture(_ recognizer: NSMagnificationGestureRecognizer) {
    guard isActive, currentMode == .crop else { return }
    switch recognizer.state {
    case .began:
      pinchStartZoom = nil
      pinchAnchor = nil
      let point = recognizer.location(in: cropBoxView)
      guard cropBoxView.previewRect.contains(point), !cropBoxView.isDragging else { return }
      pinchStartZoom = cropBoxView.previewTransform.zoom
      pinchAnchor = point
    case .changed, .ended:
      break
    default:
      pinchStartZoom = nil
      pinchAnchor = nil
      return
    }
    if let pinchStartZoom, let pinchAnchor {
      cropBoxView.setZoom(pinchStartZoom * max(0, 1 + recognizer.magnification), at: pinchAnchor)
    }
    if recognizer.state == .ended {
      pinchStartZoom = nil
      pinchAnchor = nil
    }
  }

  @objc private func zoomMenuAction(_ sender: NSMenuItem) {
    mainWindow.window?.makeFirstResponder(cropBoxView)
    cropBoxView.setZoom(CGFloat(sender.tag) / 100)
  }

  private func updatePreviewTransform() {
    guard isActive, let layer = mainWindow.videoView.layer else { return }
    let zoom = cropBoxView.previewTransform.zoom
    let viewport = cropBoxView.previewRect
    let image = cropBoxView.imageRect
    guard viewport.width > 0, viewport.height > 0 else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    var transform = CATransform3DMakeScale(zoom, zoom, 1)
    // AppKit-backed video layers can use a bottom-left anchor instead of the center.
    transform.m41 = image.minX - viewport.minX - (1 - zoom) * layer.bounds.width * layer.anchorPoint.x
    transform.m42 = image.minY - viewport.minY - (1 - zoom) * layer.bounds.height * layer.anchorPoint.y
    layer.transform = CATransform3DConcat(originalVideoTransform, transform)
    if zoom > 1 {
      previewMask.backgroundColor = NSColor.white.cgColor
      previewMask.frame = NSRect(x: layer.bounds.minX + (viewport.minX - image.minX) / zoom,
                                 y: layer.bounds.minY + (viewport.minY - image.minY) / zoom,
                                 width: viewport.width / zoom, height: viewport.height / zoom)
      layer.mask = previewMask
    } else {
      layer.mask = originalVideoMask
    }
    CATransaction.commit()
    let percent = Int((zoom * 100).rounded())
    zoomControl.item(at: 0)?.title = "\(percent)%"
    zoomControl.setAccessibilityValue("\(percent)%")
    for item in zoomControl.itemArray.dropFirst() {
      item.state = abs(zoom * 100 - CGFloat(item.tag)) < 0.5 ? .on : .off
    }
  }

  func canDragWindow(at point: NSPoint) -> Bool {
    let containerPoint = mainWindow.videoViewContainer.convert(point, from: nil)
    guard cropBoxView.hitTest(containerPoint) == nil else { return false }
    let controlHit = controlBar.hitTest(containerPoint)
    return controlHit == nil || controlHit === controlBar
  }

  private func selectionRect(for filter: MPVFilter) -> NSRect? {
    guard let params = filter.params,
          let width = params["w"].flatMap(Int.init), let height = params["h"].flatMap(Int.init),
          width > 0, height > 0 else { return nil }
    let x = params["x"].flatMap(Int.init) ?? Int((videoGeometry.sourceSize.width - CGFloat(width)) / 2)
    let y = params["y"].flatMap(Int.init) ?? Int((videoGeometry.sourceSize.height - CGFloat(height)) / 2)
    return videoGeometry.selectionRect(forFilterRect: NSRect(x: x, y: y, width: width, height: height))
  }

  func exit(applyingCrop: Bool = false, discardingCrop: Bool = false, then: @escaping () -> Void = {}) {
    cancelEntryTransition()
    guard isActive, let window = mainWindow.window else { return }
    let popover = aspectPopover
    aspectPopover = nil
    isTrackingEditorMenu = false
    popover?.delegate = nil
    popover?.performClose(nil)
    let player = mainWindow.player
    let wasCropping = currentMode == .crop
    let shouldResume = currentMode == .delogo && !isPausedPriorToInteractiveMode
    removeEditorEventMonitor()
    window.makeFirstResponder(nil)
    isActive = false
    currentMode = nil
    pinchStartZoom = nil
    pinchAnchor = nil
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if !mainWindow.deferCropVideoRestoration(transform: originalVideoTransform, mask: originalVideoMask) {
      mainWindow.videoView.layer?.transform = originalVideoTransform
      mainWindow.videoView.layer?.mask = originalVideoMask
    }
    CATransaction.commit()
    originalVideoMask = nil
    exitPreviewTransform = nil
    cropBoxView.removeFromSuperview()
    controlBar.removeFromSuperview()
    controlBarWidth?.isActive = false
    controlBarWidth = nil
    controlBarBottom?.isActive = false
    controlBarBottom = nil
    window.backgroundColor = .black
    mainWindow.standardWindowButtons.forEach { $0.isEnabled = true }
    mainWindow.videoView.shadow = nil
    mainWindow.updateVideoViewConstraints([.top: 0, .bottom: 0, .leading: 0, .trailing: 0])
    if !discardingCrop, player.scopedCropPreview == nil, !applyingCrop, let originalCropFilter, player.setCrop(fromFilter: originalCropFilter) {
      player.info.unsureCrop = originalCropDescription
    }
    originalCropFilter = nil
    then()
    if !discardingCrop, player.scopedCropPreview != nil { player.finishScopedCustomCrop() }
    player.postNotification(.iinaTrackSettingsChanged)
    // A restored/applied filter will refresh geometry once mpv reports its output.
    if wasCropping, player.info.cropFilter == nil {
      mainWindow.handleVideoSizeChange(keepWindowSize: true)
    }
    if shouldResume {
      player.resume()
    } else if player.info.state == .paused {
      mainWindow.liveText.requestAnalysis()
    }
  }

  private func selectedRectUpdated() {
    guard isActive else { return }
    let rect = cropBoxView.selectedRect
    let filterRect = videoGeometry.filterRect(for: rect)
    cropx = Int(filterRect.minX)
    cropy = Int(filterRect.minY)
    cropw = Int(filterRect.width)
    croph = Int(filterRect.height)
    if widthInput.currentEditor() == nil { widthInput.integerValue = Int(rect.width) }
    if heightInput.currentEditor() == nil { heightInput.integerValue = Int(rect.height) }
    saveButton.isEnabled = cropw > 0 && croph > 0
    selectedPreset = matchingPreset(for: rect)
    if !cropBoxView.isDragging && !isUpdatingDimension { updateAspectLabel() }
    aspectSelector.setToolTip(ui.localized("crop.aspect"), forSegment: 0)
  }

  private func updateAspectLabel() {
    aspectSelector.setLabel(aspectTitle, forSegment: 0)
  }

  private var aspectTitle: String {
    if let selectedPreset, presetAspects.indices.contains(selectedPreset) {
      return CropVideoGeometry.aspectTitle(forRatio: presetAspects[selectedPreset])
    }
    return videoGeometry.aspectTitle(for: cropBoxView.selectedRect)
  }

  private func matchingPreset(for rect: NSRect) -> Int? {
    guard !rect.isEmpty else { return nil }
    return presetAspects.firstIndex { aspect in
      let pixelAspect = aspect / videoGeometry.pixelAspectRatio
      return abs(rect.width - rect.height * pixelAspect) <= min(max(1, pixelAspect) / 2, rect.width * 0.001)
    }
  }

  private func switchAspect(direction: Int) {
    guard isActive, direction != 0 else { return }
    reloadAspectPresets()
    let count = presetAspects.count
    guard count > 0 else { return }
    let index = selectedPreset.map { ($0 + (direction > 0 ? 1 : -1) + count) % count } ?? (direction > 0 ? 0 : count - 1)
    applyPreset(index, direction: direction)
  }

  private func applyPreset(_ index: Int, direction: Int = 0) {
    guard !cropBoxView.isAnimatingSelection else { return }
    let previousTitle = aspectSelector.label(forSegment: 0) ?? ""
    aspectSelector.animatesDigits = false
    defer { aspectSelector.animatesDigits = true }
    mainWindow.window?.makeFirstResponder(cropBoxView)
    let videoSize = cropBoxView.videoSize
    guard presetAspects.indices.contains(index) else { return }
    let size = videoSize.crop(withAspect: Aspect(size: NSSize(width: presetAspects[index] / videoGeometry.pixelAspectRatio, height: 1)))
    cropBoxView.setSelectedRect(to: CropSelectionGeometry.resized(
      NSRect(origin: .zero, size: videoSize), to: size, in: videoSize))
    // Pixel rounding can make a small source match several ratios; retain the chosen preset.
    selectedPreset = index
    aspectSelector.setLabel(aspectTitle, forSegment: 0)
    if direction != 0 {
      aspectSelector.roll(through: [previousTitle, aspectTitle], direction: direction)
    }
  }

  private func reloadAspectPresets() {
    let stored = Preference.array(for: .customCropAspectPresets) ?? []
    var aspects: [CGFloat] = []
    for value in stored {
      guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue.isFinite, number.doubleValue > 0 else { continue }
      let aspect = CGFloat(number.doubleValue)
      if !aspects.contains(where: { abs($0 / aspect - 1) < 1e-10 }) { aspects.append(aspect) }
    }
    guard aspects != presetAspects else { return }
    presetAspects = aspects
    selectedPreset = matchingPreset(for: cropBoxView.selectedRect)
  }

  func makeAspectMenu() -> NSMenu {
    reloadAspectPresets()
    let menu = NSMenu()
    menu.autoenablesItems = false
    let font = menu.font ?? NSFont.menuFont(ofSize: 0)
    menu.minimumWidth = ["crop.add_preset", "crop.delete_selected_preset"].map {
      (ui.localized($0) as NSString).size(withAttributes: [.font: font]).width + 56
    }.max() ?? 100
    for (index, aspect) in presetAspects.enumerated() {
      let item = NSMenuItem(title: CropVideoGeometry.aspectTitle(forRatio: aspect),
                            action: #selector(aspectMenuAction), keyEquivalent: "")
      item.target = self
      // Keep the value on the item so another player cannot invalidate its index.
      item.representedObject = Double(aspect)
      item.state = selectedPreset == index ? .on : .off
      menu.addItem(item)
    }
    if !presetAspects.isEmpty { menu.addItem(.separator()) }
    let add = NSMenuItem(title: ui.localized("crop.add_preset"), action: #selector(addAspectPreset), keyEquivalent: "")
    add.target = self
    add.isEnabled = !cropBoxView.selectedRect.isEmpty && matchingPreset(for: cropBoxView.selectedRect) == nil
    menu.addItem(add)
    return menu
  }

  func deleteAspectPreset(_ sender: NSMenuItem) {
    guard isActive, currentMode == .crop, let aspect = sender.representedObject as? Double else { return }
    reloadAspectPresets()
    guard let index = presetAspects.firstIndex(of: CGFloat(aspect)) else { return }
    aspectPopover?.performClose(nil)
    presetAspects.remove(at: index)
    Preference.set(presetAspects.map { Double($0) }, for: .customCropAspectPresets)
    selectedPreset = matchingPreset(for: cropBoxView.selectedRect)
    aspectSelector.animatesDigits = false
    updateAspectLabel()
    aspectSelector.animatesDigits = true
  }

  @objc private func showAspectMenu(_ sender: NSSegmentedControl) {
    // Publish pending W/H edits before taking the menu's selection snapshot.
    mainWindow.window?.makeFirstResponder(cropBoxView)
    let menu = makeAspectMenu()
    let popover = NSPopover()
    popover.behavior = .transient
    popover.animates = false
    popover.delegate = self
    let content = CropAspectPresetListController(menu: menu)
    content.cancel = { [weak self] in self?.aspectPopover?.performClose(nil) }
    content.select = { [weak self] item in
      self?.aspectPopover?.performClose(nil)
      guard let action = item.action else { return }
      NSApp.sendAction(action, to: item.target, from: item)
    }
    content.deletePreset = { [weak self] item in self?.deleteAspectPreset(item) }
    content.setOptionHeld(NSEvent.modifierFlags.contains(.option))
    let buttonFrame = sender.convert(sender.bounds, to: mainWindow.videoViewContainer)
    content.maximumHeight = max(44, mainWindow.videoViewContainer.bounds.maxY - buttonFrame.maxY - 28)
    popover.contentViewController = content
    aspectPopover = popover
    isTrackingEditorMenu = true
    popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: sender.isFlipped ? .minY : .maxY)
    content.focusList()
  }

  func popoverDidClose(_ notification: Notification) {
    guard let popover = notification.object as? NSPopover, popover === aspectPopover else { return }
    aspectPopover = nil
    isTrackingEditorMenu = false
    if isActive { mainWindow.window?.makeFirstResponder(cropBoxView) }
  }

  @objc private func aspectMenuAction(_ sender: NSMenuItem) {
    guard isActive, currentMode == .crop, let aspect = sender.representedObject as? Double else { return }
    reloadAspectPresets()
    guard let index = presetAspects.firstIndex(of: CGFloat(aspect)) else { return }
    applyPreset(index)
  }

  @objc private func addAspectPreset(_ sender: NSMenuItem) {
    guard isActive, currentMode == .crop else { return }
    mainWindow.window?.makeFirstResponder(cropBoxView)
    reloadAspectPresets()
    let rect = cropBoxView.selectedRect
    guard !rect.isEmpty, matchingPreset(for: rect) == nil else { return }
    // Preserve the display ratio across videos with different pixel aspects and rotations.
    let aspect = rect.width / rect.height * videoGeometry.pixelAspectRatio
    guard aspect.isFinite, aspect > 0 else { return }
    presetAspects.append(aspect)
    Preference.set(presetAspects.map { Double($0) }, for: .customCropAspectPresets)
    selectedPreset = presetAspects.count - 1
    updateAspectLabel()
  }

  @objc private func resetAction(_ sender: AnyObject) {
    let animatesDigits = aspectSelector.animatesDigits
    aspectSelector.animatesDigits = currentMode == .crop
    defer { aspectSelector.animatesDigits = animatesDigits }
    mainWindow.window?.makeFirstResponder(cropBoxView)
    cropBoxView.setSelectedRect(to: NSRect(origin: .zero, size: cropBoxView.videoSize), animated: currentMode == .crop)
  }

  func controlTextDidChange(_ notification: Notification) {
    guard let input = notification.object as? NSTextField,
          let value = Int(input.stringValue), value > 0 else { return }
    updateDimension(input, value: value)
  }

  func controlTextDidBeginEditing(_ notification: Notification) {
    guard let input = notification.object as? NSTextField, input === widthInput || input === heightInput else { return }
    let rect = cropBoxView.selectedRect
    dimensionEditCenter = rect.isEmpty ? nil : NSPoint(x: rect.midX, y: rect.midY)
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    guard let input = notification.object as? NSTextField else { return }
    commitDimension(input)
    dimensionEditCenter = nil
  }

  @objc private func dimensionInputAction(_ sender: NSTextField) {
    commitDimension(sender)
  }

  private func commitDimension(_ input: NSTextField) {
    guard isActive, input === widthInput || input === heightInput else { return }
    if let value = Int(input.stringValue) { updateDimension(input, value: max(1, value)) }
    input.integerValue = Int(input === widthInput ? cropBoxView.selectedRect.width : cropBoxView.selectedRect.height)
    updateAspectLabel()
  }

  private func updateDimension(_ input: NSTextField, value: Int) {
    guard isActive, input === widthInput || input === heightInput else { return }
    let current = cropBoxView.selectedRect
    guard !cropBoxView.isAnimatingSelection else {
      input.integerValue = Int(input === widthInput ? current.width : current.height)
      return
    }
    let size = NSSize(width: input === widthInput ? CGFloat(value) : max(1, current.width),
                       height: input === heightInput ? CGFloat(value) : max(1, current.height))
    isUpdatingDimension = true
    defer { isUpdatingDimension = false }
    cropBoxView.setSelectedRect(to: CropSelectionGeometry.resized(
      current, to: size, in: cropBoxView.videoSize, center: dimensionEditCenter))
  }

  @objc private func doneAction(_ sender: AnyObject) {
    mainWindow.window?.makeFirstResponder(nil)
    guard cropw > 0 && croph > 0 else { return }
    switch currentMode {
    case .crop: cropAction()
    case .delogo: delogoAction()
    case nil: break
    }
  }

  private func cropAction() {
    let player = mainWindow.player
    let isFullFrame = isFullFrameSelected
    let crop = isFullFrame ? nil : TrackVideoCrop(x: cropx, y: cropy, width: cropw, height: croph)
    prepareExit(selection: cropBoxView.selectedRect) { [self] in
      if player.scopedCropPreview != nil {
        guard player.finishScopedCustomCrop(crop: crop, applying: true) else { return false }
        exit(applyingCrop: true)
        return true
      }
      if let crop {
        let filter = MPVFilter.crop(w: crop.width, h: crop.height, x: crop.x, y: crop.y, exact: true)
        guard player.setCrop(fromFilter: filter) else { return false }
      }
      exit(applyingCrop: true) {
        if isFullFrame {
          player.removeCropFilter()
          return
        }
        player.sendOSD(.crop(self.readableCropString))
      }
      return true
    }
  }

  private func prepareExit(selection: NSRect, completion: @escaping () -> Bool) {
    guard !mainWindow.isCropTransitionInProgress else { return }
    if mainWindow.player.scopedCropPreview != nil { _ = completion(); return }
    let container: NSView = mainWindow.videoViewContainer
    container.layoutSubtreeIfNeeded()
    let imageFrame = container.convert(cropBoxView.imageRect, from: cropBoxView)
    let clip = container.convert(cropBoxView.previewRect, from: cropBoxView)
    let controlsFrame = container.convert(controlBar.bounds, from: controlBar)
    let controlsImage = controlBar.bitmapImageRepForCachingDisplay(in: controlBar.bounds).map { bitmap in
      controlBar.cacheDisplay(in: controlBar.bounds, to: bitmap)
      let image = NSImage(size: controlBar.bounds.size)
      image.addRepresentation(bitmap)
      return image
    }
    exitPreviewTransform = cropBoxView.previewTransform
    let fromSelection = cropBoxView.beginExitPresentation()
    mainWindow.prepareCropExit(selection: selection, sourceSize: cropBoxView.videoSize,
                               initialFrame: imageFrame, initialClip: clip, initialSelection: fromSelection,
                               controlsImage: controlsImage, controlsFrame: controlsFrame,
                               completion: completion)
  }

  func beginNativeExitPresentation() {
    controlBar.isHidden = true
    cropBoxView.isHidden = true
    mainWindow.updateVideoViewConstraints([.top: 0, .bottom: 0, .leading: 0, .trailing: 0])
    mainWindow.videoViewContainer.layoutSubtreeIfNeeded()
    mainWindow.videoView.layer?.transform = originalVideoTransform
    mainWindow.videoView.layer?.mask = originalVideoMask
  }

  func restoreExitPresentation() {
    controlBar.isHidden = false
    cropBoxView.isHidden = false
    guard isActive, let preview = exitPreviewTransform else { return }
    exitPreviewTransform = nil
    cropBoxView.restoreExitPresentation(preview)
    resize()
  }

  private func delogoAction() {
    let player = mainWindow.player
    exit {
      let filter = MPVFilter(lavfiName: "delogo", label: Constants.FilterName.delogo, paramDict: [
        "x": String(self.cropx), "y": String(self.cropy), "w": String(self.cropw), "h": String(self.croph)
      ])
      if let existingFilter = player.info.delogoFilter { let _ = player.removeVideoFilter(existingFilter) }
      if !player.addVideoFilter(filter) {
        Utility.showAlert("filter.incorrect")
        return
      }
      player.info.delogoFilter = filter
    }
  }

  @objc private func cancelAction(_ sender: AnyObject) {
    guard currentMode == .crop else { exit(); return }
    let selection = originalCropFilter.flatMap { selectionRect(for: $0) } ??
      NSRect(origin: .zero, size: cropBoxView.videoSize)
    let filter = originalCropFilter
    let description = originalCropDescription
    prepareExit(selection: selection) { [self] in
      if let filter {
        guard mainWindow.player.setCrop(fromFilter: filter) else { return false }
        mainWindow.player.info.unsureCrop = description
      }
      exit(applyingCrop: true)
      return true
    }
  }
}

// NSMenu's tracking loop consumes secondary clicks before a row can delete its saved ratio.
private final class CropAspectPresetListController: NSViewController {
  let presetMenu: NSMenu
  var maximumHeight: CGFloat = 400
  var select: ((NSMenuItem) -> Void)?
  var cancel: (() -> Void)?
  var deletePreset: ((NSMenuItem) -> Void)?
  private let actionItem: NSMenuItem?
  private let addTitle: String
  private let addEnabled: Bool
  private var optionHeld = false
  private weak var actionRow: CropAspectPresetMenuView?

  init(menu: NSMenu) {
    presetMenu = menu
    actionItem = menu.items.last
    addTitle = menu.items.last?.title ?? ui.localized("crop.add_preset")
    addEnabled = menu.items.last?.isEnabled ?? false
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func loadView() {
    let menu = presetMenu
    let font = menu.font ?? NSFont.menuFont(ofSize: 0)
    let list = CropAspectPresetListView()
    list.select = { [weak self] in self?.activate($0) }
    list.optionChanged = { [weak self] in self?.setOptionHeld($0) }
    list.cancel = { [weak self] in self?.cancel?() }
    let width = max(menu.minimumWidth, menu.items.map { ($0.title as NSString).size(withAttributes: [.font: font]).width + 56 }.max() ?? 100)
    list.frame.size.width = width
    var y: CGFloat = 4
    for item in menu.items {
      if item.isSeparatorItem {
        let separator = NSBox(frame: NSRect(x: 10, y: y + 3, width: width - 20, height: 1))
        separator.boxType = .separator
        list.addSubview(separator)
        y += 9
      } else {
        let row = CropAspectPresetMenuView(item: item, font: font)
        row.frame = NSRect(x: 0, y: y, width: width, height: row.frame.height)
        row.select = { [weak self] in self?.activate($0) }
        if item === actionItem { actionRow = row }
        if item.representedObject != nil { row.deletePreset = { [weak self] in self?.deletePreset?(item) } }
        list.rows.append(row)
        list.addSubview(row)
        y += row.frame.height
      }
    }
    list.frame = NSRect(x: 0, y: 0, width: width, height: y + 4)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: min(y + 4, maximumHeight)))
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.documentView = list
    list.autoresizingMask = [.width]
    view = scroll
    preferredContentSize = scroll.frame.size
    setOptionHeld(optionHeld)
  }

  func setOptionHeld(_ held: Bool) {
    optionHeld = held
    guard let actionItem else { return }
    actionItem.title = held ? ui.localized("crop.delete_selected_preset") : addTitle
    actionItem.isEnabled = held ? checkedPreset != nil : addEnabled
    actionRow?.refreshAccessibility()
  }

  private var checkedPreset: NSMenuItem? {
    presetMenu.items.first { $0.representedObject != nil && $0.state == .on }
  }

  private func activate(_ item: NSMenuItem) {
    guard item.isEnabled else { return }
    if item === actionItem && optionHeld {
      if let checkedPreset { deletePreset?(checkedPreset) }
    } else {
      select?(item)
    }
  }

  func focusList() {
    guard let list = (view as? NSScrollView)?.documentView else { return }
    view.window?.makeFirstResponder(list)
  }
}

private final class CropAspectPresetListView: NSView {
  var rows: [CropAspectPresetMenuView] = []
  var select: ((NSMenuItem) -> Void)?
  var cancel: (() -> Void)?
  var optionChanged: ((Bool) -> Void)?
  private var keyboardIndex: Int?
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  override func flagsChanged(with event: NSEvent) {
    optionChanged?(event.modifierFlags.contains(.option))
  }

  override func keyDown(with event: NSEvent) {
    let enabled = rows.indices.filter { rows[$0].item.isEnabled }
    switch event.keyCode {
    case 125, 126:
      guard !enabled.isEmpty else { return }
      let direction = event.keyCode == 125 ? 1 : -1
      let index = keyboardIndex.flatMap { enabled.firstIndex(of: $0) }
      keyboardIndex = enabled[index.map { ($0 + direction + enabled.count) % enabled.count } ?? (direction > 0 ? 0 : enabled.count - 1)]
      for (index, row) in rows.enumerated() { row.keyboardHighlight = index == keyboardIndex }
      rows[keyboardIndex!].scrollToVisible(rows[keyboardIndex!].bounds)
    case 36, 76:
      if let keyboardIndex, rows[keyboardIndex].item.isEnabled { select?(rows[keyboardIndex].item) }
    case 53:
      cancel?()
    default: super.keyDown(with: event)
    }
  }
}

private final class CropAspectPresetMenuView: NSView {
  let item: NSMenuItem
  private let font: NSFont
  private var hoverArea: NSTrackingArea?
  private var isHovered = false
  private var isContextClick = false
  var keyboardHighlight = false { didSet { needsDisplay = true } }
  var select: ((NSMenuItem) -> Void)?
  var deletePreset: (() -> Void)?

  init(item: NSMenuItem, font: NSFont) {
    self.item = item
    self.font = font
    let size = (item.title as NSString).size(withAttributes: [.font: font])
    super.init(frame: NSRect(x: 0, y: 0, width: ceil(size.width) + 56, height: max(22, ceil(size.height) + 8)))
    autoresizingMask = [.width]
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    refreshAccessibility()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
    addTrackingArea(area)
    hoverArea = area
  }

  func refreshAccessibility() {
    setAccessibilityLabel(item.title)
    setAccessibilityEnabled(item.isEnabled)
    needsDisplay = true
  }

  override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
  override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

  override func draw(_ dirtyRect: NSRect) {
    let highlighted = item.isEnabled && (isHovered || keyboardHighlight)
    if highlighted {
      NSColor.selectedContentBackgroundColor.setFill()
      NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5).fill()
    }
    let color = item.isEnabled ? (highlighted ? NSColor.selectedMenuItemTextColor : NSColor.labelColor) : NSColor.disabledControlTextColor
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let title = item.title as NSString
    let y = (bounds.height - title.size(withAttributes: attributes).height) / 2
    title.draw(at: NSPoint(x: 30, y: y), withAttributes: attributes)
    if item.state == .on { ("✓" as NSString).draw(at: NSPoint(x: 12, y: y), withAttributes: attributes) }
  }

  override func mouseDown(with event: NSEvent) {
    isContextClick = event.modifierFlags.contains(.control)
    if isContextClick { rightMouseDown(with: event) }
  }

  override func mouseUp(with event: NSEvent) {
    guard !isContextClick else { isContextClick = false; return }
    if bounds.contains(convert(event.locationInWindow, from: nil)) { activatePreset() }
  }

  override func rightMouseDown(with event: NSEvent) { _ = accessibilityDeletePreset() }

  override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
    guard deletePreset != nil else { return nil }
    return [NSAccessibilityCustomAction(name: ui.localized("crop.delete_preset"), target: self, selector: #selector(accessibilityDeletePreset))]
  }

  @objc func accessibilityDeletePreset() -> Bool {
    guard item.isEnabled, let deletePreset else { return false }
    deletePreset()
    return true
  }

  override func accessibilityPerformPress() -> Bool { activatePreset() }

  @discardableResult private func activatePreset() -> Bool {
    guard item.isEnabled else { return false }
    select?(item)
    return select != nil
  }
}

private final class CropZoomPopUpButton: NSPopUpButton {
  var menuTrackingChanged: ((Bool) -> Void)?

  override func mouseDown(with event: NSEvent) { showMenuAbove() }
  override func performClick(_ sender: Any?) { showMenuAbove() }
  override func accessibilityPerformPress() -> Bool {
    guard isEnabled else { return false }
    showMenuAbove()
    return true
  }

  override func keyDown(with event: NSEvent) {
    if [UInt16(49), 125, 126].contains(event.keyCode) { showMenuAbove() }
    else { super.keyDown(with: event) }
  }

  private func showMenuAbove() {
    guard isEnabled, let menu, let titleItem = menu.items.first else { return }
    // The first item supplies the pull-down title and is not a zoom choice.
    let wasHidden = titleItem.isHidden
    titleItem.isHidden = true
    menuTrackingChanged?(true)
    defer {
      titleItem.isHidden = wasHidden
      menuTrackingChanged?(false)
    }
    let top = isFlipped ? bounds.minY - menu.size.height - 4 : bounds.maxY + menu.size.height + 4
    menu.popUp(positioning: nil, at: NSPoint(x: bounds.minX, y: top), in: self)
  }
}

struct CropEditorInsets {
  let top: CGFloat
  let side: CGFloat
  let gap: CGFloat
  let bottom: CGFloat

  init(size: NSSize) {
    let shortSide = min(size.width, size.height)
    top = min(48, max(28, shortSide * 0.075))
    side = min(24, max(12, shortSide * 0.04))
    gap = min(20, max(10, shortSide * 0.03))
    bottom = side
  }
}

private final class CropControlBar: NSView {
  private let adjustments: NSStackView
  private let utilities: NSStackView
  private let buttons: NSView
  private let adjustmentWidth: CGFloat
  private var utilityLeading: NSLayoutConstraint!
  private var buttonsTrailing: NSLayoutConstraint!
  private var adjustmentBottom: NSLayoutConstraint!
  private var reservedHeight: CGFloat = 0
  private(set) var layoutWidth: CGFloat = 0

  init(dimensions: NSView, selector: ScrollSelectionControl, reset: NSView, zoom: NSView, buttons: NSView) {
    adjustments = ui.hStack(spacing: 8, dimensions, selector)
    utilities = ui.hStack(spacing: 8, reset, zoom)
    self.buttons = buttons
    // Reserve the longest possible ratio, independent of the current title animation.
    adjustmentWidth = dimensions.fittingSize.width + 8 + selector.fittingWidth(forTitle: "99:99")
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    [adjustments, utilities, buttons].forEach { addSubview($0) }
    utilityLeading = utilities.leadingAnchor.constraint(equalTo: leadingAnchor)
    buttonsTrailing = buttons.trailingAnchor.constraint(equalTo: trailingAnchor)
    adjustmentBottom = adjustments.bottomAnchor.constraint(equalTo: bottomAnchor)
    NSLayoutConstraint.activate([
      utilityLeading, buttonsTrailing, adjustmentBottom,
      utilities.bottomAnchor.constraint(equalTo: bottomAnchor),
      buttons.bottomAnchor.constraint(equalTo: bottomAnchor),
      adjustments.centerXAnchor.constraint(equalTo: centerXAnchor)
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: reservedHeight)
  }

  func arrange(availableSize: NSSize, previewAspect: CGFloat) -> NSSize {
    let utilityWidth = utilities.fittingSize.width
    let buttonWidth = buttons.fittingSize.width
    let actionWidth = utilityWidth + 8 + buttonWidth
    let minimumWidth = max(adjustmentWidth, actionWidth)
    let actionHeight = max(utilities.fittingSize.height, buttons.fittingSize.height)
    let adjustmentHeight = adjustments.fittingSize.height
    let singleHeight = max(actionHeight, adjustmentHeight)
    let rowOffset = actionHeight + 8
    let twoRowHeight = actionHeight + 8 + adjustmentHeight
    let aspectSize = NSSize(width: previewAspect, height: 1)
    // Measure with both rows reserved to avoid a preview-height/layout-width feedback loop.
    let footprint = aspectSize.shrink(toSize:
      NSSize(width: availableSize.width, height: max(1, availableSize.height - twoRowHeight)))
    let clearWidth = adjustmentWidth + 2 * max(utilityWidth, buttonWidth) + 16
    let spread = smoothProgress((footprint.width - minimumWidth) / max(1, clearWidth - minimumWidth))
    let mergeWidth = max(36, 0.65 * rowOffset * previewAspect)
    let merge = smoothProgress((footprint.width - clearWidth) / mergeWidth)
    let offset = rowOffset * (1 - merge)
    let height = singleHeight + offset
    if height != reservedHeight {
      reservedHeight = height
      invalidateIntrinsicContentSize()
    }
    let preview = aspectSize.shrink(toSize:
      NSSize(width: availableSize.width, height: max(1, availableSize.height - height)))
    layoutWidth = min(availableSize.width, max(minimumWidth, preview.width))
    let sideInset = max(0, (layoutWidth - actionWidth) / 2) * (1 - spread)
    utilityLeading.constant = sideInset
    buttonsTrailing.constant = -sideInset
    adjustmentBottom.constant = -offset
    return preview
  }

  private func smoothProgress(_ value: CGFloat) -> CGFloat {
    let progress = max(0, min(1, value))
    return progress * progress * (3 - 2 * progress)
  }
}

struct CropVideoGeometry {
  let sourceSize: NSSize
  let selectionSize: NSSize
  let displaySize: NSSize
  let rotation: Int

  var pixelAspectRatio: CGFloat {
    guard selectionSize.width > 0, selectionSize.height > 0 else { return 1 }
    return (displaySize.width / displaySize.height) / (selectionSize.width / selectionSize.height)
  }

  init(sourceSize: NSSize, displaySize: NSSize, rotation: Int) {
    self.sourceSize = sourceSize
    self.rotation = ((rotation % 360) + 360) % 360
    let display = displaySize.width > 0 && displaySize.height > 0 ? displaySize : sourceSize
    if self.rotation == 90 || self.rotation == 270 {
      selectionSize = NSSize(width: sourceSize.height, height: sourceSize.width)
      self.displaySize = NSSize(width: display.height, height: display.width)
    } else {
      selectionSize = sourceSize
      self.displaySize = display
    }
  }

  func aspectTitle(for rect: NSRect) -> String {
    guard !rect.isEmpty else { return "—" }
    return Self.aspectTitle(forRatio: rect.width / rect.height * pixelAspectRatio)
  }

  static func aspectTitle(forRatio ratio: CGFloat) -> String {
    guard ratio.isFinite, ratio > 0 else { return "—" }
    for (width, height) in [(4, 3), (16, 9), (16, 10), (21, 9), (3, 2), (5, 4)] {
      if abs(ratio - CGFloat(width) / CGFloat(height)) < 1e-10 { return "\(width):\(height)" }
      if abs(ratio - CGFloat(height) / CGFloat(width)) < 1e-10 { return "\(height):\(width)" }
    }
    let portrait = ratio < 1
    let target = min(99, portrait ? 1 / ratio : ratio)
    var numerator = 1, denominator = 1
    var smallestError = CGFloat.greatestFiniteMagnitude
    for height in 1...99 {
      let width = min(99, max(1, Int((target * CGFloat(height)).rounded())))
      let error = abs(CGFloat(width) / CGFloat(height) - target)
      if error < smallestError - 1e-12 {
        numerator = width
        denominator = height
        smallestError = error
      }
    }
    return portrait ? "\(denominator):\(numerator)" : "\(numerator):\(denominator)"
  }

  // Selection uses bottom-left coordinates after rotation; filters use top-left source coordinates.
  func filterRect(for rect: NSRect) -> NSRect {
    guard !rect.isEmpty else { return .zero }
    switch rotation {
    case 90:
      return NSRect(x: sourceSize.width - rect.maxY, y: sourceSize.height - rect.maxX,
                    width: rect.height, height: rect.width)
    case 180:
      return NSRect(x: sourceSize.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
    case 270:
      return NSRect(x: rect.minY, y: rect.minX, width: rect.height, height: rect.width)
    default:
      return NSRect(x: rect.minX, y: sourceSize.height - rect.maxY, width: rect.width, height: rect.height)
    }
  }

  func selectionRect(forFilterRect rect: NSRect) -> NSRect {
    switch rotation {
    case 90:
      return NSRect(x: sourceSize.height - rect.maxY, y: sourceSize.width - rect.maxX,
                    width: rect.height, height: rect.width)
    case 180:
      return NSRect(x: sourceSize.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
    case 270:
      return NSRect(x: rect.minY, y: rect.minX, width: rect.height, height: rect.width)
    default:
      return NSRect(x: rect.minX, y: sourceSize.height - rect.maxY, width: rect.width, height: rect.height)
    }
  }
}

enum CropSelectionGeometry {
  static func bounded(_ rect: NSRect, in size: NSSize) -> NSRect {
    guard size.width >= 1, size.height >= 1,
          [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite),
          !rect.isEmpty else { return .zero }
    let x = min(max(0, rect.minX.rounded()), size.width - 1)
    let y = min(max(0, rect.minY.rounded()), size.height - 1)
    let maxX = min(max(x + 1, rect.maxX.rounded()), size.width)
    let maxY = min(max(y + 1, rect.maxY.rounded()), size.height)
    return NSRect(x: x, y: y, width: maxX - x, height: maxY - y)
  }

  static func resized(_ rect: NSRect, to requested: NSSize, in size: NSSize, center: NSPoint? = nil) -> NSRect {
    guard size.width >= 1, size.height >= 1 else { return .zero }
    let width = min(size.width, max(1, requested.width.rounded()))
    let height = min(size.height, max(1, requested.height.rounded()))
    let center = center ?? (rect.isEmpty ? NSPoint(x: size.width / 2, y: size.height / 2) : NSPoint(x: rect.midX, y: rect.midY))
    return NSRect(x: min(max(0, (center.x - width / 2).rounded()), size.width - width),
                   y: min(max(0, (center.y - height / 2).rounded()), size.height - height),
                   width: width, height: height)
  }
}

struct CropPreviewTransform: Equatable {
  static let maximumZoom: CGFloat = 8
  private(set) var zoom: CGFloat = 1
  private(set) var center = NSPoint(x: 0.5, y: 0.5)

  func imageRect(in viewport: NSRect) -> NSRect {
    let size = NSSize(width: viewport.width * zoom, height: viewport.height * zoom)
    return NSRect(x: viewport.midX - center.x * size.width,
                  y: viewport.midY - center.y * size.height, width: size.width, height: size.height)
  }

  mutating func setZoom(_ value: CGFloat, at point: NSPoint, in viewport: NSRect) {
    guard value.isFinite, point.x.isFinite, point.y.isFinite,
          viewport.width > 0, viewport.height > 0 else { return }
    let image = imageRect(in: viewport)
    let source = NSPoint(x: (point.x - image.minX) / image.width,
                         y: (point.y - image.minY) / image.height)
    zoom = min(Self.maximumZoom, max(1, value))
    center = NSPoint(x: source.x - (point.x - viewport.midX) / (viewport.width * zoom),
                     y: source.y - (point.y - viewport.midY) / (viewport.height * zoom))
    clampCenter()
  }

  mutating func pan(by delta: NSPoint, in viewport: NSRect) {
    guard delta.x.isFinite, delta.y.isFinite, viewport.width > 0, viewport.height > 0 else { return }
    center.x -= delta.x / (viewport.width * zoom)
    center.y -= delta.y / (viewport.height * zoom)
    clampCenter()
  }

  private mutating func clampCenter() {
    let inset = 0.5 / zoom
    center.x = min(1 - inset, max(inset, center.x))
    center.y = min(1 - inset, max(inset, center.y))
  }
}

final class CropBoxView: NSView {
  private static let resetDuration: TimeInterval = 0.28
  private let handleHitRadius: CGFloat = 9
  var rectUpdatedCallback: (() -> Void)?
  var previewUpdatedCallback: (() -> Void)?
  var allowsZoom = false
  private(set) var previewTransform = CropPreviewTransform()
  var videoSize = NSSize() {
    didSet {
      finishSelectionAnimation()
      setSelectedRect(to: selectedRect)
    }
  }
  var previewInset: CGFloat = 0
  var previewRect: NSRect { bounds.insetBy(dx: previewInset, dy: previewInset) }
  var imageRect: NSRect { previewTransform.imageRect(in: previewRect) }
  private(set) var selectedRect = NSRect()
  private var presentedSelection: NSRect?
  private var selectionTimer: Timer?
  private var outsideOpacity: CGFloat = 0.52
  var isAnimatingSelection: Bool { selectionTimer != nil }
  var boxRect: NSRect {
    guard videoSize.width > 0, videoSize.height > 0 else { return .zero }
    let image = imageRect
    let rect = presentedSelection ?? selectedRect
    return NSRect(x: image.minX + rect.minX * image.width / videoSize.width,
                   y: image.minY + rect.minY * image.height / videoSize.height,
                   width: rect.width * image.width / videoSize.width,
                   height: rect.height * image.height / videoSize.height)
  }

  private struct Edges: OptionSet {
    let rawValue: Int
    static let minX = Edges(rawValue: 1)
    static let maxX = Edges(rawValue: 2)
    static let minY = Edges(rawValue: 4)
    static let maxY = Edges(rawValue: 8)
  }

  private enum Drag {
    case resize(Edges, NSRect, NSPoint, centered: Bool, proportional: Bool, lastPoint: NSPoint)
    case move(NSRect, NSPoint)
    case select(NSPoint)
  }
  private var drag: Drag?
  var isDragging: Bool { drag != nil }

  override var acceptsFirstResponder: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  init(callback: (() -> Void)?) {
    rectUpdatedCallback = callback
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    setAccessibilityLabel(ui.localized("crop.selection"))
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  deinit { selectionTimer?.invalidate() }

  private var canAnimateSelection: Bool {
    window != nil && !isHiddenOrHasHiddenAncestor && !AccessibilityPreferences.motionReductionEnabled &&
      AccessibilityPreferences.adjustedDuration(Self.resetDuration) > 0
  }

  func setSelectedRect(to rect: NSRect, animated: Bool = false) {
    guard !isAnimatingSelection else { return }
    let target = CropSelectionGeometry.bounded(rect, in: videoSize)
    let from = presentedSelection ?? selectedRect
    finishSelectionAnimation()
    selectedRect = target
    if animated { drag = nil }
    if animated, canAnimateSelection, !from.isEmpty, from != target {
      // Save and aspect digits use the final crop while only the outline interpolates.
      presentedSelection = from
      let start = CACurrentMediaTime()
      let duration = AccessibilityPreferences.adjustedDuration(Self.resetDuration)
      let timer = Timer(timeInterval: 1 / 60.0, repeats: true) { [weak self] timer in
        guard let self else { timer.invalidate(); return }
        guard self.canAnimateSelection else { self.finishSelectionAnimation(); return }
        let progress = min(1, (CACurrentMediaTime() - start) / duration)
        let eased = CGFloat(1 - pow(1 - progress, 3))
        self.presentedSelection = NSRect(x: from.minX + (target.minX - from.minX) * eased,
                                         y: from.minY + (target.minY - from.minY) * eased,
                                         width: from.width + (target.width - from.width) * eased,
                                         height: from.height + (target.height - from.height) * eased)
        self.needsDisplay = true
        self.window?.invalidateCursorRects(for: self)
        if progress >= 1 { self.finishSelectionAnimation() }
      }
      selectionTimer = timer
      RunLoop.main.add(timer, forMode: .common)
    }
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
    setAccessibilityValue("\(Int(selectedRect.width)) × \(Int(selectedRect.height))")
    rectUpdatedCallback?()
  }

  private func finishSelectionAnimation() {
    guard selectionTimer != nil || presentedSelection != nil else { return }
    selectionTimer?.invalidate()
    selectionTimer = nil
    presentedSelection = nil
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
  }

  func beginExitPresentation() -> NSRect {
    let selection = presentedSelection ?? selectedRect
    selectionTimer?.invalidate()
    selectionTimer = nil
    presentedSelection = selection
    drag = nil
    return selection
  }

  func restoreExitPresentation(_ preview: CropPreviewTransform) {
    previewTransform = preview
    presentedSelection = nil
    outsideOpacity = 0.52
    previewDidChange()
  }

  func resetPreview() {
    previewTransform = CropPreviewTransform()
    outsideOpacity = 0.52
    previewDidChange()
  }

  func setZoom(_ zoom: CGFloat, at anchor: NSPoint? = nil) {
    guard allowsZoom, !isDragging, !isAnimatingSelection else { return }
    let previous = previewTransform
    previewTransform.setZoom(zoom, at: anchor ?? NSPoint(x: previewRect.midX, y: previewRect.midY), in: previewRect)
    if previewTransform != previous { previewDidChange() }
  }

  private func previewDidChange() {
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
    previewUpdatedCallback?()
  }

  override func scrollWheel(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    guard allowsZoom, !isDragging, !isAnimatingSelection, previewRect.contains(point) else { return }
    let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
    if event.modifierFlags.contains(.option) {
      let delta = event.scrollingDeltaY == 0 ? event.scrollingDeltaX : event.scrollingDeltaY
      guard delta.isFinite else { return }
      let exponentLimit = 2 * log(CropPreviewTransform.maximumZoom)
      let exponent = min(exponentLimit, max(-exponentLimit, delta * multiplier * 0.01))
      setZoom(previewTransform.zoom * exp(exponent), at: point)
      return
    }
    let delta: NSPoint
    if event.modifierFlags.contains(.shift) {
      // macOS may already remap Shift+wheel from the vertical axis to the horizontal axis.
      let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
      delta = NSPoint(x: horizontal * multiplier, y: 0)
    } else {
      delta = NSPoint(x: event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : 0,
                      y: -event.scrollingDeltaY * multiplier)
    }
    let previous = previewTransform
    previewTransform.pan(by: delta, in: previewRect)
    if previewTransform != previous { previewDidChange() }
  }

  override func layout() {
    super.layout()
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window == nil {
      drag = nil
      finishSelectionAnimation()
    }
  }

  private func videoPoint(from point: NSPoint) -> NSPoint {
    let image = imageRect
    return NSPoint(x: min(videoSize.width, max(0, (point.x - image.minX) * videoSize.width / image.width)),
                   y: min(videoSize.height, max(0, (point.y - image.minY) * videoSize.height / image.height)))
  }

  private var cornerLength: CGFloat { min(14, min(boxRect.width, boxRect.height) / 3) }

  private var cornerHitAreas: [(rect: NSRect, edges: Edges)] {
    let rect = boxRect
    let insetX = min(cornerLength + 3, rect.width / 2)
    let insetY = min(cornerLength + 3, rect.height / 2)
    return [
      (NSRect(x: rect.minX - handleHitRadius, y: rect.minY - handleHitRadius,
              width: insetX + handleHitRadius, height: insetY + handleHitRadius), [.minX, .minY]),
      (NSRect(x: rect.maxX - insetX, y: rect.minY - handleHitRadius,
              width: insetX + handleHitRadius, height: insetY + handleHitRadius), [.maxX, .minY]),
      (NSRect(x: rect.minX - handleHitRadius, y: rect.maxY - insetY,
              width: insetX + handleHitRadius, height: insetY + handleHitRadius), [.minX, .maxY]),
      (NSRect(x: rect.maxX - insetX, y: rect.maxY - insetY,
              width: insetX + handleHitRadius, height: insetY + handleHitRadius), [.maxX, .maxY])
    ]
  }

  private func edges(at point: NSPoint) -> Edges {
    guard !selectedRect.isEmpty,
          (previewRect.minX - handleHitRadius...previewRect.maxX + handleHitRadius).contains(point.x),
          (previewRect.minY - handleHitRadius...previewRect.maxY + handleHitRadius).contains(point.y) else { return [] }
    if let corner = cornerHitAreas.first(where: { $0.rect.contains(point) }) { return corner.edges }
    let rect = boxRect
    guard (rect.minX - handleHitRadius...rect.maxX + handleHitRadius).contains(point.x),
          (rect.minY - handleHitRadius...rect.maxY + handleHitRadius).contains(point.y) else { return [] }
    var result: Edges = []
    let left = abs(point.x - rect.minX), right = abs(point.x - rect.maxX)
    let bottom = abs(point.y - rect.minY), top = abs(point.y - rect.maxY)
    if left <= handleHitRadius && left <= right { result.insert(.minX) }
    else if right <= handleHitRadius { result.insert(.maxX) }
    if bottom <= handleHitRadius && bottom <= top { result.insert(.minY) }
    else if top <= handleHitRadius { result.insert(.maxY) }
    return result
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard !isHidden else { return nil }
    let localPoint = convert(point, from: superview)
    return previewRect.contains(localPoint) || !edges(at: localPoint).isEmpty ? self : nil
  }

  override func mouseDown(with event: NSEvent) {
    guard !isAnimatingSelection, previewRect.width > 0, previewRect.height > 0,
          videoSize.width > 0, videoSize.height > 0 else { return }
    let point = convert(event.locationInWindow, from: nil)
    guard previewRect.contains(point) || !edges(at: point).isEmpty else { return }
    window?.makeFirstResponder(self)
    let anchor = videoPoint(from: point)
    let hitEdges = edges(at: point)
    if !hitEdges.isEmpty {
      drag = .resize(hitEdges, selectedRect, anchor, centered: event.modifierFlags.contains(.option),
                     proportional: event.modifierFlags.contains([.option, .shift]), lastPoint: anchor)
    } else if !selectedRect.isEmpty && boxRect.contains(point) {
      drag = .move(selectedRect, anchor)
      NSCursor.closedHand.set()
    } else {
      drag = .select(anchor)
      NSCursor.crosshair.set()
    }
  }

  override func mouseDragged(with event: NSEvent) {
    guard let drag, previewRect.width > 0, previewRect.height > 0 else { return }
    let point = videoPoint(from: convert(event.locationInWindow, from: nil))
    let rect: NSRect
    switch drag {
    case let .select(anchor):
      rect = NSRect(x: min(anchor.x, point.x), y: min(anchor.y, point.y),
                    width: max(1, abs(point.x - anchor.x)), height: max(1, abs(point.y - anchor.y)))
    case let .move(initial, anchor):
      rect = NSRect(x: min(max(0, initial.minX + point.x - anchor.x), videoSize.width - initial.width),
                    y: min(max(0, initial.minY + point.y - anchor.y), videoSize.height - initial.height),
                    width: initial.width, height: initial.height)
    case let .resize(edges, initial, anchor, wasCentered, wasProportional, lastPoint):
      let centered = event.modifierFlags.contains(.option)
      let proportional = event.modifierFlags.contains([.option, .shift])
      // Rebase modifier changes at the visible frame to avoid a jump.
      let sameMode = centered == wasCentered && proportional == wasProportional
      let base = sameMode ? initial : selectedRect
      let origin = sameMode ? anchor : lastPoint
      self.drag = .resize(edges, base, origin, centered: centered, proportional: proportional, lastPoint: point)
      var minX = base.minX, maxX = base.maxX, minY = base.minY, maxY = base.maxY
      let dx = point.x - origin.x, dy = point.y - origin.y
      if proportional {
        // Project corners onto their displayed diagonal; edge drags use only their own axis.
        let halfX: CGFloat = edges.contains(.minX) ? -base.width / 2 :
          (edges.contains(.maxX) ? base.width / 2 : 0)
        let halfY: CGFloat = edges.contains(.minY) ? -base.height / 2 :
          (edges.contains(.maxY) ? base.height / 2 : 0)
        let pixelX = imageRect.width / videoSize.width
        let pixelY = imageRect.height / videoSize.height
        let denominator = pow(halfX * pixelX, 2) + pow(halfY * pixelY, 2)
        let requested = 1 + (dx * halfX * pixelX * pixelX + dy * halfY * pixelY * pixelY) / denominator
        let maximum = min(2 * min(base.midX, videoSize.width - base.midX) / base.width,
                          2 * min(base.midY, videoSize.height - base.midY) / base.height)
        // Preserve integer edges and the exact center, including odd sizes.
        let minimumWidth: CGFloat = Int(base.width) % 2 == 0 ? 2 : 1
        let minimumHeight: CGFloat = Int(base.height) % 2 == 0 ? 2 : 1
        let minimum = max(minimumWidth / base.width, minimumHeight / base.height)
        let scale = min(maximum, max(minimum, requested))
        let changeX = ((scale - 1) * base.width / 2).rounded()
        let changeY = ((scale - 1) * base.height / 2).rounded()
        minX -= changeX
        maxX += changeX
        minY -= changeY
        maxY += changeY
      } else if centered {
        // Whole source-pixel steps preserve the exact center, including at image boundaries.
        func inset(_ delta: CGFloat, length: CGFloat, margin: CGFloat) -> CGFloat {
          min(floor((length - 1) / 2), max(-margin, delta.rounded()))
        }
        if !edges.intersection([.minX, .maxX]).isEmpty {
          let change = inset(edges.contains(.minX) ? dx : -dx, length: base.width,
                             margin: min(base.minX, videoSize.width - base.maxX))
          minX += change
          maxX -= change
        }
        if !edges.intersection([.minY, .maxY]).isEmpty {
          let change = inset(edges.contains(.minY) ? dy : -dy, length: base.height,
                             margin: min(base.minY, videoSize.height - base.maxY))
          minY += change
          maxY -= change
        }
      } else {
        if edges.contains(.minX) { minX = min(maxX - 1, max(0, minX + dx)) }
        if edges.contains(.maxX) { maxX = max(minX + 1, min(videoSize.width, maxX + dx)) }
        if edges.contains(.minY) { minY = min(maxY - 1, max(0, minY + dy)) }
        if edges.contains(.maxY) { maxY = max(minY + 1, min(videoSize.height, maxY + dy)) }
      }
      rect = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    setSelectedRect(to: rect)
  }

  override func mouseUp(with event: NSEvent) {
    guard isDragging else { return }
    drag = nil
    window?.invalidateCursorRects(for: self)
    rectUpdatedCallback?()
  }

  override func keyDown(with event: NSEvent) {
    let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
    let delta: NSPoint
    switch event.keyCode {
    case 123: delta = NSPoint(x: -step, y: 0)
    case 124: delta = NSPoint(x: step, y: 0)
    case 125: delta = NSPoint(x: 0, y: -step)
    case 126: delta = NSPoint(x: 0, y: step)
    default: super.keyDown(with: event); return
    }
    guard !isAnimatingSelection, !selectedRect.isEmpty else { return }
    var rect = selectedRect
    rect.origin.x = min(max(0, rect.minX + delta.x), videoSize.width - rect.width)
    rect.origin.y = min(max(0, rect.minY + delta.y), videoSize.height - rect.height)
    setSelectedRect(to: rect)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let rect = boxRect
    let outside = NSBezierPath(rect: previewRect)
    let visibleSelection = rect.intersection(previewRect)
    if !visibleSelection.isEmpty { outside.appendRect(visibleSelection) }
    outside.windingRule = .evenOdd
    NSColor.black.withAlphaComponent(outsideOpacity).setFill()
    outside.fill()
    guard !selectedRect.isEmpty else { return }

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: previewRect.insetBy(dx: -3, dy: -3)).addClip()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
    shadow.shadowBlurRadius = 2
    shadow.set()
    NSColor.white.withAlphaComponent(0.85).setStroke()
    let outline = NSBezierPath(rect: rect)
    outline.lineWidth = 1
    outline.stroke()
    let corners = NSBezierPath()
    let length = cornerLength
    for (x, dx) in [(rect.minX, CGFloat(1)), (rect.maxX, CGFloat(-1))] {
      for (y, dy) in [(rect.minY, CGFloat(1)), (rect.maxY, CGFloat(-1))] {
        corners.move(to: NSPoint(x: x, y: y + dy * length))
        corners.line(to: NSPoint(x: x, y: y))
        corners.line(to: NSPoint(x: x + dx * length, y: y))
      }
    }
    NSColor.white.setStroke()
    corners.lineWidth = 3
    corners.lineJoinStyle = .miter
    corners.stroke()
    NSGraphicsContext.restoreGraphicsState()
  }

  override func resetCursorRects() {
    guard !isAnimatingSelection else { addCursorRect(bounds, cursor: .arrow); return }
    guard !selectedRect.isEmpty else { addCursorRect(previewRect, cursor: .crosshair); return }
    func addVisibleCursorRect(_ area: NSRect, cursor: NSCursor) {
      let visible = area.intersection(bounds)
      guard !visible.isEmpty else { return }
      addCursorRect(visible, cursor: cursor)
    }
    let rect = boxRect
    let visibleSelection = rect.intersection(previewRect)
    addVisibleCursorRect(visibleSelection, cursor: drag == nil ? .openHand : .closedHand)
    let edgeRects: [(NSRect, NSCursor)] = [
      (NSRect(x: rect.minX, y: rect.minY - handleHitRadius, width: rect.width, height: 2 * handleHitRadius), ResizeCursor.vertical),
      (NSRect(x: rect.minX, y: rect.maxY - handleHitRadius, width: rect.width, height: 2 * handleHitRadius), ResizeCursor.vertical),
      (NSRect(x: rect.minX - handleHitRadius, y: rect.minY, width: 2 * handleHitRadius, height: rect.height), ResizeCursor.horizontal),
      (NSRect(x: rect.maxX - handleHitRadius, y: rect.minY, width: 2 * handleHitRadius, height: rect.height), ResizeCursor.horizontal)
    ]
    for (area, cursor) in edgeRects { addVisibleCursorRect(area, cursor: cursor) }
    for corner in cornerHitAreas {
      let cursor = corner.edges.contains(.minX) == corner.edges.contains(.minY) ? ResizeCursor.rising : ResizeCursor.falling
      addVisibleCursorRect(corner.rect, cursor: cursor)
    }
  }
}
