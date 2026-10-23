//
//  FloatingOSCScale.swift
//  iina
//

import AppKit

/// Scale against full window content, before subtracting sidebar widths.
enum FloatingOSCScale {
  static let minimum: CGFloat = 0.8
  static let maximum: CGFloat = 1

  static let compactContentSize = NSSize(width: 450, height: 250)
  static let comfortableContentSize = NSSize(width: 900, height: 500)

  static func factor(for contentSize: NSSize) -> CGFloat {
    guard contentSize.width.isFinite, contentSize.height.isFinite,
          contentSize.width > 0, contentSize.height > 0 else { return minimum }
    let widthProgress = (contentSize.width - compactContentSize.width)
      / (comfortableContentSize.width - compactContentSize.width)
    let heightProgress = (contentSize.height - compactContentSize.height)
      / (comfortableContentSize.height - compactContentSize.height)
    let progress = max(0, min(1, min(widthProgress, heightProgress)))
    return minimum + (maximum - minimum) * progress
  }
}

struct FloatingOSCReturnCurve {
  let overshootRatio: CGFloat
  private let tension: CGFloat
  private let crossingPoint: CGFloat
  private let turningPoint: CGFloat
  private let stretchTime: CGFloat
  private static let launch: CGFloat = 3
  private static let stretchExtension: CGFloat = 0.12
  private static let settlingExtension: CGFloat = 0.08

  static func duration(for distance: CGFloat) -> TimeInterval {
    0.75 * (0.36 + min(0.30, Double(distance) / 2200))
      * Double(1 + stretchExtension + settlingExtension)
  }

  init(overshootRatio: CGFloat) {
    self.overshootRatio = overshootRatio
    // Zero overshoot must not reverse the trajectory.
    guard overshootRatio > 0 else {
      tension = 10 - Self.launch
      crossingPoint = 1
      turningPoint = 1
      stretchTime = 0
      return
    }
    // Fit the derivative's single positive turning point to the available stretch without clipping.
    var lower: CGFloat = 10 - Self.launch
    var upper: CGFloat = 40
    for _ in 0..<16 {
      let weight = (lower + upper) / 2
      let peak = Self.turningPoint(for: weight)
      if Self.value(at: peak, tension: weight) > 1 + overshootRatio {
        upper = weight
      } else {
        lower = weight
      }
    }
    tension = (lower + upper) / 2
    turningPoint = Self.turningPoint(for: tension)
    lower = 0
    upper = turningPoint
    for _ in 0..<20 {
      let phase = (lower + upper) / 2
      if Self.value(at: phase, tension: tension) < 1 { lower = phase }
      else { upper = phase }
    }
    crossingPoint = (lower + upper) / 2
    stretchTime = min(Self.stretchExtension, turningPoint - crossingPoint)
  }

  func value(at progress: CGFloat) -> CGFloat {
    guard progress > 0 else { return 0 }
    guard progress < 1 else { return 1 }
    // Extend time only after target crossing; launch speed and overshoot amplitude must stay unchanged.
    var phase = progress * (1 + Self.stretchExtension + Self.settlingExtension)
    if stretchTime > 0, phase > crossingPoint {
      if phase < turningPoint + stretchTime {
        let elapsed = phase
        var lower = crossingPoint
        var upper = turningPoint
        for _ in 0..<20 {
          let candidate = (lower + upper) / 2
          let u = (candidate - crossingPoint) / (turningPoint - crossingPoint)
          // Quintic timing keeps speed and acceleration continuous at the flight/rebound joins.
          let offset = u * u * u * (10 + u * (-15 + 6 * u))
          if candidate + stretchTime * offset < elapsed { lower = candidate }
          else { upper = candidate }
        }
        phase = (lower + upper) / 2
      } else {
        phase -= stretchTime
      }
    }
    guard phase < 1 + Self.settlingExtension else { return 1 }
    if phase > turningPoint, turningPoint < 1 {
      let remaining = 1 - turningPoint
      let settlingDuration = remaining + Self.settlingExtension
      let settled = (phase - turningPoint) / settlingDuration
      // Unit phase speed at the turn and zero at rest preserve the curve's velocity/acceleration joins.
      phase = 1 - remaining * pow(1 - settled, settlingDuration / remaining)
    }
    return Self.value(at: min(1, phase), tension: tension)
  }

