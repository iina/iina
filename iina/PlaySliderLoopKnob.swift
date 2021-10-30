//
//  PlaySliderKnob.swift
//  iina
//
//  Created by low-batt on 10/14/21.
//  Copyright © 2021 lhc. All rights reserved.
//

import Cocoa

// These colors are for 10.13- only
@available(macOS, obsoleted: 10.14)
fileprivate extension NSColor {
  // Use different colors to distinguish loop knobs from the primary knob.
  static let darkKnobColor = NSColor(calibratedRed: 0.59, green: 0.59, blue: 0.59, alpha: 1)
  static let lightKnobColor = NSColor(calibratedRed: 0.35, green: 0.35, blue: 0.35, alpha: 1)
}

/// This class adds an additional thumb (knob) to a slider.
///
/// This class is used to add thumbs representing the A and B loop points of the [mpv](https://mpv.io/manual/stable/) A-B
/// loop feature when that feature is in use. When the feature is not being used the thumbs are hidden.
/// - Requires: The custom slider provided by `PlaySlider` must be used with this class.
/// - Note: This class is derived from `NSView` in part to gain support for help tags (tool tips).
final class PlaySliderLoopKnob: NSView {

  // Must accept first responder for help tags to work.
  override var acceptsFirstResponder: Bool { true }

  /// The location of this knob as a slider value which is always greater than or equal to the slider's `minValue` and less than or equal
  /// to the slider's `maxValue`.
  var doubleValue: Double {
    get { value }
    set {
      value = constrainValue(newValue)
      // Move the knob to the position on the bar that represents the new value.
      moveKnob(to: computeX())
    }
  }

  var isDragging: Bool = false

  override var isFlipped: Bool {
    // Match the behavior of the slider and use a flipped coordinate system.
    get { slider.isFlipped }
  }

  // MARK:- Private Properties

  private var cell: PlaySliderCell!

  /// Number of points to add to the width of the knob's frame.
  ///
  /// If a user attempts to click on a loop knob but fails to put the cursor precisely on the loop knob, clicking will land on the slider
  /// which moves the primary knob. Since the small size of the knobs makes this an easy mistake to make, the width of the frame of
  /// loop knobs is sightly increased over the width of the primary knob to mitigate the problem of unintentional movement of the
  /// primary knob. Loop knobs are still drawn with the same width as the primary knob.
  private static let frameWidthAdjustment: CGFloat = 2

  /// Number of points to offset X coordinate by due to enlargement of the frame.
  private static let xAdjustment = frameWidthAdjustment / 2

  private let knobHeight: CGFloat
  
  /// Percentage of the height of the primary knob to use for the loop knobs when drawing.
  ///
  /// The height of loop knobs is reduced in order to give prominence to the primary knob.
  private static let knobHeightAdjustment: CGFloat = 0.75

  // The X coordinate of the last mouse location when dragging.
  private var lastDragLocation: CGFloat = 0

  private var slider: PlaySlider!

  private var value: Double = 0

  /// The knob's x coordinate calculated based on the value.
  private var x: CGFloat {
    get {
      let valueToX = computeX()
      // If the size of the slider bar has changed the knob will no longer be in the correct
      // position and will need to be moved.
      if frame.origin.x != valueToX {
        moveKnob(to: valueToX)
      }
      return valueToX
    }
    set {
      let constrainedX = constrainX(newValue)
      // Calculate the value selected by the new location.
      let bar = cell.barRect(flipped: isFlipped)
      // The knob is not allowed to slide past the end of the bar, so the usable width is reduced.
      let effectiveWidth = bar.width - cell.knobWidth
      // The knob's frame is larger than the drawn knob. Adjust x to start of drawn knob.
      let percentage = Double((constrainedX + PlaySliderLoopKnob.xAdjustment) / effectiveWidth)
      value = constrainValue(percentage * slider.maxValue)
      moveKnob(to: constrainedX)
    }
  }

  // MARK:- Initialization

