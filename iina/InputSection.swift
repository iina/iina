//
//  MPVInputSection.swift
//  iina
//
//  Created by Matt Svoboda on 2022.06.10.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

enum InputBindingOrigin: Codable {
  case confFile    // Input config file (can include @iina commands or mpv commands)
  case iinaPlugin  // Plugin menu key equivalent
  case savedFilter // Key equivalent for saved video or audio filter
  case libmpv      // Set by input sections transmitted over libmpv (almost always Lua scripts, but could include other RPC clients)
}

protocol InputSection: CustomStringConvertible {
  // Section name must be unique within a player core
  var name: String { get }

  var keyMappingList: [KeyMapping] { get }

  /*
   - If true, indicates that all bindings in `keyMappingList` are "force" (AKA "strong")
     according to the mpv vocabulary: each will always override any previous binding with the same key.
   - If false, indicates that they are all "weak" (AKA "default", AKA "builtin"): each will only be enabled
     if no previous binding with the same key has been set.
   */
  var isForce: Bool { get }

  /*
   Where this section came from (category). Note: "origin" is only used for display purposes
   */
  var origin: InputBindingOrigin { get }
}

class MPVInputSection: InputSection {
  static let FLAG_DEFAULT = "default"
  static let FLAG_FORCE = "force"
  static let FLAG_EXCLUSIVE = "exclusive"

  let name: String
  fileprivate(set) var keyMappingList: [KeyMapping]
  let isForce: Bool
  let origin: InputBindingOrigin

  init(name: String, _ keyMappingsDict: [String: KeyMapping], isForce: Bool, origin: InputBindingOrigin) {
    self.name = name
    self.keyMappingList = Array(keyMappingsDict.values)
    self.isForce = isForce
    self.origin = origin
  }

  init(name: String, _ keyMappingsArray: [KeyMapping], isForce: Bool, origin: InputBindingOrigin) {
    self.name = name
    self.keyMappingList = keyMappingsArray
    self.isForce = isForce
    self.origin = origin
  }

  var description: String {
    get {
      "MPVInputSection(\"\(name)\", \(isForce ? "force" : "weak"), \(keyMappingList.count) mappings)"
    }
  }
}

class SharedInputSection: MPVInputSection {
  // The "default" section contains the bindings loaded from the user's currently
  // selected input conf file, and will be shared for all `PlayerCore` instances.
  // Note: mpv expects this section to be named "default", so this constant should not be changed.
  static let USER_CONF_SECTION_NAME = "default"

  static let VIDEO_FILTERS_SECTION_NAME = "IINA Video Filters"
  static let AUDIO_FILTERS_SECTION_NAME = "IINA Audio Filters"

  // One section to store the key equivalents for all the IINA plugins.
  // Only one instance of this exists for the whole IINA app.
  // Its `keyMappingList` will be regenerated each time the Plugin menu is updated.
  static let PLUGINS_SECTION_NAME = "IINA Plugins"

  init(name: String, isForce: Bool, origin: InputBindingOrigin) {
    super.init(name: name, [], isForce: isForce, origin: origin)
  }

  func setKeyMappingList(_ keyMappingList: [KeyMapping]) {
    Logger.log("Replacing all mappings in section \"\(name)\" with \(keyMappingList.count) mappings", level: .verbose)
    self.keyMappingList = keyMappingList
  }
}
