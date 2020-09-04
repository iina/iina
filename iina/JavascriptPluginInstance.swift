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
  var apis: [String: JavascriptAPI]!
  private var polyfill: JavascriptPolyfill!

  lazy var js: JSContext = {
    let ctx = JSContext()!
    ctx.exceptionHandler = { [unowned self] context, exception in
      Logger.log(exception?.toString() ?? "Unknown exception", level: .error, subsystem: self.subsystem)
    }

    apis = [
      "core": JavascriptAPICore(context: ctx, pluginInstance: self),
      "mpv": JavascriptAPIMpv(context: ctx, pluginInstance: self),
      "event": JavascriptAPIEvent(context: ctx, pluginInstance: self),
      "http": JavascriptAPIHttp(context: ctx, pluginInstance: self),
      "console": JavascriptAPIConsole(context: ctx, pluginInstance: self),
      "menu": JavascriptAPIMenu(context: ctx, pluginInstance: self),
      "overlay": JavascriptAPIOverlay(context: ctx, pluginInstance: self),
      "standaloneWindow": JavascriptAPIStandaloneWindow(context: ctx, pluginInstance: self),
      "playlist": JavascriptAPIPlaylist(context: ctx, pluginInstance: self),
      "subtitle": JavascriptAPISubtitle(context: ctx, pluginInstance: self),
      "utils": JavascriptAPIUtils(context: ctx, pluginInstance: self),
      "preferences": JavascriptAPIPreferences(context: ctx, pluginInstance: self)
    ]

    ctx.setObject(apis, forKeyedSubscript: "iina" as NSString)
    apis.values.forEach { $0.extraSetup() }

    polyfill = JavascriptPolyfill(pluginInstance: self)
    polyfill.register(inContext: ctx)

    return ctx
  }()

  weak var player: PlayerCore!
  weak var plugin: JavascriptPlugin!

  lazy var overlayView: PluginOverlayView = {
    let view = PluginOverlayView.create(pluginInstance: self)
    view.attachTo(windowController: player.mainWindow)
    return view
  }()
  var overlayViewLoaded = false

  lazy var standaloneWindow: PluginStandaloneWindow = {
    let window = PluginStandaloneWindow.create(pluginInstance: self)
    standaloneWindowCreated = true
    return window
  }()
  var standaloneWindowCreated = false

  var menuItems: [JavascriptPluginMenuItem] = []

  lazy var queue: DispatchQueue = {
    DispatchQueue(label: "com.colliderli.iina.plugin.\(plugin.identifier)", qos: .background)
  }()

  lazy var subsystem: Logger.Subsystem = .init(rawValue: "JS:\(plugin.name)")

  var currentFile: URL?

  init?(player: PlayerCore, plugin: JavascriptPlugin) {
    self.player = player
    self.plugin = plugin
    _ = evaluateFile(plugin.entryURL)
  }

  deinit {
    Logger.log("Unload \(self.plugin.name)", level: .debug, subsystem: subsystem)
    apis.values.forEach { $0.cleanUp(self) }
  }

  @objc func menuItemAction(_ sender: NSMenuItem) {
    guard let item = sender.representedObject as? JavascriptPluginMenuItem else { return }
    if !item.callAction() {
      Logger.log("Action of the menu item \"\(item.title)\" is not a function", level: .error, subsystem: subsystem)
    }
  }

  @objc func playlistMenuItemAction(_ sender: NSMenuItem) {
    guard let item = sender.representedObject as? JavascriptPluginMenuItem else { return }
    if !item.callAction() {
      Logger.log("Action of the menu item \"\(item.title)\" is not a function", level: .error, subsystem: subsystem)
    }
  }

  func evaluateFile(_ url: URL, asModule: Bool = false) -> JSValue! {
    currentFile = url
    guard let content = try? String(contentsOf: url) else {
      Logger.log("Cannot read script \(url.path)", level: .error, subsystem: subsystem)
      return JSValue(nullIn: js)
    }
    let script: String
    if asModule {
      script =
      """
      (function() {
      const module = {};
      \(content)
      return module.exports;
      })();
      """
    } else {
      script =
      """
      \(content)
      """
    }
    return js.evaluateScript(script, withSourceURL: url)
  }

  private func exceptionHandler(_ context: JSContext?, _ exception: JSValue?) {
    Logger.log(exception?.toString() ?? "Unknown exception", level: .error, subsystem: subsystem)
  }
}
