//
//  JavascriptPlugin.swift
//  iina
//
//  Created by Collider LI on 11/9/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore
import Just

fileprivate let githubRepoRegex = Regex("^[\\w-]+/[\\w-]+$")
fileprivate let idRegex = Regex("^([\\w-_]+\\.)+[\\w-_]+$")

class JavascriptPlugin: NSObject {
  enum Permission: String {
    case networkRequest = "network-request"
    case callProcess = "call-process"
    case showOSD = "show-osd"
    case showAlert = "show-alert"
    case addMenuItems = "menu-items"
    case displayVideoOverlay = "video-overlay"
    case accessFileSystem = "file-system"

    var isDangerous: Bool {
      switch self {
      case .networkRequest, .callProcess:
        return true
      default:
        return false
      }
    }
  }

  enum PluginError: Error {
    case fileNotFound
    case cannotUnpackage(String, String)
    case invalidURL
    case cannotDownload(String, String)
    case cannotLoadPlugin
  }

  static var plugins = loadPlugins() {
    didSet {
      NotificationCenter.default.post(Notification(name: .iinaPluginChanged))
    }
  }

  var globalInstance: JavascriptPluginInstance?

  @objc var enabled: Bool {
    didSet {
      UserDefaults.standard.set(enabled, forKey: "PluginEnabled." + identifier)
      if enabled {
        registerSubProviders()
      } else {
        removeSubProviders()
      }
      PlayerCore.reloadPluginForAll(self)
      reloadGlobalInstance()
      NotificationCenter.default.post(Notification(name: .iinaPluginChanged))
    }
  }

  let name: String
  let authorName: String
  let authorEmail: String?
  let authorURL: String?
  var identifier: String
  let version: String
  let desc: String?

  var root: URL
  let entryPath: String
  let globalEntryPath: String?
  let preferencesPage: String?
  let helpPage: String?

  let githubRepo: String?
  let githubVersion: Int?

  let permissions: Set<Permission>
  let domainList: [String]

  var subProviders: [[String: String]]?
  let sidebarTabName: String?

  var entryURL: URL
  var globalEntryURL: URL?
  var preferencesPageURL: URL?
  var helpPageURL: URL?
  var githubURLString: String? {
    guard let githubRepo = githubRepo else { return nil }
    return "https://github.com/\(githubRepo)"
  }

  lazy var preferences: [String: Any] = {
    NSDictionary(contentsOfFile: preferencesFileURL.path) as? [String: Any] ?? [:]
  }()
  let defaultPrefernces: [String: Any]

  static private func loadPlugins() -> [JavascriptPlugin] {
    guard let contents = try?
      FileManager.default.contentsOfDirectory(at: Utility.pluginsURL,
                                              includingPropertiesForKeys: [.isDirectoryKey],
                                              options: [.skipsHiddenFiles, .skipsPackageDescendants])
    else {
      Logger.log("Unable to read plugin directory.")
      return []
    }

    let orderArray = UserDefaults.standard.array(forKey: "PluginOrder") as? [String] ?? []
    let order = Array(NSOrderedSet(array: orderArray)) as! [String]
    let orderDict = [String: Int](uniqueKeysWithValues: zip(order, 0...order.count))
    var identifiers = Set<String>()

    let result = contents
      .filter { $0.pathExtension == "iinaplugin" && $0.isExistingDirectory }
      .compactMap { path -> JavascriptPlugin? in
        if let plugin = JavascriptPlugin(filename: path.lastPathComponent) {
          if identifiers.contains(plugin.identifier) {
            Utility.showAlert("duplicated_plugin_id", comment: nil, arguments: [plugin.identifier])
            plugin.identifier += ".\(UUID().uuidString)"
          }
          identifiers.insert(plugin.identifier)
          return plugin
        }
        return nil
      }
      .sorted { orderDict[$0.identifier, default: Int.max] < orderDict[$1.identifier, default: Int.max] }

    savePluginOrder(result)
    return result
  }

  static func loadGlobalInstances() {
    plugins.forEach { plugin in
      guard plugin.enabled else { return }
      if plugin.globalEntryPath != nil {
        plugin.globalInstance = .init(player: nil, plugin: plugin)
      }
    }
  }

