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

  lazy var js: JSContext = createJSContext()

  weak var player: PlayerCore!
  weak var plugin: JavascriptPlugin!
  let isGlobal: Bool

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

  lazy var sidebarTabView: PluginSidebarView = {
    let view = PluginSidebarView.create(pluginInstance: self)
    return view
  }()

  var menuItems: [JavascriptPluginMenuItem] = []

  lazy var queue: DispatchQueue = {
    DispatchQueue(label: "com.colliderli.iina.plugin.\(plugin.identifier)", qos: .background)
  }()

  lazy var subsystem: Logger.Subsystem = .init(rawValue: "JS:\(plugin.name)")

  var currentFile: URL? {
    currentFileStack.last
  }
  private var currentFileStack: [URL] = []

  init(player: PlayerCore?, plugin: JavascriptPlugin) {
    self.plugin = plugin

    if let player = player {
      // normal plugin instance
      self.player = player
      isGlobal = false
      evaluateFile(plugin.entryURL)
    } else {
      // if player is nil, the plugin instance is a global controller
      isGlobal = true
      evaluateFile(plugin.globalEntryURL!)
    }
  }

  deinit {
    Logger.log("Unload \(self.plugin.name)", level: .debug, subsystem: subsystem)
    apis.values.forEach { $0.cleanUp(self) }
  }

  func canAccess(url: URL) -> Bool {
    guard let host = url.host else {
      return false
    }
    guard plugin.domainList.contains(where: { domain -> Bool in
      if domain == "*" {
        return true
      } else if domain.hasPrefix("*.") {
        return host.hasSuffix(domain.dropFirst())
      } else {
        return domain == host
      }
    }) else {
      return false
    }
    return true
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

  @discardableResult
  func evaluateFile(_ url: URL, asModule: Bool = false) -> JSValue! {
    currentFileStack.append(url)
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
    let result = js.evaluateScript(script, withSourceURL: url)
    currentFileStack.removeLast()
    return result
  }

  private func createJSContext() -> JSContext {
    let ctx = JSContext()!
    ctx.name = "\(isGlobal ? "Global" : "Main") — \(plugin.name)"
    ctx.exceptionHandler = { [unowned self] context, exception in
      let message = exception?.toString() ?? "Unknown exception"
      let stack = exception?.objectForKeyedSubscript("stack")?.toString() ?? "???"
      Logger.log(
        "\(message)\n---Stack Trace---\n\(stack)\n-----------------",
        level: .error,
        subsystem: self.subsystem
      )
    }

    apis = [
      "menu": JavascriptAPIMenu(context: ctx, pluginInstance: self),
      "standaloneWindow": JavascriptAPIStandaloneWindow(context: ctx, pluginInstance: self),
      "utils": JavascriptAPIUtils(context: ctx, pluginInstance: self),
      "file": JavascriptAPIFile(context: ctx, pluginInstance: self),
      "preferences": JavascriptAPIPreferences(context: ctx, pluginInstance: self),
      "console": JavascriptAPIConsole(context: ctx, pluginInstance: self),
      "http": JavascriptAPIHttp(context: ctx, pluginInstance: self)
    ]

    if !isGlobal {
      apis["core"] = JavascriptAPICore(context: ctx, pluginInstance: self)
      apis["mpv"] = JavascriptAPIMpv(context: ctx, pluginInstance: self)
      apis["event"] = JavascriptAPIEvent(context: ctx, pluginInstance: self)
      apis["overlay"] = JavascriptAPIOverlay(context: ctx, pluginInstance: self)
      apis["sidebar"] = JavascriptAPISidebarView(context: ctx, pluginInstance: self)
      apis["playlist"] = JavascriptAPIPlaylist(context: ctx, pluginInstance: self)
      apis["subtitle"] = JavascriptAPISubtitle(context: ctx, pluginInstance: self)
    }

    if player == nil {
      // it's a global instance
      apis["global"] = JavascriptAPIGlobalController(context: ctx, pluginInstance: self)
    } else if let globalAPI = plugin.globalInstance?.apis["global"] as? JavascriptAPIGlobalController {
      // it's a normal instance
      let childAPI = JavascriptAPIGlobalChild(context: ctx, pluginInstance: self)
      childAPI.parentAPI = globalAPI
      apis["global"] = childAPI
    }

    ctx.setObject(apis, forKeyedSubscript: "iina" as NSString)
    apis.values.forEach { $0.extraSetup() }

    polyfill = JavascriptPolyfill(pluginInstance: self)
    polyfill.register(inContext: ctx)

    return ctx
  }
}
