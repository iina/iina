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
    self.roundCorners(withRadius: 6)
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
        if !isAlignFeedbackSent {
          NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
          isAlignFeedbackSent = true
        }
      } else {
        isAlignFeedbackSent = false
      }
    }
    // bound to window frame
    let xMax = windowFrame.width - frame.width - 10
    let yMax = windowFrame.height - frame.height - 25
    newOrigin = newOrigin.constrained(to: NSRect(x: 10, y: 0, width: xMax, height: yMax))
    // apply position
    xConstraint.constant = newOrigin.x + frame.width / 2
    yConstraint.constant = newOrigin.y
  }

  override func mouseUp(with event: NSEvent) {
    isDragging = false
    guard let windowFrame = window?.frame else { return }
    // save final position
    Preference.set(xConstraint.constant / windowFrame.width, for: .controlBarPositionHorizontal)
    Preference.set(yConstraint.constant / windowFrame.height, for: .controlBarPositionVertical)
  }

}
