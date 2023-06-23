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
  func onMouseUp(_ button: String, _ callback: JSValue, _ priority: Int)
  func onKeyDown(_ key: String, _ callback: JSValue , _ priority: Int)
  func onKeyUp(_ key: String, _ callback: JSValue, _ priority: Int)
}


class JavascriptAPIInput: JavascriptAPI, JavascriptAPIInputExportable {
  override func extraSetup() {
    context.evaluateScript("""
    iina.input.PRIORITY_LOW = \(PluginInputManager.Priority.low.rawValue);
    iina.input.PRIORITY_HIGH = \(PluginInputManager.Priority.high.rawValue);
    iina.input.MOUSE = "\(PluginInputManager.Input.mouse)";
    iina.input.RIGHT_MOUSE = "\(PluginInputManager.Input.rightMouse)";
    iina.input.OTHER_MOUSE = "\(PluginInputManager.Input.otherMouse)";
    """)
  }
  
  func onKeyDown(_ key: String, _ callback: JSValue, _ priority: Int) {
    addListener(.keyDown, key, callback, priority)
  }
  
  func onKeyUp(_ key: String,  _ callback: JSValue, _ priority: Int) {
    addListener(.keyUp, key, callback, priority)
  }
  
  func onMouseUp(_ button: String, _ callback: JSValue, _ priority: Int) {
    addListener(.mouseUp, button, callback, 0, normalizeKey: false)
  }
  
  fileprivate func addListener(
    _ event: PluginInputManager.Event,
    _ key: String,  _ callback: JSValue, _ priority: Int, normalizeKey: Bool = true
  ) {
    pluginInstance.input.addListener(
      forInput: normalizeKey ? KeyCodeHelper.normalizeMpv(key) : key,
      event: event,
      callback: callback,
      priority: priority,
      owner: self
    )
  }
}
