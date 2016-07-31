//
//  MPVTrack.swift
//  mpvx
//
//  Created by lhc on 31/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class MPVTrack: NSObject {
  
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
  
}
