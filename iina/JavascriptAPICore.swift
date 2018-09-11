//
//  JavascriptAPICore.swift
//  iina
//
//  Created by Collider LI on 11/9/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore

@objc protocol JavascriptAPICoreExportable: JSExport {
  func sendOSD(_ message: String)
  func log(_ message: JSValue, _ level: JSValue)
}

class JavascriptAPICore: JavascriptAPI, JavascriptAPICoreExportable {

  @objc func sendOSD(_ message: String) {
    player.sendOSD(.custom(message))
  }

  @objc func log(_ message: JSValue, _ level: JSValue) {
    let level = level.isNumber ? Int(level.toInt32()) : 2
    Logger.log(message.toString(),
               level: Logger.Level(rawValue: level) ?? .warning,
               subsystem: subsystem)
  }

  @objc func getWindowFrame() -> JSValue {
    guard let frame = player.mainWindow.window?.frame else { return JSValue(undefinedIn: context) }
    return JSValue(rect: frame, in: context)
  }
}
