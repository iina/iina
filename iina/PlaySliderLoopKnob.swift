//
//  PlaySliderLoopKnob.swift
//  iina
//
//  Created by low-batt on 10/14/21.
//  Copyright © 2021 lhc. All rights reserved.
//

import Cocoa

/// This class adds an additional thumb (knob) to a slider.
///
/// This class is used to add thumbs representing the A and B loop points of the [mpv](https://mpv.io/manual/stable/) A-B
/// loop feature when that feature is in use. When the feature is not being used the thumbs are hidden.
/// - Requires: The custom slider provided by `PlaySlider` must be used with this class.
/// - Note: This class is derived from `NSView` in part to gain support for help tags (tool tips).
final class PlaySliderLoopKnob: NSView {

  /// The location of this knob as a slider value.
  ///
  /// The value is always greater than or equal to the slider's `minValue` and less than or equal to the slider's `maxValue`.
  var doubleValue: Double = 0 {
    didSet {
      doubleValue = doubleValue.clamped(to: slider.range)
      slider.needsDisplay = true
    }
  }

  /// A Boolean value indicating whether the view uses a flipped coordinate system.
  ///
  /// Knobs match the behavior of the slider.
  override var isFlipped: Bool { slider.isFlipped }

  // MARK:- Private Properties

  private var cell: PlaySliderCell!

  private let knobHeight: CGFloat
  
  /// Percentage of the height of the primary knob to use for the loop knobs when drawing.
  ///
  /// The height of loop knobs is reduced in order to give prominence to the slider's knob that controls the playback position.
  private static let knobHeightAdjustment: CGFloat = 0.75

  // The x coordinate of the last mouse location when dragging.
  private var lastDragLocation: CGFloat = 0

  private var slider: PlaySlider!

  /// The knob's x coordinate associated with the current value.
  ///
  /// The x coordinate is calculated based on the current knob value and the current usable width of the slider's bar. When the OSC's
  /// layout is set to `Bottom` or `Top` the width of the slider's bar will change with the width of the window. The width will also
  /// change if the user changes the OSC layout from either of those layouts to `Floating`. Thus the x coordinate can change even
  /// though the value has remained constant.
  private var x: CGFloat {
    get {
      let bar = cell.barRect(flipped: isFlipped)
      // The usable width of the bar is reduced by the width of the knob.
      let effectiveWidth = bar.width - cell.knobWidth
      let percentage = CGFloat(doubleValue / slider.span)
      let calculatedX = constrainX(bar.origin.x + percentage * effectiveWidth)
      setFrameOrigin(NSPoint(x: calculatedX, y: frame.origin.y))
      return calculatedX
    }
    set {
      let constrainedX = constrainX(newValue)
      // Calculate the value selected by the new location.
      let bar = cell.barRect(flipped: isFlipped)
      // The usable width of the bar is reduced by the width of the knob.
      let effectiveWidth = bar.width - cell.knobWidth
      let percentage = Double((constrainedX - bar.origin.x) / effectiveWidth)
      doubleValue = percentage * slider.span
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
    // Set the size of the frame to match the size of the slider's knob. The frame origin will be
    // adjusted when the knob is unhidden.
    let rect = cell.knobRect(flipped: isFlipped)
    setFrameSize(NSSize(width: rect.width, height: rect.height))
    slider.addSubview(self)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// Constrain the x coordinate to insure the knob stays within the bar.
  /// - Parameter x: The proposed x coordinate.
  /// - Returns: The given x coordinate constrained to keep the knob within the bar.
  private func constrainX(_ x: CGFloat) -> CGFloat {
    let bar = cell.barRect(flipped: isFlipped)
    // The coordinate must be short of the end of the bar to keep the knob within the bar.
    let maxX = bar.maxX - cell.knobWidth
    return x.clamped(to: bar.minX...maxX)
  }

  // MARK:- Drawing

  private func knobColor() -> NSColor {
    return NSColor(named: .mainSliderLoopKnob)!
  }

  /// Draw the knob.
  ///
  /// If IINA is running under macOS Ventura or earlier this method is called directly by `PlaySlider.draw`. This workaround
  /// requires this method to use the knob position within the slider as the x-coordinate when drawing. In macOS Sonoma
  /// [NSSlider](https://developer.apple.com/documentation/appkit/nsslider) changed and the workaround is no
  /// longer required and the drawing origin is relative to this view's frame. See `PlaySlider.draw` for more details.
  override func draw(_ dirtyRect: NSRect) {
    guard !isHiddenOrHasHiddenAncestor else { return }
    let rect = knobRect()
    // The frame is taller than the drawn knob. Adjust the y coordinate accordingly.
    let adjustedY = rect.origin.y + (rect.height - knobHeight) / 2
    let drawing: NSRect
    if #available(macOS 14, *) {
      drawing = NSMakeRect(0, adjustedY, cell.knobWidth, knobHeight)
    } else {
      // Round the X position for cleaner drawing
      drawing = NSMakeRect(round(rect.origin.x), adjustedY, cell.knobWidth, knobHeight)
    }
    let path = NSBezierPath(roundedRect: drawing, xRadius: cell.knobRadius, yRadius: cell.knobRadius)
    knobColor().setFill()
    path.fill()
  }

  private func knobRect() -> NSRect {
    let rect = cell.knobRect(flipped: isFlipped)
    return NSMakeRect(x, rect.origin.y, rect.width, rect.height)
  }

  // MARK:- Mouse Events

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    // Match the behavior of the slider and respond to click-throughs.
    slider.acceptsFirstMouse(for: event)
  }

  /// Begin dragging the knob.
  /// - Parameter event: An object encapsulating information about the mouse-down event initiating the drag.
  func beginDragging(with event: NSEvent) {
    let clickLocation = slider.convert(event.locationInWindow, from: nil)
    lastDragLocation = constrainX(clickLocation.x)
  }

  /// The user has pressed the left mouse button within the frame of this knob.
  ///
  /// When the slider knobs are overlapping we assume the user is trying to move the play knob rather than one of the loop knobs in
  /// order to avoid the user accidentally changing the loop points. The desired priority order for which knob is selected when they are
  /// overlapping is:
  /// - Play knob
  /// - B loop knob
  /// - A loop knob
  ///
  /// The order of slider subviews controls the order of the responder chain. That order is:
  /// - B loop knob
  /// - A loop knob
  /// - Play knob
  ///
  /// Thus the B loop knob is naturally given preference over the A loop knob, however to give priority to the play knob this method
  /// must specifically test to see if the click falls within the play knob and if so, pass the event up the responder chain.
  override func mouseDown(with event: NSEvent) {
    let clickLocation = slider.convert(event.locationInWindow, from: nil)
    // If this click lands on the play knob then pass the event up the responder chain.
    if isMousePoint(clickLocation, in: slider.customCell.knobRect(flipped: slider.isFlipped)) {
      super.mouseDown(with: event)
      return
    }
    // This loop knob will be hidden when this loop point is not active.
    if !isHidden && isMousePoint(clickLocation, in: frame) {
      beginDragging(with: event)
      return
    }
    super.mouseDown(with: event)
  }

  override func mouseDragged(with event: NSEvent) {
    let newDragLocation = slider.convert(event.locationInWindow, from: nil)
    x += newDragLocation.x - lastDragLocation
    lastDragLocation = constrainX(newDragLocation.x)
    NotificationCenter.default.post(Notification(name: .iinaPlaySliderLoopKnobChanged, object: self))
  }
}
