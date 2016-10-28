//
//  PlaySlider.swift
//  mpvx
//
//  Created by lhc on 25/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class PlaySliderCell: NSSliderCell {
  
  let knobWidth: CGFloat = 3
  let knobHeight: CGFloat = 13
  let knobRadius: CGFloat = 2
  
  static let darkColor = NSColor(red: 1, green: 1, blue: 1, alpha: 0.9)
  static let lightColor = NSColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)
  
  var isInDarkTheme: Bool = true {
    didSet {
      self.knobColor = isInDarkTheme ? PlaySliderCell.darkColor : PlaySliderCell.lightColor
    }
  }
  private var knobColor: NSColor = PlaySliderCell.darkColor
  
  override func awakeFromNib() {
    minValue = 0
    maxValue = 100
    
  }
  
  override func drawKnob(_ knobRect: NSRect) {
    let rect = NSMakeRect(knobRect.origin.x,
                          knobRect.origin.y + 0.5 * (knobRect.height - knobHeight),
                          knobRect.width,
                          knobHeight)
    let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
    knobColor.setFill()
    path.fill()
  }
  
  override func knobRect(flipped: Bool) -> NSRect {
    let slider = self.controlView as! NSSlider
    let bounds = super.barRect(flipped: flipped)
    let percentage = slider.doubleValue / (slider.maxValue - slider.minValue)
    let pos = CGFloat(percentage) * bounds.width
    let rect = super.knobRect(flipped: flipped)
    let flippedMultiplier = flipped ? CGFloat(-1) : CGFloat(1)
    return NSMakeRect(pos - flippedMultiplier * 0.5 * knobWidth, rect.origin.y, knobWidth, rect.height)
    
  }
  
}
