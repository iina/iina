//
//  MPVFilter.swift
//  iina
//
//  Created by lhc on 2/9/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

// FIXME: can refactor using RawRepresent
class MPVFilter: NSObject {

  enum FilterType: String {
    case crop = "crop"
    case flip = "flip"
    case mirror = "mirror"
    case lavfi = "lavfi"
  }

  // MARK: - Static filters

  static func crop(w: Int?, h: Int?, x: Int?, y: Int?) -> MPVFilter {
    let f = MPVFilter(name: "crop", label: nil,
                      params: ["w": w?.toStr() ?? "", "h": h?.toStr() ?? "", "x": x?.toStr() ?? "", "y": y?.toStr() ?? ""])
    return f
  }

  static func flip() -> MPVFilter {
    return MPVFilter(name: "flip", label: nil, params: nil)
  }

  static func mirror() -> MPVFilter {
    return MPVFilter(name: "mirror", label: nil, params: nil)
  }

  /** 
   A ffmpeg `unsharp` filter.
   Args: l(uma)x, ly, la, c(hroma)x, xy, ca; default 5:5:0:5:5:0.
   We only change la and ca here.
   - parameter amount: Anount for la and ca. Should be in [-1.5, 1.5].
   */
  static func unsharp(amount: Float) -> MPVFilter {
    let amoutStr = "\(amount)"
    return MPVFilter(lavfiName: "unsharp", label: nil, params: ["5", "5", amoutStr, "5", "5", amoutStr])
  }

  // MARK: - Members

  var type: FilterType?
  var name: String
  var label: String?
  var params: [String: String]?
  var rawParamString: String?

  var stringFormat: String {
    get {
      var str = ""
      if let label = label { str += "@\(label):" }
      str += name
      if let rpstr = rawParamString {
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
          str += params!.map({ (k, v) -> String in return "\(k)=\(v)" }).joined(separator: ":")
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
    self.params = params
  }

  init?(rawString: String) {
    let splitted = rawString.characters.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true).map { String($0) }
    guard splitted.count == 1 || splitted.count == 2 else { return nil }
    self.name = splitted[0]
    self.rawParamString = splitted.at(1)
  }

  init(lavfiName: String, label: String?, params: [String]) {
    self.name = "lavfi"
    self.type = FilterType(rawValue: name)
    self.label = label
    var ffmpegGraph = "[\(lavfiName)="
    ffmpegGraph += params.joined(separator: ":")
    ffmpegGraph += "]"
    self.rawParamString = ffmpegGraph
  }

  init(lavfiName: String, label: String?, parmDict: [String: String]) {
    self.name = "lavfi"
    self.type = FilterType(rawValue: name)
    self.label = label
    var ffmpegGraph = "[\(lavfiName)="
    ffmpegGraph += parmDict.map { "\($0)=\($1)" }.joined(separator: ":")
    ffmpegGraph += "]"
    self.rawParamString = ffmpegGraph
  }

  // MARK: - Others

  static let formats: [FilterType: String] = [
    .crop: "w:h:x:y"
  ]

  // MARK: - Param getter

  func cropParams(videoSize: NSSize) -> [String: Double] {
    guard type == .crop else {
      Utility.fatal("Trying to get crop params from a non-crop filter!")
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