  /// Creates an additional thumb for the given
  /// [slider](https://developer.apple.com/design/human-interface-guidelines/macos/selectors/sliders/)
  /// - Parameters:
  ///   - slider: The slider this thumb belongs to.
  ///   - toolTip: The help tag to display for this thumb.
  init(slider: PlaySlider, toolTip: String) {
    self.slider = slider
    self.cell = slider.customCell
    // We want loop knobs to be shorter than the primary knob.
    knobHeight = round(cell.knobHeight * PlaySliderLoopKnob.knobHeightAdjustment)
    // The frame is calculated and set once the superclass is initialized.
    super.init(frame: NSZeroRect)
    self.toolTip = toolTip
    // This knob is hidden unless the mpv A-B loop feature is activated.
    isHidden = true
    let rect = knobRect()
    setFrameOrigin(NSPoint(x: rect.origin.x, y: rect.origin.y))
    setFrameSize(NSSize(width: rect.width, height: rect.height))
    slider.addSubview(self)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func constrainValue(_ value: Double) -> Double {
    return value.clamped(to: cell.minValue...cell.maxValue)
  }

  /// Constrain the x coordinate to insure the knob stays within the bar.
  /// - Parameter x: The proposed x coordinate.
  /// - Returns: The given x coordinate constrained to keep the knob within the bar.
  private func constrainX(_ x: CGFloat) -> CGFloat {
    let bar = cell.barRect(flipped: isFlipped)
    // The knob's frame is larger than the drawn knob so the frame can start before the bar and the
    // knob will still be contained within the bar.
    let minX = bar.minX - PlaySliderLoopKnob.xAdjustment
    // The coordinate must be short of the end of the bar to keep the knob within the bar.
    let maxX = bar.maxX - cell.knobWidth - PlaySliderLoopKnob.xAdjustment
    return x.clamped(to: minX...maxX)
  }

  /// Compute the position of the knob on the bar that represents the current value.
  /// - Returns: The x coordinate to use for the knob's frame.
  private func computeX() -> CGFloat {
    let percentage = CGFloat(value / slider.maxValue)
    let bar = cell.barRect(flipped: isFlipped)
    // The knob is not allowed to slide past the end of the bar, so the usable width is reduced.
    let effectiveWidth = bar.width - cell.knobWidth
    // The knob's frame is larger than the drawn knob, offset the frame location accordingly.
    return constrainX(percentage * effectiveWidth - PlaySliderLoopKnob.xAdjustment)
  }

  // MARK:- Drawing

  private func knobColor() -> NSColor {
    // Starting with macOS Mojave 10.14 colors can be configured to automatically adjust for the
    // current appearance.
    if #available(macOS 10.14, *) {
      return NSColor(named: .mainSliderLoopKnob)!
    } else {
      return slider.window!.effectiveAppearance.isDark ? .darkKnobColor : .lightKnobColor
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    guard !isHiddenOrHasHiddenAncestor else { return }
    let rect = knobRect()
    // The frame is taller than the drawn knob. Adjust the y coordinate accordingly.
    let adjustedY = rect.origin.y + (rect.height - knobHeight) / 2
    // The frame is wider than the drawn knob. Adjust the x coordinate accordingly.
    let adjustedX = rect.origin.x + PlaySliderLoopKnob.xAdjustment
    let drawing = NSMakeRect(adjustedX, adjustedY, cell.knobWidth, knobHeight)
    let path = NSBezierPath(roundedRect: drawing, xRadius: cell.knobRadius, yRadius: cell.knobRadius)
    knobColor().setFill()
    path.fill()
  }

  private func knobRect() -> NSRect {
    let rect = cell.knobRect(flipped: isFlipped)
    // The frame of a loop knob is larger than the drawn knob to make it easier to click on.
    return NSMakeRect(x, rect.origin.y, rect.width + PlaySliderLoopKnob.frameWidthAdjustment, rect.height)
  }

  // MARK:- Mouse Events

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    // Match the behavior of the slider and respond to click-throughs.
    slider.acceptsFirstMouse(for: event)
  }

  /// Begin dragging the knob.
  ///
  /// - Important: The method `mouseDown` is not overriden in order to allow `PlaySlider` to give preference to the primary
  ///     knob when the knobs are overlapping
  /// - Parameter event: An object encapsulating information about the mouse-down event initiating the drag.
  func beginDragging(with event: NSEvent) {
    let clickLocation = slider.convert(event.locationInWindow, from: nil)
    lastDragLocation = constrainX(clickLocation.x)
    isDragging = true
  }

  override func mouseDragged(with event: NSEvent) {
    let newDragLocation = slider.convert(event.locationInWindow, from: nil)
    x = frame.origin.x + newDragLocation.x - lastDragLocation
    lastDragLocation = constrainX(newDragLocation.x)
    NotificationCenter.default.post(Notification(name: .iinaPlaySliderLoopKnobChanged, object: self))
  }

  override func mouseUp(with event: NSEvent) {
    isDragging = false
  }

  private func moveKnob(to x: CGFloat) {
    setFrameOrigin(NSPoint(x: x, y: frame.origin.y))
    slider.needsDisplay = true
  }
}
