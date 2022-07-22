//
//  MPVInputSection.swift
//  iina
//
//  Created by Matt Svoboda on 2022.06.10.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class MPVInputSection: CustomStringConvertible {
  static let FLAG_DEFAULT = "default"
  static let FLAG_FORCE = "force"
  static let FLAG_EXCLUSIVE = "exclusive"

  let name: String
  let keyBindings: [KeyMapping]
  let isForce: Bool

  init(name: String, _ keyBindingsDict: [String: KeyMapping], isForce: Bool) {
    self.name = name
    self.keyBindings = Array(keyBindingsDict.values)
    self.isForce = isForce
  }

  init(name: String, _ keyBindingsArray: [KeyMapping], isForce: Bool) {
    self.name = name
    self.keyBindings = keyBindingsArray
    self.isForce = isForce
  }

  var description: String {
    get {
      "InputSection(\"\(name)\", \(isForce ? "force" : "weak"), \(keyBindings.count) bindings)"
    }
  }
}
