//
//  VolumeSliderCell.swift
//  iina
//
//  Created by lhc on 26/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class VolumeSliderCell: NSSliderCell {

  override func awakeFromNib() {
    minValue = 0
    maxValue = Double(Preference.integer(for: .maxVolume))
  }

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
