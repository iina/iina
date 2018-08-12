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
    super.drawBar(inside: rect, flipped: flipped)

    if maxValue > 100 {
      NSGraphicsContext.saveGraphicsState()
      NSColor.controlColor.setStroke()
      let x = rect.minX + rect.width * CGFloat(100 / maxValue)
      let y0 = (flipped ? rect.height : 0) + 1
      let y1 = y0 + rect.height - 2
      let linePath = NSBezierPath()
      linePath.move(to: NSPoint(x: x, y: y0))
      linePath.line(to: NSPoint(x: x, y: y1))
      linePath.stroke()
      NSGraphicsContext.restoreGraphicsState()
    }
  }

}
