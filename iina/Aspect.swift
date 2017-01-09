//
//  Aspect.swift
//  iina
//
//  Created by lhc on 2/9/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class Aspect: NSObject {

  private var size: NSSize!

  var width: CGFloat {
    get {
      return size.width
    }
    set {
      size.width = newValue
    }
  }

  var height: CGFloat {
    get {
      return size.height
    }
    set {
      size.height = newValue
    }
  }

  var value: CGFloat {
    get {
      return size.width / size.height
    }
  }

  init(size: NSSize) {
    self.size = size
  }

  init(width: CGFloat, height: CGFloat) {
    self.size = NSMakeSize(width, height)
  }

  init?(string: String) {
    if AppData.aspectRegex.matches(string) {
      let wh = string.components(separatedBy: ":")
      if let cropW = Float(wh[0]), let cropH = Float(wh[1]) {
        self.size = NSMakeSize(CGFloat(cropW), CGFloat(cropH))
      }
    } else {
      return nil
    }
  }

}
