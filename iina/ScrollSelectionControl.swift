//
//  ScrollSelectionControl.swift
//  iina
//
//  Copyright © 2026 lhc. All rights reserved.
//

import Cocoa

struct ScrollSelectionCylinder {
  static func transform(angle: CGFloat, radius: CGFloat) -> CATransform3D {
    var transform = CATransform3DMakeRotation(-angle, 1, 0, 0)
    transform.m42 = radius * sin(angle)
    transform.m43 = radius * (cos(angle) - 1)
    return transform
  }

  static func opacity(angle: CGFloat) -> Float {
    guard abs(angle) < .pi / 2 else { return 0 }
    return Float(pow(cos(angle), 0.7))
  }
}

struct ScrollSelectionDigitRoll {
  enum Column: Hashable {
    case digit(side: Int, place: Int)
    case separator
  }

  struct Glyph {
    let column: Column
    let text: String
  }

  static func glyphs(in title: String) -> [Glyph]? {
    let sides = title.split(separator: ":", omittingEmptySubsequences: false)
    guard sides.count == 2, sides.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0 >= "0" && $0 <= "9" } }) else { return nil }
    var glyphs: [Glyph] = []
    for (side, number) in sides.enumerated() {
      if side > 0 { glyphs.append(Glyph(column: .separator, text: ":")) }
      for (index, digit) in number.enumerated() {
        glyphs.append(Glyph(column: .digit(side: side, place: number.count - index - 1), text: String(digit)))
      }
    }
    return glyphs
  }

  static func path(from old: String, to new: String) -> (titles: [String], direction: Int)? {
    guard old.count == 1, new.count == 1, let from = Int(old), let to = Int(new),
          (0...9).contains(from), (0...9).contains(to) else { return nil }
    let forward = (to - from + 10) % 10
    let steps = forward <= 5 ? forward : forward - 10
    let direction = steps < 0 ? -1 : 1
    return ((0...abs(steps)).map { String((from + direction * $0 + 10) % 10) }, direction)
  }
}

private final class ScrollSelectionOverlay: NSView {
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@available(macOS 26.0, *)
private final class ScrollSelectionGlass: NSGlassEffectView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

class ScrollSelectionControl: NSSegmentedControl {
  var switchSelection: ((Int) -> Void)?
  var animatesDigits = false
  /// When set, grow immediately and debounce shrinking by this interval.
  var shrinkDelay: TimeInterval?
  var maximumWidth: CGFloat = .greatestFiniteMagnitude {
    didSet {
      guard maximumWidth != oldValue, maximumWidth > 0 else { return }
      resizeToTitle(animated: canAnimate, delayed: false)
    }
  }
  private var accumulatedDelta: CGFloat = 0
  private var didSwitchInGesture = false
  private var lastEventTime: TimeInterval?
  private var title = ""
  private var selectionImage: NSImage?
  private var foreground: ScrollSelectionOverlay!
  private var glassBackground: NSView?
  private var nativeAlignmentInsets = NSEdgeInsets()
  private let iconView = NSImageView()
  private let titleMask = CALayer()
  private var rollLayer: CALayer?
  private var rollGeneration = 0
  private var preferredSize = NSSize(width: 32, height: 28)
  private var displayedWidth: CGFloat = 32
  private var widthConstraint: NSLayoutConstraint!
  private var pendingResize: DispatchWorkItem?
  private var resizeTimer: Timer?
  private var resizeTarget: CGFloat?

  var isRolling: Bool { rollLayer != nil }
  var isResizing: Bool { pendingResize != nil || resizeTimer != nil }
  private var canAnimate: Bool {
    window != nil && !isHiddenOrHasHiddenAncestor && isEnabled &&
      !AccessibilityPreferences.motionReductionEnabled &&
      AccessibilityPreferences.adjustedDuration(0.22) > 0
  }
  private var titleFont: NSFont {
    font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize(for: controlSize))
  }
  private var contentInset: CGFloat {
    if #available(macOS 26.0, *) { return controlSize == .extraLarge ? 18 : 14 }
    return 10
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    if #available(macOS 26.0, *) {
      // Native segmented bezels stretch on hover, even without a selection change.
      let glass = ScrollSelectionGlass()
      if #available(macOS 27.0, *) { glass.effectIsInteractive = false }
      glass.setAccessibilityElement(false)
      glassBackground = glass
      cell?.isBordered = false
      cell?.isBezeled = false
      addSubview(glass, positioned: .below, relativeTo: nil)
    }
    widthConstraint = widthAnchor.constraint(equalToConstant: displayedWidth)
    widthConstraint.priority = .defaultHigh
    widthConstraint.isActive = true
    foreground = ScrollSelectionOverlay(frame: bounds)
    foreground.wantsLayer = true
    foreground.setAccessibilityElement(false)
    iconView.imageScaling = .scaleNone
    iconView.setAccessibilityElement(false)
    foreground.addSubview(iconView)
    foreground.layer!.addSublayer(titleMask)
    titleMask.masksToBounds = true
    titleMask.isGeometryFlipped = true
    addSubview(foreground)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  deinit {
    pendingResize?.cancel()
    resizeTimer?.invalidate()
  }

