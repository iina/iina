//
//  PrefPluginViewController.swift
//  iina
//
//  Created by Collider LI on 12/9/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa
import WebKit

fileprivate let defaultPlugins = [
  ["url": "iina/plugin-demo", "id": "io.iina.demo"],
  ["url": "iina/plugin-online-media", "id": "io.iina.ytdl"],
]

fileprivate extension NSUserInterfaceItemIdentifier {
  static let cellView = NSUserInterfaceItemIdentifier("PluginCell")
  static let installed = NSUserInterfaceItemIdentifier("InstalledCell")
  static let url = NSUserInterfaceItemIdentifier("URLCell")
}

fileprivate extension NSPasteboard.PasteboardType {
  static let iinaPluginID = NSPasteboard.PasteboardType(rawValue: "com.colliderli.iina.pluginID")
}

class PrefPluginViewController: NSViewController, PreferenceWindowEmbeddable {
  override var nibName: NSNib.Name {
    return NSNib.Name("PrefPluginViewController")
  }

  var preferenceTabTitle: String {
    return NSLocalizedString("preference.plugins", comment: "Plugins")
  }

  var preferenceTabImage: NSImage {
    return NSImage(named: NSImage.Name("pref_general"))!
  }

  var preferenceContentIsScrollable: Bool {
    return false
  }

  var plugins: [JavascriptPlugin] = []
  var currentPlugin: JavascriptPlugin?

  @IBOutlet weak var tabView: NSTabView!
  @IBOutlet weak var tableView: NSTableView!
  @IBOutlet weak var segmentControl: NSSegmentedControl!
  @IBOutlet weak var pluginInfoContentView: NSView!
  @IBOutlet weak var pluginNameLabel: NSTextField!
  @IBOutlet weak var pluginVersionLabel: NSTextField!
  @IBOutlet weak var pluginAuthorLabel: NSTextField!
  @IBOutlet weak var pluginIdentifierLabel: NSTextField!
  @IBOutlet weak var pluginDescLabel: NSTextField!
  @IBOutlet weak var pluginSourceLabel: NSTextField!
  @IBOutlet weak var pluginCheckUpdatesBtn: NSButton!
  @IBOutlet weak var pluginPermissionsView: PrefPluginPermissionListView!
  @IBOutlet weak var pluginWebsiteEmailStackView: NSStackView!
  @IBOutlet weak var pluginWebsiteBtn: NSButton!
  @IBOutlet weak var pluginEmailBtn: NSButton!
  @IBOutlet weak var pluginSupportStackView: NSStackView!
  @IBOutlet weak var pluginSourceView: NSView!
  @IBOutlet weak var pluginHelpView: NSView!
  @IBOutlet weak var pluginHelpContainerView: NSView!
  @IBOutlet weak var pluginHelpWebViewLoadingIndicator: NSProgressIndicator!
  @IBOutlet weak var pluginHelpLoadingFailedView: NSView!
  @IBOutlet weak var pluginPreferencesContentView: NSView!

  @IBOutlet var newPluginSheet: NSWindow!
  @IBOutlet weak var newPluginSourceTextField: NSTextField!
  @IBOutlet weak var newPluginInstallBtn: NSButton!
  @IBOutlet weak var pluginInstallationProgressIndicator: NSProgressIndicator!
  @IBOutlet weak var pluginCheckUpdatesProgressIndicator: NSProgressIndicator!
  @IBOutlet weak var defaultPluginsTableView: NSTableView!

  var pluginHelpWebView: NonscrollableWebview!
  var pluginHelpWebViewHeight: NSLayoutConstraint!

  var pluginPreferencesWebView: NonscrollableWebview!
  var pluginPreferencesWebViewHeight: NSLayoutConstraint!
  var pluginPreferencesViewController: PrefPluginPreferencesViewController!

  private var defaultPluginsData: [[String: Any]] = []
  private var queue = DispatchQueue(label: "com.collider.iina.plugin-install", qos: .userInteractive)

