//
//  JavascriptAPIMpv.swift
//  iina
//
//  Created by Collider LI on 11/9/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore

@objc protocol JavascriptAPIMpvExportable: JSExport {
  func getFlag(_ property: String) -> Bool
  func getNumber(_ property: String) -> Double
  func getString(_ property: String) -> String?
  func getNative(_ property: String) -> Any?
  func set(_ property: String, _ value: JSValue)
  func command(_ commandName: String, _ args: [String])
  func addHook(_ name: String, _ priority: Int, _ callback: JSValue)
}

class JavascriptAPIMpv: JavascriptAPI, JavascriptAPIMpvExportable {
  private var identifier: String!

  override func extraSetup() {
    identifier = pluginInstance.plugin.identifier
  }

  override func cleanUp(_ instance: JavascriptPluginInstance) {
    player!.mpv.removeHooks(withIdentifier: identifier)
  }

  @objc func getFlag(_ property: String) -> Bool {
    return player!.mpv.getFlag(property)
  }

  @objc func getNumber(_ property: String) -> Double {
    return player!.mpv.getDouble(property)
  }

  @objc func getString(_ property: String) -> String? {
    return player!.mpv.getString(property)
  }

  @objc func getNative(_ property: String) -> Any? {
    return player!.mpv.getNode(property)
  }

  @objc func set(_ property: String, _ value: JSValue) {
    if value.isNumber {
      player!.mpv.setDouble(property, value.toDouble())
    } else if value.isString {
      player!.mpv.setString(property, value.toString())
    } else if value.isBoolean {
      player!.mpv.setFlag(property, value.toBool())
    } else if value.isObject {
      if let object = value.toObject() {
        player!.mpv.setNode(property, object)
      }
    } else {
      throwError(withMessage: "mpv.set only supports numbers, strings, booleans and objects.")
    }
  }

  @objc func command(_ commandName: String, _ args: [String]) {
    player!.mpv.command(MPVCommand(commandName), args: args, checkError: false)
  }

  @objc func addHook(_ name: String, _ priority: Int, _ callback: JSValue) {
    let hook = MPVHookValue(withIdentifier: identifier, jsContext: context, jsBlock: callback, owner: self)
    player!.mpv.addHook(MPVHook(name), priority: Int32(priority), hook: hook)
  }
}
