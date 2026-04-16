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
    let plugin = pluginInstance.plugin!
    if let value = plugin.preferences[key] {
      return value
    }
    if let value = plugin.defaultPreferences[key] {
      return value
    }
    Logger.log("Trying to get preference value for undefined key \(key)", level: .warning, subsystem: pluginInstance.subsystem)
    return nil
  }

  @objc func set(_ key: String, _ value: Any) {
    pluginInstance.plugin.preferences[key] = value
  }

  @objc func sync() {
    pluginInstance.plugin.syncPreferences()
  }
}
