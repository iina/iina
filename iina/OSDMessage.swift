//
//  OSDMessage.swift
//  iina
//
//  Created by lhc on 27/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

/// Available constants in OSD messages:
///
/// {{duration}}
/// {{position}}
/// {{percentPos}}
/// {{currChapter}}
/// {{chapterCount}}

import Foundation

fileprivate func toPercent(_ value: Double, _ bound: Double) -> Double {
  return (value + bound).clamped(to: 0...(bound * 2)) / (bound * 2)
}

enum OSDType {
  case normal
  case withText(String)
  case withProgress(Double)
}

enum OSDMessage {

  case fileStart(String)

  case pause
  case resume
  case seek(String, Double)  // text, percentage
  case volume(Int)
  case speed(Double)
  case aspect(String)
  case crop(String)
  case rotate(Int)
  case deinterlace(Bool)
  case hwdec(Bool)
  case audioDelay(Double)
  case subDelay(Double)
  case subScale(Double)
  case subPos(Double)
  case mute
  case unMute
  case screenshot
  case abLoop(Int)
  case stop
  case chapter(String)
  case track(MPVTrack)
  case addToPlaylist(Int)
  case clearPlaylist

  case contrast(Int)
  case hue(Int)
  case saturation(Int)
  case brightness(Int)
  case gamma(Int)

  case addFilter(String)
  case removeFilter

  case startFindingSub(String)  // sub source
  case foundSub(Int)
  case downloadedSub(String)  // filename
  case savedSub
  case cannotLogin
  case fileError
  case networkError
  case canceled
  case fileLoop(Bool)
  case playlistLoop(Bool)

  case custom(String)

