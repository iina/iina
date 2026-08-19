//
//  VolumeSlider.swift
//  iina
//
//  Created by low-batt on 6/30/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Cocoa

/// A custom [slider](https://developer.apple.com/design/human-interface-guidelines/macos/selectors/sliders/)
/// for the volume slider in the on screen controller.
class VolumeSlider: NSSlider {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    self.cell = VolumeSliderCell()
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  // MARK: - Mouse / Trackpad events

  /// Keep AppKit's slider tracking path active on macOS versions affected by IINA issue #5768.
  ///
  /// Without this explicit override, AppKit may skip mouse tracking for NSSlider subclasses,
  /// allowing a movable window background to handle the drag instead.
  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)
  }

  /// The user is scrolling while the cursor is within the slider.
  ///
  /// With certain kinds of input devices, such as a mouse with a scroll wheel that spins freely, it is easy to accidentally move the cursor
  /// over the slider and unintentionally change the volume. For users that dislike this behavior IINA provides a setting to disable
  /// scrolling the slider. When this setting is enabled the user must grab and drag the slider's thumb to change the volume or click on a
  /// position within the slider.
  /// - Parameter event: Event indicating the scroll wheel position changed.
  override func scrollWheel(with event: NSEvent) {
    guard !Preference.bool(for: .disableVolumeSliderScrolling) else { return }
    super.scrollWheel(with: event)
  }
}


fileprivate class VolumeSliderCell: NSSliderCell {
  /// Draws the slider’s bar—but not its bezel or knob—inside the specified rectangle.
  ///
  /// IINA overrides the
  /// [NSSliderCell.drawBar](https://developer.apple.com/documentation/appkit/nsslidercell/drawbar(inside:flipped:))
  /// method in order to:
  /// - Round the ends of the slider bar (matching the playback position slider)
  /// - Alter the colors of the bar
  /// - Leave a small gap that marks the position representing 100% volume, when the `Maximum volume` setting has been used to
  ///     allow the volume to be set beyond 100%
  ///
  /// As merely moving the cursor displays the on screen controller it is desirable that this UI element not be intrusive. For this reason
  /// the OSC intentionally differs in its appearance from other user interface elements. To make the OSC have a subtle appearance a
  /// greyscale color scheme is used. In particular it is important to override the use of
  /// [controlAccentColor](https://developer.apple.com/documentation/appkit/nscolor/controlaccentcolor)
  /// by [NSSlider](https://developer.apple.com/documentation/appkit/nsslider) as that color is intended to stand
  /// out and attract attention.
  /// - Parameters:
  ///   - rect: The bounds of the slider’s bar, not of its interior rectangle.
  ///   - flipped: A Boolean value that indicates whether the cell’s control view—that is, the `NSSlider` or `NSMatrix`
  ///       associated with the` NSSliderCell`—has a flipped coordinate system.
  override func drawBar(inside rect: NSRect, flipped: Bool) {

    // The position of the knob, rounded for cleaner drawing.
    let knobPos: CGFloat = round(knobRect(flipped: flipped).origin.x);

    // Round the slider bar ends like is done for the playback progress slider.
    let radius: CGFloat = 1.5
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // The position at which volume is set to 100 rounded to obtain a pixel perfect clip line.
    let x100 = round(rect.minX + rect.width * CGFloat(100 / maxValue))

    // If the IINA "Maximum volume" setting has been increased beyond 100 then the slider bar will
    // be drawn with a small gap at the position that represents 100% volume.
    let gapClip: NSBezierPath?
    if maxValue > 100 {
      let width: CGFloat = 2
      let gapRect = NSMakeRect(x100 - width / 2, rect.minY, width, rect.height)
      gapClip = NSBezierPath(rect: gapRect).reversed
    } else {
      gapClip = nil
    }

    // Draw the portion of the slider bar that is to the left of the knob.
    NSGraphicsContext.saveGraphicsState()
    let clipLeft = NSBezierPath(rect: NSMakeRect(rect.minX, rect.minY, knobPos, rect.height))
    if let gapClip, x100 < knobPos {
      // The gap representing 100% volume is in this portion of the bar.
      clipLeft.append(gapClip)
    }
    clipLeft.addClip()
    NSColor.volumeSliderBarLeft.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Draw the portion of the slider bar that is to the right of the knob.
    NSGraphicsContext.saveGraphicsState()
    let rightRect = NSMakeRect(rect.minX + knobPos, rect.minY, rect.width - knobPos, rect.height)
    let clipRight = NSBezierPath(rect: rightRect)
    if let gapClip, knobPos < x100 {
      // The gap representing 100% volume is in this portion of the bar.
      clipRight.append(gapClip)
    }
    clipRight.addClip()
    NSColor.volumeSliderBarRight.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
  }
}
