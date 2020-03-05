//
//  JavascriptPlugin.swift
//  iina
//
//  Created by Collider LI on 11/9/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore

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

  static var plugins = loadPlugins()

  @objc var enabled: Bool {
    didSet {
      UserDefaults.standard.set(enabled, forKey: "IINAPlugin" + identifier)
      PlayerCore.playerCores.forEach { $0.loadPlugins() }
    }
  }

  let name: String
  let authorName: String
  let authorEmail: String?
  let authorURL: String?
  let identifier: String
  let version: String
  let desc: String?

  let root: URL
  let entryPath: String
  let scriptPaths: [String]
  let preferencesPage: String?

  let permissions: Set<Permission>
  let domainList: [String]

  var entryURL: URL {
    return root.appendingPathComponent(entryPath)
  }

  var preferencesPageURL: URL? {
    if let preferencePage = preferencesPage {
      return root.appendingPathComponent(preferencePage)
    } else {
      return nil
    }
  }

  lazy var preferences: [String: Any] = {
    NSDictionary(contentsOfFile: preferencesFileURL.path) as? [String: Any] ?? [:]
  }()
  let defaultPrefernces: [String: Any]

  static private func loadPlugins() -> [JavascriptPlugin] {
    guard let contents = try? FileManager.default.contentsOfDirectory(at: Utility.pluginsURL,
                                                                      includingPropertiesForKeys: [.isDirectoryKey],
                                                                      options: [.skipsHiddenFiles, .skipsPackageDescendants])
    else {
      Logger.log("Unable to read plugin directory.")
      return []
    }
    return contents.filter { $0.pathExtension == "iinaplugin" && $0.isExistingDirectory }
      .compactMap { JavascriptPlugin.init(filename: $0.deletingPathExtension().lastPathComponent) }
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
      let identifier = jsonDict["identifier"] as? String,
      let version = jsonDict["version"] as? String,
      let entry = jsonDict["entry"] as? String
      else {
      Logger.log("Info.json must contain these keys: name, author, identifier, version and entry.", level: .error)
      return nil
    }
    self.name = name
    self.version = version
    self.entryPath = entry
    self.authorName = authorName
    self.authorURL = author["url"]
    self.authorEmail = author["email"]
    self.identifier = identifier
    self.desc = jsonDict["description"] as? String
    self.scriptPaths = (jsonDict["scripts"] as? [String]) ?? []
    self.preferencesPage = jsonDict["preferencesPage"] as? String
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
    enabled = UserDefaults.standard.bool(forKey: "IINAPlugin" + identifier)
    self.permissions = permissions
    self.domainList = (jsonDict["domainList"] as? [String]) ?? []
    if let defaultPrefernces = jsonDict["preferenceDefaults"] as? [String: Any] {
      self.defaultPrefernces = defaultPrefernces
    } else {
      Logger.log("Unable to read preferenceDefaults", level: .warning)
      self.defaultPrefernces = [:]
    }
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
