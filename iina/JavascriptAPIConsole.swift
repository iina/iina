//
//  JavascriptAPIConsole.swift
//  iina
//
//  Created by Collider LI on 12/9/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore

@objc protocol JavascriptAPIConsoleExportable: JSExport {
  func log()
  func warn(_ message: JSValue)
  func error(_ message: JSValue)
}

class JavascriptAPIConsole: JavascriptAPI, JavascriptAPIConsoleExportable {

  @objc func log() {
    guard let args = JSContext.currentArguments() as? [JSValue] else { return }
    if args.count == 1 {
      log(getStringValue(args[0]), level: .debug)
      return
    }
    var message = ""
    for arg in args {
      message += getStringValue(arg)
      message += arg.isObject ? "\n" : " "
    }
    log(message, level: .debug)
  }

  @objc func warn(_ message: JSValue) {
    log(getStringValue(message), level: .warning)
  }

  @objc func error(_ message: JSValue) {
    log(getStringValue(message), level: .error)
  }

  private func getStringValue(_ object: JSValue) -> String {
    if object.isString {
      return object.toString()
    } else if object.isNull {
      return "<null>"
    } else if object.isUndefined {
      return "<undefined>"
    } else if object.isDate || object.isNumber || object.isBoolean {
      return object.invokeMethod("toString", withArguments: [])!.toString()
    }
    return context.objectForKeyedSubscript("JSON")!
      .invokeMethod("stringify", withArguments: [object, JSValue(nullIn: context)!, 2])!.toString()
  }
}
