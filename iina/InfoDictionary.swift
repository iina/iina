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
  var buildConfiguration: String? { dictionary["\(buildKeyPrefix).configuration"] as? String }
  var buildCommit: String? { dictionary["\(buildKeyPrefix).commit"] as? String }
  var shortCommitSHA: String? {
    guard let buildCommit = buildCommit else { return nil }
    return String(buildCommit.prefix(7))
  }

  var buildDate: String? {
    let dateParser: (String) -> Date?
    if #available(macOS 10.12, *) {
      let formatter = ISO8601DateFormatter()
      dateParser = formatter.date(from:)
    } else {
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
      dateParser = formatter.date(from:)
    }
    guard let date = dictionary["\(buildKeyPrefix).date"] as? String,
          let dateObj = dateParser(date) else {
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

  /// The type of build used to generate this IINA executable.
  ///
  /// This corresponds to the Xcode build configuration.
  var buildType: BuildType {
    guard let buildConfiguration = buildConfiguration else { return .nightly }
    return BuildType(rawValue: buildConfiguration) ?? .nightly
  }

  /// A string identifying the Xcode build configuration that was used to generate this executable.
  ///
  /// IINA's convention is that if there is no indication of the type of build then it is a release build. Therefore this property is `nil` if
  /// this executable was built using the release configuration. Otherwise this property contains a string suitable for display to the user.
  var buildTypeIdentifier: String? { buildType == .release ? nil : buildType.description }

  var bundleIdentifier: String { dictionary["CFBundleIdentifier"] as! String }

  var copyright: String { dictionary["NSHumanReadableCopyright"] as! String }

  let dictionary = Bundle.main.infoDictionary!

  /// A Boolean value that indicates whether this executable was an optimized (not debug) build.
  #if DEBUG
  let isDebug = true
  #else
  let isDebug = false
  #endif

  var version: (String, String) {
    return (dictionary["CFBundleShortVersionString"] as! String,
            dictionary["CFBundleVersion"] as! String)
  }

  // MARK: - Enums

  /// Enum corresponding to the build configurations in IINA's Xcode project.
  enum BuildType: String, CustomStringConvertible {
    case beta = "Beta"
    case nightly = "Nightly"
    case release = "Release"
    case debug = "Debug"

    /// A textual representation of this instance.
    ///
    /// IINA's convention is to display the build type in capital letters to ensure it is not over looked.
    var description: String {
      switch self {
      case .beta: return "BETA"
      case .nightly: return "NIGHTLY"
      case .release: return "RELEASE"
      case .debug: return "DEBUG"
      }
    }
  }
}