  private static func turningPoint(for tension: CGFloat) -> CGFloat {
    let b = 30 - 5 * launch + 3 * tension
    return (b + sqrt(b * b + 48 * tension * launch)) / (12 * tension)
  }

  private static func value(at t: CGFloat, tension: CGFloat) -> CGFloat {
    let remaining = 1 - t
    // Endpoint velocity is zero; final acceleration also settles to zero.
    return t * t * (t * (10 + t * (-15 + 6 * t)) +
      (launch + tension * t) * remaining * remaining * remaining)
  }
}

/// Each axis uses its own clearance; a crowded axis must not suppress the other's overshoot.
struct FloatingOSCReturnPath {
  private let origin: CGPoint
  private let delta: CGPoint
  private let horizontal: FloatingOSCReturnCurve
  private let vertical: FloatingOSCReturnCurve

  init(from origin: CGPoint, to target: CGPoint,
       horizontalRange: ClosedRange<CGFloat>, verticalRange: ClosedRange<CGFloat>) {
    self.origin = origin
    delta = CGPoint(x: target.x - origin.x, y: target.y - origin.y)
    let distance = hypot(delta.x, delta.y)
    let stretchRatio = distance > 0 ? min(0.20, 96 / distance) : 0
    func curve(travel: CGFloat, end: CGFloat, bounds: ClosedRange<CGFloat>) -> FloatingOSCReturnCurve {
      let desired = abs(travel) * stretchRatio
      let room = max(0, travel > 0 ? bounds.upperBound - end : end - bounds.lowerBound)
      let extra = min(desired, room)
      // A few pixels of rebound after a long flight look like a shake.
      let meaningful = extra >= max(12, desired * 0.4)
      return FloatingOSCReturnCurve(overshootRatio: meaningful ? extra / abs(travel) : 0)
    }
    horizontal = curve(travel: delta.x, end: target.x, bounds: horizontalRange)
    vertical = curve(travel: delta.y, end: target.y, bounds: verticalRange)
  }

  func position(at progress: CGFloat) -> CGPoint {
    CGPoint(x: origin.x + delta.x * horizontal.value(at: progress),
            y: origin.y + delta.y * vertical.value(at: progress))
  }
}

enum FloatingOSCMetrics {
  static let preferredWidth: CGFloat = 460
  static let minimumWindowSize = NSSize(width: 400, height: 225)
  static let topInset: CGFloat = 14
  static let compactTopInset: CGFloat = 10
  static let sideInset: CGFloat = 12
  static let bottomInset: CGFloat = 8
  static let compactBottomInset: CGFloat = 5
  static let timelineInset: CGFloat = 8
  static let rowGap: CGFloat = 8
  static let controlHeight: CGFloat = 24
  static let sliderVerticalInset: CGFloat = 6

  static func panelSize(scale: CGFloat, compact: Bool, sliderHeight: CGFloat) -> NSSize {
    let padding = (compact ? compactTopInset : topInset) + controlHeight + rowGap
      + (compact ? compactBottomInset : bottomInset)
    return NSSize(width: preferredWidth * scale, height: padding * scale + sliderHeight + 2 * sliderVerticalInset)
  }

}

