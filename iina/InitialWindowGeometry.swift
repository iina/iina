import Foundation
import CoreGraphics

/// Preview coordinates are relative to a display's visibleFrame.
struct InitialWindowGeometry {
  enum SizeDimension: Int { case width = 0, height = 1 }
  enum Unit: Int { case points = 0, percent = 1 }
  enum HorizontalAnchor: Int { case left = 0, right = 1 }
  enum VerticalAnchor: Int { case top = 0, bottom = 1 }

  var sizeEnabled = false
  var positionEnabled = false
  var sizeDimension = SizeDimension.width
  var sizeValue = 40
  var sizeUnit = Unit.percent
  var independentSize = false
  var otherSizeValue: Int?
  var otherSizeUnit = Unit.percent
  var widthValue: Int {
    get { sizeDimension == .width ? sizeValue : otherSizeValue ?? 0 }
    set { if sizeDimension == .width { sizeValue = newValue } else { otherSizeValue = newValue } }
  }
  var heightValue: Int {
    get { sizeDimension == .height ? sizeValue : otherSizeValue ?? 0 }
    set { if sizeDimension == .height { sizeValue = newValue } else { otherSizeValue = newValue } }
  }
  var widthUnit: Unit {
    get { sizeDimension == .width ? sizeUnit : otherSizeUnit }
    set { if sizeDimension == .width { sizeUnit = newValue } else { otherSizeUnit = newValue } }
  }
  var heightUnit: Unit {
    get { sizeDimension == .height ? sizeUnit : otherSizeUnit }
    set { if sizeDimension == .height { sizeUnit = newValue } else { otherSizeUnit = newValue } }
  }
  var xAnchor = HorizontalAnchor.left
  var xValue = 50
  var xUnit = Unit.percent
  var yAnchor = VerticalAnchor.top
  var yValue = 50
  var yUnit = Unit.percent

  private let original: String
  private var originalSize = ""
  private var originalSizeToken: String?
  private var originalPosition = ""
  private var initialSize: SizeState!
  private var initialPosition: PositionState!

  private struct SizeState: Equatable {
    let enabled: Bool
    let dimension: SizeDimension
    let value: Int
    let unit: Unit
    let independent: Bool
    let otherValue: Int?
    let otherUnit: Unit
  }

  private struct PositionState: Equatable {
    let enabled: Bool
    let xAnchor: HorizontalAnchor
    let xValue: Int
    let xUnit: Unit
    let yAnchor: VerticalAnchor
    let yValue: Int
    let yUnit: Unit
  }

  private var sizeState: SizeState {
    SizeState(enabled: sizeEnabled, dimension: sizeDimension, value: sizeValue, unit: sizeUnit,
              independent: independentSize, otherValue: otherSizeValue, otherUnit: otherSizeUnit)
  }

  private var positionState: PositionState {
    PositionState(enabled: positionEnabled, xAnchor: xAnchor, xValue: xValue, xUnit: xUnit,
                  yAnchor: yAnchor, yValue: yValue, yUnit: yUnit)
  }

  init(_ raw: String) {
    original = raw
    if let parsed = GeometryDef.parse(raw),
       [parsed.w, parsed.h, parsed.x, parsed.y].compactMap({ $0 }).allSatisfy({ Self.amount($0) != nil }) {
      originalSize = (parsed.w ?? "") + (parsed.h.map { "x" + $0 } ?? "")
      if let width = parsed.w, width != "0" || parsed.h == nil {
        sizeEnabled = true
        sizeDimension = .width
        sizeValue = Self.amount(width)!
        sizeUnit = width.hasSuffix("%") ? .percent : .points
        originalSizeToken = width
      } else if let height = parsed.h {
        sizeEnabled = true
        sizeDimension = .height
        sizeValue = Self.amount(height)!
        sizeUnit = height.hasSuffix("%") ? .percent : .points
        originalSizeToken = height
      }
      if let width = parsed.w, let height = parsed.h, width != "0", height != "0" {
        independentSize = true
        let other = sizeDimension == .width ? height : width
        otherSizeValue = Self.amount(other)
        otherSizeUnit = other.hasSuffix("%") ? .percent : .points
      }
      if let x = parsed.x, let y = parsed.y, let xSign = parsed.xSign, let ySign = parsed.ySign {
        positionEnabled = true
        xAnchor = xSign == "+" ? .left : .right
        xValue = Self.amount(x)!
        xUnit = x.hasSuffix("%") ? .percent : .points
        yAnchor = ySign == "+" ? .bottom : .top
        yValue = Self.amount(y)!
        yUnit = y.hasSuffix("%") ? .percent : .points
        originalPosition = xSign + x + ySign + y
      }
    }
    initialSize = sizeState
    initialPosition = positionState
  }

