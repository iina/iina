//
//  InfoDictionary.swift
//  iina
//
//  Created by low-batt on 10/9/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/// Wrapper for the dictionary constructed from the bundle’s `Info.plist` file.
///
/// This class exposes some of the entries contained in `Bundle.main.infoDictionary` as properties to provide for easier access
/// to information contained in the dictionary from other classes.
struct InfoDictionary {

  static let shared = InfoDictionary()

  var buildBranch: String? { dictionary["\(buildKeyPrefix).branch"] as? String }
  var buildCommit: String? { dictionary["\(buildKeyPrefix).commit"] as? String }
  var buildDate: String? {
    let fromString = ISO8601DateFormatter()
    guard let date = dictionary["\(buildKeyPrefix).date"] as? String,
          let dateObj = fromString.date(from: date) else {
      return nil
    }
    // Use a localized date for the build date.
    let toString = DateFormatter()
    toString.dateStyle = .medium
    toString.timeStyle = .medium
    return toString.string(from: dateObj)
  }

  private var buildKeyPrefix: String {
    // As recommended by Apple, IINA's custom Info.plist keys start with the bundle identifier.
    bundleIdentifier + ".build"
  }

  var bundleIdentifier: String { dictionary["CFBundleIdentifier"] as! String }

  var copyright: String { dictionary["NSHumanReadableCopyright"] as! String }

  let dictionary = Bundle.main.infoDictionary!

  var version: (String, String) {
    return (dictionary["CFBundleShortVersionString"] as! String,
            dictionary["CFBundleVersion"] as! String)
  }
}
