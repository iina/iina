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

  unowned var player: PlayerCore?


  var readableTitle: String {
    get {
      return "\(self.idString) \(self.infoString)"
    }
  }

  var idString: String {
    get {
      return "#\(self.id)"
    }
  }

  var infoString: String {
    get {
      // title
      let title = self.title ?? ""
      // lang
      let language: String
      if let lang = self.lang, lang != "und", let rawLang = ISO639Helper.dictionary[lang] {
        language = "[\(rawLang)]"
      } else {
        language = ""
      }
      // info
      var components: [String] = []
      if let ds = self.decoderDesc, let shortDs = ds.components(separatedBy: "(")[at: 0] {
        components.append("\(shortDs.replacingOccurrences(of: " ", with: ""))")
      }
      switch self.type {
      case .video:
        if let w = self.demuxW, let h = self.demuxH {
          components.append("\(w)\u{d7}\(h)")
        }
        if let fps = self.demuxFps {
          components.append("\(fps.prettyFormat())fps")
        }
      case .audio:
        if let ch = self.demuxChannelCount {
          components.append("\(ch)ch")
        }
        if let sr = self.demuxSamplerate {
          components.append("\((Double(sr)/1000).prettyFormat())kHz")
        }
      default:
        break
      }
      let info = components.joined(separator: ", ")
      // default
      let isDefault = self.isDefault ? "(" + NSLocalizedString("quicksetting.item_default", comment: "Default") + ")" : ""
      // final string
      return [language, title, info, isDefault].filter { !$0.isEmpty }.joined(separator: " ")
    }

  }

  var isAlbumart: Bool = false

  // unimplemented

  var ffIndex: Int?
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
