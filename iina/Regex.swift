//
//  Regex.swift
//  iina
//
//  Created by lhc on 12/1/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

class Regex {

  static let aspect = Regex("\\A\\d+(\\.\\d+)?:\\d+(\\.\\d+)?\\Z")
  static let httpFileName = Regex("attachment; filename=(.+?)\\Z")
  static let url = Regex("^(https?|ftp)://[^\\s/$.?#].[^\\s]*$")
  static let filePath = Regex("^(/[^/]+)+$")
  static let iso639_2Desc = Regex("^.+?\\(([a-z]{3})\\)$")
  static let geometry = Regex("^((\\d+%?)?(x(\\d+%?))?)?((\\+|\\-)(\\d+%?)(\\+|\\-)(\\d+%?))?$")
  static let mpvURL = Regex("^[A-z0-9_]+://")

  var regex: NSRegularExpression?

  init (_ pattern: String) {
    if let exp = try? NSRegularExpression(pattern: pattern, options: []) {
      self.regex = exp
    } else {
      Utility.fatal("Cannot create regex \(pattern)")
    }
  }

  func matches(_ str: String) -> Bool {
    if let matches = regex?.numberOfMatches(in: str, options: [], range: NSMakeRange(0, str.count)) {
      return matches > 0
    } else {
      return false
    }
  }

  func captures(in str: String) -> [String] {
    var result: [String] = []
    if let match = regex?.firstMatch(in: str, options: [], range: NSMakeRange(0, str.count)) {
      for i in 0..<match.numberOfRanges {
        let range = match.range(at: i)
        if range.length > 0 {
          result.append((str as NSString).substring(with: match.range(at: i)))
        } else {
          result.append("")
        }
      }
    }
    return result
  }
}
