//
//  SettingsPagePlugin.swift
//  iina
//
//  Created by Hechen Li on 2026-02-02.
//  Copyright © 2026 lhc. All rights reserved.
//

import WebKit

class SettingsPagePlugin: SettingsPage {
  override var title: String {
    return NSLocalizedString("preference.plugins", comment: "Plugins")
  }
  
  override var image: NSImage {
    return makeSymbol("puzzlepiece.extension", fallbackImage: "pref_plugin")
  }
  
  override var localizationTable: String {
    "SettingsPluginLocalizable"
  }
  
  private lazy var installView: PluginInstallView = .init(l10n: localizationContext)
  private lazy var pluginList: PluginListView = .init(l10n: localizationContext)
  
  override func content() -> NSView {
    return sections {
      sectionInstall()
      sectionPluginList()
    }
  }
  
  private func sectionInstall() -> [NSView] {
    return section {
      SettingsListView() {
        SettingsItem.Custom()
          .view(installView.view)
      }
    }
  }
  
  private func sectionPluginList() -> [NSView] {
    return section {
      SettingsListView() {
        SettingsItem.Custom()
          .view(pluginList.view)
      }
    }
  }
}


fileprivate class PluginInstallView: SettingsAccessory.Base {
  override init(l10n: SettingsLocalization.Context) {
    super.init(l10n: l10n)
    
    let githubBtn = makeButton(.text_InstallFromGitHub)
    let localBtn = makeButton(.text_InstallPackage)
    let btnStackView = makeStackView([githubBtn, localBtn])
    
    let installLabel = makeLabel(.text_YouCanInstallANew).makeMultiLine()
    
    let stackView = makeStackView([installLabel, btnStackView], orientation: .vertical)
    stackView.alignment = .leading
    
    view.addSubview(stackView)
    stackView.padding(.all(12))
  }
}


fileprivate extension NSUserInterfaceItemIdentifier {
  static let pluginItem = NSUserInterfaceItemIdentifier("PluginCell")
  static let installed = NSUserInterfaceItemIdentifier("InstalledCell")
  static let url = NSUserInterfaceItemIdentifier("URLCell")
}

fileprivate extension NSPasteboard.PasteboardType {
  static let iinaPluginID = NSPasteboard.PasteboardType(rawValue: "com.colliderli.iina.pluginID")
}

fileprivate class PluginListView: SettingsAccessory.Base {
  static var currentPlugin: JavascriptPlugin?
  let tableView: NSTableView

  override init(l10n: SettingsLocalization.Context) {
    self.tableView = NSTableView()
    
    super.init(l10n: l10n)
    
    let column = NSTableColumn(identifier: .pluginItem)
    column.title = "Items"
    tableView.style = .plain
    tableView.addTableColumn(column)
    tableView.dataSource = self
    tableView.delegate = self
    tableView.registerForDraggedTypes([.iinaPluginID])
    tableView.gridStyleMask = .solidHorizontalGridLineMask
    tableView.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(tableView)
    tableView.padding(.all(0))
  }
}

extension PluginListView: NSTableViewDelegate, NSTableViewDataSource {
  class ItemView: NSTableCellView {
    var nameLabel: NSTextField!
    var enabledSwitch: NSSwitch!
    var versionLabel: NSTextField!
    var descLabel: NSTextField!
    var aboutBtn: NSButton!
    var actionsBtn: NSButton!
    weak var plugin: JavascriptPlugin!
    
    weak private var listView: PluginListView!
    
    func setup(plugin: JavascriptPlugin, listView: PluginListView) {
      self.plugin = plugin
      
      if nameLabel == nil {
        self.identifier = .pluginItem
        self.listView = listView

        // left
        nameLabel = NSTextField(labelWithString: plugin.name)
        nameLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .bold)
        
        enabledSwitch = NSSwitch()
        enabledSwitch.state = plugin.enabled ? .on : .off
        enabledSwitch.controlSize = .mini
        
        versionLabel = NSTextField(labelWithString: plugin.version + (plugin.isExternal ? " DEV" : ""))
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        
        let nameStackView = NSStackView()
        nameStackView.translatesAutoresizingMaskIntoConstraints = false
        nameStackView.orientation = .horizontal
        nameStackView.distribution = .fill
        
        self.actionsBtn = NSButton()
        actionsBtn.image = .findSFSymbol(["gearshape.fill"])
        actionsBtn.isBordered = false
        actionsBtn.target = self
        actionsBtn.action = #selector(actionsBtnAction)
        
        [enabledSwitch, nameLabel, versionLabel, actionsBtn].forEach {
          nameStackView.addArrangedSubview($0)
        }
        
        // bottom
        descLabel = NSTextField(labelWithString: plugin.desc ?? "No description")
        descLabel.lineBreakMode = .byTruncatingTail
        descLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        descLabel.textColor = .secondaryLabelColor
        
        let stackView = NSStackView(views: [nameStackView, descLabel])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        
        self.aboutBtn = NSButton()
        aboutBtn.size(width: 18, height: 18)
        aboutBtn.image = .findSFSymbol(["info.circle"])
        aboutBtn.imageScaling = .scaleProportionallyUpOrDown
        aboutBtn.isBordered = false
        aboutBtn.translatesAutoresizingMaskIntoConstraints = false
        aboutBtn.target = self
        aboutBtn.action = #selector(aboutBtnAction)
        
        self.addSubview(stackView)
        self.addSubview(aboutBtn)
        
        stackView.padding(.top(12), .bottom(4), .leading(8), .trailing(20))
        aboutBtn.padding(.trailing(8))
          .center(with: self, y: true)
      } else {
        nameLabel.stringValue = plugin.name
        versionLabel.stringValue = plugin.version
        enabledSwitch.state = plugin.enabled ? .on : .off
        descLabel.stringValue = plugin.desc ?? "No description"
      }
    }
    