  var geometryString: String {
    if sizeState == initialSize && positionState == initialPosition { return original }
    let size: String
    if !sizeEnabled {
      size = ""
    } else if sizeState == initialSize {
      size = originalSize
    } else if independentSize, let otherSizeValue {
      let primary = Self.token(sizeValue, sizeUnit)
      let secondary = Self.token(otherSizeValue, otherSizeUnit)
      size = sizeDimension == .width ? primary + "x" + secondary : secondary + "x" + primary
    } else {
      size = (sizeDimension == .height ? "x" : "") + Self.token(sizeValue, sizeUnit)
    }
    let position: String
    if !positionEnabled {
      position = ""
    } else if positionState == initialPosition {
      position = originalPosition
    } else {
      position = (xAnchor == .left ? "+" : "-") + Self.token(xValue, xUnit)
        + (yAnchor == .bottom ? "+" : "-") + Self.token(yValue, yUnit)
    }
    return size + position
  }

  mutating func prepareIndependentSize(screenSize: NSSize, aspect: CGFloat,
                                       minimumSize: NSSize = AppData.mainWindowMinSize,
                                       enforceMinimumAfterScreenFit: Bool = false) {
    if otherSizeValue == nil {
      var proportional = self
      proportional.independentSize = false
      proportional.sizeEnabled = true
      let frame = proportional.previewFrame(screenSize: screenSize, aspect: aspect, minimumSize: minimumSize,
                                             enforceMinimumAfterScreenFit: enforceMinimumAfterScreenFit)
      let value = sizeDimension == .width ? frame.height : frame.width
      let extent = sizeDimension == .width ? screenSize.height : screenSize.width
      otherSizeUnit = sizeUnit
      otherSizeValue = Self.rounded(otherSizeUnit == .percent ? value / max(1, extent) * 100 : value)
    }
    independentSize = true
  }

  func previewFrame(screenSize: NSSize, aspect: CGFloat = 16 / 9,
                    minimumSize: NSSize = AppData.mainWindowMinSize,
                    enforceMinimumAfterScreenFit: Bool = false) -> NSRect {
    guard screenSize.width.isFinite, screenSize.height.isFinite,
          screenSize.width > 0, screenSize.height > 0 else { return .zero }
    let ratio = aspect.isFinite && aspect > 0 ? aspect : 16 / 9
    var size = NSSize(width: max(minimumSize.width, screenSize.width * 0.5), height: 0)
    size.height = size.width / ratio
    if sizeEnabled && (sizeValue != 0 || sizeUnit == .percent
                       || (sizeState == initialSize && originalSizeToken != "0")) {
      if sizeDimension == .width {
        size.width = max(minimumSize.width,
                         Self.distance(sizeValue, sizeUnit, screenSize.width))
        size.height = size.width / ratio
      } else {
        size.height = max(minimumSize.height,
                          Self.distance(sizeValue, sizeUnit, screenSize.height))
        size.width = size.height * ratio
      }
    }
    if sizeEnabled, independentSize, let otherSizeValue {
      if sizeDimension == .width {
        size.height = max(minimumSize.height, Self.distance(otherSizeValue, otherSizeUnit, screenSize.height))
      } else {
        size.width = max(minimumSize.width, Self.distance(otherSizeValue, otherSizeUnit, screenSize.width))
      }
    } else if enforceMinimumAfterScreenFit {
      size.width = max(size.width, minimumSize.width)
      size.height = max(size.height, minimumSize.height)
    } else {
      let growth = max(1, minimumSize.width / size.width, minimumSize.height / size.height)
      size.width *= growth
      size.height *= growth
    }
    if independentSize {
      size.width = min(size.width, screenSize.width)
      size.height = min(size.height, screenSize.height)
    } else {
      let scale = min(1, screenSize.width / size.width, screenSize.height / size.height)
      size.width *= scale
      size.height *= scale
    }
    if enforceMinimumAfterScreenFit {
      size.width = max(size.width, min(minimumSize.width, screenSize.width))
      size.height = max(size.height, min(minimumSize.height, screenSize.height))
    }
    var origin = NSPoint(x: (screenSize.width - size.width) / 2,
                         y: (screenSize.height - size.height) / 2)
    if positionEnabled {
      let x = Self.distance(xValue, xUnit, screenSize.width) - (xUnit == .percent ? size.width / 2 : 0)
      let y = Self.distance(yValue, yUnit, screenSize.height) - (yUnit == .percent ? size.height / 2 : 0)
      origin.x = xAnchor == .left ? x : screenSize.width - x - size.width
      origin.y = yAnchor == .bottom ? y : screenSize.height - y - size.height
    }
    origin.x = min(max(0, origin.x), screenSize.width - size.width)
    origin.y = min(max(0, origin.y), screenSize.height - size.height)
    return NSRect(origin: origin, size: size)
  }

