//
//  OSDMessage.swift
//  mpvx
//
//  Created by lhc on 27/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Foundation

enum OSDMessage {
  
  case pause
  case resume
  case volume(Int)
  case speed(Double)
  case aspect(String)
  case rotate(Int)
  case audioDelay(Double)
  case subDelay(Double)
  case subScale(Double)
  case subPos(Double)
  case mute
  case unMute
  case screenShot
  case abLoop(Int)
  case stop
  case chapter(String)
  case addToPlaylist(Int)
  case clearPlaylist
  
  case contrast(Double)
  case hue(Double)
  case saturation(Double)
  case brightness(Double)
  case gamma(Double)
  
  
  func message() -> String {
    switch self {
    case .pause:
      return "Paused"
      
    case .resume:
      return "Resumed"
      
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
        return "Audio Delay: \(abs(value))s \(word)"
      }
      
    case .subDelay(let value):
      if value == 0 {
        return "Subtitle Delay: No Delay"
      } else {
        let word = value > 0 ? "Later" : "Earlier"
        return "Subtitle Delay: \(abs(value))s \(word)"
      }
      
    case .subPos(let value):
      return "Sub Position: \(value) / 100"
      
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
      
    case .chapter(let name):
      return "Go to \"\(name)\""
      
    case .subScale(let value):
      return "Subtitle Scale: \(value)x"
      
    case .addToPlaylist(let count):
      return "Added \(count) files to playlist"
      
    case .clearPlaylist:
      return "Cleared playlist"
      
    case .contrast(let value):
      return "Contrast: \(value)"
      
    case .gamma(let value):
      return "Gamma: \(value)"
      
    case .hue(let value):
      return "Hue: \(value)"
      
    case .saturation(let value):
      return "Saturation: \(value)"
      
    case .brightness(let value):
      return "Brightness: \(value)"
      
    }
  }
}
