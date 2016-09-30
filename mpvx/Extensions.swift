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
  
  var aspect: CGFloat {
    get {
      return width / height
    }
  }
  
  /** Resize to no smaller than a min size while keeping same aspect */
  func satisfyMinSizeWithSameAspectRatio(_ minSize: NSSize) -> NSSize {
    if width >= minSize.width && height >= minSize.height {  // no need to resize if larger
      return self
    } else {
      return grow(toSize: minSize)
    }
  }
  
  /** Resize to no larger than a max size while keeping same aspect */
  func satisfyMaxSizeWithSameAspectRatio(_ maxSize: NSSize) -> NSSize {
    if width <= maxSize.width && height <= maxSize.height {  // no need to resize if smaller
      return self
    } else {
      return shrink(toSize: maxSize)
    }
  }
  
  func crop(withAspect aspectRect: Aspect) -> NSSize {
    let targetAspect = aspectRect.value
    if aspect > targetAspect {  // self is wider, crop width, use same height
      return NSSize(width: height * targetAspect, height: height)
    } else {
      return NSSize(width: width, height: width / targetAspect)
    }
  }
  
  func expand(withAspect aspectRect: Aspect) -> NSSize {
    let targetAspect = aspectRect.value
    if aspect < targetAspect {  // self is taller, expand width, use same height
      return NSSize(width: height * targetAspect, height: height)
    } else {
      return NSSize(width: width, height: width / targetAspect)
    }
  }
  
  func grow(toSize size: NSSize) -> NSSize {
    let sizeAspect = size.aspect
    if aspect > sizeAspect {  // self is wider, grow to meet height
      return NSSize(width: size.height * aspect, height: size.height)
    } else {
      return NSSize(width: size.width, height: size.width / aspect)
    }
  }
  
  func shrink(toSize size: NSSize) -> NSSize {
    let  sizeAspect = size.aspect
    if aspect < sizeAspect { // self is taller, shrink to meet height
      return NSSize(width: size.height * aspect, height: size.height)
    } else {
      return NSSize(width: size.width, height: size.width / aspect)
    }
  }
  
  func multiply(_ multiplier: CGFloat) -> NSSize {
    return NSSize(width: width * multiplier, height: height * multiplier)
  }
  
}

extension NSRect {
  mutating func toCenteredResize(fromOriginalRect oRect: NSRect) {
    origin = CGPoint(x: oRect.origin.x + (oRect.width - width) / 2, y: oRect.origin.y + (oRect.height - height) / 2)
  }
  
  func multiply(_ multiplier: CGFloat) -> NSRect {
    return NSRect(x: origin.x, y: origin.y, width: width * multiplier, height: height * multiplier)
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

extension Int {
  func toStr() -> String {
    return "\(self)"
  }
  
  func constrain(min: Int, max: Int) -> Int {
    var value = self
    if self < min { value = min }
    if self > max { value = max }
    return value
  }
}

extension NSColor {
  var mpvString: String {
    get {
      return "\(self.redComponent)/\(self.greenComponent)/\(self.blueComponent)\(self.alphaComponent)"
    }
  }
}
