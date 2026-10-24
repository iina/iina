//
//  Aspect.swift
//  iina
//
//  Created by lhc on 2/9/16.
//  Copyright © 2016 lhc. All rights reserved.
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

  init?(string: String) {
    guard Regex.aspect.matches(string) else { return nil }
    let wh = string.components(separatedBy: ":")
    guard wh.count == 2, let cropW = Double(wh[0]), let cropH = Double(wh[1]),
          cropW.isFinite, cropH.isFinite, cropW > 0, cropH > 0,
          (cropW / cropH).isFinite, cropW / cropH > 0 else { return nil }
    self.size = NSSize(width: cropW, height: cropH)
  }

}
