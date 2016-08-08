//
//  OSDMessage.swift
//  mpvx
//
//  Created by lhc on 27/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Foundation

struct OSDMessage {
  static func volume(_ value: Int) -> String {
    return "Volume: \(value)"
  }
  
  static func speed(_ value: Double) -> String {
    let formattedValue = String(format: "%.2f", value)
    return "Speed: \(formattedValue)"
  }
  
  static func aspect(_ value: String) -> String {
    return "Aspect Ratio: \(value)"
  }
  
  static func rotate(_ value: Int) -> String {
    return "Rotate: \(value)°"
  }
  
  static func audioDelay(_ value: Double) -> String {
    if value == 0 {
      return "Audio Delay: No Delay"
    } else {
      let word = value > 0 ? "Later" : "Earlier"
      return "Audio Delay: \(value)s \(word)"
    }
  }
  
  static func subDelay(_ value: Double) -> String {
    if value == 0 {
      return "Subtitle Delay: No Delay"
    } else {
      let word = value > 0 ? "Later" : "Earlier"
      return "Subtitle Delay: \(value)s \(word)"
    }
  }
  
  static let mute = "Mute"
  static let unMute = "Mute Off"
}
