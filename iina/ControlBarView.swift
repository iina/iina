//
//  ControlBarView.swift
//  iina
//
//  Created by lhc on 16/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class ControlBarView: NSVisualEffectView {
  
  var mousePosRelatedToView: CGPoint?
  
  var isDragging: Bool = false

  override func awakeFromNib() {
    self.layer?.cornerRadius = 4
  }
  
  override func mouseDown(with event: NSEvent) {
    mousePosRelatedToView = NSEvent.mouseLocation()
    mousePosRelatedToView!.x -= self.frame.origin.x
    mousePosRelatedToView!.y -= self.frame.origin.y
    isDragging = true
  }
  
  override func mouseDragged(with event: NSEvent) {
    if mousePosRelatedToView != nil {
      let currentLocation = NSEvent.mouseLocation()
      var newOrigin = CGPoint(
        x: currentLocation.x - mousePosRelatedToView!.x,
        y: currentLocation.y - mousePosRelatedToView!.y
      )
      // stick to center
      let windowFrame = window!.frame
      if UserDefaults.standard.bool(forKey: Preference.Key.controlBarStickToCenter) {
        let xPosWhenCenter = (windowFrame.width - frame.width) / 2
        if  abs(newOrigin.x - xPosWhenCenter) <= 25 {
          newOrigin.x = xPosWhenCenter
        }
      }
      // bound to parent
      let xMax = windowFrame.width - frame.width
      let yMax = windowFrame.height - frame.height
      if newOrigin.x > xMax {
        newOrigin.x = xMax
      }
      if newOrigin.y > yMax {
        newOrigin.y = yMax
      }
      if newOrigin.x < 0 {
        newOrigin.x = 0
      }
      if newOrigin.y < 0 {
        newOrigin.y = 0
      }
      self.setFrameOrigin(newOrigin)
    }
  }
  override func mouseUp(with event: NSEvent) {
    isDragging = false
  }
  
}
