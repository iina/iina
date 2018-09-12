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
  func osd(_ message: String)
}

class JavascriptAPICore: JavascriptAPI, JavascriptAPICoreExportable {

  @objc func osd(_ message: String) {
    permit(to: .showOSD) {
      self.player.sendOSD(.custom(message))
    }
  }

  @objc func getWindowFrame() -> JSValue {
    guard let frame = player.mainWindow.window?.frame else { return JSValue(undefinedIn: context) }
    return JSValue(rect: frame, in: context)
  }
}
