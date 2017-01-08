//
//  OSDMessage.swift
//  iina
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
  case crop(String)
  case rotate(Int)
  case deinterlace(Bool)
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
  
  case contrast(Int)
  case hue(Int)
  case saturation(Int)
  case brightness(Int)
  case gamma(Int)
  
  
  func message() -> String {
    switch self {
    case .pause:
      return NSLocalizedString("osd.pause", comment: "Paused")
      
    case .resume:
      return NSLocalizedString("osd.resume", comment: "Resumed")
      
    case .volume(let value):
      return String(format: NSLocalizedString("osd.volume", comment: "Volume: %i"), value)
      
    case .speed(let value):
      return String(format: NSLocalizedString("osd.speed", comment: "Speed: %.2f"), value)
      
    case .aspect(let value):
      return String(format: NSLocalizedString("osd.aspect", comment: "Aspect Ratio: %@"),value)
      
    case .crop(let value):
      return String(format: NSLocalizedString("osd.crop", comment: "Crop: %@"), value)
      
    case .rotate(let value):
      return String(format: NSLocalizedString("osd.rotate", comment: "Rotate: %i"), value)
      
    case .deinterlace(let enable):
      return String(format: NSLocalizedString("osd.deinterlace", comment: "Deinterlace: %@"), enable ? NSLocalizedString("on", comment: "On") : NSLocalizedString("off", comment: "Off"))
      
    case .audioDelay(let value):
      if value == 0 {
        return NSLocalizedString("osd.audio_delay.nodelay", comment: "Audio Delay: No Delay")
      } else {
        return value > 0 ? String(format: NSLocalizedString("osd.audio_delay.later", comment: "Audio Delay: %fs Later"),abs(value)) : String(format: NSLocalizedString("osd.audio_delay.earlier", comment: "Audio Delay: %fs Earlier"), abs(value))
      }
      
    case .subDelay(let value):
      if value == 0 {
        return NSLocalizedString("osd.subtitle_delay.nodelay", comment: "Subtitle Delay: No Delay")
      } else {
                return value > 0 ? String(format: NSLocalizedString("osd.subtitle_delay.later", comment: "Subtitle Delay: %fs Later"),abs(value)) : String(format: NSLocalizedString("osd.subtitle_delay.earlier", comment: "Subtitle Delay: %fs Earlier"), abs(value))
      }
      
    case .subPos(let value):
      return String(format: NSLocalizedString("osd.subtitle_pos", comment: "Subtitle Position: %f"), value)
      
    case .mute:
      return NSLocalizedString("osd.mute", comment: "Mute")
      
    case .unMute:
      return NSLocalizedString("osd.unmute", comment: "Unmute")
      
    case .screenShot:
      return NSLocalizedString("osd.screenshot", comment: "Screenshot captured")
      
    case .abLoop(let value):
      if value == 1 {
        return NSLocalizedString("osd.abloop.a", comment: "AB-Loop: A")
      } else if value == 2 {
        return NSLocalizedString("osd.abloop.b", comment: "AB-Loop: B")
      } else {
        return NSLocalizedString("osd.abloop.clear", comment: "AB-Loop: Cleared")
      }
      
    case .stop:
      return NSLocalizedString("osd.stop", comment: "Stopped")
      
    case .chapter(let name):
      return String(format: NSLocalizedString("osd.chapter", comment: "Chapter: %@"), name)
      
    case .subScale(let value):
      return String(format: NSLocalizedString("osd.subtitle_scale", comment: "Subtitle Scale: %.2fx"), value)
      
    case .addToPlaylist(let count):
      return String(format: NSLocalizedString("osd.add_to_playlist", comment: "Added %i files to playlist"), count)
      
    case .clearPlaylist:
      return NSLocalizedString("osd.clear_playlist", comment: "Cleared playlist")
      
    case .contrast(let value):
      return String(format: NSLocalizedString("osd.graphic_equalizer.contrast", comment: "Contrast: %i"), value)
      
    case .gamma(let value):
      return String(format: NSLocalizedString("osd.graphic_equalizer.gamma", comment: "Grama: %i"), value)
      
    case .hue(let value):
      return String(format: NSLocalizedString("osd.graphic_equalizer.hue", comment: "Hue: %i"), value)
      
    case .saturation(let value):
      return String(format: NSLocalizedString("osd.graphic_equalizer.saturation", comment: "Saturation: %i"), value)
      
    case .brightness(let value):
      return String(format: NSLocalizedString("osd.graphic_equalizer.brightness", comment: "Brightness: %i"), value)
      
    }
  }
}
