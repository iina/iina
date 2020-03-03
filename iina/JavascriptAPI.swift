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

  func whenPermitted<T>(to permission: JavascriptPlugin.Permission, block: () -> T?) -> T? {
    guard permitted(to: permission) else {
      return nil
    }
    return block()
  }

  func permitted(to permission: JavascriptPlugin.Permission) -> Bool {
    guard pluginInstance.plugin.permissions.contains(permission) else {
      log("To call this API, the plugin must declare permission \(permission.rawValue) in its Info.json.", level: .error)
      return false
    }
    return true
  }

  func extraSetup() { }

  func createPromise(_ block: @escaping @convention(block) (JSValue, JSValue) -> Void) -> JSValue {
    return context.objectForKeyedSubscript("Promise")!.construct(withArguments: [JSValue(object: block, in: context)!])
  }
}