  func reloadGlobalInstance(forced: Bool = false) {
    guard globalEntryPath != nil else { return }

    if globalInstance == nil {
      guard enabled else { return }
      globalInstance = .init(player: nil, plugin: self)
    } else {
      if enabled {
        // no need to reload, unless forced
        guard forced else { return }
        globalInstance = .init(player: nil, plugin: self)
      } else {
        globalInstance = nil
      }
    }
  }

  static func savePluginOrder(_ values: [JavascriptPlugin]? = nil) {
    UserDefaults.standard.set((values ?? plugins).map({ $0.identifier }), forKey: "PluginOrder")
  }

  @discardableResult
  static func create(fromPackageURL url: URL) throws -> JavascriptPlugin {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw PluginError.fileNotFound
    }

    let pluginsRoot = Utility.pluginsURL
    let tempFolder = ".temp.\(UUID().uuidString)"
    let tempZipFile = "\(tempFolder).zip"
    let tempDecompressDir = "\(tempFolder)-1"

    defer {
      [tempZipFile, tempDecompressDir].forEach { item in
        try? FileManager.default.removeItem(at: pluginsRoot.appendingPathComponent(item))
      }
    }

    func removeTempPluginFolder() {
      try? FileManager.default.removeItem(at: pluginsRoot.appendingPathComponent(tempFolder))
    }

    let cmd = [
      "cp '\(url.path)' '\(tempZipFile)'",
      "mkdir '\(tempFolder)' '\(tempDecompressDir)'",
      "unzip '\(tempZipFile)' -d '\(tempDecompressDir)'",
      "mv '\(tempDecompressDir)'/* '\(tempFolder)'/"
    ].joined(separator: " && ")
    let (process, stdout, stderr) = Process.run(["/bin/bash", "-c", cmd], at: pluginsRoot)

    guard process.terminationStatus == 0 else {
      let outText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "None"
      let errText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "None"
      removeTempPluginFolder()
      throw PluginError.cannotUnpackage(outText, errText)
    }

