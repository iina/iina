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

  /// A textual representation of this instance.
  /// - Note: Optional properties that are `nil` are not included in the description of the instance.
  override var description: String {
    var result =
      """
      Track \(idString)
        type: \(type)\n
      """
    result += Mirror(reflecting: self).children.compactMap { child -> (String, String)? in
      guard let label = child.label, label != "id", label != "type" else { return nil }
      if case Optional<Any>.none = child.value { return nil }
      var value = String(describing: child.value)
      let prefix = "Optional("
      if value.hasPrefix(prefix), value.hasSuffix(")") {
        value = String(value.dropFirst(prefix.count).dropLast(1))
      }
      return (label, "\(value)")
    }.sorted { $0.0 < $1.0 }.map { "  \($0): \($1)" }.joined(separator: "\n")
    return result
  }

  var id: Int
  var type: TrackType
  var srcId: Int?
  var title: String?
  var lang: String?
  var isDefault: Bool
  var isForced: Bool
  var isImage: Bool
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


  var readableTitle: String { "\(idString) \(readableString())" }

  var idString: String { "#\(id)" }

  func readableString(includingLanguage: Bool = true) -> String {
    // title
    let title = title ?? NSLocalizedString("general.no_title", comment: "No Title")
    // lang
    let language: String
    if includingLanguage, let lang, lang != "und", let readableLanguage {
      language = "[\(readableLanguage)]"
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
    if isDefault {
      components.append(NSLocalizedString("quicksetting.item_default", comment: "Default"))
    }
    var info = components.joined(separator: ", ")
    if !info.isEmpty {
      info = "(\(info))"
    }
    // final string
    return [language, title, info].filter { !$0.isEmpty }.joined(separator: " ")
  }

  var readableLanguage: String? {
    lang.flatMap {
      Locale.current.localizedString(forIdentifier: $0)
    }
  }

  var isAlbumart: Bool = false

  // unimplemented

  var decoderDesc: String?

  init(id: Int, type: TrackType, isDefault: Bool, isForced: Bool, isImage: Bool = false,
       isSelected: Bool, isExternal: Bool) {
    self.id = id
    self.type = type
    self.isDefault = isDefault
    self.isForced = isForced
    self.isImage = isImage
    self.isSelected = isSelected
    self.isExternal = isExternal
  }

  /// Returns a `MVPTrack` object or `nil` if initialization fails..
  /// - Note: Failure of this initializer occurs if the given dictionary is missing required properties.
  /// - Parameter dict: A dictionary containing the properties of the track.
  convenience init?(_ dict: [String: Any]) {
    guard let idAsNodeValue = dict["id"], let typeAsString = dict["type"] as? String,
          let type =  MPVTrack.TrackType(rawValue: typeAsString),
          let isDefault = dict["default"] as? Bool, let isForced = dict["forced"] as? Bool,
          let isImage = dict["image"] as? Bool, let isSelected = dict["selected"] as? Bool,
          let isExternal = dict["external"] as? Bool else {
      // Internal error, should not occur.
      return nil
    }
    let id = MPVController.nodeValueAsInt(idAsNodeValue)
    self.init(id: id, type: type, isDefault: isDefault, isForced: isForced, isImage: isImage,
              isSelected: isSelected, isExternal: isExternal)
    srcId = MPVController.nodeValueAsInt(dict["src-id"])
    title = dict["title"] as? String
    lang = dict["lang"] as? String
    codec = dict["codec"] as? String
    externalFilename = dict["external-filename"] as? String
    isAlbumart = dict["albumart"] as? Bool ?? false
    decoderDesc = dict["decoder-desc"] as? String
    demuxW = MPVController.nodeValueAsInt(dict["demux-w"])
    demuxH = MPVController.nodeValueAsInt(dict["demux-h"])
    demuxFps = dict["demux-fps"] as? Double
    demuxChannelCount = MPVController.nodeValueAsInt(dict["demux-channel-count"])
    demuxChannels = dict["demux-channels"] as? String
    demuxSamplerate = MPVController.nodeValueAsInt(dict["demux-samplerate"])
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
