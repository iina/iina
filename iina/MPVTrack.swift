//
//  MPVTrack.swift
//  iina
//
//  Created by lhc on 31/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class MPVTrack: NSObject {

  /** For binding a none track object to menu, id = 0 */
  static let noneVideoTrack: MPVTrack = {
    let track = MPVTrack(id: 0, type: .video, isDefault: false, isForced: false, isSelected: false, isExternal: false)
    track.title = NSLocalizedString("track.none", comment: "<None>")
    return track
  }()
  /** For binding a none track object to menu, id = 0 */
  static let noneAudioTrack: MPVTrack = {
    let track = MPVTrack(id: 0, type: .audio, isDefault: false, isForced: false, isSelected: false, isExternal: false)
    track.title = NSLocalizedString("track.none", comment: "<None>")
    return track
  }()
  /** For binding a none track object to menu, id = 0 */
  static let noneSubTrack: MPVTrack = {
    let track = MPVTrack(id: 0, type: .sub, isDefault: false, isForced: false, isSelected: false, isExternal: false)
    track.title = NSLocalizedString("track.none", comment: "<None>")
    return track
  }()
  /** For binding a none track object to menu, id = 0 */
  static let noneSecondSubTrack = MPVTrack(id: 0, type: .secondSub, isDefault: false, isForced: false, isSelected: false, isExternal: false)

  static func emptyTrack(for type: TrackType) -> MPVTrack {
    switch type {
    case .video: return noneVideoTrack
    case .audio: return noneAudioTrack
    case .sub: return noneSubTrack
    case .secondSub: return noneSecondSubTrack
    }

  }

  enum TrackType: String {
    case audio = "audio"
    case video = "video"
    case sub = "sub"
    // Only for setting a second sub track, hence the raw value is unused
    case secondSub = "secondSub"
  }

  var id: Int
  var type: TrackType
  var srcId: Int?
  var title: String?
  var lang: String?
  var isDefault: Bool
  var isForced: Bool
  var isSelected: Bool
  var isExternal: Bool
  var externalFilename: String?
  var codec: String?
  var demuxW: Int?
  var demuxH: Int?
  var demuxChannelCount: Int?
  var demuxChannels: String?
  var demuxSamplerate: Int?
  var demuxFps: Double?


  var readableTitle: String { "\(idString) \(infoString)" }

  var idString: String { "#\(id)" }

  var infoString: String {
    get {
      // title
      let title = title ?? ""
      // lang
      let language: String
      if let lang, lang != "und", let rawLang = ISO639Helper.dictionary[lang] {
        language = "[\(rawLang)]"
      } else {
        language = ""
      }
      // info
      var components: [String] = []
      if let codec {
        components.append(codec)
      }
      switch type {
      case .video:
        if let demuxW, let demuxH {
          components.append("\(demuxW)\u{d7}\(demuxH)")
        }
        if let demuxFps {
          components.append("\(demuxFps.prettyFormat())fps")
        }
      case .audio:
        if let demuxChannelCount {
          components.append("\(demuxChannelCount)ch")
        }
        if let demuxSamplerate {
          components.append("\((Double(demuxSamplerate)/1000).prettyFormat())kHz")
        }
      default:
        break
      }
      let info = components.joined(separator: ", ")
      // default
      let isDefault = isDefault ? "(" + NSLocalizedString("quicksetting.item_default", comment: "Default") + ")" : ""
      // final string
      return [language, title, info, isDefault].filter { !$0.isEmpty }.joined(separator: " ")
    }

  }

  var isAlbumart: Bool = false

  // unimplemented

  var decoderDesc: String?

  init(id: Int, type: TrackType, isDefault: Bool, isForced: Bool, isSelected: Bool, isExternal: Bool) {
    self.id = id
    self.type = type
    self.isDefault = isDefault
    self.isForced = isForced
    self.isSelected = isSelected
    self.isExternal = isExternal
  }

  // Utils

  var isImageSub: Bool {
    get {
      if type == .video || type == .audio { return false }
      // demux/demux_mkv.c:1727
      return codec == "hdmv_pgs_subtitle" || codec == "dvb_subtitle"
    }
  }

  var isAssSub: Bool {
    get {
      if type == .video || type == .audio { return false }
      // demux/demux_mkv.c:1727
      return codec == "ass"
    }
  }
}
