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
  
  static let mute = "Mute"
  static let unMute = "UnMute"
}