  override func viewDidLoad() {
    super.viewDidLoad()

    tableView.delegate = self
    tableView.dataSource = self
    tableView.registerForDraggedTypes([.iinaPluginID])

    defaultPluginsTableView.dataSource = self
    defaultPluginsTableView.delegate = self

    clearPluginPage()
  }

  private func createPreferenceView() {
    let config = WKWebViewConfiguration()
    config.userContentController.addUserScript(WKUserScript(source: """
      let counter = 0;
      window.onerror = (msg, url, line, col, error) => {
        window.iina._post("error", [msg, url, line, col, error]);
      };
      window.iina = {
        log(message) {
          this._post("log", [message])
        },
        _post(name, data) {
          webkit.messageHandlers.iina.postMessage([name, data]);
        },
        _callbacks: {},
        _call(id, data) {
          this._callbacks[id].call(null, data);
          delete this._callbacks[id];
        }
      };
      window.iina.preferences = {
        set(name, value) {
          window.iina._post("set", [name, value]);
        },
        get(name, callback) {
          counter++;
          window.iina._post("get", [name, counter]);
          if (typeof callback !== "function")
            throw Error("Callback is not provided.");
          window.iina._callbacks[counter] = callback;
        },
      };
    """, injectionTime: .atDocumentStart, forMainFrameOnly: true))

    config.userContentController.addUserScript(WKUserScript(source: """
      const { preferences } = window.iina;
      const inputs = document.querySelectorAll("input[data-pref-key]");
      const radioNames = new Set();
      Array.prototype.forEach.call(inputs, input => {
        const key = input.dataset.prefKey;
        const type = input.type;
        if (type === "radio") {
          radioNames.add(input.name);
        } else {
          preferences.get(key, (value) => {
              if (type === "number") {
                input.value = parseFloat(value);
              } else if (type === "checkbox") {
                input.checked = value;
              } else {
                input.value = value;
              }
          });
          input.addEventListener("change", () => {
              let value = input.value;
              switch (input.dataset.type) {
                  case "int": value = parseInt(value); break;
                  case "float": value = parseFloat(value); break;
              }
              preferences.set(key, input.type === "checkbox" ? !!input.checked : value);
          });
        }
      });
      for (const name of radioNames.values()) {
        const inputs = document.getElementsByName(name);
        preferences.get(name, (value) => {
          Array.prototype.forEach.call(inputs, input => {
            if (input.value === value) input.checked = true;
            input.addEventListener("change", () => {
              if (input.checked) preferences.set(name, input.value);
            });
          });
        });
      }
    """, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

    config.userContentController.add(self, name: "iina")
    
    pluginPreferencesWebView = NonscrollableWebview(frame: .zero, configuration: config)
    pluginPreferencesViewController = PrefPluginPreferencesViewController()
    pluginPreferencesViewController.view = pluginPreferencesWebView

    pluginPreferencesWebView.navigationDelegate = self
    pluginPreferencesWebView.translatesAutoresizingMaskIntoConstraints = false
    pluginPreferencesContentView.addSubview(pluginPreferencesWebView)
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": pluginPreferencesWebView])
    pluginPreferencesWebViewHeight = NSLayoutConstraint(item: pluginPreferencesWebView!, attribute: .height,
                                                        relatedBy: .equal, toItem: nil, attribute: .notAnAttribute,
                                                        multiplier: 1, constant: 0)
    pluginPreferencesWebView.addConstraint(pluginPreferencesWebViewHeight)
  }

  private func createHelpView() {
    pluginHelpWebView = NonscrollableWebview(frame: .zero)

    pluginHelpWebView.navigationDelegate = self
    pluginHelpWebView.translatesAutoresizingMaskIntoConstraints = false
    pluginHelpContainerView.addSubview(pluginHelpWebView, positioned: .below, relativeTo: nil)
    Utility.quickConstraints(["H:|[v]|", "V:|[v]-(0@40)-|"], ["v": pluginHelpWebView])
    pluginHelpWebViewHeight = NSLayoutConstraint(item: pluginHelpWebView!, attribute: .height,
                                                        relatedBy: .equal, toItem: nil, attribute: .notAnAttribute,
                                                        multiplier: 1, constant: 32)
    pluginHelpWebView.addConstraint(pluginHelpWebViewHeight)
  }

  @IBAction func tabSwitched(_ sender: NSSegmentedControl) {
    tabView.selectTabViewItem(at: sender.selectedSegment)
    guard let currentPlugin = currentPlugin else { return }
    if sender.selectedSegment == 2 {
      // Preferences
      guard let prefURL = currentPlugin.preferencesPageURL else { return }
      if pluginPreferencesWebView == nil {
        createPreferenceView()
      }
      pluginPreferencesWebView.loadFileURL(prefURL, allowingReadAccessTo: currentPlugin.root)
      pluginPreferencesViewController.plugin = currentPlugin
    } else if sender.selectedSegment == 1 {
      // About
      if let _ = currentPlugin.helpPageURL {
        pluginSupportStackView.setVisibilityPriority(.mustHold, for: pluginHelpView)
        if pluginHelpWebView == nil {
          createHelpView()
        }
        loadHelpPage()
      } else {
        pluginSupportStackView.setVisibilityPriority(.notVisible, for: pluginHelpView)
      }
    }
  }

  private func clearPluginPage() {
    pluginInfoContentView.isHidden = true
  }

  private func loadPluginPage(_ plugin: JavascriptPlugin) {
    tabView.selectTabViewItem(at: 0)
    segmentControl.selectedSegment = 0
    pluginHelpWebViewLoadingIndicator.stopAnimation(self)
    pluginInfoContentView.isHidden = false
    pluginNameLabel.stringValue = plugin.name
    pluginAuthorLabel.stringValue = plugin.authorName
    pluginVersionLabel.stringValue = plugin.version
    pluginDescLabel.stringValue = plugin.desc ?? "No Description"
    pluginIdentifierLabel.stringValue = plugin.identifier
    pluginWebsiteEmailStackView.setVisibilityPriority(plugin.authorEmail == nil ? .notVisible : .mustHold, for: pluginEmailBtn)
    pluginWebsiteEmailStackView.setVisibilityPriority(plugin.authorURL == nil ? .notVisible : .mustHold, for: pluginWebsiteBtn)
    pluginPermissionsView.setPlugin(plugin)
    pluginSourceLabel.stringValue = plugin.githubURLString ?? NSLocalizedString("plugin.local", comment: "")
    pluginCheckUpdatesBtn.isHidden = plugin.githubRepo == nil || plugin.githubVersion == nil

    currentPlugin = plugin
  }

  private func loadHelpPage() {
    guard let currentPlugin = currentPlugin, let helpURL = currentPlugin.helpPageURL else { return }
    if helpURL.isFileURL {
      pluginHelpWebView.loadFileURL(helpURL, allowingReadAccessTo: currentPlugin.root)
    } else {
      pluginHelpWebView.load(URLRequest(url: helpURL))
    }
  }

  private func handleInstallationError(_ error: Error) {
    let message: String
    if let pluginError = error as? JavascriptPlugin.PluginError {
      switch pluginError {
      case .invalidURL:
        message = NSLocalizedString("plugin.install_error.invalid_url", comment: "")
      case .cannotDownload(_, let err):
        let str = NSLocalizedString("plugin.install_error.cannot_download", comment: "")
        message = String(format: str, err)
      case .cannotLoadPlugin:
        message = NSLocalizedString("plugin.install_error.cannot_load", comment: "")
      }
    } else {
      message = error.localizedDescription
    }
    if Thread.isMainThread {
      Utility.showAlert("plugin.install_error", arguments: [message], sheetWindow: self.view.window!)
    } else {
      DispatchQueue.main.sync {
        Utility.showAlert("plugin.install_error", arguments: [message], sheetWindow: self.view.window!)
      }
    }
  }

  private func showPermissionsSheet(forPlugin plugin: JavascriptPlugin, previousPlugin: JavascriptPlugin?, handler: @escaping (Bool) -> Void) {
    let block = {
      let alert = NSAlert()
      let permissionListView = PrefPluginPermissionListView()
      let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 280, height: 300))
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
      alert.beginSheetModal(for: self.view.window!) { result in
        handler(result == .alertFirstButtonReturn)
      }
    }
    if Thread.isMainThread {
      block()
    } else {
      DispatchQueue.main.sync {
        block()
      }
    }
  }