  func message() -> (String, OSDType) {
    switch self {
    case .fileStart(let filename):
      return (filename, .normal)

    case .pause:
      return (NSLocalizedString("osd.pause", comment: "Pause"), .withText("{{position}} / {{duration}}"))

    case .resume:
      return (NSLocalizedString("osd.resume", comment: "Resume"), .withText("{{position}} / {{duration}}"))

    case .seek(let text, let percent):
      return (text, .withProgress(percent))

    case .volume(let value):
      return (
        String(format: NSLocalizedString("osd.volume", comment: "Volume: %i"), value),
        .withProgress(Double(value) / Double(Preference.integer(for: .maxVolume)))
      )

    case .speed(let value):
      return (
        String(format: NSLocalizedString("osd.speed", comment: "Speed: %.2fx"), value),
        .normal
      )

    case .aspect(var value):
      if value == "Default" {
        value = Constants.String.default
      }
      return (
        String(format: NSLocalizedString("osd.aspect", comment: "Aspect Ratio: %@"), value),
        .normal
      )

    case .crop(var value):
      if value == "None" {
        value = Constants.String.none
      }
      return (
        String(format: NSLocalizedString("osd.crop", comment: "Crop: %@"), value),
        .normal
      )

    case .rotate(let value):
      return (
        String(format: NSLocalizedString("osd.rotate", comment: "Rotate: %i°"), value),
        .normal
      )

    case .deinterlace(let enabled):
      return (
        String(format: NSLocalizedString("osd.deinterlace", comment: "Deinterlace: %@"), enabled ? NSLocalizedString("general.on", comment: "On") : NSLocalizedString("general.off", comment: "Off")),
        .normal
      )

    case .hwdec(let enabled):
      return (
        String(format: NSLocalizedString("osd.hwdec", comment: "Hardware Decoding: %@"), enabled ? NSLocalizedString("general.on", comment: "On") : NSLocalizedString("general.off", comment: "Off")),
        .normal
      )

    case .audioDelay(let value):
      if value == 0 {
        return (
          NSLocalizedString("osd.audio_delay.nodelay", comment: "Audio Delay: No Delay"),
          .withProgress(0.5)
        )
      } else {
        let str = value > 0 ? String(format: NSLocalizedString("osd.audio_delay.later", comment: "Audio Delay: %fs Later"),abs(value)) : String(format: NSLocalizedString("osd.audio_delay.earlier", comment: "Audio Delay: %fs Earlier"), abs(value))
        return (str, .withProgress(toPercent(value, 10)))
      }

    case .subDelay(let value):
      if value == 0 {
        return (
          NSLocalizedString("osd.sub_delay.nodelay", comment: "Subtitle Delay: No Delay"),
          .withProgress(0.5)
        )
      } else {
        let str = value > 0 ? String(format: NSLocalizedString("osd.sub_delay.later", comment: "Subtitle Delay: %fs Later"),abs(value)) : String(format: NSLocalizedString("osd.sub_delay.earlier", comment: "Subtitle Delay: %fs Earlier"), abs(value))
        return (str, .withProgress(toPercent(value, 10)))
      }

    case .subPos(let value):
      return (
        String(format: NSLocalizedString("osd.subtitle_pos", comment: "Subtitle Position: %f"), value),
        .withProgress(value / 100)
      )

    case .mute:
      return (NSLocalizedString("osd.mute", comment: "Mute"), .normal)

    case .unMute:
      return (NSLocalizedString("osd.unmute", comment: "Unmute"), .normal)

    case .screenshot:
      return (NSLocalizedString("osd.screenshot", comment: "Screenshot Captured"), .normal)

    case .abLoop(let value):
      if value == 1 {
        return (NSLocalizedString("osd.abloop.a", comment: "AB-Loop: A"), .withText("{{position}} / {{duration}}"))
      } else if value == 2 {
        return (NSLocalizedString("osd.abloop.b", comment: "AB-Loop: B"), .withText("{{position}} / {{duration}}"))
      } else {
        return (NSLocalizedString("osd.abloop.clear", comment: "AB-Loop: Cleared"), .normal)
      }

    case .stop:
      return (NSLocalizedString("osd.stop", comment: "Stop"), .normal)

    case .chapter(let name):
      return (
        String(format: NSLocalizedString("osd.chapter", comment: "Chapter: %@"), name),
        .withText("({{currChapter}}/{{chapterCount}}) {{position}} / {{duration}}")
      )

    case .track(let track):
      let trackTypeStr: String
      switch track.type {
      case .video: trackTypeStr = "Video"
      case .audio: trackTypeStr = "Audio"
      case .sub: trackTypeStr = "Subtitle"
      case .secondSub: trackTypeStr = "Second Subtitle"
      }
      return (trackTypeStr + ": " + track.readableTitle, .normal)

    case .subScale(let value):
      return (
        String(format: NSLocalizedString("osd.subtitle_scale", comment: "Subtitle Scale: %.2fx"), value),
        .normal
      )

    case .addToPlaylist(let count):
      return (
        String(format: NSLocalizedString("osd.add_to_playlist", comment: "Added %i Files to Playlist"), count),
        .normal
      )

    case .clearPlaylist:
      return (NSLocalizedString("osd.clear_playlist", comment: "Cleared Playlist"), .normal)

    case .contrast(let value):
      return (
        String(format: NSLocalizedString("osd.video_eq.contrast", comment: "Contrast: %i"), value),
        .withProgress(toPercent(Double(value), 100))
      )

    case .gamma(let value):
      return (
        String(format: NSLocalizedString("osd.video_eq.gamma", comment: "Grama: %i"), value),
        .withProgress(toPercent(Double(value), 100))
      )

    case .hue(let value):
      return (
        String(format: NSLocalizedString("osd.video_eq.hue", comment: "Hue: %i"), value),
        .withProgress(toPercent(Double(value), 100))
      )

    case .saturation(let value):
      return (
        String(format: NSLocalizedString("osd.video_eq.saturation", comment: "Saturation: %i"), value),
        .withProgress(toPercent(Double(value), 100))
      )

    case .brightness(let value):
      return (
        String(format: NSLocalizedString("osd.video_eq.brightness", comment: "Brightness: %i"), value),
        .withProgress(toPercent(Double(value), 100))
      )

    case .addFilter(let name):
      return (
        String(format: NSLocalizedString("osd.filter_added", comment: "Added Filter: %@"), name),
        .normal
      )

    case .removeFilter:
      return (
        NSLocalizedString("osd.filter_removed", comment: "Removed Filter"),
        .normal
      )

    case .startFindingSub(let source):
      return (
        NSLocalizedString("osd.find_online_sub", comment: "Finding online subtitles..."),
        .withText(NSLocalizedString("osd.find_online_sub.source", comment: "from") + " " + source)
      )

    case .foundSub(let count):
      let str = count == 0 ?
        NSLocalizedString("osd.sub_not_found", comment: "No subtitles found.") :
        String(format: NSLocalizedString("osd.sub_found", comment: "%d subtitle(s) found. Downloading..."), count)
      return (str, .normal)

    case .downloadedSub(let filename):
      return (
        NSLocalizedString("osd.sub_downloaded", comment: "Subtitle downloaded"),
        .withText(filename)
      )

    case .savedSub:
      return (
        NSLocalizedString("osd.sub_saved", comment: "Subtitle saved"),
        .normal
      )

    case .networkError:
      return (
        NSLocalizedString("osd.network_error", comment: "Network error"),
        .normal
      )

    case .fileError:
      return (
        NSLocalizedString("osd.file_error", comment: "Error reading file"),
        .normal
      )

    case .cannotLogin:
      return (
        NSLocalizedString("osd.cannot_login", comment: "Cannot login"),
        .normal
      )

    case .canceled:
      return (
        NSLocalizedString("osd.canceled", comment: "Canceled"),
        .normal
      )

    case .fileLoop(let enabled):
      return (
        String(format: NSLocalizedString("osd.file_loop", comment: "File Loop: %@"),
               enabled ? NSLocalizedString("general.on", comment: "On") : NSLocalizedString("general.off", comment: "Off")),
        .normal
      )

    case .playlistLoop(let enabled):
      return (
        String(format: NSLocalizedString("osd.playlist_loop", comment: "Playlist Loop: %@"),
               enabled ? NSLocalizedString("general.on", comment: "On") : NSLocalizedString("general.off", comment: "Off")),
        .normal
      )
    case .custom(let message):
      return (message, .normal)
    }
  }
}