/// Explicit per-axis units. Percent values use 0...1; point values measure
/// panel-edge to usable-window-edge distance. Near means left/top, far right/bottom.
struct FloatingOSCPosition: Equatable {
  enum Unit: Int { case percent, point }
  enum Edge: Int { case near, far }
  struct Axis: Equatable {
    var value: CGFloat
    var unit: Unit = .percent
    var edge: Edge = .near
  }
  var horizontal: Axis
  var vertical: Axis
  static let initial = FloatingOSCPosition(horizontal: Axis(value: 0.5),
    vertical: Axis(value: 16, unit: .point, edge: .far))
  static func percentages(_ x: CGFloat, _ y: CGFloat) -> FloatingOSCPosition {
    FloatingOSCPosition(horizontal: Axis(value: x), vertical: Axis(value: y))
  }
  var dictionary: [String: Any] {
    func encode(_ axis: Axis) -> [String: Any] {
      ["value": Double(axis.value), "unit": axis.unit.rawValue, "edge": axis.edge.rawValue]
    }
    return ["version": 2, "horizontal": encode(horizontal), "vertical": encode(vertical)]
  }
  init(horizontal: Axis, vertical: Axis) { self.horizontal = horizontal; self.vertical = vertical }
  init?(dictionary: [String: Any]) {
    func decode(_ value: Any?) -> Axis? {
      guard let data = value as? [String: Any], let number = data["value"] as? Double,
            let unitRaw = data["unit"] as? Int, let unit = Unit(rawValue: unitRaw),
            let edgeRaw = data["edge"] as? Int, let edge = Edge(rawValue: edgeRaw),
            number.isFinite, number >= 0, number <= (unit == .percent ? 1 : 100000) else { return nil }
      return Axis(value: CGFloat(number), unit: unit, edge: edge)
    }
    guard let version = dictionary["version"] as? Int, [1, 2].contains(version),
          let x = decode(dictionary["horizontal"]), let y = decode(dictionary["vertical"]) else { return nil }
    // Version 1 ignored percent edges and always measured from left/top.
    var horizontal = x
    var vertical = y
    if version == 1 {
      if horizontal.unit == .percent { horizontal.edge = .near }
      if vertical.unit == .percent { vertical.edge = .near }
    }
    self.init(horizontal: horizontal, vertical: vertical)
  }
}

/// Placement uses physical edges, independent of interface direction.
struct FloatingOSCPlacement {
  static func gapRatio(gap: CGFloat, available: CGFloat, fallback: CGFloat = 0.5) -> CGFloat {
    guard available > 0 else { return fallback }
    return (gap / available).clamped(to: 0...1)
  }

  static func verticalRange(height: CGFloat, windowHeight: CGFloat,
                            titlebarBottom: CGFloat?, margin: CGFloat = 16) -> ClosedRange<CGFloat> {
    let top = min(windowHeight, max(0, titlebarBottom ?? windowHeight))
    let upper = max(0, top - height - margin)
    return min(margin, upper)...upper
  }

  static let defaultMargin: CGFloat = 16
  static let sidebarMargin: CGFloat = 6

  static func horizontalRange(width: CGFloat, windowWidth: CGFloat,
                              margin: CGFloat = defaultMargin) -> ClosedRange<CGFloat> {
    let available = max(0, windowWidth - width)
    let inset = min(margin, available / 2)
    return inset...max(inset, available - inset)
  }

  /// Nil preserves X while vertical dragging remains available: the OSC cannot fit beside the sidebars.
  static func horizontalDragRange(width: CGFloat, windowWidth: CGFloat,
                                  leftSidebar: CGFloat, rightSidebar: CGFloat) -> ClosedRange<CGFloat>? {
    let physical = horizontalRange(width: width, windowWidth: windowWidth)
    let lower = max(physical.lowerBound, leftSidebar > 0 ? leftSidebar + sidebarMargin : physical.lowerBound)
    let upper = min(physical.upperBound, rightSidebar > 0 ? windowWidth - rightSidebar - sidebarMargin - width : physical.upperBound)
    return lower <= upper ? lower...upper : nil
  }

  /// Percentages divide the safe travel range after subtracting the panel size.
  /// X runs physically left to right; Y runs top to bottom, independent of RTL.
  static func defaultFrame(horizontal: CGFloat, vertical: CGFloat, size: NSSize,
                           contentSize: NSSize, titlebarBottom: CGFloat?,
                           margin: CGFloat = defaultMargin, verticalMargin: CGFloat = 0) -> NSRect {
    let xRange = horizontalRange(width: size.width, windowWidth: contentSize.width, margin: margin)
    let yRange = verticalRange(height: size.height, windowHeight: contentSize.height,
                               titlebarBottom: titlebarBottom, margin: verticalMargin)
    return NSRect(x: xRange.lowerBound + (xRange.upperBound - xRange.lowerBound) * horizontal.clamped(to: 0...1),
                  y: yRange.upperBound - (yRange.upperBound - yRange.lowerBound) * vertical.clamped(to: 0...1),
                  width: size.width, height: size.height)
  }

