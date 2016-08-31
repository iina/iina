//
//  Extensions.swift
//  mpvx
//
//  Created by lhc on 12/8/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

extension NSSlider {
  /** Returns the positon of knob center by point */
  func knobPointPosition() -> CGFloat {
    let sliderOrigin = frame.origin.x + knobThickness / 2
    let sliderWidth = frame.width - knobThickness
    let knobPos = sliderOrigin + sliderWidth * CGFloat((doubleValue - minValue) / (maxValue - minValue))
    return knobPos
  }
}

extension NSSize {
  /** Constrain a NSSize to satisfy a min size while keeping same aspect */
  func satisfyMinSizeWithFixedAspectRatio(_ minSize: NSSize) -> NSSize {
    let aspect = width / height
    if width >= minSize.width && height >= minSize.height {
      return self
    } else {
      let tryWidth = minSize.height * aspect
      let tryHeight = minSize.width / aspect
      if tryWidth >= width {  // use minSize.height
        return NSSize(width: tryWidth, height: minSize.height)
      } else {  // use minSize.width
        return NSSize(width: minSize.width, height: tryHeight)
      }
    }
  }
}

extension Array {
  func at(_ pos: Int) -> Element? {
    if pos < count - 1 {
      return self[pos]
    } else {
      return nil
    }
  }
}

extension NSMenu {
  func addItem(withTitle string: String, action selector: Selector?, tag: Int?, obj: Any?, stateOn: Bool) {
    let menuItem = NSMenuItem(title: string, action: selector, keyEquivalent: "")
    menuItem.tag = tag ?? -1
    menuItem.representedObject = obj
    menuItem.state = stateOn ? NSOnState : NSOffState
    self.addItem(menuItem)
  }
}