  @IBAction func websiteBtnAction(_ sender: NSButton) {
    if let website = currentPlugin?.authorURL, let url = URL(string: website) {
      NSWorkspace.shared.open(url)
    }
  }

  @IBAction func emailBtnAction(_ sender: NSButton) {
    if let email = currentPlugin?.authorEmail, let url = URL(string: "mailto:\(email)") {
      NSWorkspace.shared.open(url)
    }
  }

  @IBAction func helpViewReloadBtnAction(_ sender: Any) {
    guard let _ = pluginHelpWebView else { return }
    loadHelpPage()
  }

  @IBAction func promptToInstallFromGitHub(_ sender: Any) {
    defaultPluginsData = defaultPlugins.map { d in
      let installed = JavascriptPlugin.plugins.contains { $0.identifier == d["id"] }
      return [
        "url": d["url"]!,
        "notInstalledRaw": !installed,
        "installed": NSLocalizedString(installed ? "plugin.installed" : "plugin.not_installed", comment: "")
      ]
    }
    defaultPluginsTableView.reloadData()
    newPluginSourceTextField.stringValue = ""
    view.window!.beginSheet(newPluginSheet)
  }

  @IBAction func installPluginFromGitHub(_ sender: Any) {
    pluginInstallationProgressIndicator.startAnimation(self)
    defaultPluginsTableView.isEnabled = false
    newPluginSourceTextField.isEnabled = false
    newPluginInstallBtn.isEnabled = false

    let source = self.newPluginSourceTextField.stringValue
    queue.async {
      defer {
        DispatchQueue.main.async {
          self.pluginInstallationProgressIndicator.stopAnimation(self)
          self.defaultPluginsTableView.isEnabled = true
          self.newPluginSourceTextField.isEnabled = true
          self.newPluginInstallBtn.isEnabled = true
          self.view.window!.endSheet(self.newPluginSheet)
        }
      }
      do {
        let plugin = try JavascriptPlugin.create(fromGitURL: source)
        self.showPermissionsSheet(forPlugin: plugin, previousPlugin: nil) { ok in
          if ok {
            plugin.normalizePath()
            plugin.enabled = true
            JavascriptPlugin.plugins.append(plugin)
            PlayerCore.reloadPluginForAll(plugin)
            self.tableView.reloadData()
          } else {
            plugin.remove()
          }
        }
      } catch let error {
        self.handleInstallationError(error)
      }
    }
  }

