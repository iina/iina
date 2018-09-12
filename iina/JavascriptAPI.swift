//
//  JavascriptAPI.swift
//  iina
//
//  Created by Collider LI on 11/9/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore

class JavascriptAPI: NSObject {
  weak var context: JSContext!
  weak var player: PlayerCore!

  weak var pluginInstance: JavascriptPluginInstance!

  init(context: JSContext, pluginInstance: JavascriptPluginInstance) {
    self.context = context
    self.player = pluginInstance.player
    self.pluginInstance = pluginInstance
  }

  func throwError(withMessage message: String) {
    context.exception = JSValue(newErrorFromMessage: message, in: context)
  }

  func log(_ message: String, level: Logger.Level = .debug) {
    Logger.log(message, level: level, subsystem: pluginInstance.subsystem)
  }

  func permit<T>(to permission: JavascriptPlugin.Permission, block: () -> T) -> T? {
    if pluginInstance.plugin.permissions.contains(permission) {
      return block()
    } else {
      log("To call this API, the plugin must declare permission \(permission.rawValue) in Info.json.", level: .error)
    }
    return nil
  }
}
