//
//  OSDMessage.swift
//  mpvx
//
//  Created by lhc on 27/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Foundation

enum OSDMessage {
  
  case volume(Int)
  case speed(Double)
  case aspect(String)
  case rotate(Int)
  case audioDelay(Double)
  case subDelay(Double)
  case mute
  case unMute
  case screenShot
  case abLoop(Int)
  case stop
  
  func message() -> String {
    switch self {
    case .volume(let value):
      return "Volume: \(value)"
      
    case .speed(let value):
      let formattedValue = String(format: "%.2f", value)
      return "Speed: \(formattedValue)"
      
    case .aspect(let value):
      return "Aspect Ratio: \(value)"
      
    case .rotate(let value):
      return "Rotate: \(value)°"
      
    case .audioDelay(let value):
      if value == 0 {
        return "Audio Delay: No Delay"
      } else {
        let word = value > 0 ? "Later" : "Earlier"
        return "Audio Delay: \(value)s \(word)"
      }
      
    case .subDelay(let value):
      if value == 0 {
        return "Subtitle Delay: No Delay"
      } else {
        let word = value > 0 ? "Later" : "Earlier"
        return "Subtitle Delay: \(value)s \(word)"
      }
      
    case .mute:
      return "Mute"
      
    case .unMute:
      return "Mute Off"
      
    case .screenShot:
      return "Screenshoted"
      
    case .abLoop(let value):
      if value == 1 {
        return "AB-Loop: A"
      } else if value == 2 {
        return "AB-Loop: B"
      } else {
        return "AB-Loop: Clear Both"
      }
      
    case .stop:
      return "Stopped"
    }
  }
}
