//
//  JavascriptAPIInput.swift
//  iina
//
//  Created by Hechen Li on 6/1/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore


@objc protocol JavascriptAPIInputExportable: JSExport {
  func normalizeKeyCode(_ code: String) -> String
  func getAllKeyBindings() -> JSValue
  func onMouseUp(_ button: String, _ callback: JSValue, _ priority: JSValue)
  func onMouseDown(_ button: String, _ callback: JSValue, _ priority: JSValue)
  func onMouseDrag(_ button: String, _ callback: JSValue, _ priority: JSValue)
  func onKeyDown(_ key: String, _ callback: JSValue , _ priority: JSValue)
  func onKeyUp(_ key: String, _ callback: JSValue, _ priority: JSValue)
}


class JavascriptAPIInput: JavascriptAPI, JavascriptAPIInputExportable {
  func normalizeKeyCode(_ code: String) -> String {
    return KeyCodeHelper.normalizeMpv(code)
  }
  
  func getAllKeyBindings() -> JSValue {
    let keyBindings = PlayerCore.keyBindings.mapValues { $0.toDict() }
    return JSValue(object: keyBindings, in: JSContext.current()!)
  }
  
  override func extraSetup() {
    context.evaluateScript("""
    iina.input.PRIORITY_LOW = \(PluginInputManager.Priority.low.rawValue);
    iina.input.PRIORITY_HIGH = \(PluginInputManager.Priority.high.rawValue);
    iina.input.MOUSE = "\(PluginInputManager.Input.mouse)";
    iina.input.RIGHT_MOUSE = "\(PluginInputManager.Input.rightMouse)";
    iina.input.OTHER_MOUSE = "\(PluginInputManager.Input.otherMouse)";
    """)
  }
  
  func onKeyDown(_ key: String, _ callback: JSValue, _ priority: JSValue) {
    addListener(.keyDown, key, callback, priority)
  }
  
  func onKeyUp(_ key: String,  _ callback: JSValue, _ priority: JSValue) {
    addListener(.keyUp, key, callback, priority)
  }
  
  func onMouseUp(_ button: String, _ callback: JSValue, _ priority: JSValue) {
    addListener(.mouseUp, button, callback, priority, normalizeKey: false)
  }

  func onMouseDown(_ button: String, _ callback: JSValue, _ priority: JSValue) {
    addListener(.mouseDown, button, callback, priority, normalizeKey: false)
  }

  func onMouseDrag(_ button: String, _ callback: JSValue, _ priority: JSValue) {
    addListener(.mouseDrag, button, callback, priority, normalizeKey: false)
  }

  fileprivate func addListener(
    _ event: PluginInputManager.Event,
    _ key: String,  _ callback: JSValue, _ priority: JSValue, normalizeKey: Bool = true
  ) {
    pluginInstance.input.addListener(
      forInput: normalizeKey ? KeyCodeHelper.normalizeMpv(key) : key,
      event: event,
      callback: callback,
      priority: priority.isNumber ? Int(priority.toInt32()) : PluginInputManager.Priority.low.rawValue,
      owner: self
    )
  }
}


fileprivate extension KeyMapping {
  func toDict() -> [String: Any] {
    return [
      "key": self.normalizedMpvKey,
      "action": self.rawAction,
      "isIINACommand": self.isIINACommand
    ]
  }
}
