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
  func on(_ event: String, _ callback: JSValue) -> String?
  func off(_ event: String, _ id: String)
}

// Examples:
// event.on("mpv.file-start")
// event.on("mpv.fullscreen.changed")
// event.on("iina.window-resized")
// event.on("iina.pip.changed")

class JavascriptAPIEvent: JavascriptAPI, JavascriptAPIEventExportable {
  private var addedListeners: [(String, EventController.Name)] = []

  @objc func on(_ event: String, _ callback: JSValue) -> String? {
    let splitted = event.split(separator: ".")
    let isEventListener = splitted.count == 2
    let isPropertyChangedListener = splitted.count == 3 && splitted[2] == "changed"
    let isMpv = splitted[0] == "mpv"
    let isIINA = splitted[0] == "iina"
    guard (isEventListener || isPropertyChangedListener) && (isMpv || isIINA) else {
      throwError(withMessage: "Incorrect event name syntax: \"\(event)\"")
      return nil
    }
    let eventName = String(splitted[1])
    if isMpv && isPropertyChangedListener && player.mpv.observeProperties[eventName] == nil {
      player.mpv.observe(property: eventName)
    }
    let name = EventController.Name(event)
    let id = player.events.addListener(JavascriptAPIEventCallback(callback), for: name)
    addedListeners.append((id, name))
    return id
  }

  @objc func off(_ event: String,_ id: String) {
    if !player.events.removeListener(id, for: .init(event)) {
      log("Event listener not found for id \(id)", level: .warning)
    }
  }

  override func cleanUp(_ instance: JavascriptPluginInstance) {
    addedListeners.forEach { (id, name) in
      player.events.removeListener(id, for: name)
    }
    addedListeners.removeAll()
  }
}

class JavascriptAPIEventCallback: EventCallable {
  private var callback: JSManagedValue!  // should we use `weak` here?

  init(_ callback: JSValue) {
    self.callback = JSManagedValue(value: callback)
    JSContext.current()!.virtualMachine.addManagedReference(self.callback, withOwner: self)
  }

  func call(withArguments args: [Any]) {
    callback.value.call(withArguments: args.map { arg in
      if let rect = arg as? CGRect {
        return JSValue(rect: rect, in: callback.value.context)!
      } else {
        return arg
      }
    })
  }
}
