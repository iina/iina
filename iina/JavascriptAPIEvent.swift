//
//  JavascriptAPIEvent.swift
//  iina
//
//  Created by Collider LI on 11/9/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore

@objc protocol JavascriptAPIEventExportable: JSExport {
  func on(_ event: String, _ callback: JSValue)
}

// Examples:
// event.on("mpv.file-start")
// event.on("mpv.fullscreen.changed")
// event.on("iina.window-resized")
// event.on("iina.pip.changed")

class JavascriptAPIEvent: JavascriptAPI, JavascriptAPIEventExportable {

  @objc func on(_ event: String, _ callback: JSValue) {
    let splitted = event.split(separator: ".")
    let isEventListener = splitted.count == 2
    let isPropertyChangedListener = splitted.count == 3 && splitted[2] == "changed"
    let isMpv = splitted[0] == "mpv"
    let isIINA = splitted[0] == "iina"
    guard (isEventListener || isPropertyChangedListener) && (isMpv || isIINA) else {
      throwError(withMessage: "Incorrect event name syntax.")
      return
    }
    let eventName = String(splitted[1])
    if isMpv {
      if isEventListener {
        player.pluginAddMPVEventListener(for: eventName, callback: JavascriptAPIEventCallback(callback))
      } else {
        player.pluginAddMPVPropertyListener(for: eventName, callback: JavascriptAPIEventCallback(callback))
      }
    } else { // isIINA
      // TODO
    }
  }

}

class JavascriptAPIEventCallback {
  private var callback: JSValue!  // should we use `weak` here?

  init(_ callback: JSValue) {
    self.callback = callback
  }

  func call(_ args: Any...) {
    callback.call(withArguments: args)
  }
}
