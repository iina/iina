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
      throwError(withMessage: "To call this API, the plugin must declare permission \"\(permission.rawValue)\" in its Info.json.")
      return nil
    }
    return block()
  }

  func permitted(to permission: JavascriptPlugin.Permission) -> Bool {
    return pluginInstance.plugin.permissions.contains(permission)
  }

  func extraSetup() { }

  func createPromise(_ block: @escaping @convention(block) (JSValue, JSValue) -> Void) -> JSValue {
    return context.objectForKeyedSubscript("Promise")!.construct(withArguments: [JSValue(object: block, in: context)!])
  }

  func parsePath(_ path: String) -> (path: String?, local: Bool) {
    if path.hasPrefix("@tmp/") {
      return (expandPath(path, byReplacing: "tmp", with: pluginInstance.plugin.tmpURL), true)
    } else if path.hasPrefix("@data/") {
      return (expandPath(path, byReplacing: "data", with: pluginInstance.plugin.dataURL), true)
    }

    return whenPermitted(to: .accessFileSystem) {
      var absPath = path
      if path.hasPrefix("@current/") {
        guard let currentURL = player.info.currentURL else {
          log("@current is unavailable when no file playing", level: .error)
          return (nil, false)
        }
        absPath = expandPath(path, byReplacing: "current", with: currentURL.deletingLastPathComponent(), validate: false)!
      }
      guard absPath.hasPrefix("/") else {
        throwError(withMessage: "The path should be an absolute path: \(path)")
        return (nil, false)
      }
      return (absPath, false)
    }!
  }

  private func expandPath(_ path: String, byReplacing symbol: String, with url: URL, validate: Bool = true) -> String? {
    let remaining = String(path.suffix(from: path.index(path.startIndex, offsetBy: symbol.count + 2)))
    let expanded = url.appendingPathComponent(remaining).standardized
    if validate {
      guard expanded.path.hasPrefix(url.path) else {
        throwError(withMessage: "The path does not locate inside the @\(symbol) directory: \"\(path)\"")
        return nil
      }
    }
    return expanded.path
  }
}
