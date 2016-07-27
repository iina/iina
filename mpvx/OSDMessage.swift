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
  
  static let mute = "Mute"
  static let unMute = "Mute Off"
}