  @IBAction func endSheet(_ sender: NSButton) {
    view.window!.endSheet(sender.window!)
  }

  @IBAction func uninstallPlugin(_ sender: Any) {
    guard let currentPlugin = currentPlugin else { return }
    Utility.quickAskPanel("plugin_uninstall", titleArgs: [currentPlugin.name], sheetWindow: view.window!) { response in
      if response == .alertFirstButtonReturn {
        currentPlugin.remove()
        self.clearPluginPage()
        self.tableView.reloadData()
      }
    }
  }

  @IBAction func revealPlugin(_ sender: Any) {
    guard let currentPlugin = currentPlugin else { return }
    NSWorkspace.shared.activateFileViewerSelecting([currentPlugin.root])
  }

  @IBAction func checkForPluginUpdate(_ sender: Any) {
    guard let currentPlugin = currentPlugin else { return }
    pluginCheckUpdatesProgressIndicator.startAnimation(self)
    pluginCheckUpdatesBtn.isEnabled = false

    currentPlugin.checkForUpdates() { [unowned self] version in
      DispatchQueue.main.async {
        defer {
          self.pluginCheckUpdatesProgressIndicator.stopAnimation(self)
          self.pluginCheckUpdatesBtn.isEnabled = true
        }

        guard let version = version else {
          Utility.showAlert("plugin_no_update", style: .informational, sheetWindow: self.view.window!)
          return
        }
        Utility.quickAskPanel("plugin_update_found", titleArgs: [currentPlugin.name], messageArgs: [version, currentPlugin.version], sheetWindow: self.view.window!) { response in
          guard response == .alertFirstButtonReturn else { return }
          DispatchQueue.main.async {
            self.updatePlugin()
          }
        }
      }
    }
  }

