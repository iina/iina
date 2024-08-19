//
//  FirstRunManager.swift
//  iina
//
//  Created by Collider LI on 29/1/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation

class FirstRunManager {
  struct Key: RawRepresentable {
    typealias RawValue = String
    var rawValue: String

    init(_ value: String) {
      self.rawValue = value
    }

    init(rawValue: String) {
      self.rawValue = rawValue
    }
  }

  static func isFirstRun(for key: Key) -> Bool {
    let filename = ".\(key.rawValue)"
    let fileURL = Utility.appSupportDirUrl.appendingPathComponent(filename, isDirectory: false)
    let exists = FileManager.default.fileExists(atPath: fileURL.path)
    if exists {
      return false
    } else {
      FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
      return true
    }
  }
}
