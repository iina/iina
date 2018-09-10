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

  var subsystem: Logger.Subsystem

  init(context: JSContext, pluginInstance: JavascriptPluginInstance) {
    self.context = context
    self.player = pluginInstance.player
    self.subsystem = pluginInstance.subsystem
  }

  func throwError(withMessage message: String) {
    context.exception = JSValue(newErrorFromMessage: message, in: context)
  }
}

@objc protocol JavascriptAPICoreExportable: JSExport {
  func sendOSD(_ message: String)
  func log(_ message: JSValue, _ level: JSValue)
}

class JavascriptAPICore: JavascriptAPI, JavascriptAPICoreExportable {

  func sendOSD(_ message: String) {

  }

  func log(_ message: JSValue, _ level: JSValue) {
    let level = level.isNumber ? Int(level.toInt32()) : 2
    Logger.log(message.toString(),
               level: Logger.Level(rawValue: level) ?? .warning,
               subsystem: subsystem)
  }
}

@objc protocol JavascriptAPIMpvExportable: JSExport {
  func getFlag(_ property: String) -> Bool
  func getNumber(_ property: String) -> Double
  func getString(_ property: String) -> String?
  func getNative(_ property: String) -> Any?
  func set(_ property: String, _ value: Any)
}

class JavascriptAPIMpv: JavascriptAPI, JavascriptAPIMpvExportable {

  @objc func getFlag(_ property: String) -> Bool {
    return player.mpv.getFlag(property)
  }

  @objc func getNumber(_ property: String) -> Double {
    return player.mpv.getDouble(property)
  }

  @objc func getString(_ property: String) -> String? {
    return player.mpv.getString(property)
  }

  @objc func getNative(_ property: String) -> Any? {
    return player.mpv.getNode(property)
  }

  @objc func set(_ property: String, _ value: Any) {
    switch value {
    case is Int:
      player.mpv.setInt(property, value as! Int)
    case is Double:
      player.mpv.setDouble(property, value as! Double)
    case is String:
      player.mpv.setString(property, value as! String)
    case is Bool:
      player.mpv.setFlag(property, value as! Bool)
    default:
      throwError(withMessage: "mpv.set only supports numbers, strings and booleans.")
    }
  }
}