    guard let plugin = JavascriptPlugin(filename: tempFolder) else {
      removeTempPluginFolder()
      throw PluginError.cannotLoadPlugin
    }
    return plugin
  }

  @discardableResult
  static func create(fromGitURL urlString: String) throws -> JavascriptPlugin {
    var formatted: String
    if githubRepoRegex.matches(urlString) {
      formatted = "https://github.com/\(urlString)"
    } else {
      guard Regex("^https://github.com/[\\w-]+/[\\w-]+/?$").matches(urlString) else {
        throw PluginError.invalidURL
      }
      formatted = urlString
    }

    guard let url = NSURL(string: formatted)?.standardized else {
      throw PluginError.invalidURL
    }

    let pluginsRoot = Utility.pluginsURL
    let tempFolder = ".temp.\(UUID().uuidString)"
    let tempZipFile = "\(tempFolder).zip"
    let tempDecompressDir = "\(tempFolder)-1"
    let githubMasterURL = url.appendingPathComponent("archive/master.zip").absoluteString

    defer {
      [tempZipFile, tempDecompressDir].forEach { item in
        try? FileManager.default.removeItem(at: pluginsRoot.appendingPathComponent(item))
      }
    }

    func removeTempPluginFolder() {
      try? FileManager.default.removeItem(at: pluginsRoot.appendingPathComponent(tempFolder))
    }

    let cmd = [
      "curl -fsSL '\(githubMasterURL)' > '\(tempZipFile)'",
      "mkdir '\(tempFolder)' '\(tempDecompressDir)'",
      "unzip '\(tempZipFile)' -d '\(tempDecompressDir)'",
      "mv '\(tempDecompressDir)'/*/* '\(tempFolder)'/"
    ].joined(separator: " && ")
    let (process, stdout, stderr) = Process.run(["/bin/bash", "-c", cmd], at: pluginsRoot)

    guard process.terminationStatus == 0 else {
      let outText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "None"
      let errText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "None"
      removeTempPluginFolder()
      throw PluginError.cannotDownload(outText, errText)
    }

    guard let plugin = JavascriptPlugin(filename: tempFolder) else {
      removeTempPluginFolder()
      throw PluginError.cannotLoadPlugin
    }

    guard plugin.githubVersion != nil, formatted == plugin.githubURLString else {
      Logger.log("The plugin \(plugin.name) doesn't contain a ghVersion field or its ghRepo doesn't match the current requested URL \(formatted).")
      removeTempPluginFolder()
      throw PluginError.cannotLoadPlugin
    }
    return plugin
  }

  init?(filename: String) {
    // find package
    let url = Utility.pluginsURL.appendingPathComponent(filename)
    Logger.log("Loading JS plugin from \(url.path)")
    guard url.isFileURL && url.isExistingDirectory else {
      Logger.log("The plugin package doesn't exist.")
      return nil
    }

    // read package
    guard
      let data = try? Data(contentsOf: url.appendingPathComponent("Info.json"), options: .mappedIfSafe),
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
      let identifier = jsonDict["identifier"] as? String,
      let version = jsonDict["version"] as? String,
      let entry = jsonDict["entry"] as? String
      else {
      Logger.log("Info.json must contain these keys: name, author, identifier, version and entry.", level: .error)
      return nil
    }

    guard idRegex.matches(identifier) else {
      Logger.log("Plugin ID \"\(identifier)\"should comply with the Reverse domain name notation", level: .error)
      return nil
    }

    self.root = url
    self.name = name
    self.version = version
    self.entryPath = entry
    self.globalEntryPath = jsonDict["globalEntry"] as? String
    self.authorName = authorName
    self.authorURL = author["url"]
    self.authorEmail = author["email"]
    self.identifier = identifier
    self.desc = jsonDict["description"] as? String
    self.preferencesPage = jsonDict["preferencesPage"] as? String
    self.helpPage = jsonDict["helpPage"] as? String
    self.domainList = (jsonDict["allowedDomains"] as? [String]) ?? []
    self.subProviders = jsonDict["subtitleProviders"] as? [[String: String]]

    if let sidebarTabDef = jsonDict["sidebarTab"] as? [String: String] {
      self.sidebarTabName = sidebarTabDef["name"]
    } else {
      self.sidebarTabName = nil
    }

    self.enabled = UserDefaults.standard.bool(forKey: "PluginEnabled." + identifier)

    if let ghRepo = jsonDict["ghRepo"] as? String {
      if githubRepoRegex.matches(ghRepo) {
        self.githubRepo = ghRepo
      } else {
        Logger.log("Invalid ghRepo format", level: .error)
        return nil
      }
    } else {
      self.githubRepo = nil
    }
    self.githubVersion = jsonDict["ghVersion"] as? Int

    var permissions = Set<Permission>()
    if let permList = jsonDict["permissions"] as? [String] {
      permList.forEach {
        if let p = Permission(rawValue: $0) {
          permissions.insert(p)
        } else {
          Logger.log("Unknown permission: \($0)", level: .warning)
        }
      }
    }
    self.permissions = permissions

    guard let entryURL = resolvePath(entryPath, root: root) else { return nil }
    self.entryURL = entryURL
    self.globalEntryURL = resolvePath(globalEntryPath, root: root)
    self.preferencesPageURL = resolvePath(preferencesPage, root: root)
    self.helpPageURL = resolvePath(helpPage, root: root, allowNetwork: true)

    if let defaultPrefernces = jsonDict["preferenceDefaults"] as? [String: Any] {
      self.defaultPrefernces = defaultPrefernces
    } else {
      Logger.log("Unable to read preferenceDefaults", level: .warning)
      self.defaultPrefernces = [:]
    }

    super.init()

    if (enabled) {
      registerSubProviders()
    }
  }

  func registerSubProviders() {
    guard let subProviders = subProviders else { return }
    for provider in subProviders {
      guard let spID = provider["id"], let spName = provider["name"] else {
        Logger.log("A subtitle provider declaration should have an id and a name.", level: .error)
        continue
      }
      OnlineSubtitle.Providers.registerFromPlugin(identifier, name, id: spID, name: spName)
    }
  }

  func removeSubProviders() {
    OnlineSubtitle.Providers.removeAllFromPlugin(identifier)
  }

  func normalizePath() {
    let pluginsURL = Utility.pluginsURL
    let fileManager = FileManager.default

    var dest = pluginsURL.appendingPathComponent("\(identifier).iinaplugin")
    if fileManager.fileExists(atPath: dest.path) {
      for i in 2..<Int.max {
        dest = pluginsURL.appendingPathComponent("\(identifier)-\(i).iinaplugin")
        if !fileManager.fileExists(atPath: dest.path) { break }
      }
    }

    do {
      try fileManager.moveItem(at: self.root, to: dest)
      self.root = dest
      self.entryURL = resolvePath(entryPath, root: root)!
      self.preferencesPageURL = resolvePath(preferencesPage, root: root)
      self.helpPageURL = resolvePath(helpPage, root: root, allowNetwork: true)
    } catch let error {
      Utility.showAlert(error.localizedDescription)
    }
  }

  @discardableResult
  func remove() -> Int? {
    let pos = JavascriptPlugin.plugins.firstIndex(of: self)
    if let pos = pos {
      JavascriptPlugin.plugins.remove(at: pos)
    }
    try? FileManager.default.removeItem(at: root)
    return pos
  }

  func checkForUpdates(_ handler: @escaping (String?) -> Void) {
    if let ghVersion = githubVersion, let ghRepo = githubRepo {
      Just.get("https://raw.githubusercontent.com/\(ghRepo)/master/Info.json") { result in
        if let json = result.json as? [String: Any],
          let newGHVersion = json["ghVersion"] as? Int,
          let newVersion = json["version"] as? String,
          newGHVersion > ghVersion {
          handler(newVersion)
        } else {
          handler(nil)
        }
      }
    } else {
      handler(nil)
    }
  }

  func updated() throws -> JavascriptPlugin? {
    if let ghURL = githubURLString {
      let plugin = try JavascriptPlugin.create(fromGitURL: ghURL)
      guard plugin.identifier == identifier else {
        Logger.log("The updated plugin has an identifier \(plugin.identifier), which doesn't match the current one (\(identifier))", level: .error)
        throw PluginError.cannotLoadPlugin
      }
      return plugin
    }
    return nil
  }

  func syncPreferences() {
    let url = preferencesFileURL
    Utility.createFileIfNotExist(url: url)
    if #available(macOS 10.13, *) {
      do {
        try (preferences as NSDictionary).write(to: url)
      } catch let e {
        Logger.log("Unable to write preferences file: \(e.localizedDescription)", level: .error)
      }
    } else {
      (preferences as NSDictionary).write(to: url, atomically: true)
    }
  }

  private var preferencesFileURL: URL {
    let url = Utility.pluginsURL
      .appendingPathComponent(".preferences", isDirectory: true)
    Utility.createDirIfNotExist(url: url)
    return url.appendingPathComponent("\(identifier).plist", isDirectory: false)
  }

  lazy var dataURL: URL = {
    let url = Utility.pluginsURL.appendingPathComponent(".data", isDirectory: true)
      .appendingPathComponent(identifier, isDirectory: true)
    Utility.createDirIfNotExist(url: url)
    return url
  }()

  lazy var tmpURL: URL = {
    let url = Utility.tempDirURL.appendingPathComponent("iina-\(identifier)", isDirectory: true)
    Utility.createDirIfNotExist(url: url)
    return url
  }()
}


fileprivate func resolvePath(_ path: String?, root: URL, allowNetwork: Bool = false) -> URL? {
  guard let path = path else { return nil }
  if path.hasPrefix("http://") || path.hasPrefix("https://") {
    if allowNetwork { return URL(string: path) }
    else { return nil }
  } else {
    let url = root.appendingPathComponent(path).standardized
    if url.absoluteString.hasPrefix(root.absoluteString) {
      guard FileManager.default.fileExists(atPath: url.path) else {
        Logger.log("The file \(path) doesn't exist", level: .error)
        return nil
      }
      return url
    } else {
      Logger.log("The file path \(path) is invalid", level: .error)
      return nil
    }
  }
}
