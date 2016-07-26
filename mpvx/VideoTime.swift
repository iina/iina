//
//  SimpleTime.swift
//  mpvx
//
//  Created by lhc on 25/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Foundation

class VideoTime {
  
  var second: Int
  
  var h: Int {
    get {
      return (second / 3600)
    }
  }
  
  var m: Int {
    get {
      return (second % 3600) / 60
    }
  }
  
  var s: Int {
    get {
      return (second % 3600) % 60
    }
  }
  
  var stringRepresentation: String {
    get {
      let ms = (m < 10 ? "0\(m)" : "\(m)")
      let ss = (s < 10 ? "0\(s)" : "\(s)")
      let hs = (h > 0 ? "\(h):" : "")
      return "\(hs)\(ms):\(ss)"
    }
  }
  
  init(_ second: Int) {
    self.second = second
    
  }
  
  init(_ hour: Int, _ minute: Int, _ second: Int) {
    self.second = hour * 3600 + minute * 60 + second
  }

}
