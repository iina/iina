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

  override func drawBar(inside rect: NSRect, flipped: Bool) {
    NSGraphicsContext.saveGraphicsState()
    if maxValue > 100 {
      // round this value to obtain a pixel perfect clip line
      let x = round(rect.minX + rect.width * CGFloat(100 / maxValue))
      let clipPath = NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: x - 1, height: rect.height))
      clipPath.append(NSBezierPath(rect: NSRect(x: x + 1, y: rect.minY, width: rect.maxX - x - 1, height: rect.height)))
      clipPath.setClip()
    }
    super.drawBar(inside: rect, flipped: flipped)
    NSGraphicsContext.restoreGraphicsState()
  }

}