  override var alignmentRectInsets: NSEdgeInsets {
    glassBackground == nil ? super.alignmentRectInsets : nativeAlignmentInsets
  }

  override var intrinsicContentSize: NSSize {
    NSSize(width: displayedWidth, height: preferredSize.height)
  }

  override func setLabel(_ label: String, forSegment segment: Int) {
    guard segment == 0 else { super.setLabel(label, forSegment: segment); return }
    guard title != label else { return }
    let previousTitle = title
    finishRoll(restoringTitle: false)
    title = label
    // The foreground draws content; the native cell retains actions and accessibility.
    super.setLabel("\u{200B}", forSegment: 0)
    super.setToolTip(label, forSegment: 0)
    setAccessibilityLabel(label)
    cell?.setAccessibilityLabel(label)
    for child in cell?.accessibilityChildren() ?? [] {
      (child as? NSAccessibilityProtocol)?.setAccessibilityLabel(label)
    }
    refreshMetrics()
    showTitle()
    resizeToTitle(animated: canAnimate, delayed: true)
    if animatesDigits { rollDigits(from: previousTitle, to: title) }
  }

  override func label(forSegment segment: Int) -> String? {
    segment == 0 ? title : super.label(forSegment: segment)
  }

  override func image(forSegment segment: Int) -> NSImage? {
    segment == 0 ? selectionImage : super.image(forSegment: segment)
  }

  override func setImage(_ image: NSImage?, forSegment segment: Int) {
    guard segment == 0 else { super.setImage(image, forSegment: segment); return }
    finishRoll(restoringTitle: false)
    if let image {
      let padded = NSImage(size: NSSize(width: image.size.width + 4, height: image.size.height),
                           flipped: false) { rect in
        image.draw(in: NSRect(origin: rect.origin, size: image.size))
        return true
      }
      padded.isTemplate = image.isTemplate
      selectionImage = padded
      let spacer = NSImage(size: padded.size, flipped: false) { _ in true }
      super.setImage(spacer, forSegment: 0)
    } else {
      selectionImage = nil
      super.setImage(nil, forSegment: 0)
    }
    iconView.image = selectionImage
    refreshMetrics()
    showTitle()
    resizeToTitle(animated: false, delayed: false)
  }

  override var controlSize: NSControl.ControlSize {
    didSet {
      guard foreground != nil else { return }
      finishRoll(restoringTitle: false)
      refreshMetrics()
      showTitle()
      resizeToTitle(animated: false, delayed: false)
    }
  }

  override var isEnabled: Bool {
    didSet {
      guard foreground != nil else { return }
      if !isEnabled {
        finishRoll(restoringTitle: false)
        settleWidth()
      }
      showTitle()
    }
  }