    @objc func actionsBtnAction(_ sender: NSButton) {
      PluginListView.currentPlugin = plugin
      
      let l10n = listView.l10n!
      let actionMenu = NSMenu()
      actionMenu.addItem(withTitle: l10n.localized(.text_Uninstall), image: ["trash"],
                         action: #selector(uninstallAction),
                         target: plugin.isExternal ? nil : listView)
      actionMenu.addItem(withTitle: l10n.localized(.text_ShowInFinder), image: ["folder"],
                         action: #selector(showPluginInFinderAction), target: listView)
      NSMenu.popUpContextMenu(actionMenu, with: NSApp.currentEvent!, for: sender)
    }
    
    @objc func aboutBtnAction(_ sender: NSButton) {
      PluginListView.currentPlugin = plugin
      
      let sheetWindow = PluginDetailsWindow(l10n: listView.l10n, plugin: plugin, window: window!)
      window!.beginSheet(sheetWindow)
    }
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    return JavascriptPlugin.plugins.count
  }
  
  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    return 60
  }
  
  func selectionShouldChange(in tableView: NSTableView) -> Bool {
    return false
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    return JavascriptPlugin.plugins[at: row]
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let identifier: NSUserInterfaceItemIdentifier = .pluginItem
    guard let plugin = JavascriptPlugin.plugins[at: row] else { return nil }
    
    let view = (tableView.makeView(withIdentifier: identifier, owner: self) as? ItemView) ?? ItemView()
    view.setup(plugin: plugin, listView: self)
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
}

extension PluginListView {
  @objc func uninstallAction() {
    guard let currentPlugin = PluginListView.currentPlugin else { return }
    Utility.quickAskPanel("plugin_uninstall", titleArgs: [currentPlugin.name], sheetWindow: view.window!) { response in
      if response == .alertFirstButtonReturn {
        currentPlugin.enabled = false
        currentPlugin.remove()
        self.tableView.reloadData()
      }
    }
  }
  
  @objc func showPluginInFinderAction(_ sender: Any) {
    guard let currentPlugin = PluginListView.currentPlugin else { return }
    NSWorkspace.shared.activateFileViewerSelecting([currentPlugin.root])
  }
}


