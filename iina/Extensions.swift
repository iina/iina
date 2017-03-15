//
//  Extensions.swift
//  iina
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

extension NSSegmentedControl {
  func selectSegment(withLabel label: String) {
    self.selectedSegment = -1
    for i in 0..<segmentCount {
      if self.label(forSegment: i) == label {
        self.selectedSegment = i
      }
    }
  }
}

func - (lhs: NSPoint, rhs: NSPoint) -> NSPoint {
  return NSMakePoint(lhs.x - rhs.x, lhs.y - rhs.y)
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
    // new size
    var newSize = size
    if newSize.width > biggerRect.width || newSize.height > biggerRect.height {
      newSize = size.shrink(toSize: biggerRect.size)
    }
    // new origin
    var newOrigin = origin
    if newOrigin.x < biggerRect.origin.x {
      newOrigin.x = biggerRect.origin.x
    }
    if newOrigin.y < biggerRect.origin.y {
      newOrigin.y = biggerRect.origin.y
    }
    if newOrigin.x + width > biggerRect.origin.x + biggerRect.width {
      newOrigin.x = biggerRect.origin.x + biggerRect.width - width
    }
    if newOrigin.y + height > biggerRect.origin.y + biggerRect.height {
      newOrigin.y = biggerRect.origin.y + biggerRect.height - height
    }
    return NSRect(origin: newOrigin, size: newSize)
  }
}

extension NSPoint {
  func constrain(in rect: NSRect) -> NSPoint {
    let l = rect.origin.x
    let r = l + rect.width
    let t = rect.origin.y
    let b = t + rect.height
    return NSMakePoint(x.constrain(min: l, max: r), y.constrain(min: t, max: b))
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
  func addItem(withTitle string: String, action selector: Selector? = nil, tag: Int? = nil, obj: Any? = nil, stateOn: Bool = false) {
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

extension CGFloat {
  func constrain(min: CGFloat, max: CGFloat) -> CGFloat {
    var value = self
    if self < min { value = min }
    if self > max { value = max }
    return value
  }

  var unifiedDouble: Double {
    get {
      return self == 0 ? 0 : (self > 0 ? 1 : -1)
    }
  }
}

extension Double {
  func toStr() -> String {
    return "\(self)"
  }

  func constrain(min: Double, max: Double) -> Double {
    var value = self
    if self < min { value = min }
    if self > max { value = max }
    return value
  }

  func prettyFormat() -> String {
    if truncatingRemainder(dividingBy: 1) == 0 {
      return "\(Int(self))"
    } else {
      return "\(self)"
    }
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


extension NSMutableAttributedString {
  convenience init?(linkTo url: String, text: String, font: NSFont) {
    self.init(string: text)
    let range = NSRange(location: 0, length: self.length)
    let nsurl = NSURL(string: url)!
    self.beginEditing()
    self.addAttribute(NSLinkAttributeName, value: nsurl, range: range)
    self.addAttribute(NSFontAttributeName, value: font, range: range)
    self.endEditing()
  }
}


extension UserDefaults {

  func mpvColor(forKey key: String) -> String? {
    guard let data = self.data(forKey: key) else { return nil }
    guard let color = NSUnarchiver.unarchiveObject(with: data) as? NSColor else { return nil }
    return color.usingColorSpace(.deviceRGB)?.mpvColorString
  }
}


extension NSData {
  func md5() -> NSString {
    let digestLength = Int(CC_MD5_DIGEST_LENGTH)
    let md5Buffer = UnsafeMutablePointer<CUnsignedChar>.allocate(capacity: digestLength)

    CC_MD5(bytes, CC_LONG(length), md5Buffer)

    let output = NSMutableString(capacity: Int(CC_MD5_DIGEST_LENGTH * 2))
    for i in 0..<digestLength {
      output.appendFormat("%02x", md5Buffer[i])
    }

    return NSString(format: output)
  }
}

extension Data {
  var md5: String {
    get {
      return (self as NSData).md5() as String
    }
  }

  var chksum64: UInt64 {
    get {
      let count64 = self.count / MemoryLayout<UInt64>.size
      return self.withUnsafeBytes{ (ptr: UnsafePointer<UInt64>) -> UInt64 in
        let bufferPtr = UnsafeBufferPointer(start: ptr, count: count64)
        return bufferPtr.reduce(UInt64(0), &+)
      }
    }
  }

  func saveToFolder(_ url: URL, filename: String) -> URL? {
    let fileUrl = url.appendingPathComponent(filename)
    do {
      try self.write(to: fileUrl)
    } catch {
      Utility.showAlert("error_saving_file", arguments: ["data", filename])
      return nil
    }
    return fileUrl
  }
}
