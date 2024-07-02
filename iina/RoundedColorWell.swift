//
//  RoundedColorWell.swift
//  iina
//
//  Created by lhc on 24/10/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class RoundedColorWell: NSColorWell {

  var isMouseDown: Bool = false

  override func awakeFromNib() {
    if #available(macOS 13, *) {
      self.colorWellStyle = .minimal
      super.awakeFromNib()
      return
    }
    // disable default activation of color panel
    self.isBordered = false
  }

  override func draw(_ dirtyRect: NSRect) {
    if #available(macOS 13, *) {
      super.draw(dirtyRect)
      return
    }
    let circleRect = NSInsetRect(bounds, 3, 3)

    // darker if is pressing mouse button
    if self.isMouseDown {
      (self.color.shadow(withLevel: 0.2) ?? self.color).setFill()
    } else {
      self.color.setFill()
    }

    // draw
    NSColor.white.withAlphaComponent(0.8).setStroke()
    let circlePath = NSBezierPath(ovalIn: circleRect)
    circlePath.lineWidth = 1.5
    circlePath.fill()
    circlePath.stroke()
  }

  override func mouseDown(with event: NSEvent) {
    if #available(macOS 13, *) {
      super.mouseDown(with: event)
      return
    }
    isMouseDown = true
    self.needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    if #available(macOS 13, *) {
      super.mouseUp(with: event)
      return
    }
    isMouseDown = false
    self.activate(true)
    self.needsDisplay = true
  }



}