  private func updatePlugin() {
    guard let currentPlugin = currentPlugin else { return }
    pluginCheckUpdatesProgressIndicator.startAnimation(self)
    pluginCheckUpdatesBtn.isEnabled = false
    pluginCheckUpdatesBtn.title = NSLocalizedString("plugin.updating", comment: "")
    
    defer {
      self.pluginCheckUpdatesProgressIndicator.stopAnimation(self)
      pluginCheckUpdatesBtn.title = NSLocalizedString("plugin.check_for_updates", comment: "")
      pluginCheckUpdatesBtn.isEnabled = true
    }

    do {
      guard let newPlugin = try currentPlugin.updated() else { return }
      let install = {
        if let pos = currentPlugin.remove() {
          JavascriptPlugin.plugins.insert(newPlugin, at: pos)
        }
        newPlugin.normalizePath()
        PlayerCore.reloadPluginForAll(newPlugin)
        self.currentPlugin = newPlugin
        self.tableView.reloadData()
        self.loadPluginPage(newPlugin)
      }
      if newPlugin.permissions.subtracting(currentPlugin.permissions).isEmpty {
        install()
      } else {
        showPermissionsSheet(forPlugin: newPlugin, previousPlugin: currentPlugin) { ok in
          if ok { install() }
        }
      }
    } catch let error {
      handleInstallationError(error)
    }
  }
}

extension PrefPluginViewController: NSTableViewDelegate, NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int {
    if tableView == self.tableView {
      return JavascriptPlugin.plugins.count
    } else {
      return defaultPlugins.count
    }
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    if tableView == self.tableView {
      return JavascriptPlugin.plugins[at: row]
    } else {
      return defaultPluginsData[at: row]
    }
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let identifier: NSUserInterfaceItemIdentifier = tableView == self.tableView ? .cellView :
      tableColumn?.identifier.rawValue == "URL" ? .url : .installed
    let view = tableView.makeView(withIdentifier: identifier, owner: self)
    if tableView == self.tableView {
      (view as! NSTableCellView).textField?.stringValue = JavascriptPlugin.plugins[at: row]?.name ?? ""
    }
    return view
  }

  func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
    guard rowIndexes.count == 1, let item = JavascriptPlugin.plugins[at: rowIndexes[rowIndexes.startIndex]] else { return false }
    pboard.setString(item.identifier, forType: .iinaPluginID)
    return true
  }

  func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
    tableView.setDropRow(row, dropOperation: .above)
    guard info.draggingSource as? NSTableView == tableView else { return [] }
    return .move
  }

  func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
    guard
      let id = info.draggingPasteboard.string(forType: .iinaPluginID),
      let originalRow = JavascriptPlugin.plugins.firstIndex(where: { $0.identifier == id })
      else { return false }

    let p = JavascriptPlugin.plugins.remove(at: originalRow)
    JavascriptPlugin.plugins.insert(p, at: originalRow < row ? row - 1 : row)
    JavascriptPlugin.savePluginOrder()

    tableView.beginUpdates()
    tableView.moveRow(at: originalRow, to: row)
    tableView.endUpdates()
    return true
  }

  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    if tableView == defaultPluginsTableView {
      return defaultPluginsData[at: row]?["notInstalledRaw"] as? Bool ?? true
    }
    return true
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard let tv = notification.object as? NSTableView else { return }
    if tv == tableView {
      guard let plugin = JavascriptPlugin.plugins[at: tableView.selectedRow] else {
        clearPluginPage()
        return
      }
      loadPluginPage(plugin)
    } else if tv == defaultPluginsTableView {
      guard tv.selectedRow >= 0 else { return }
      newPluginSourceTextField.stringValue = defaultPlugins[tv.selectedRow]["url"]!
    }
  }
}