  /// A collapsed axis cannot reveal position intent; retain its supplied fallback.
  static func defaultPosition(frame: NSRect, contentSize: NSSize, titlebarBottom: CGFloat?,
                              fallback: NSPoint, margin: CGFloat = defaultMargin, verticalMargin: CGFloat = 0) -> NSPoint {
    let xRange = horizontalRange(width: frame.width, windowWidth: contentSize.width, margin: margin)
    let yRange = verticalRange(height: frame.height, windowHeight: contentSize.height,
                               titlebarBottom: titlebarBottom, margin: verticalMargin)
    return NSPoint(x: gapRatio(gap: frame.minX - xRange.lowerBound,
                              available: xRange.upperBound - xRange.lowerBound, fallback: fallback.x),
                   y: gapRatio(gap: yRange.upperBound - frame.minY,
                               available: yRange.upperBound - yRange.lowerBound, fallback: fallback.y))
  }

  static func frame(position: FloatingOSCPosition, size: NSSize, contentSize: NSSize,
                    titlebarBottom: CGFloat?, pointScale: CGFloat = 1) -> NSRect {
    let xRange = horizontalRange(width: size.width, windowWidth: contentSize.width,
                                margin: defaultMargin * pointScale)
    let yRange = verticalRange(height: size.height, windowHeight: contentSize.height,
                              titlebarBottom: titlebarBottom, margin: 0)
    let x = position.horizontal
    let y = position.vertical
    let top = min(contentSize.height, max(0, titlebarBottom ?? contentSize.height))
    let originX = x.unit == .percent ? xRange.lowerBound + (xRange.upperBound - xRange.lowerBound) * (x.edge == .near ? x.value : 1 - x.value) :
      (x.edge == .near ? x.value * pointScale : contentSize.width - size.width - x.value * pointScale)
    let originY = y.unit == .percent ? yRange.upperBound - (yRange.upperBound - yRange.lowerBound) * (y.edge == .near ? y.value : 1 - y.value) :
      (y.edge == .near ? top - size.height - y.value * pointScale : y.value * pointScale)
    return NSRect(x: originX.clamped(to: xRange), y: originY.clamped(to: yRange), width: size.width, height: size.height)
  }

  /// Collapsed travel cannot determine intent; keep the previous value for that axis.
  static func capturing(frame: NSRect, keeping previous: FloatingOSCPosition, contentSize: NSSize,
                        titlebarBottom: CGFloat?, pointScale: CGFloat = 1) -> FloatingOSCPosition {
    var result = previous
    let xRange = horizontalRange(width: frame.width, windowWidth: contentSize.width,
                                margin: defaultMargin * pointScale)
    let yRange = verticalRange(height: frame.height, windowHeight: contentSize.height,
                              titlebarBottom: titlebarBottom, margin: 0)
    let fractions = defaultPosition(frame: frame, contentSize: contentSize,
      titlebarBottom: titlebarBottom, fallback: NSPoint(x: previous.horizontal.value, y: previous.vertical.value),
      margin: defaultMargin * pointScale)
    let top = min(contentSize.height, max(0, titlebarBottom ?? contentSize.height))
    if xRange.upperBound > xRange.lowerBound {
      result.horizontal.value = previous.horizontal.unit == .percent ? (previous.horizontal.edge == .near ? fractions.x : 1 - fractions.x) :
        max(0, previous.horizontal.edge == .near ? frame.minX : contentSize.width - frame.maxX) / pointScale
    }
    if yRange.upperBound > yRange.lowerBound {
      result.vertical.value = previous.vertical.unit == .percent ? (previous.vertical.edge == .near ? fractions.y : 1 - fractions.y) :
        max(0, previous.vertical.edge == .near ? top - frame.maxY : frame.minY) / pointScale
    }
    return result
  }

