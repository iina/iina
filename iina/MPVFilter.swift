//
//  MPVFilter.swift
//  iina
//
//  Created by lhc on 2/9/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

// See https://github.com/mpv-player/mpv/blob/master/options/m_option.c#L2955
// #define NAMECH "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
fileprivate let mpvAllowedCharacters = Set<Character>("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")

fileprivate extension String {
  var mpvQuotedFilterValue: String {
    return self.allSatisfy({ mpvAllowedCharacters.contains($0) }) ? self : mpvFixedLengthQuoted
  }
}

/**
 Represents a mpv filter. It can be either created by user or loaded from mpv.
 */
class MPVFilter: NSObject {

  enum FilterType: String {
    case crop = "crop"
    case expand = "expand"
    case flip = "flip"
    case mirror = "hflip"
    case lavfi = "lavfi"
  }

  // MARK: - Static filters

  static func crop(w: Int?, h: Int?, x: Int?, y: Int?) -> MPVFilter {
    let f = MPVFilter(name: "crop", label: nil,
                      params: ["w": w?.description ?? "", "h": h?.description ?? "", "x": x?.description ?? "", "y": y?.description ?? ""])
    return f
  }

  // FIXME: use lavfi vflip
  static func flip() -> MPVFilter {
    return MPVFilter(name: "vflip", label: nil, params: nil)
  }

  // FIXME: use lavfi hflip
  static func mirror() -> MPVFilter {
    return MPVFilter(name: "hflip", label: nil, params: nil)
  }

  /**
   A ffmpeg `unsharp` filter.
   Args: l(uma)x, ly, la, c(hroma)x, xy, ca; default 5:5:0:5:5:0.
   We only change la and ca here.
   - parameter msize: Value for lx, ly, cx and cy. Should be an odd integer in [3, 23].
   - parameter amount: Anount for la and ca. Should be in [-1.5, 1.5].
   */
  static func unsharp(amount: Float, msize: Int = 5) -> MPVFilter {
    let amoutStr = amount.description
    let msizeStr = msize.description
    return MPVFilter(lavfiName: "unsharp", label: nil, params: [msizeStr, msizeStr, amoutStr, msizeStr, msizeStr, amoutStr])
  }

  // MARK: - Members

  var type: FilterType?
  var name: String
  var label: String?
  var params: [String: String]?
  var rawParamString: String?

  /** Convert the filter to a valid mpv filter string. */
  var stringFormat: String {
    get {
      var str = ""
      // label
      if let label = label { str += "@\(label):" }
      // name
      str += name
      // params
      if let rpstr = rawParamString {
        // if is set by user
        str += "="
        str += rpstr
      } else if params != nil && params!.count > 0 {
        // if have format info, print using the format
        if type != nil, let format = MPVFilter.formats[type!] {
          str += "="
          str += format.components(separatedBy: ":").map { params![$0] ?? "" }.joined(separator: ":")
          // else print param names
        } else {
          str += "="
          // special tweak for lavfi filters
          if name == "lavfi" {
            str += "[\(params!["graph"]!)]"
          } else {
            str += params!.map { "\($0)=\($1.mpvQuotedFilterValue)" } .joined(separator: ":")
          }
        }
      }
      return str
    }
  }

  // MARK: - Initializers

  init(name: String, label: String?, params: [String: String]?) {
    self.type = FilterType(rawValue: name)
    self.name = name
    self.label = label
    if let params = params, let type = type, let format = MPVFilter.formats[type]?.components(separatedBy: ":") {
      var translated: [String: String] = [:]
      for (key, value) in params {
        if let number = Int(key.dropFirst()) {
          translated[format[number]] = value
        } else {
          translated[key] = value
        }
      }
      self.params = translated
    } else {
      self.params = params
    }
  }

  init?(rawString: String) {
    let splitted = rawString.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true).map { String($0) }
    guard splitted.count == 1 || splitted.count == 2 else { return nil }
    self.name = splitted[0]
    self.rawParamString = splitted[at: 1]
  }

  init(name: String, label: String?, paramString: String) {
    self.name = name
    self.type = FilterType(rawValue: name)
    self.label = label
    self.rawParamString = paramString
  }

  convenience init(lavfiName: String, label: String?, params: [String]) {
    var ffmpegGraph = "[\(lavfiName)="
    ffmpegGraph += params.joined(separator: ":")
    ffmpegGraph += "]"
    self.init(name: "lavfi", label: label, paramString: ffmpegGraph)
  }

  convenience init(lavfiName: String, label: String?, paramDict: [String: String]) {
    var ffmpegGraph = "[\(lavfiName)="
    ffmpegGraph += paramDict.map { "\($0)=\($1)" }.joined(separator: ":")
    ffmpegGraph += "]"
    self.init(name: "lavfi", label: label, paramString: ffmpegGraph)
  }

  convenience init(lavfiFilterFromPresetInstance instance: FilterPresetInstance) {
    var dict: [String: String] = [:]
    instance.params.forEach { (k, v) in
      dict[k] = v.stringValue
    }
    self.init(lavfiName: instance.preset.name, label: nil, paramDict: dict)
  }

  convenience init(mpvFilterFromPresetInstance instance: FilterPresetInstance) {
    var dict: [String: String] = [:]
    instance.params.forEach { (k, v) in
      dict[k] = v.stringValue
    }
    self.init(name: instance.preset.name, label: nil, params: dict)
  }

  // MARK: - Others

  /** The parameter order when omitting their names. */
  static let formats: [FilterType: String] = [
    .crop: "w:h:x:y",
    .expand: "w:h:x:y:aspect:round"
  ]

  // MARK: - Param getter

  func cropParams(videoSize: NSSize) -> [String: Double] {
    guard type == .crop else {
      Logger.fatal("Trying to get crop params from a non-crop filter!")
    }
    guard let params = params else { return [:] }
    // w and h should always valid
    let w = Double(params["w"]!)!
    let h = Double(params["h"]!)!
    let x: Double, y: Double
    // check x and y
    if let testx = Double(params["x"] ?? ""), let testy = Double(params["y"] ?? "") {
      x = testx
      y = testy
    } else {
      let cx = Double(videoSize.width) / 2
      let cy = Double(videoSize.height) / 2
      x = cx - w / 2
      y = cy - h / 2
    }

    return ["x": x, "y": y, "w": w, "h": h]
  }

}

