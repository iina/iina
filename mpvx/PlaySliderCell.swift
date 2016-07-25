//
//  PlaySlider.swift
//  mpvx
//
//  Created by lhc on 25/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class PlaySliderCell: NSSliderCell {
  
  var knobWidth: CGFloat = 2
  var knobHeight: CGFloat = 15
  var knobRadius: CGFloat = 2
  
  override func awakeFromNib() {
    minValue = 0
    maxValue = 100
  }
  
  override func drawKnob(_ knobRect: NSRect) {
    let rect = NSMakeRect(knobRect.origin.x + 0.5 * (knobRect.width - knobWidth),
                          knobRect.origin.y + 0.5 * (knobRect.height - knobHeight),
                          knobWidth,
                          knobHeight)
    let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
    NSColor(red: 1, green: 1, blue: 1, alpha: 0.9).setFill()
    path.fill()
  }
}
