//
//  JavascriptAPIPreferences.swift
//  iina
//
//  Created by Collider LI on 26/3/2019.
//  Copyright © 2019 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore

@objc protocol JavascriptAPIPreferencesExportable: JSExport {
  func get(_ key: String) -> Any?
  func set(_ key: String, _ value: Any)
  func sync()
}

class JavascriptAPIPreferences: JavascriptAPI, JavascriptAPIPreferencesExportable {
  @objc func get(_ key: String) -> Any? {
    guard let plugin = pluginInstance?.plugin else { return nil }
    if let value = plugin.preferences[key] {
      return value
    }
    if let value = plugin.defaultPreferences[key] {
      return value
    }
    if let subsystem = pluginInstance?.subsystem {
      Logger.log("Trying to get preference value for undefined key \(key)", level: .warning, subsystem: subsystem)
    }
    return nil
  }

  @objc func set(_ key: String, _ value: Any) {
    guard let plugin = pluginInstance?.plugin else { return }
    plugin.preferences[key] = value
  }

  @objc func sync() {
    guard let plugin = pluginInstance?.plugin else { return }
    plugin.syncPreferences()
  }
}
