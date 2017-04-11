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

  case startFindingSub
  case foundSub(Int)
  case downloadedSub
  case savedSub
  case cannotLogin
  case fileError
  case networkError
  case canceled


  func message() -> String {
    switch self {
    case .pause:
      return NSLocalizedString("osd.pause", comment: "Pause")

    case .resume:
      return NSLocalizedString("osd.resume", comment: "Resume")

    case .volume(let value):
      return String(format: NSLocalizedString("osd.volume", comment: "Volume: %i"), value)

    case .speed(let value):
      return String(format: NSLocalizedString("osd.speed", comment: "Speed: %.2fx"), value)

    case .aspect(let value):
      return String(format: NSLocalizedString("osd.aspect", comment: "Aspect Ratio: %@"),value)

    case .crop(let value):
      return String(format: NSLocalizedString("osd.crop", comment: "Crop: %@"), value)

    case .rotate(let value):
      return String(format: NSLocalizedString("osd.rotate", comment: "Rotate: %i°"), value)

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
        return NSLocalizedString("osd.sub_delay.nodelay", comment: "Subtitle Delay: No Delay")
      } else {
                return value > 0 ? String(format: NSLocalizedString("osd.sub_delay.later", comment: "Subtitle Delay: %fs Later"),abs(value)) : String(format: NSLocalizedString("osd.sub_delay.earlier", comment: "Subtitle Delay: %fs Earlier"), abs(value))
      }

    case .subPos(let value):
      return String(format: NSLocalizedString("osd.subtitle_pos", comment: "Subtitle Position: %f"), value)

    case .mute:
      return NSLocalizedString("osd.mute", comment: "Mute")

    case .unMute:
      return NSLocalizedString("osd.unmute", comment: "Unmute")

    case .screenShot:
      return NSLocalizedString("osd.screenshot", comment: "Screenshot Captured")

    case .abLoop(let value):
      if value == 1 {
        return NSLocalizedString("osd.abloop.a", comment: "AB-Loop: A")
      } else if value == 2 {
        return NSLocalizedString("osd.abloop.b", comment: "AB-Loop: B")
      } else {
        return NSLocalizedString("osd.abloop.clear", comment: "AB-Loop: Cleared")
      }

    case .stop:
      return NSLocalizedString("osd.stop", comment: "Stop")

    case .chapter(let name):
      return String(format: NSLocalizedString("osd.chapter", comment: "Chapter: %@"), name)

    case .subScale(let value):
      return String(format: NSLocalizedString("osd.subtitle_scale", comment: "Subtitle Scale: %.2fx"), value)

    case .addToPlaylist(let count):
      return String(format: NSLocalizedString("osd.add_to_playlist", comment: "Added %i Files to Playlist"), count)

    case .clearPlaylist:
      return NSLocalizedString("osd.clear_playlist", comment: "Cleared Playlist")

    case .contrast(let value):
      return String(format: NSLocalizedString("osd.video_eq.contrast", comment: "Contrast: %i"), value)

    case .gamma(let value):
      return String(format: NSLocalizedString("osd.video_eq.gamma", comment: "Grama: %i"), value)

    case .hue(let value):
      return String(format: NSLocalizedString("osd.video_eq.hue", comment: "Hue: %i"), value)

    case .saturation(let value):
      return String(format: NSLocalizedString("osd.video_eq.saturation", comment: "Saturation: %i"), value)

    case .brightness(let value):
      return String(format: NSLocalizedString("osd.video_eq.brightness", comment: "Brightness: %i"), value)

    case .startFindingSub:
      return NSLocalizedString("osd.find_online_sub", comment: "Finding online subtitles...")

    case .foundSub(let count):
      return count == 0 ?
        NSLocalizedString("osd.sub_not_found", comment: "No subtitle found.") :
        String(format: NSLocalizedString("osd.sub_found", comment: "%d subtitle(s) found. Downloading..."), count)

    case .downloadedSub:
      return NSLocalizedString("osd.sub_downloaded", comment: "Subtitle downloaded")

    case .savedSub:
      return NSLocalizedString("osd.sub_saved", comment: "Subtitle saved")

    case .networkError:
      return NSLocalizedString("osd.network_error", comment: "Network error")

    case .fileError:
      return NSLocalizedString("osd.file_error", comment: "Error reading file")

    case .cannotLogin:
      return NSLocalizedString("osd.cannot_login", comment: "Cannot login")

    case .canceled:
      return NSLocalizedString("osd.canceled", comment: "Canceled")
    }
  }
}