extension PrefPluginViewController: WKNavigationDelegate {
  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    if webView == pluginPreferencesWebView {
      guard
        let url = navigationAction.request.url,
        let currentPluginPrefPageURL = currentPlugin?.preferencesPageURL,
        url.absoluteString.starts(with: currentPluginPrefPageURL.absoluteString)
      else {
        Logger.log("Loading page from \(navigationAction.request.url?.absoluteString ?? "?") is not allowed", level: .error)
          decisionHandler(.cancel)
          return
      }
    }
    decisionHandler(.allow)
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    if webView == pluginHelpWebView {
      pluginHelpLoadingFailedView.isHidden = true
      pluginHelpWebViewLoadingIndicator.startAnimation(self)
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    pluginHelpWebViewLoadingIndicator.stopAnimation(self)

    let currentConstraint = webView == pluginPreferencesWebView ?
      pluginPreferencesWebViewHeight : pluginHelpWebViewHeight
    webView.evaluateJavaScript("document.readyState", completionHandler: { (complete, error) in
      if complete == nil { return }
      webView.evaluateJavaScript("document.body.scrollHeight", completionHandler: { (height, error) in
        currentConstraint?.constant = height as! CGFloat
      })
    })
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    failedLoadingHelpPage()
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    failedLoadingHelpPage()
  }

  private func failedLoadingHelpPage() {
    pluginHelpLoadingFailedView.isHidden = false
    pluginHelpWebViewLoadingIndicator.stopAnimation(self)
    pluginHelpWebViewHeight.constant = 0
  }
}

extension PrefPluginViewController: WKScriptMessageHandler {
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let plugin = currentPlugin else { return }
    guard let dict = message.body as? [Any], dict.count == 2 else { return }
    guard let name = dict[0] as? String else { return }
    guard let data = dict[1] as? [Any], let prefName = data[0] as? String else { return }
    if name == "set" {
      plugin.preferences[prefName] = data[1]
    } else if name == "get" {
      var value: Any? = nil
      if let v = plugin.preferences[prefName] {
        value = v
      } else if let v = plugin.defaultPrefernces[prefName] {
        value = v
      }
      let result: String
      if let value = value {
        if JSONSerialization.isValidJSONObject(value), let json = try? String(data: JSONSerialization.data(withJSONObject: value, options: []), encoding: .utf8) {
          result = json
        } else if value is String {
          result = "\"\(value)\""
        } else {
          result = "\(value)"
        }
      } else {
        result = "null"
      }
      pluginPreferencesWebView.evaluateJavaScript("window.iina._call(\(data[1]), \(result))")
    } else if name == "error" {
      Logger.log("JS:\(plugin.name) Preference page \(data[0]) \(data[2]),\(data[3]): \(data[4])")
    } else if name == "log" {
      Logger.log("JS:\(plugin.name) Preference page: \(data[0])")
    }
  }
}


class PrefPluginPreferencesViewController: NSViewController {
  var plugin: JavascriptPlugin?

  override func viewWillDisappear() {
    if let plugin = plugin {
      plugin.syncPreferences()
    }
  }
}


class NonscrollableWebview: WKWebView {
  override func scrollWheel(with event: NSEvent) {
    nextResponder?.scrollWheel(with: event)
  }
}
