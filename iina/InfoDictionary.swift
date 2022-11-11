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
class InfoDictionary {
  
  static let shared = InfoDictionary()

  let buildBranch: String?
  let buildCommit: String?
  let buildDate: String?
  
  let bundleIdentifier: String
  
  var copyright: String { Bundle.main.infoDictionary!["NSHumanReadableCopyright"] as! String }

  var version: (String, String) {
    let infoDic = Bundle.main.infoDictionary!
    return (infoDic["CFBundleShortVersionString"] as! String, infoDic["CFBundleVersion"] as! String)
  }

  private init() {
    let infoDic = Bundle.main.infoDictionary!
    bundleIdentifier = infoDic["CFBundleIdentifier"] as! String

    // As recommended by Apple, IINA's custom Info.plist keys start with the bundle identifier.
    let keyPrefix = bundleIdentifier + ".build"
    buildBranch = infoDic["\(keyPrefix).branch"] as? String
    buildCommit = infoDic["\(keyPrefix).commit"] as? String
    
    // Xcode refused to allow the build date in the Info.plist to use Date as the type because the
    // value specified in the Info.plist is an identifier that is replaced at build time using the
    // C preprocessor. So we need to convert from the ISO formatted string to a Date object.
    let fromString = ISO8601DateFormatter()
    guard let date = infoDic["\(keyPrefix).date"] as? String,
          let dateObj = fromString.date(from: date) else {
      buildDate = nil
      return
    }
    // Use a localized date for the build date.
    let toString = DateFormatter()
    toString.dateStyle = .medium
    toString.timeStyle = .medium
    buildDate = toString.string(from: dateObj)
  }
}
