//
//  SimpleTime.swift
//  iina
//
//  Created by lhc on 25/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation

class VideoTime {

  static let infinite = VideoTime(999, 0, 0)
  static let zero = VideoTime(0)

  var second: Double

  var h: Int {
    Int(second) / 3600
  }

  var m: Int {
    (Int(second) % 3600) / 60
  }

  var s: Int {
    (Int(second) % 3600) % 60
  }

  var stringRepresentation: String {
    stringRepresentationWithPrecision(0)
  }

  func stringRepresentationWithPrecision(_ precision: UInt) -> String {
    if self == Constants.Time.infinite {
      return "End"
    }
    let h_ = h > 0 ? "\(h):" : ""
    let m_ = m < 10 ? "0\(m)" : "\(m)"
    let s_: String

    if precision >= 1 && precision <= 3 {
      s_ = String(format: "%0\(precision + 3).\(precision)f", fmod(second, 60))
    } else {
      s_ = s < 10 ? "0\(s)" : "\(s)"
    }

    return h_ + m_ + ":" + s_
  }

  convenience init?(_ format: String) {
    let split = format.split(separator: ":").map { Int($0) }
    if split.contains(nil) {
      return nil
    }
    switch split.count {
    case 1:
      self.init(0, 0, split[0]!)
    case 2:
      self.init(0, split[0]!, split[1]!)
    case 3:
      self.init(split[0]!, split[1]!, split[2]!)
    default:
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
