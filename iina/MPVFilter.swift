//
//  MPVFilter.swift
//  iina
//
//  Created by lhc on 2/9/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

// See https://github.com/mpv-player/mpv/blob/master/options/m_option.c#L3161
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
   - parameter amount: Amount for la and ca. Should be in [-1.5, 1.5].
   */
  static func unsharp(amount: Float, msize: Int = 5) -> MPVFilter {
    let amountStr = amount.description
    let msizeStr = msize.description
    return MPVFilter(lavfiName: "unsharp", label: nil, params: [msizeStr, msizeStr, amountStr, msizeStr, msizeStr, amountStr])
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

  override var debugDescription: String {
    Mirror(reflecting: self).children.map({"\($0.label!)=\($0.value)"}).joined(separator: ", ")
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
    if name.hasPrefix("@") {
      // The name starts with a label. Separate them into the respected properties.
      name.removeFirst()
      let nameSplitted = name.split(separator: ":", maxSplits: 1).map { String($0) }
      guard nameSplitted.count == 2 else { return nil }
      self.label = nameSplitted[0]
      self.name = nameSplitted[1]
    }
    self.rawParamString = splitted[at: 1]
    self.params = MPVFilter.parseRawParamString(name, rawParamString)
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

  /// Names of filters without parameters or whose parameters do not need to be parsed.
  private static let doNotParse = ["crop", "flip", "hflip", "lavfi"]

  /// Parse the given string containing filter parameters.
  ///
  /// Filters that support multiple parameters have more than one valid string representation due to there being no requirement on the
  /// order in which those parameters are given in a filter. For such filters the string representation of the parameters needs to be parsed
  /// to form a `Dictionary` containing individual parameter-value pairs. This allows the parameters of two `MPVFilter` objects
  /// to be compared using a `Dictionary` to `Dictionary` comparison rather than a string comparison that might fail due to the
  /// parameters being in a different order in the string. This method will return `nil` if it determines this kind of filter can be compared
  /// using the string representation, or if parsing failed.
  /// - Note:
  /// Related issues:
  /// * [Audio filters with same name cannot be removed. #3620](https://github.com/iina/iina/issues/3620)
  /// * [mpv_get_property returns filter params in unordered map breaking remove #9841](https://github.com/mpv-player/mpv/issues/9841)
  /// - Parameter name: Name of the filter.
  /// - Parameter rawParamString: String to be parsed.
  /// - Returns: A `Dictionary` containing the filter parameters or `nil` if the parameters were not parsed.
  private static func parseRawParamString(_ name: String, _ rawParamString: String?) -> [String: String]? {
    guard let rawParamString = rawParamString, !doNotParse.contains(name) else { return nil }
    let pairs = rawParamString.split(separator: ":")
    // If there is only one parameter then parameter order is not an issue.
    guard pairs.count > 1 else { return nil }
    var dict: [String: String] = [:]
    for pair in pairs {
      let split = pair.split(separator: "=", maxSplits: 1).map { String($0) }
      guard split.count == 2 else {
        // This indicates either this kind of filter needs to be added to the doNotParse list, or
        // this parser needs to be enhanced to be able to parse the string representation of this
        // kind of filter.
        Logger.log("Unable to parse filter \(name) params: \(rawParamString)", level: .warning)
        return nil
      }
      // Add the pair to the dictionary stripping any %n% style quoting from the front of the value.
      dict[split[0]] = split[1].replacingOccurrences(of: "^%\\d+%", with: "",
                                                     options: .regularExpression)
    }
    return dict
  }

  // MARK: - Param getter

  /// Returns `true` if this filter is equal to the given filter `false` otherwise.
  ///
  /// Filters that support multiple parameters have more than one valid string representation due to there being no requirement on the
  /// order in which those parameters are given in a filter. In the `mpv_node` tree returned for the mpv property representing the audio
  /// filter list or the video filter list, filter parameters are contained in random order in a `MPV_FORMAT_NODE_MAP`. When IINA
  /// converts the `mpv_node` tree into `MPVFilter` objects parameters are stored in a `Dictionary` which also does not
  /// provide a predictable order. This is all correct behavior as per discussions with the mpv project in mpv issue #9841. Due to this
  /// issue with the string representation of some types of filters this method gives preference to comparing the dictionaries in the
  /// `params` property if available over comparing string representations.
  /// - Note:
  /// Related issues:
  /// * [Audio filters with same name cannot be removed. #3620](https://github.com/iina/iina/issues/3620)
  /// * [mpv_get_property returns filter params in unordered map breaking remove #9841](https://github.com/mpv-player/mpv/issues/9841)
  /// - Parameter object: The object to compare to this filter.
  /// - Returns: `true` if this filter is equal to the given object, otherwise `false`.
  override func isEqual(_ object: Any?) -> Bool {
    guard let object = object as? MPVFilter, label == object.label, name == object.name else { return false }
    if let lhs = params, let rhs = object.params {
      return lhs == rhs
    }
    return stringFormat == object.stringFormat
  }
}
