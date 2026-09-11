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
  private var pendingTimers = Set<String>()
  private let timerLock = NSLock()
  private var stopped = false

  init(pluginInstance: JavascriptPluginInstance) {
    self.plugin = pluginInstance
  }

  deinit {
    for timer in timers.values {
      timer.invalidate()
    }
  }

  func removeAllTimers() {
    timerLock.lock()
    defer { timerLock.unlock() }
    stopped = true
    pendingTimers.removeAll()
    for timer in timers.values {
      timer.invalidate()
    }
    timers.removeAll()
  }

  func removeTimer(identifier: String) {
    timerLock.lock()
    defer { timerLock.unlock() }
    pendingTimers.remove(identifier)
    let timer = self.timers.removeValue(forKey: identifier)
    timer?.invalidate()
  }

  func createTimer(callback: JSValue, ms: Double, repeats : Bool) -> String {
    let timeInterval  = ms/1000.0
    let uuid = NSUUID().uuidString

    timerLock.lock()
    guard !stopped else {
      timerLock.unlock()
      return uuid
    }
    pendingTimers.insert(uuid)
    timerLock.unlock()
    DispatchQueue.main.async { [weak self] in
      guard let self, let plugin = self.plugin, plugin.isActive else { return }
      self.timerLock.lock()
      defer { self.timerLock.unlock() }
      guard self.pendingTimers.remove(uuid) != nil else { return }
      withExtendedLifetime(plugin) {
        let timer = Timer.scheduledTimer(timeInterval: timeInterval,
                                        target: self,
                                        selector: #selector(self.callJSCallback),
                                        userInfo: callback,
                                        repeats: repeats)
        self.timers[uuid] = timer
      }
    }
    return uuid
  }

  @objc func callJSCallback(_ timer: Timer) {
    guard timer.isValid, let plugin, plugin.isActive else { return }
    let callback = (timer.userInfo as! JSValue)
    plugin.withActiveContext { callback.call(withArguments: nil) }
  }

  func register(inContext context: JSContext) {
    let setInterval: @convention(block) (JSValue, Double) -> String = { [weak self] (callback, ms) in
      return self?.createTimer(callback: callback, ms: ms, repeats: true) ?? ""
    }

    let setTimeout: @convention(block) (JSValue, Double) -> String = { [weak self] (callback, ms) in
      return self?.createTimer(callback: callback, ms: ms, repeats: false) ?? ""
    }

    let clearInterval: @convention(block) (String) -> () = { [weak self] identifier in
      self?.removeTimer(identifier: identifier)
    }

    let clearTimeout: @convention(block) (String) -> () = { [weak self] identifier in
      self?.removeTimer(identifier: identifier)
    }

    let require: @convention(block) (String) -> Any? = { [weak self] path in
      guard let instance = self?.plugin, instance.isActive else { return nil }
      let currentPath = instance.currentFile!.deletingLastPathComponent()
      let requiredURL = currentPath.appendingPathComponent(path).standardized
      guard requiredURL.absoluteString.hasPrefix(instance.plugin.root.absoluteString) else {
        return nil
      }
      return [
        "path": requiredURL.path,
        "module": instance.evaluateFile(requiredURL, asModule: true)
      ] as [String: Any?]
    }

    context.setObject(clearInterval, forKeyedSubscript: "clearInterval" as NSString)
    context.setObject(clearTimeout, forKeyedSubscript: "clearTimeout" as NSString)
    context.setObject(setInterval, forKeyedSubscript: "setInterval" as NSString)
    context.setObject(setTimeout, forKeyedSubscript: "setTimeout" as NSString)
    context.setObject(require, forKeyedSubscript: "__require__" as NSString)
    context.evaluateScript(requirePolyfill)
  }
}

fileprivate let requirePolyfill = """
require = (() => {
  const cache = {};
  return function (file) {
    if (cache[file]) {
      return cache[file];
    }
    const result = __require__(file);
    if (result) {
      cache[result.path] = result.module;
      return result.module;
    }
    return undefined;
  };
})();
"""
