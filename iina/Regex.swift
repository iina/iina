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
  static let tagVersion = Regex("\\Av(\\d+\\.\\d+\\.\\d+)\\Z")

  var regex: NSRegularExpression?

  init (_ pattern: String) {
    if let exp = try? NSRegularExpression(pattern: pattern, options: []) {
      self.regex = exp
    } else {
      Utility.fatal("Cannot create regex \(pattern)")
    }
  }

  func matches(_ str: String) -> Bool {
    if let matches = regex?.numberOfMatches(in: str, options: [], range: NSMakeRange(0, str.characters.count)) {
      return matches > 0
    } else {
      return false
    }
  }

  func captures(in str: String) -> [String] {
    var result: [String] = []
    if let match = regex?.firstMatch(in: str, options: [], range: NSMakeRange(0, str.characters.count)) {
      for i in 0..<match.numberOfRanges {
        result.append((str as NSString).substring(with: match.rangeAt(i)))
      }
    }
    return result
  }
}