  mutating func movePreview(to origin: NSPoint, screenSize: NSSize, windowSize: NSSize) {
    guard positionEnabled, screenSize.width > 0, screenSize.height > 0,
          screenSize.width.isFinite, screenSize.height.isFinite,
          origin.x.isFinite, origin.y.isFinite, windowSize.width.isFinite, windowSize.height.isFinite else { return }
    let x = xUnit == .percent ? origin.x + windowSize.width / 2 : origin.x
    let y = yUnit == .percent ? origin.y + windowSize.height / 2 : origin.y
    let xOffset = xAnchor == .left ? x : screenSize.width - x - (xUnit == .points ? windowSize.width : 0)
    let yOffset = yAnchor == .bottom ? y : screenSize.height - y - (yUnit == .points ? windowSize.height : 0)
    xValue = Self.roundedPosition(xUnit == .percent ? xOffset / screenSize.width * 100 : xOffset,
      origin: origin.x, travel: screenSize.width - windowSize.width, fromFarEdge: xAnchor == .right)
    yValue = Self.roundedPosition(yUnit == .percent ? yOffset / screenSize.height * 100 : yOffset,
      origin: origin.y, travel: screenSize.height - windowSize.height, fromFarEdge: yAnchor == .top)
  }

  mutating func resizePreview(to size: NSSize, screenSize: NSSize) {
    guard sizeEnabled, screenSize.width > 0, screenSize.height > 0,
          screenSize.width.isFinite, screenSize.height.isFinite,
          size.width.isFinite, size.height.isFinite else { return }
    let value = sizeDimension == .width ? size.width : size.height
    let extent = sizeDimension == .width ? screenSize.width : screenSize.height
    sizeValue = Self.rounded(sizeUnit == .percent ? value / extent * 100 : value)
    if independentSize {
      let other = sizeDimension == .width ? size.height : size.width
      let otherExtent = sizeDimension == .width ? screenSize.height : screenSize.width
      otherSizeValue = Self.rounded(otherSizeUnit == .percent ? other / otherExtent * 100 : other)
    }
  }

  private static func amount(_ token: String) -> Int? {
    Int(token.hasSuffix("%") ? String(token.dropLast()) : token)
  }

  private static func token(_ value: Int, _ unit: Unit) -> String {
    String(max(0, value)) + (unit == .percent ? "%" : "")
  }

  private static func distance(_ value: Int, _ unit: Unit, _ extent: CGFloat) -> CGFloat {
    CGFloat(max(0, value)) * (unit == .percent ? extent / 100 : 1)
  }

  private static func rounded(_ value: CGFloat) -> Int {
    guard value.isFinite else { return 0 }
    // CGFloat(Int.max) rounds upward on 64-bit platforms.
    return Int(min(max(0, value.rounded()), CGFloat(Int.max).nextDown))
  }

  private static func roundedPosition(_ value: CGFloat, origin: CGFloat, travel: CGFloat, fromFarEdge: Bool) -> Int {
    // Nearest rounding can move a boundary-touching frame inward; round toward the touched edge.
    if travel > 0.000001 {
      if origin <= 0.000001 { return rounded(value.rounded(fromFarEdge ? .up : .down)) }
      if origin >= travel - 0.000001 { return rounded(value.rounded(fromFarEdge ? .down : .up)) }
    }
    return rounded(value)
  }
}