  static func center(preferred: CGFloat, width: CGFloat, windowWidth: CGFloat,
                     leftSidebar: CGFloat, rightSidebar: CGFloat, margin: CGFloat = 10) -> CGFloat {
    let half = min(width, windowWidth) / 2
    let edgeMargin = min(margin, max(0, (windowWidth - width) / 2))
    let physical = (half + edgeMargin)...max(half + edgeMargin, windowWidth - half - edgeMargin)
    let original = preferred.clamped(to: physical)
    let left = max(0, leftSidebar)
    let right = max(0, rightSidebar)
    guard (left > 0 && original - half < left + sidebarMargin) ||
            (right > 0 && original + half > windowWidth - right - sidebarMargin) else { return original }
    let lower = max(physical.lowerBound, left > 0 ? left + sidebarMargin + half : physical.lowerBound)
    let upper = min(physical.upperBound, right > 0 ? windowWidth - right - sidebarMargin - half : physical.upperBound)
    // Keep the gap until the physical edge stops the OSC; dropping it causes a jump.
    if right == 0 { return max(original, lower).clamped(to: physical) }
    if left == 0 { return min(original, upper).clamped(to: physical) }
    if lower <= upper { return original.clamped(to: lower...upper) }
    let availableMargin = max(0, min(sidebarMargin,
      (windowWidth - left - right - 2 * half) / 2,
      physical.upperBound - left - half,
      windowWidth - right - half - physical.lowerBound))
    let tightLower = max(physical.lowerBound, left + half + availableMargin)
    let tightUpper = min(physical.upperBound, windowWidth - right - half - availableMargin)
    if tightLower <= tightUpper { return original.clamped(to: tightLower...tightUpper) }

    // Center the remaining corridor so unequal sidebars share unavoidable overlap equally.
    return ((left + windowWidth - right) / 2).clamped(to: physical)
  }
}

/// Anchored groups avoid NSStackView's stale gravity geometry during live resize.
final class FloatingOSCControlsView: NSView {
  private let volume: NSView
  private let playback: NSStackView
  private let toolbar: NSStackView
  private var rowConstraints: [NSLayoutConstraint] = []
  private var volumeWidth: NSLayoutConstraint!
  private var volumeHeight: NSLayoutConstraint!
  private var toolbarWidth: NSLayoutConstraint!
  private var playbackWidth: NSLayoutConstraint!
  private var rowHeight: NSLayoutConstraint!

  init(volume: NSView, playback: NSStackView, toolbar: NSStackView, speedLabels: [NSView],
       scale: CGFloat, buttonCount: Int) {
    self.volume = volume
    self.playback = playback
    self.toolbar = toolbar
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    [volume, playback, toolbar].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      addSubview($0)
    }
    volumeWidth = volume.widthAnchor.constraint(equalToConstant: 108 * scale)
    volumeHeight = volume.heightAnchor.constraint(equalToConstant: 24 * scale)
    toolbarWidth = toolbar.widthAnchor.constraint(equalToConstant: CGFloat(buttonCount) * 24 * scale)
    playbackWidth = playback.widthAnchor.constraint(equalToConstant: 180 * scale)
    rowHeight = heightAnchor.constraint(equalToConstant: 24 * scale)
    rowConstraints = [
      volume.leadingAnchor.constraint(equalTo: leadingAnchor),
      toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
      playback.centerXAnchor.constraint(equalTo: centerXAnchor),
      volume.centerYAnchor.constraint(equalTo: centerYAnchor),
      toolbar.centerYAnchor.constraint(equalTo: centerYAnchor),
      playback.centerYAnchor.constraint(equalTo: centerYAnchor),
      volumeWidth, volumeHeight, toolbarWidth, playbackWidth, rowHeight
    ]
    NSLayoutConstraint.activate(rowConstraints)
    speedLabels.forEach { playback.setVisibilityPriority(.mustHold, for: $0) }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func update(scale: CGFloat, buttonCount: Int) {
    volumeWidth.constant = 108 * scale
    volumeHeight.constant = 24 * scale
    toolbarWidth.constant = CGFloat(buttonCount) * 24 * scale
    playbackWidth.constant = 180 * scale
    rowHeight.constant = 24 * scale
    needsLayout = true
  }

  func detachControls() {
    // Child size constraints survive reparenting into a docked stack.
    NSLayoutConstraint.deactivate(rowConstraints)
    [volume, playback, toolbar].forEach { $0.isHidden = false; $0.removeFromSuperview() }
    removeFromSuperview()
  }
}
