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
  // Main-thread confinement includes JavaScriptCore, API resource registries,
  // pending callbacks and active hooks. Background IO may only enqueue delivery.
  private(set) var isActive = true
  fileprivate var pendingCallbacks: [UUID: JavascriptPluginCallback] = [:]

  fileprivate var activeHookContinuations: [UUID: JavascriptPluginHookContinuation] = [:]

  var logHandler: ((String, Logger.Level) -> Void)?

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
  
  let input = PluginInputManager()

  lazy var queue: DispatchQueue = {
    DispatchQueue(label: "com.colliderli.iina.plugin.\(plugin.identifier)", qos: .background)
  }()

  lazy var subsystem = Logger.makeSubsystem("\(isGlobal ? "global" : "player\(player.label!)") - \(plugin.name)", ["puzzlepiece.extension"])

  var currentFile: URL? {
    currentFileStack.last
  }
  private var currentFileStack: [URL] = []

  init(player: PlayerCore?, plugin: JavascriptPlugin) {
    dispatchPrecondition(condition: .onQueue(.main))
    self.plugin = plugin

    if let player {
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
    if let plugin = self.plugin {
      Logger.log("Unload \(plugin.name)", level: .debug, subsystem: subsystem)
    }
    tearDown()
  }

  /// Called before removing or replacing an instance, even if another owner retains it.
  func tearDown() {
    dispatchPrecondition(condition: .onQueue(.main))
    guard isActive else { return }
    isActive = false
    polyfill.removeAllTimers()
    pendingCallbacks.values.forEach { $0.invalidate() }
    pendingCallbacks.removeAll()
    // Cancel delivery first, then release mpv even when the hook was awaiting IO
    // that cleanup will cancel. Remove ownership before calling native code.
    let continuations = Array(activeHookContinuations.values)
    activeHookContinuations.removeAll()
    continuations.forEach { $0.finish() }
    apis.values.forEach { $0.cleanUp(self) }
  }

  func makeCallback(_ values: [JSValue], once: Bool = true) -> JavascriptPluginCallback {
    dispatchPrecondition(condition: .onQueue(.main))
    let callback = JavascriptPluginCallback(instance: self, values: values, once: once)
    if isActive {
      pendingCallbacks[callback.id] = callback
    } else {
      callback.invalidate()
    }
    return callback
  }

  /// A callback may enter a modal AppKit loop in which the user disables/reloads
  /// plugins. Keep both weak API owners alive until that in-flight call returns.
  @discardableResult
  func withActiveContext<T>(_ body: () -> T) -> T? {
    dispatchPrecondition(condition: .onQueue(.main))
    guard isActive, let plugin else { return nil }
    return withExtendedLifetime((self, plugin), body)
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
    guard isActive else { return }
    guard let item = sender.representedObject as? JavascriptPluginMenuItem else { return }
    if !item.callAction() {
      Logger.log("Action of the menu item \"\(item.title)\" is not a function", level: .error, subsystem: subsystem)
    }
  }

  @objc func playlistMenuItemAction(_ sender: NSMenuItem) {
    guard isActive else { return }
    guard let item = sender.representedObject as? JavascriptPluginMenuItem else { return }
    if !item.callAction() {
      Logger.log("Action of the menu item \"\(item.title)\" is not a function", level: .error, subsystem: subsystem)
    }
  }

  @discardableResult
  func evaluateFile(_ url: URL, asModule: Bool = false) -> JSValue! {
    dispatchPrecondition(condition: .onQueue(.main))
    guard isActive else { return nil }
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
    ctx.exceptionHandler = { [weak self] context, exception in
      guard let self, self.isActive else { return }
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
      apis["input"] = JavascriptAPIInput(context: ctx, pluginInstance: self)
    }
    apis["ws"] = JavascriptAPIWebSocketController(context: ctx, pluginInstance: self)

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

/// Teardown clears the JavaScript values even if native IO still retains this token.
/// Its JavaScript values and the instance registry are accessed on the main thread.
final class JavascriptPluginCallback {
  fileprivate let id = UUID()
  private weak var instance: JavascriptPluginInstance?
  private var values: [JSValue]?
  private let once: Bool

  fileprivate init(instance: JavascriptPluginInstance, values: [JSValue], once: Bool) {
    self.instance = instance
    self.values = values
    self.once = once
  }

  fileprivate func invalidate() {
    dispatchPrecondition(condition: .onQueue(.main))
    values = nil
  }

  func cancel() {
    if !Thread.isMainThread {
      DispatchQueue.main.async { [self] in cancel() }
      return
    }
    instance?.pendingCallbacks.removeValue(forKey: id)
    invalidate()
  }

  func callHook(withNextBlock next: @escaping () -> Void) {
    DispatchQueue.main.async { [self] in
      guard let instance, instance.isActive, let callback = values?.first else {
        next()
        return
      }
      let continuation = JavascriptPluginHookContinuation(next: next)
      instance.activeHookContinuations[continuation.id] = continuation
      let advance: @convention(block) () -> Void = { [weak instance] in
        instance?.activeHookContinuations.removeValue(forKey: continuation.id)
        continuation.finish()
      }
      instance.withActiveContext {
        // Reading constructor can itself reenter JS and trigger teardown.
        let isAsync = callback.forProperty("constructor")?.forProperty("name")?.toString() == "AsyncFunction"
        guard instance.isActive else { return }
        callback.call(withArguments: [JSValue(object: advance, in: callback.context)!])
        if !isAsync { advance() }
      }
    }
  }

  func resolve(_ arguments: [Any]) { call(withArguments: arguments) }
  func reject(_ arguments: [Any]) { call(withArguments: arguments, index: 1) }

  func call(withArguments arguments: [Any], index: Int = 0) {
    DispatchQueue.main.async { [self] in
      guard let instance, instance.isActive, let values else { return }
      // Take the values before removing the registry entry. Completion and teardown
      // can both release their ownership without invalidating the current call.
      if once { cancel() }
      instance.withActiveContext {
        values[index].call(withArguments: arguments)
      }
    }
  }
}

/// Native continuation only; never owns JavaScript. All access is on main.
fileprivate final class JavascriptPluginHookContinuation {
  let id = UUID()
  private var next: (() -> Void)?

  init(next: @escaping () -> Void) { self.next = next }

  func finish() {
    dispatchPrecondition(condition: .onQueue(.main))
    let action = next
    next = nil
    action?()
  }
}