fileprivate class PluginDetailsWindow: NSWindow {
  private let plugin: JavascriptPlugin
  private let okButton: NSButton
  private var webView: WKWebView!
  private var currentTab: Tab = .about
  
  unowned let window: NSWindow
  
  enum Tab {
    case about, help, settings
  }
  
  init(l10n: SettingsLocalization.Context, plugin: JavascriptPlugin, window: NSWindow) {
    self.window = window
    self.plugin = plugin
    let style: NSWindow.StyleMask = [.titled, .resizable, .fullSizeContentView]
    
    self.okButton = NSButton(title: l10n.localized(.text_OK), target: nil, action: nil)
    okButton.translatesAutoresizingMaskIntoConstraints = false
    
    super.init(contentRect: NSRect(x: 0, y: 0, width: 600, height: 450),
               styleMask: style,
               backing: .buffered,
               defer: false)
    
    okButton.target = self
    okButton.action = #selector(dismissSheet)
    
    let nameLabel = NSTextField(labelWithString: plugin.name)
    nameLabel.translatesAutoresizingMaskIntoConstraints = false
    nameLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .bold)
    
    let versionLabel = NSTextField(labelWithString: plugin.version)
    versionLabel.translatesAutoresizingMaskIntoConstraints = false
    versionLabel.textColor = .secondaryLabelColor
    versionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)

    let iconView = NSImageView()
    iconView.image = NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil)
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.size(width: 24, height: 24)
    
    let segControl = NSSegmentedControl()
    segControl.segmentCount = 3
    segControl.segmentStyle = .texturedSquare
    if #available(macOS 26.0, *) {
      segControl.controlSize = .extraLarge
    } else {
      segControl.size(width: 360)
    }
    segControl.translatesAutoresizingMaskIntoConstraints = false
    
    let segments: [(String, SettingsLocalization.Key)] = [
      ("info.circle", .text_About),
      ("questionmark.circle", .text_Help),
      ("gearshape.circle", .text_Settings)
    ]
    for (i, seg) in segments.enumerated() {
      segControl.setImage(NSImage(systemSymbolName: seg.0, accessibilityDescription: nil), forSegment: i)
      segControl.setLabel(l10n.localized(seg.1), forSegment: i)
    }
    
    contentView?.addSubview(iconView)
    iconView.padding(.leading(16), .top(20))
    contentView?.addSubview(nameLabel)
    nameLabel.padding(.top(16)).spacing(to: iconView, .leading(8))
    contentView?.addSubview(versionLabel)
    versionLabel.spacing(to: nameLabel, .top(4)).spacing(to: iconView, .leading(8))
    contentView?.addSubview(segControl)
    segControl.padding(.top(16), .trailing(16))
    contentView?.addSubview(okButton)
    okButton.padding(.bottom(16), .trailing(16))
    
    createWebView()
    contentView?.addSubview(webView)
    webView.padding(.horizontal(16))
      .spacing(to: segControl, .top(12))
      .spacing(to: okButton, .bottom(16))
    
    generateAboutPage(plugin: plugin)
  }
  
  private func createWebView() {
    let config = WKWebViewConfiguration()
    config.userContentController.addUserScript(
      WKUserScript(source: IINABridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))

    config.userContentController.addUserScript(
      WKUserScript(source: PreferenceSyncScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

    config.userContentController.addUserScript(WKUserScript(source: """
    const styleSheet = document.createElement("style");
    styleSheet.innerHTML = `\(WebViewCSS)`;
    document.head.appendChild(styleSheet);
    """, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

    config.userContentController.add(self, name: "iina")
    
    webView = WKWebView(frame: .zero, configuration: config)
    if #available(macOS 13.3, *) {
      webView.isInspectable = true
    }
    webView.navigationDelegate = self
    webView.translatesAutoresizingMaskIntoConstraints = false
    webView.setValue(false, forKey: "drawsBackground")
  }

  private func generateAboutPage(plugin: JavascriptPlugin) {
    var body = """
    <div class="small secondary">Identifier</div>
    <div class="pd">\(plugin.identifier)</div> 
    <div class="small secondary">Author</div>
    <div class="pd">\(plugin.authorName)</div> 
    """
    if let url = plugin.authorURL, !url.isEmpty {
      body += """
      <div class="small secondary>Website</div>
      <div class="pd">\(url)</div> 
      """
    }
    webView.loadHTMLString(generateHTML(body: body), baseURL: nil)
  }
  
  private func generateHelpPage(plugin: JavascriptPlugin) {
    
  }
  
  private func generateHTML(body: String) -> String {
    return """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Help</title>
    </head>
    <body>
    \(body)
    </body>
    </html>
    """
  }

  @objc func dismissSheet() {
    window.endSheet(self)
  }
}

extension PluginDetailsWindow: WKScriptMessageHandler, WKNavigationDelegate {
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    // Since all tabs share the same webview, we don't want uncontrolled message from anywhere, e.g. the help page
    guard currentTab == .settings else { return }
    
    guard let dict = message.body as? [Any], dict.count == 2 else { return }
    guard let name = dict[0] as? String else { return }
    guard let data = dict[1] as? [Any], let prefName = data[0] as? String else { return }
    
    if name == "set" {
      plugin.preferences[prefName] = data[1]
    } else if name == "get" {
      var value: Any? = nil
      if let v = plugin.preferences[prefName] {
        value = v
      } else if let v = plugin.defaultPreferences[prefName] {
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
      webView.evaluateJavaScript("window.iina._call(\(data[1]), \(result))")
    } else if name == "error" {
      Logger.log("JS:\(plugin.name) Preference page \(data[0]) \(data[2]),\(data[3]): \(data[4])")
    } else if name == "log" {
      Logger.log("JS:\(plugin.name) Preference page: \(data[0])")
    }
  }
}


fileprivate let IINABridgeScript = """
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
"""


fileprivate let PreferenceSyncScript = """
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
"""


/// The CSS for About/Preference view.
/// The Help view can be a cusotm webpage so we don't want to apply additional CSS.
fileprivate let WebViewCSS = """
* {
  box-sizing: border-box;
}

html {
  margin: 0;
  padding: 0;
}

body {
  padding: 16px;
  margin: 0;
  font-size: 13px;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Helvetica Neue", sans-serif;
}

p {
  margin: 0;
}

small, .small {
  font-size: 11px;
}

.secondary {
  color: rgba(0, 0, 0, 0.5);
}

.pref-section, .pd {
  margin-bottom: 12px;
}

.pref-help {
  margin-top: 2px;
}

@media (prefers-color-scheme: dark) {
  body {
    color-scheme: dark;
    color: #fff;
  }

  .secondary {
    color: rgba(255, 255, 255, .5);
  }
}

"""
