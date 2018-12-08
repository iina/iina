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

  enum Permission: String {
    case networkRequest = "network-request"
    case callProcess = "call-process"
    case showOSD = "show-osd"
    case showAlert = "show-alert"
    case addMenuItems = "menu-items"

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

  let name: String
  let authorName: String
  let authorEmail: String?
  let authorURL: String?
  let version: String
  let description: String?

  let root: URL
  let entryPath: String
  let scriptPaths: [String]

  let permissions: Set<Permission>
  let domainList: [String]

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
    self.domainList = (jsonDict["domainList"] as? [String]) ?? []
  }

}