  override func layout() {
    super.layout()
    guard foreground != nil else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let height = min(bounds.height, preferredSize.height)
    foreground.frame = NSRect(x: 0, y: bounds.midY - height / 2, width: bounds.width, height: height)
    if #available(macOS 26.0, *), let glass = glassBackground as? ScrollSelectionGlass {
      glass.frame = foreground.frame
      glass.cornerRadius = height / 2
    }
    foreground.layer!.cornerRadius = height / 2
    foreground.layer!.masksToBounds = true
    let imageSize = selectionImage?.size ?? .zero
    iconView.frame = NSRect(x: contentInset, y: (height - imageSize.height) / 2,
                            width: imageSize.width, height: imageSize.height)
    iconView.contentTintColor = isEnabled ? .labelColor : .disabledControlTextColor
    let textLeft = contentInset + imageSize.width + (selectionImage == nil ? 0 : 3)
    titleMask.frame = NSRect(x: textLeft, y: 0,
                            width: max(0, bounds.width - contentInset - textLeft), height: height)
    if let rollLayer {
      rollLayer.position = NSPoint(x: 0, y: height / 2)
    }
    CATransaction.commit()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    guard foreground != nil else { return }
    finishRoll(restoringTitle: false)
    showTitle()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    guard foreground != nil else { return }
    finishRoll(restoringTitle: false)
    showTitle()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard foreground != nil else { return }
    finishRoll(restoringTitle: false)
    settleWidth()
    showTitle()
    if window == nil {
      accumulatedDelta = 0
      didSwitchInGesture = false
      lastEventTime = nil
    }
  }

  override func mouseDown(with event: NSEvent) {
    finishRoll()
    super.mouseDown(with: event)
  }

  func fittingWidth(forTitle title: String) -> CGFloat {
    min(maximumWidth, measureTitle(title).size.width)
  }

  private func measureTitle(_ title: String) -> (size: NSSize, insets: NSEdgeInsets) {
    let measure = NSSegmentedControl()
    measure.segmentCount = 1
    measure.trackingMode = .momentary
    measure.controlSize = controlSize
    measure.font = titleFont
    measure.setLabel(title, forSegment: 0)
    measure.setImage(selectionImage, forSegment: 0)
    var size = measure.intrinsicContentSize
    // Our foreground has a fixed leading inset and must fit without native centering.
    let textWidth = ceil((title as NSString).size(withAttributes: [.font: titleFont]).width)
    let foregroundWidth = contentInset * 2 + (selectionImage?.size.width ?? 0) +
      (selectionImage == nil ? 0 : 3) + textWidth
    size.width = max(size.width, foregroundWidth)
    return (size, measure.alignmentRectInsets)
  }

  private func refreshMetrics() {
    let metrics = measureTitle(title)
    preferredSize = metrics.size
    nativeAlignmentInsets = metrics.insets
  }

  private func resizeToTitle(animated: Bool, delayed: Bool) {
    let target = min(preferredSize.width, maximumWidth)
    if shrinkDelay != nil, delayed, animated, resizeTimer != nil,
       resizeTarget == target, target > displayedWidth { return }
    cancelResize()
    guard animated, abs(target - displayedWidth) > 0.5 else {
      applyWidth(target)
      return
    }
    if displayedWidth > maximumWidth { applyWidth(maximumWidth) }
    if delayed && (shrinkDelay == nil || target < displayedWidth) {
      let work = DispatchWorkItem { [weak self] in
        guard let self else { return }
        self.pendingResize = nil
        self.animateWidth(to: min(self.preferredSize.width, self.maximumWidth))
      }
      pendingResize = work
      DispatchQueue.main.asyncAfter(deadline: .now() + (shrinkDelay ?? 0.12), execute: work)
    } else {
      animateWidth(to: target)
    }
  }

  private func animateWidth(to target: CGFloat) {
    let from = displayedWidth
    guard canAnimate, abs(from - target) > 0.5 else { applyWidth(target); return }
    let start = CACurrentMediaTime()
    let duration = AccessibilityPreferences.adjustedDuration(0.22)
    resizeTarget = target
    let timer = Timer(timeInterval: 1 / 60.0, repeats: true) { [weak self] timer in
      guard let self else { timer.invalidate(); return }
      guard self.canAnimate else { self.settleWidth(); return }
      let progress = min(1, (CACurrentMediaTime() - start) / duration)
      let eased = progress * progress * (3 - 2 * progress)
      self.applyWidth(from + (target - from) * eased)
      if progress >= 1 {
        timer.invalidate()
        self.resizeTimer = nil
        self.resizeTarget = nil
      }
    }
    resizeTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func applyWidth(_ width: CGFloat) {
    displayedWidth = max(1, width)
    widthConstraint.constant = displayedWidth
    invalidateIntrinsicContentSize()
    needsLayout = true
    superview?.layoutSubtreeIfNeeded()
  }

  private func cancelResize() {
    pendingResize?.cancel()
    pendingResize = nil
    resizeTimer?.invalidate()
    resizeTimer = nil
    resizeTarget = nil
  }

  private func settleWidth() {
    cancelResize()
    applyWidth(min(preferredSize.width, maximumWidth))
  }

  func finishRoll(restoringTitle: Bool = true) {
    guard let rollLayer else { return }
    rollGeneration += 1
    rollLayer.sublayers?.forEach { $0.removeAllAnimations() }
    rollLayer.removeFromSuperlayer()
    self.rollLayer = nil
    if restoringTitle { showTitle() }
  }

  private func showTitle() {
    guard foreground != nil, !isRolling else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    titleMask.sublayers?.forEach { $0.removeFromSuperlayer() }
    if let face = textLayer(title) {
      face.anchorPoint = NSPoint(x: 0, y: 0.5)
      face.position = NSPoint(x: 0, y: preferredSize.height / 2)
      titleMask.addSublayer(face)
    }
    needsLayout = true
    CATransaction.commit()
  }

  func roll(through titles: [String], direction: Int, duration: TimeInterval = 0.28) {
    finishRoll()
    let duration = AccessibilityPreferences.adjustedDuration(duration)
    guard titles.count > 1, direction != 0, duration > 0, canAnimate,
          bounds.width > 0, bounds.height > 0 else { return }
    let faces = titles.compactMap(textLayer)
    guard faces.count == titles.count else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let cylinder = CALayer()
    installRoll(cylinder)
    animateCylinder(cylinder, faces: faces, direction: direction, duration: duration)
    CATransaction.commit()
  }

  private func installRoll(_ layer: CALayer) {
    titleMask.sublayers?.forEach { $0.removeFromSuperlayer() }
    rollLayer = layer
    titleMask.addSublayer(layer)
    let generation = rollGeneration
    CATransaction.setCompletionBlock { [weak self] in
      guard let self, self.rollGeneration == generation else { return }
      self.finishRoll()
    }
  }

  private func animateCylinder(_ cylinder: CALayer, faces: [CALayer], direction: Int, duration: TimeInterval,
                               continuous: Bool = false) {
    let height = preferredSize.height
    cylinder.anchorPoint = NSPoint(x: 0, y: 0.5)
    cylinder.bounds = NSRect(x: 0, y: 0, width: faces.map { $0.bounds.width }.max()!, height: height)
    cylinder.position = NSPoint(x: 0, y: height / 2)
    let radius = height / 2
    var perspective = CATransform3DIdentity
    perspective.m34 = -1 / (radius * 8)
    cylinder.sublayerTransform = perspective
    let step = CGFloat.pi / 2
    let steps = CGFloat(faces.count - 1)
    let sign: CGFloat = direction > 0 ? 1 : -1
    let samples = 48
    for (index, face) in faces.enumerated() {
      face.anchorPoint = NSPoint(x: 0, y: 0.5)
      face.position = NSPoint(x: 0, y: height / 2)
      face.isDoubleSided = false
      cylinder.addSublayer(face)
      let angles = (0...samples).map { sample in
        let time = CGFloat(sample) / CGFloat(samples)
        let progress = steps * CGFloat(sample) / CGFloat(samples)
        let turn = floor(progress)
        let fraction = progress - turn
        // Digit rolls start and finish with zero velocity and acceleration.
        let smooth = time * time * time * (time * (time * 6 - 15) + 10)
        let eased = continuous ? steps * smooth : turn + (1 - cos(.pi * fraction)) / 2
        return sign * (eased - CGFloat(index)) * step
      }
      let transforms = angles.map { ScrollSelectionCylinder.transform(angle: $0, radius: radius) }
      let opacities = angles.map { ScrollSelectionCylinder.opacity(angle: $0) }
      face.transform = transforms.last!
      face.opacity = opacities.last!
      let rotation = CAKeyframeAnimation(keyPath: "transform")
      rotation.values = transforms.map { NSValue(caTransform3D: $0) }
      let shading = CAKeyframeAnimation(keyPath: "opacity")
      shading.values = opacities
      let animation = CAAnimationGroup()
      animation.animations = [rotation, shading]
      animation.duration = duration
      rotation.duration = duration
      shading.duration = duration
      animation.timingFunction = CAMediaTimingFunction(name: .linear)
      face.add(animation, forKey: "selectionCylinder")
    }
  }

  private func rollDigits(from oldTitle: String, to newTitle: String) {
    guard canAnimate, bounds.width > 0, bounds.height > 0,
          let oldGlyphs = positionedGlyphs(in: oldTitle), let newGlyphs = positionedGlyphs(in: newTitle) else { return }
    let old = Dictionary(uniqueKeysWithValues: oldGlyphs.map { ($0.glyph.column, $0) })
    let new = Dictionary(uniqueKeysWithValues: newGlyphs.map { ($0.glyph.column, $0) })
    let columns = newGlyphs.map { $0.glyph.column } + oldGlyphs.map { $0.glyph.column }.filter { new[$0] == nil }
    let duration = AccessibilityPreferences.adjustedDuration(0.6)
    let height = preferredSize.height
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let drums = CALayer()
    drums.anchorPoint = NSPoint(x: 0, y: 0.5)
    drums.bounds = NSRect(x: 0, y: 0, width: max(textWidth(oldTitle), textWidth(newTitle)), height: height)
    drums.position = NSPoint(x: 0, y: height / 2)
    installRoll(drums)
    for key in columns {
      let previous = old[key], next = new[key]
      let glyph = next ?? previous!
      let column = CALayer()
      column.anchorPoint = NSPoint(x: 0, y: 0.5)
      column.bounds = NSRect(x: 0, y: 0, width: ceil(textWidth(glyph.glyph.text)), height: height)
      column.position = NSPoint(x: glyph.x, y: height / 2)
      column.masksToBounds = true
      drums.addSublayer(column)
      if let previous, let next, let path = ScrollSelectionDigitRoll.path(from: previous.glyph.text, to: next.glyph.text),
         path.titles.count > 1 {
        let faces = path.titles.compactMap(textLayer)
        guard faces.count == path.titles.count else {
          finishRoll()
          CATransaction.commit()
          return
        }
        let cylinder = CALayer()
        column.addSublayer(cylinder)
        animateCylinder(cylinder, faces: faces, direction: path.direction, duration: duration, continuous: true)
      } else if let face = textLayer(glyph.glyph.text) {
        face.anchorPoint = NSPoint(x: 0, y: 0.5)
        face.position = NSPoint(x: 0, y: height / 2)
        column.addSublayer(face)
      }
      if let previous, let next, previous.x != next.x {
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = previous.x
        slide.toValue = next.x
        slide.duration = duration
        slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        column.add(slide, forKey: "digitPosition")
      }
      if previous == nil || next == nil {
        column.opacity = next == nil ? 0 : 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = previous == nil ? 0 : 1
        fade.toValue = column.opacity
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        column.add(fade, forKey: "digitPresence")
      }
    }
    CATransaction.commit()
  }

  private func textWidth(_ text: String) -> CGFloat {
    (text as NSString).size(withAttributes: [.font: titleFont]).width
  }

  private func positionedGlyphs(in title: String) -> [(glyph: ScrollSelectionDigitRoll.Glyph, x: CGFloat)]? {
    guard let glyphs = ScrollSelectionDigitRoll.glyphs(in: title) else { return nil }
    var x: CGFloat = 0
    return glyphs.map { glyph in
      defer { x += textWidth(glyph.text) }
      return (glyph, x)
    }
  }

  private func textLayer(_ title: String) -> CALayer? {
    let scale = window?.backingScaleFactor ?? 2
    let width = max(1, ceil((title as NSString).size(withAttributes: [.font: titleFont]).width))
    let height = preferredSize.height
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
      pixelsWide: Int(ceil(width * scale)), pixelsHigh: Int(ceil(height * scale)),
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: scale, y: scale)
    effectiveAppearance.performAsCurrentDrawingAppearance {
      let attributes: [NSAttributedString.Key: Any] = [
        .font: titleFont, .foregroundColor: isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor
      ]
      let size = (title as NSString).size(withAttributes: attributes)
      (title as NSString).draw(at: NSPoint(x: 0, y: (height - size.height) / 2), withAttributes: attributes)
    }
    NSGraphicsContext.restoreGraphicsState()
    let face = CALayer()
    face.bounds = NSRect(x: 0, y: 0, width: width, height: height)
    face.contents = bitmap.cgImage
    face.contentsScale = scale
    return face
  }

  override func scrollWheel(with event: NSEvent) {
    guard isEnabled else { return }
    // Momentum belongs to the gesture that already selected a panel.
    guard event.momentumPhase.isEmpty else { return }
    if event.phase.contains(.began) ||
      (event.phase.isEmpty && lastEventTime.map({ event.timestamp - $0 > 0.25 }) != false) {
      accumulatedDelta = 0
      didSwitchInGesture = false
    }
    lastEventTime = event.timestamp
    if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
      accumulatedDelta = 0
      didSwitchInGesture = false
      return
    }
    let delta = event.scrollingDeltaY
    guard abs(delta) > abs(event.scrollingDeltaX) else { return }
    if event.hasPreciseScrollingDeltas {
      guard !didSwitchInGesture else { return }
      accumulatedDelta += delta
      guard abs(accumulatedDelta) >= 12 else { return }
      didSwitchInGesture = true
      switchSelection?(accumulatedDelta < 0 ? 1 : -1)
    } else if delta != 0 {
      switchSelection?(delta < 0 ? 1 : -1)
    }
  }
}
