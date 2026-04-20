//
//  SettingsPluginUIUtils.swift
//  iina
//
//  Created by Hechen Li on 2026-04-17.
//  Copyright © 2026 lhc. All rights reserved.
//

class PluginManager {
  enum Result {
    case installed, reinstalled, cancelled, noUpdate
  }

  private let window: NSWindow

  private var installationHandler: ((Result) -> Void)?

  init(window: NSWindow) {
    self.window = window
  }

  @MainActor
  func showPermissionsSheet(forPlugin plugin: JavascriptPlugin, previousPlugin: JavascriptPlugin? = nil) async -> Bool {
    let alert = NSAlert()
    let permissionListView = PrefPluginPermissionListView()
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
    permissionListView.translatesAutoresizingMaskIntoConstraints = false
    alert.messageText = NSLocalizedString("alert.title_warning", comment: "Warning")
    alert.informativeText = NSLocalizedString(previousPlugin == nil ? "alert.plugin_permission" : "alert.plugin_permission_added", comment: "")
    alert.alertStyle = .warning
    alert.accessoryView = scrollView
    scrollView.drawsBackground = false
    scrollView.documentView = permissionListView
    Utility.quickConstraints(["H:|-0-[v]-0-|", "V:|-0-[v]"], ["v": permissionListView])
    alert.addButton(withTitle: NSLocalizedString("plugin.install", comment: "Install"))
    alert.addButton(withTitle: NSLocalizedString("general.cancel", comment: "Cancel"))
    permissionListView.setPlugin(plugin, onlyShowAddedFrom: previousPlugin)
    alert.layout()
    let height = permissionListView.frame.height
    if height < 300 {
      scrollView.frame.size.height = height
      alert.layout()
    }
    return await alert.beginSheetModal(for: self.window) == .alertFirstButtonReturn
  }

  @MainActor
  func update(_ plugin: JavascriptPlugin) async -> (Result, JavascriptPlugin?) {
    do {
      // check if new update exists
      guard let version = try await plugin.checkNewVersion() else {
        await Dialogs.alert("plugin_no_update", style: .informational).show(in: window)
        return (.noUpdate, nil)
      }

      // ask if the user wants to install
      guard await Dialogs.ask("plugin_update_found",
                              titleArgs: [plugin.name],
                              messageArgs: [version, plugin.version]).show(in: window) else {
        return (.cancelled, nil)
      }

      // install update
      guard let newPlugin = try plugin.updated() else {
        return (.cancelled, nil)
      }

      // alert the user if plugin has new permissions
      var permissionCleared = newPlugin.permissions.subtracting(plugin.permissions).isEmpty
      if (!permissionCleared) {
        permissionCleared = await showPermissionsSheet(forPlugin: newPlugin, previousPlugin: plugin)
      }
      if permissionCleared {
        if let pos = plugin.remove() {
          JavascriptPlugin.plugins.insert(newPlugin, at: pos)
        }
        newPlugin.normalizePath()
        newPlugin.reloadGlobalInstance()
        PlayerCore.reloadPluginForAll(newPlugin, forced: true)
        return (.installed, newPlugin)
      }
      return (.cancelled, nil)
    } catch let error {
      handleInstallationError(error)
      return (.cancelled, nil)
    }
  }

  @MainActor
  func handleInstallationError(_ error: Error) {
    let message: String
    if let pluginError = error as? JavascriptPlugin.PluginError {
      switch pluginError {
      case .fileNotFound(let url):
        Logger.log("Plugin install error: file not found: \"\(url)\"", level: .error)
        message = NSLocalizedString("plugin.install_error.file_not_found", comment: "")
      case .invalidURL(let url):
        Logger.log("Plugin install error: URL is invalid: \"\(url)\"", level: .error)
        message = NSLocalizedString("plugin.install_error.invalid_url", comment: "")
      case .cannotDownload(let out, let err):
        Logger.log("Plugin install error: cannot download", level: .error)
        Logger.log("\nSTDOUT_BEGIN\(out)\nSTDOUT_END", level: .debug)
        Logger.log("\nSTDERR_BEGIN\(err)\nSTDERR_END", level: .error)
        let str = NSLocalizedString("plugin.install_error.cannot_download", comment: "")
        message = String(format: str, err)
      case .cannotUnpackage(_, let err):
        let str = NSLocalizedString("plugin.install_error.cannot_unpackage", comment: "")
        message = String(format: str, err)
      case .cannotLoadPlugin:
        message = NSLocalizedString("plugin.install_error.cannot_load", comment: "")
      }
    } else {
      message = error.localizedDescription
    }
    if Thread.isMainThread {
      Utility.showAlert("plugin.install_error", arguments: [message], sheetWindow: window)
    } else {
      DispatchQueue.main.sync {
        Utility.showAlert("plugin.install_error", arguments: [message], sheetWindow: window)
      }
    }
  }

  @MainActor
  private func install(_ plugin: JavascriptPlugin) async -> Result {
    guard await showPermissionsSheet(forPlugin: plugin) else {
      plugin.remove()
      return .cancelled
    }
    // check whether a duplicate plugin exists, if yes, replace
    if let pos = JavascriptPlugin.plugins.firstIndex(where: { $0.identifier == plugin.identifier }) {
      guard await Dialogs.ask("plugin_reinstall", titleArgs: [plugin.name]).show(in: window) else {
        plugin.remove()
        return .cancelled
      }
      // uninstall the old plugins
      let oldPlugin = JavascriptPlugin.plugins[pos]
      oldPlugin.enabled = false
      oldPlugin.remove()
      // install the new plugin
      plugin.normalizePath()
      JavascriptPlugin.plugins.insert(plugin, at: pos)
      plugin.enabled = true
      return .reinstalled
    } else {
      plugin.normalizePath()
      JavascriptPlugin.plugins.append(plugin)
      plugin.enabled = true
      return .installed
    }
  }

  @MainActor
  func install(gitHubString string: String? = nil, localPackageURL url: URL? = nil, handler: ((Result) -> Void)? = nil) async {
    do {
      let plugin = if let string = string {
        try JavascriptPlugin.create(fromGitURL: string)
      } else if let url = url {
        try JavascriptPlugin.create(fromPackageURL: url)
      } else {
        fatalError("PluginManager.install: a source must be provided.")
      }
      let res = await install(plugin)
      handler?(res)
    } catch let error {
      handleInstallationError(error)
      handler?(.cancelled)
    }
  }

  @MainActor
  func uninstall(_ plugin: JavascriptPlugin) async -> Bool {
    guard await Dialogs.ask("plugin_uninstall", titleArgs: [plugin.name]).show(in: window) else {
      return false
    }
    plugin.enabled = false
    plugin.remove()
    return true
  }
}
