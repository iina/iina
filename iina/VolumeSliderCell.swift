//
//  VolumeSliderCell.swift
//  iina
//
//  Created by lhc on 26/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class VolumeSliderCell: NSSliderCell {

  static let lightStrokeColor = NSColor(white: 0.6, alpha: 0.5)
  static let darkStrokeColor = NSColor(white: 0, alpha: 0.8)

  var strokeColor = VolumeSliderCell.darkStrokeColor

  var isInDarkTheme: Bool = true {
    didSet {
      self.strokeColor = isInDarkTheme ? VolumeSliderCell.darkStrokeColor : VolumeSliderCell.darkStrokeColor
    }
  }

  override func awakeFromNib() {
    minValue = 0
    maxValue = Double(Preference.integer(for: .maxVolume))
  }

  override func drawBar(inside rect: NSRect, flipped: Bool) {
    super.drawBar(inside: rect, flipped: flipped)

    if maxValue > 100 {
      NSGraphicsContext.saveGraphicsState()
      strokeColor.setStroke()
      let x = rect.x + rect.width * CGFloat(100 / maxValue)
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
