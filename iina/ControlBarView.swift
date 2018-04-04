//
//  ControlBarView.swift
//  iina
//
//  Created by lhc on 16/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class ControlBarView: NSVisualEffectView {

  @IBOutlet weak var xConstraint: NSLayoutConstraint!
  @IBOutlet weak var yConstraint: NSLayoutConstraint!

  var mousePosRelatedToView: CGPoint?

  var isDragging: Bool = false

  private var isAlignFeedbackSent = false

  override func awakeFromNib() {
    self.layer?.cornerRadius = 6
    self.translatesAutoresizingMaskIntoConstraints = false
  }

  override func mouseDown(with event: NSEvent) {
    mousePosRelatedToView = NSEvent.mouseLocation
    mousePosRelatedToView!.x -= frame.origin.x
    mousePosRelatedToView!.y -= frame.origin.y
    isAlignFeedbackSent = abs(frame.origin.x - (window!.frame.width - frame.width) / 2) <= 5
    isDragging = true
  }

  override func mouseDragged(with event: NSEvent) {
    guard let mousePos = mousePosRelatedToView, let windowFrame = window?.frame else { return }
    let currentLocation = NSEvent.mouseLocation
    var newOrigin = CGPoint(
      x: currentLocation.x - mousePos.x,
      y: currentLocation.y - mousePos.y
    )
    // stick to center
    if Preference.bool(for: .controlBarStickToCenter) {
      let xPosWhenCenter = (windowFrame.width - frame.width) / 2
      if abs(newOrigin.x - xPosWhenCenter) <= 5 {
        newOrigin.x = xPosWhenCenter
        if #available(macOS 10.11, *), !isAlignFeedbackSent {
          NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
          isAlignFeedbackSent = true
        }
      } else {
        isAlignFeedbackSent = false
      }
    }
    // bound to parent
    var updateX = true, updateY = true
    let xMax = windowFrame.width - frame.width - 10
    let yMax = windowFrame.height - frame.height
    if newOrigin.x > xMax {
      newOrigin.x = xMax
      updateX = false
    }
    if newOrigin.y > yMax {
      newOrigin.y = yMax
      updateY = false
    }
    if newOrigin.x < 10 {
      newOrigin.x = 0
      updateX = false
    }
    if newOrigin.y < 0 {
      newOrigin.y = 0
      updateY = false
    }
    // save position
    if updateX {
      let xPos = newOrigin.x + frame.width / 2
      xConstraint.constant = xPos
      Preference.set(xPos / windowFrame.width, for: .controlBarPositionHorizontal)
    }
    if updateY {
      let yPos = newOrigin.y
      yConstraint.constant = yPos
      Preference.set(yPos / windowFrame.height, for: .controlBarPositionVertical)
    }
  }
  override func mouseUp(with event: NSEvent) {
    isDragging = false
  }

}
