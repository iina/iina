//
//  SimpleTime.swift
//  iina
//
//  Created by lhc on 25/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Foundation

class VideoTime {

  static let infinite = VideoTime(999, 0, 0)
  static let zero = VideoTime(0)

  var second: Double

  var h: Int {
    get {
      return (Int(second) / 3600)
    }
  }

  var m: Int {
    get {
      return (Int(second) % 3600) / 60
    }
  }

  var s: Int {
    get {
      return (Int(second) % 3600) % 60
    }
  }

  var stringRepresentation: String {
    get {
      if self == Constants.Time.infinite {
        return "End"
      }
      let ms = (m < 10 ? "0\(m)" : "\(m)")
      let ss = (s < 10 ? "0\(s)" : "\(s)")
      let hs = (h > 0 ? "\(h):" : "")
      return "\(hs)\(ms):\(ss)"
    }
  }

  convenience init?(_ format: String) {
    let split = format.characters.split(separator: ":").map { (seq) -> Int? in
      return Int(String(seq))
    }
    if !(split.contains {$0 == nil}) {
      // if no nil in array
      if split.count == 2 {
        self.init(0, split[0]!, split[1]!)
      } else if split.count == 3 {
        self.init(split[0]!, split[1]!, split[2]!)
      } else {
        return nil
      }
    } else {
      return nil
    }
  }

  init(_ second: Double) {
    self.second = second

  }

  init(_ hour: Int, _ minute: Int, _ second: Int) {
    self.second = Double(hour * 3600 + minute * 60 + second)
  }

  /** whether self in [min, max) */
  func between(_ min: VideoTime, _ max: VideoTime) -> Bool {
    return self >= min && self < max
  }

}

extension VideoTime: Comparable { }

func <(lhs: VideoTime, rhs: VideoTime) -> Bool {
  // ignore additional digits and compare the time in milliseconds
  return Int(lhs.second * 1000) < Int(rhs.second * 1000)
}

func ==(lhs: VideoTime, rhs: VideoTime) -> Bool {
  // ignore additional digits and compare the time in milliseconds
  return Int(lhs.second * 1000) == Int(rhs.second * 1000)
}

func *(lhs: VideoTime, rhs: Double) -> VideoTime {
  return VideoTime(lhs.second * rhs)
}

func /(lhs: VideoTime?, rhs: VideoTime?) -> Double? {
  if let lhs = lhs, let rhs = rhs {
    return lhs.second / rhs.second
  } else {
    return nil
  }
}

func -(lhs: VideoTime, rhs: VideoTime) -> VideoTime {
  return VideoTime(lhs.second - rhs.second)
}
