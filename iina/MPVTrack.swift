//
//  MPVTrack.swift
//  iina
//
//  Created by lhc on 31/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class MPVTrack: NSObject {
  
  /** For binding a none track object to menu, id = 0 */
  static let noneVideoTrack = MPVTrack(id: 0, type: .video, isDefault: false, isForced: false, isSelected: false, isExternal: false)
  /** For binding a none track object to menu, id = 0 */
  static let noneAudioTrack = MPVTrack(id: 0, type: .audio, isDefault: false, isForced: false, isSelected: false, isExternal: false)
  /** For binding a none track object to menu, id = 0 */
  static let noneSubTrack = MPVTrack(id: 0, type: .sub, isDefault: false, isForced: false, isSelected: false, isExternal: false)
  /** For binding a none track object to menu, id = 0 */
  static let noneSecongSubTrack = MPVTrack(id: 0, type: .secondSub, isDefault: false, isForced: false, isSelected: false, isExternal: false)
  
  static func emptyTrack(_ type: TrackType) -> MPVTrack {
    switch type {
    case .video: return noneVideoTrack
    case .audio: return noneAudioTrack
    case .sub: return noneSubTrack
    case .secondSub: return noneSecongSubTrack
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
  
  var readableTitle: String {
    get {
      let title = self.title ?? ""
      let rawLang = self.lang ?? ""
      let lang = rawLang == "" ? "" : "[\(rawLang)]"
      let def = self.isDefault ? "(Default)" : ""
      return "#\(self.id) \(title) \(lang) \(def)"
    }
  }
  
  // unimplemented
  
  var isAlbumart: Bool?
  
  var ffIndex: Int?
  var decoderDesc: String?
  var demuxW: Int?
  var demuxH: Int?
  var demuxChannelCount: Int?
  var demuxChannels: String?
  var demuxSamplerate: Int?
  var demuxFps: Double?
  
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
