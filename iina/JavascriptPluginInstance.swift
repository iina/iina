//
//  JavascriptPluginInstance.swift
//  iina
//
//  Created by Collider LI on 11/9/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore

class JavascriptPluginInstance {

  lazy var js: JSContext = {
    let ctx = JSContext()!
    ctx.exceptionHandler = self.exceptionHandler

    let JavascriptAPIRequire: @convention(block) (String) -> JSValue = { path in
      let currentPath = self.currentFile!.deletingLastPathComponent()
      let requiredURL = currentPath.appendingPathComponent(path).standardized
      guard requiredURL.absoluteString.hasPrefix(self.plugin.root.absoluteString) else {
        return JSValue(nullIn: ctx)
      }
      return self.evaluateFile(requiredURL, asModule: true)
    }

    let iinaObject: [String: Any] = [
      "core": JavascriptAPICore(context: ctx, pluginInstance: self),
      "mpv": JavascriptAPIMpv(context: ctx, pluginInstance: self),
      "event": JavascriptAPIEvent(context: ctx, pluginInstance: self),
      "http": JavascriptAPIHttp(context: ctx, pluginInstance: self),
    ]
    ctx.setObject(JavascriptAPIRequire, forKeyedSubscript: "require" as NSString)
    ctx.setObject(iinaObject, forKeyedSubscript: "iina" as NSString)
    return ctx
  }()

  weak var player: PlayerCore!
  weak var plugin: JavascriptPlugin!

  lazy var subsystem: Logger.Subsystem = .init(rawValue: "JS|\(plugin.name)")

  private var currentFile: URL?

  init?(player: PlayerCore, plugin: JavascriptPlugin) {
    self.player = player
    self.plugin = plugin
    _ = evaluateFile(plugin.entryURL)
  }

  private func evaluateFile(_ url: URL, asModule: Bool = false) -> JSValue! {
    currentFile = url
    guard let content = try? String(contentsOf: url) else {
      Logger.log("Cannot read script \(url.path)", level: .error, subsystem: subsystem)
      return JSValue(nullIn: js)
    }
    let script: String
    if asModule {
      script =
      """
      "use strict";
      (function() {
      const module = {};
      \(content)
      return module.exports;
      })();
      """
    } else {
      script =
      """
      "use strict";
      \(content)
      """
    }
    return js.evaluateScript(script, withSourceURL: url)
  }

  private func exceptionHandler(_ context: JSContext?, _ exception: JSValue?) {
    Logger.log(exception?.toString() ?? "Unknown exception", level: .error, subsystem: subsystem)
  }
}
