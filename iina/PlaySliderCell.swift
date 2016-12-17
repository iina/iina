//
//  PlaySlider.swift
//  iina
//
//  Created by lhc on 25/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class PlaySliderCell: NSSliderCell {
  
  override var knobThickness: CGFloat {
    return knobWidth
  }
  
  let knobWidth: CGFloat = 3
  let knobHeight: CGFloat = 13
  let knobRadius: CGFloat = 2
  
  static let darkColor = NSColor(red: 1, green: 1, blue: 1, alpha: 0.9)
  static let lightColor = NSColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)
  
  static let darkBarColorLeft = NSColor(white: 1, alpha: 0.5)
  static let darkBarColorRight = NSColor(white: 1, alpha: 0.2)
  static let lightBarColorLeft = NSColor(red: 0.239, green: 0.569, blue: 0.969, alpha: 1)
  static let lightBarColorRight = NSColor(white: 0.5, alpha: 0.5)
  
  var isInDarkTheme: Bool = true {
    didSet {
      self.knobColor = isInDarkTheme ? PlaySliderCell.darkColor : PlaySliderCell.lightColor
      self.barColorLeft = isInDarkTheme ? PlaySliderCell.darkBarColorLeft : PlaySliderCell.lightBarColorLeft
      self.barColorRight = isInDarkTheme ? PlaySliderCell.darkBarColorRight : PlaySliderCell.lightBarColorRight
    }
  }
  private var knobColor: NSColor = PlaySliderCell.darkColor
  private var barColorLeft: NSColor = PlaySliderCell.darkBarColorLeft
  private var barColorRight: NSColor = PlaySliderCell.darkBarColorRight
  private var chapterStrokeColor: NSColor = NSColor(white: 0, alpha: 0.8)
  
  var drawChapters = UserDefaults.standard.bool(forKey: Preference.Key.showChapterPos)
  
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
  
  override func drawBar(inside rect: NSRect, flipped: Bool) {
    let slider = self.controlView as! NSSlider
    let percentage = CGFloat(slider.doubleValue / (slider.maxValue - slider.minValue))
    let knobPos = rect.width * percentage
    let rect = NSMakeRect(rect.origin.x, rect.origin.y + 1, rect.width, rect.height - 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
    
    // draw left
    NSGraphicsContext.saveGraphicsState()
    let pathLeft = NSMakeRect(rect.origin.x, rect.origin.y, knobPos, rect.height)
    NSBezierPath(rect: pathLeft).setClip()
    barColorLeft.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    
    // draw right
    NSGraphicsContext.saveGraphicsState()
    let pathRight = NSMakeRect(rect.origin.x + knobPos, rect.origin.y, rect.width - knobPos, rect.height)
    NSBezierPath(rect: pathRight).setClip()
    barColorRight.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    
    // draw chapters
    NSGraphicsContext.saveGraphicsState()
    if drawChapters {
      if let totalSec = PlayerCore.shared.info.videoDuration?.second {
        chapterStrokeColor.setStroke()
        var chapters = PlayerCore.shared.info.chapters
        chapters.remove(at: 0)
        chapters.forEach { chapt in
          let chapPos = CGFloat(chapt.time.second) / CGFloat(totalSec) * rect.width
          let linePath = NSBezierPath()
          linePath.move(to: NSPoint(x: chapPos, y: rect.origin.y))
          linePath.line(to: NSPoint(x: chapPos, y: rect.origin.y + rect.height))
          linePath.stroke()
        }
      }
    }
    NSGraphicsContext.restoreGraphicsState()
  }
  
  override func barRect(flipped: Bool) -> NSRect {
    let rect = super.barRect(flipped: flipped)
    return NSMakeRect(0, rect.origin.y, rect.width + rect.origin.x * 2, rect.height)
  }
  
}
