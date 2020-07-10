//
//  JavascriptPolyfill.swift
//  iina
//
//  Created by Collider LI on 6/3/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import JavaScriptCore

class JavascriptPolyfill {
  weak var plugin: JavascriptPluginInstance!
  var timers = [String: Timer]()

  init(pluginInstance: JavascriptPluginInstance) {
    self.plugin = pluginInstance
  }

  deinit {
    for timer in timers.values {
      timer.invalidate()
    }
  }

  func removeTimer(identifier: String) {
    let timer = self.timers.removeValue(forKey: identifier)
    timer?.invalidate()
  }

  func createTimer(callback: JSValue, ms: Double, repeats : Bool) -> String {
    let timeInterval  = ms/1000.0
    let uuid = NSUUID().uuidString

    plugin.queue.async(execute: {
      let timer = Timer.scheduledTimer(timeInterval: timeInterval,
                                       target: self,
                                       selector: #selector(self.callJSCallback),
                                       userInfo: callback,
                                       repeats: repeats)
      self.timers[uuid] = timer
    })
    return uuid
  }

  @objc func callJSCallback(_ timer: Timer) {
    let callback = (timer.userInfo as! JSValue)
    callback.call(withArguments: nil)
  }

  func register(inContext context: JSContext) {
    let setInterval: @convention(block) (JSValue, Double) -> String = { [unowned self] (callback, ms) in
        return self.createTimer(callback: callback, ms: ms, repeats: true)
    }

    let setTimeout: @convention(block) (JSValue, Double) -> String = { [unowned self] (callback, ms) in
        return self.createTimer(callback: callback, ms: ms, repeats: false)
    }

    let clearInterval: @convention(block) (String) -> () = { [unowned self] identifier in
        self.removeTimer(identifier: identifier)
    }

    let clearTimeout: @convention(block) (String) -> () = { [unowned self] identifier in
        self.removeTimer(identifier: identifier)
    }

    let require: @convention(block) (String) -> Any? = { [unowned self] path in
      let instance = self.plugin!
      let currentPath = instance.currentFile!.deletingLastPathComponent()
      let requiredURL = currentPath.appendingPathComponent(path).standardized
      guard requiredURL.absoluteString.hasPrefix(instance.plugin.root.absoluteString) else {
        return nil
      }
      return instance.evaluateFile(requiredURL, asModule: true)
    }

    context.setObject(clearInterval, forKeyedSubscript: "clearInterval" as NSString)
    context.setObject(clearTimeout, forKeyedSubscript: "clearTimeout" as NSString)
    context.setObject(setInterval, forKeyedSubscript: "setInterval" as NSString)
    context.setObject(setTimeout, forKeyedSubscript: "setTimeout" as NSString)
    context.setObject(require, forKeyedSubscript: "require" as NSString)
  }
}
