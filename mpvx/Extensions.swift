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
  
  func add(_ multiplier: CGFloat) -> NSSize {
    return NSSize(width: width + multiplier, height: height + multiplier)
  }
  
}

extension NSRect {
  
  func multiply(_ multiplier: CGFloat) -> NSRect {
    return NSRect(x: origin.x, y: origin.y, width: width * multiplier, height: height * multiplier)
  }
  
  func centeredResize(to newSize: NSSize) -> NSRect {
    return NSRect(x: origin.x - (newSize.width - size.width) / 2,
                  y: origin.y - (newSize.height - size.height) / 2,
                  width: newSize.width,
                  height: newSize.height)
  }
  
  func constrain(in biggerRect: NSRect) -> NSRect {
    var newX = origin.x, newY = origin.y
    if newX < 0 {
      newX = 0
    }
    if newY < 0 {
      newY = 0
    }
    if newX + size.width > biggerRect.width {
      newX = biggerRect.width - size.width
    }
    if newY + size.height > biggerRect.height {
      newY = biggerRect.height - size.height
    }
    return NSRect(x: newX, y: newY, width: size.width, height: size.height)
  }
}

extension Array {
  func at(_ pos: Int) -> Element? {
    if pos < count {
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

extension Double {
  func constrain(min: Double, max: Double) -> Double {
    var value = self
    if self < min { value = min }
    if self > max { value = max }
    return value
  }
}

extension NSColor {
  var mpvColorString: String {
    get {
      return "\(self.redComponent)/\(self.greenComponent)/\(self.blueComponent)/\(self.alphaComponent)"
    }
  }
  
  convenience init?(mpvColorString: String) {
    let splitted = mpvColorString.characters.split(separator: "/").map { (seq) -> Double? in
      return Double(String(seq))
    }
    // check nil
    if (!splitted.contains {$0 == nil}) {
      if splitted.count == 3 {  // if doesn't have alpha value
        self.init(red: CGFloat(splitted[0]!), green: CGFloat(splitted[1]!), blue: CGFloat(splitted[2]!), alpha: CGFloat(1))
      } else if splitted.count == 4 {  // if has alpha value
        self.init(red: CGFloat(splitted[0]!), green: CGFloat(splitted[1]!), blue: CGFloat(splitted[2]!), alpha: CGFloat(splitted[3]!))
      } else {
        return nil
      }
    } else {
      return nil
    }
  }
}

