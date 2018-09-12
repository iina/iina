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
  func log(_ message: JSValue)
}

class JavascriptAPIConsole: JavascriptAPI, JavascriptAPIConsoleExportable {

  @objc func log(_ message: JSValue) {
    prettifyAndLog(message, level: .debug)
  }

  @objc func warn(_ message: JSValue) {
    prettifyAndLog(message, level: .warning)
  }

  @objc func error(_ message: JSValue) {
    prettifyAndLog(message, level: .error)
  }

  private func prettifyAndLog(_ message: JSValue, level: Logger.Level) {
    let string = context.objectForKeyedSubscript("JSON")!
      .invokeMethod("stringify", withArguments: [message, JSValue(nullIn: context), 2])!
    log(string.toString(), level: level)
  }

}
