//
//  JavascriptPlugin.swift
//  iina
//
//  Created by Collider LI on 11/9/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore

class JavascriptPlugin {

  static var plugins = loadPlugins()

  let name: String
  let authorName: String
  let authorEmail: String?
  let authorURL: String?
  let version: String
  let description: String?

  let root: URL
  let entryPath: String
  let scriptPaths: [String]

  var entryURL: URL {
    return root.appendingPathComponent(entryPath)
  }

  static private func loadPlugins() -> [JavascriptPlugin] {
    return ["test"].compactMap(JavascriptPlugin.init(filename:))
  }

  init?(filename: String) {
    // find package
    let url = Utility.pluginsURL.appendingPathComponent("\(filename).iinaplugin")
    Logger.log("Loading JS plugin from \(url.path)")
    guard url.isFileURL && url.isExistingDirectory else {
      Logger.log("Plugin package doesn't exist.")
      return nil
    }
    self.root = url
    // read package
    guard
      let data = try? Data(contentsOf: root.appendingPathComponent("Info.json"), options: .mappedIfSafe),
      let jsonResult = try? JSONSerialization.jsonObject(with: data, options: .mutableLeaves),
      let jsonDict = jsonResult as? [String: Any]
      else {
      Logger.log("Cannot read plugin package content.", level: .error)
      return nil
    }
    // read json
    guard
      let name = jsonDict["name"] as? String,
      let author = jsonDict["author"] as? [String: String],
      let authorName = author["name"],
      let version = jsonDict["version"] as? String,
      let entry = jsonDict["entry"] as? String
      else {
      Logger.log("Info.json must contain these keys: name, author, version, entry.", level: .error)
      return nil
    }
    self.name = name
    self.version = version
    self.entryPath = entry
    self.authorName = authorName
    self.authorURL = author["url"]
    self.authorEmail = author["email"]
    self.description = jsonDict["description"] as? String
    self.scriptPaths = (jsonDict["scripts"] as? [String]) ?? []
  }

}


class JavascriptPluginInstance {

  lazy var js: JSContext = {
    let ctx = JSContext()!
    ctx.exceptionHandler = self.exceptionHandler
    let iinaObject: [String: Any] = [
      "core": JavascriptAPICore(context: ctx, pluginInstance: self),
      "mpv": JavascriptAPIMpv(context: ctx, pluginInstance: self)
    ]
    ctx["iina"] = iinaObject
    return ctx
  }()

  weak var player: PlayerCore!
  weak var plugin: JavascriptPlugin!

  lazy var subsystem: Logger.Subsystem = .init(rawValue: "JS|\(plugin.name)")

  init?(player: PlayerCore, plugin: JavascriptPlugin) {
    self.player = player
    self.plugin = plugin
    evaluateFile(plugin.entryURL)
  }

  private func evaluateFile(_ url: URL) {
    guard let content = try? String(contentsOf: url) else {
      Logger.log("Cannot read script \(url.path)", level: .error, subsystem: subsystem)
      return
    }
    js.evaluateScript(content, withSourceURL: url)
  }

  private func exceptionHandler(_ context: JSContext?, _ exception: JSValue?) {
    Logger.log(exception?.toString() ?? "Unknown exception", level: .error, subsystem: subsystem)
  }
}

fileprivate extension JSContext {
  subscript(_ key: String) -> Any {
    set(newValue) {
      self.setObject(newValue, forKeyedSubscript: key as NSString)
    }
    get {
      return self.objectForKeyedSubscript(key)
    }
  }
}
