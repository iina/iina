//
//  SettingsPagePlugin.swift
//  iina
//
//  Created by Hechen Li on 2026-02-02.
//  Copyright © 2026 lhc. All rights reserved.
//

import WebKit
import Just

class SettingsPagePlugin: SettingsPage {
  override var identifier: String {
    "plugin"
  }

  override var title: String {
    return NSLocalizedString("preference.plugins", comment: "Plugins")
  }

  override var image: NSImage {
    return .sf("puzzlepiece.extension", "gearshape.2", withConfiguration: symbolConfiguration)!
  }

  override var localizationTable: String {
    "SettingsPluginLocalizable"
  }

  override var sectionSpacing: CGFloat {
    8
  }

  fileprivate lazy var installView: PluginInstallView = .init(l10n: localizationContext, page: self)
  fileprivate lazy var listView: PluginListView = .init(l10n: localizationContext, page: self)
  fileprivate lazy var updateView: PluginUpdateView = .init(l10n: localizationContext, page: self)

  override func content() -> [SettingsSection] {
    return sections {
      sectionInstall()
      sectionPluginList()
    }
  }

  private func sectionInstall() -> SettingsSection {
    return section {
      SettingsList() {
        SettingsItem.Custom()
          .view(installView.view)
      }
    }
  }

  private func sectionPluginList() -> SettingsSection {
    return section {
      updateView
      SettingsList() {
        SettingsItem.Custom()
          .view(listView.view)
      }
    }
  }
}


fileprivate class PluginInstallView: SettingsAccessory.Base {
  unowned let page: SettingsPagePlugin
  private lazy var pluginManager: PluginManager = PluginManager(window: self.view.window!)

  init(l10n: SettingsLocalization.Context, page: SettingsPagePlugin) {
    self.page = page
    super.init(l10n: l10n)

    let githubBtn = ui.button(.text_GetPlugins)
    githubBtn.target = self
    githubBtn.action = #selector(installPluginFromGitHub)
    let localBtn = ui.button(.text_InstallLocalPackage)
    localBtn.target = self
    localBtn.action = #selector(installPluginFromLocalPackage)

    let btnStackView = ui.hStack(githubBtn, localBtn)

    let installLabel = ui.smallLabel(bindTo: .text_YouCanInstallANew).makeMultiLine()

    let stackView = ui.vStack(installLabel, btnStackView)
    stackView.alignment = .leading
    stackView.spacing = 12

    view.addSubview(stackView)
    stackView.padding(.all(12))
  }

  @IBAction func installPluginFromLocalPackage(_ sender: Any) {
    Utility.quickOpenPanel(title: "Install from local package",
                           chooseDir: false, sheetWindow: view.window, allowedFileTypes: ["iinaplgz"]) { url in
      Task {
        await self.pluginManager.install(localPackageURL: url)
        self.page.listView.tableView.reloadData()
      }
    }
  }

  @IBAction func installPluginFromGitHub(_ sender: Any) {
    if #available(macOS 12.0, *) {
      let panel = PluginStorePanel(l10n: l10n)
      panel.contentMaxSize = NSSize(width: 800, height: 600)
      view.window!.beginSheet(panel) { _ in
        self.page.listView.reload()
      }
    } else {
      Utility.quickPromptPanel("install_plugin_macos_11", sheetWindow: view.window!) { url in
        if url.isEmpty { return }
        Task { @MainActor in
          await self.pluginManager.install(gitHubString: url)
        }
      }
    }
  }
}


fileprivate class PluginUpdateView: SettingsContainer {
  lazy var itemID = SettingsContainerUUID.next()
  let view: NSView

  func getContainer() -> NSView {
    return view
  }

  enum Status {
    case refreshing
    case error
    case foundUpdate(UInt)
  }

  let checkUpdateLabel: NSTextField
  let checkUpdateButton: NSButton
  unowned let page: SettingsPagePlugin

  init(l10n: SettingsLocalization.Context, page: SettingsPagePlugin) {
    self.page = page
    self.view = .init(frame: .zero)
    self.checkUpdateLabel = NSTextField(labelWithString: "Checking for updates…")
    self.checkUpdateButton = NSButton()
    checkUpdateButton.translatesAutoresizingMaskIntoConstraints = false

    checkUpdateLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .bold)
    checkUpdateLabel.textColor = .secondaryLabelColor
    checkUpdateLabel.translatesAutoresizingMaskIntoConstraints = false

    checkUpdateButton.image = .sf("arrow.clockwise.circle")
    checkUpdateButton.imagePosition = .imageOnly
    checkUpdateButton.isBordered = false
    checkUpdateButton.size(width: 16, height: 16)
    checkUpdateButton.target = self
    checkUpdateButton.action = #selector(checkForUpdates)

    let checkUpdateStackView = NSStackView(views: [checkUpdateLabel, checkUpdateButton])
    checkUpdateStackView.translatesAutoresizingMaskIntoConstraints = false
    checkUpdateStackView.orientation = .horizontal

    view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(checkUpdateStackView)

    checkUpdateStackView.padding(.top(8), .bottom, .horizontal(16))
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func makeView(context: SettingsLocalization.Context) -> NSView {
    return view
  }

  @objc func checkForUpdates(_ sender: AnyObject) {
    page.listView.checkForAllPluginUpdates()
  }

  func update(_ status: Status) {
    switch status {
    case .error:
      checkUpdateLabel.stringValue = "Error checking for updates."
      checkUpdateButton.isHidden = false
    case .foundUpdate(let numOfUpdates):
      if numOfUpdates == 0 {
        checkUpdateLabel.stringValue = "All plugins are up to date."
      } else {
        checkUpdateLabel.stringValue = "Plugin updates available: \(numOfUpdates)"
      }
      checkUpdateButton.isHidden = false
    case .refreshing:
      checkUpdateLabel.stringValue = "Checking for updates…"
      checkUpdateButton.isHidden = true
    }
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
  // TODO: this is a workaround.
  // SettingsItem.Custom should also adopt the "build first, render later" design.
  class TableView: NSTableView {
    weak var listView: PluginListView!

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      listView.checkForAllPluginUpdates()
    }
  }

  static var currentPlugin: JavascriptPlugin?
  static var pluginHasUpdate: [String: Bool] = [:]
  static var isCheckingForUpdates: Bool = false

  let tableView: TableView
  unowned let page: SettingsPagePlugin

  init(l10n: SettingsLocalization.Context, page: SettingsPagePlugin) {
    self.tableView = TableView()
    self.page = page

    super.init(l10n: l10n)
    tableView.listView = self

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

  func reload() {
    tableView.reloadData()
  }

  func checkForAllPluginUpdates() {
    Task { @MainActor in
      let updateView = page.updateView
      do {
        guard PluginListView.isCheckingForUpdates == false else { return }
        PluginListView.isCheckingForUpdates = true
        updateView.update(.refreshing)
        defer {
          PluginListView.isCheckingForUpdates = false
        }

        var dict: [String: Bool] = [:]
        for plugin in JavascriptPlugin.plugins {
          let version = try await plugin.checkNewVersion()
          dict[plugin.identifier] = version != nil
        }
        PluginListView.pluginHasUpdate = dict

        let numOfUpdates = UInt(dict.values.filter{ $0 }.count)
        Logger.log("Finished checking for plugin updates, \(numOfUpdates) updates found")

        updateView.update(.foundUpdate(numOfUpdates))
        self.tableView.reloadData()
      } catch let error {
        Logger.log("Error checking for plugin updates: \(error)", level: .error)
        updateView.update(.error)
      }
    }
  }
}

extension PluginListView: NSTableViewDelegate, NSTableViewDataSource {
  private class ItemView: NSTableCellView {
    var nameLabel: NSTextField!
    var enabledSwitch: NSSwitch!
    var versionLabel: NSTextField!
    var updateBtn: NSButton!
    var devLabel: NSTextField!
    var descLabel: NSTextField!
    var aboutBtn: NSButton!
    var actionsBtn: NSButton!
    var progressIndicator: NSProgressIndicator!
    weak var plugin: JavascriptPlugin!

    private lazy var pluginManager: PluginManager = PluginManager(window: self.nameLabel.window!)
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
        enabledSwitch.target = self
        enabledSwitch.action = #selector(enabledSwitchAction)

        versionLabel = NSTextField(labelWithString: plugin.version)
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)

        updateBtn = NSButton()
        updateBtn.isBordered = false
        updateBtn.image = .sf("arrow.up.circle")
        updateBtn.contentTintColor = .systemOrange
        updateBtn.isHidden = !PluginListView.pluginHasUpdate[plugin.identifier, default: false]
        updateBtn.target = self
        updateBtn.action = #selector(updateBtnAction)

        devLabel = NSTextField(labelWithString: "DEV")
        devLabel.isHidden = !plugin.isExternal
        devLabel.textColor = .black
        devLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize * 0.8, weight: .bold)
        devLabel.drawsBackground = true
        devLabel.backgroundColor = .systemIndigo
        devLabel.wantsLayer = true
        devLabel.layer?.cornerRadius = 3

        let nameStackView = NSStackView()
        nameStackView.translatesAutoresizingMaskIntoConstraints = false
        nameStackView.orientation = .horizontal
        nameStackView.distribution = .fill

        self.progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.isHidden = true
        progressIndicator.controlSize = .mini

        self.actionsBtn = NSButton()
        actionsBtn.image = .sf("ellipsis")
        actionsBtn.isBordered = false
        actionsBtn.target = self
        actionsBtn.action = #selector(actionsBtnAction)
        actionsBtn.size(width: 16, height: 16)

        [enabledSwitch, nameLabel, progressIndicator, versionLabel, updateBtn, devLabel, actionsBtn].forEach {
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
        aboutBtn.image = .sf("info.circle")
        aboutBtn.imageScaling = .scaleProportionallyUpOrDown
        aboutBtn.isBordered = false
        aboutBtn.translatesAutoresizingMaskIntoConstraints = false
        aboutBtn.target = self
        aboutBtn.action = #selector(aboutBtnAction)

        self.addSubview(stackView)
        self.addSubview(aboutBtn)

        stackView.padding(.top(12), .bottom(4), .leading(8), .trailing(20))
        aboutBtn.padding(.trailing(8))
          .center(.y, with: self)
      } else {
        nameLabel.stringValue = plugin.name
        versionLabel.stringValue = plugin.version
        updateBtn.isHidden = !PluginListView.pluginHasUpdate[plugin.identifier, default: false]
        devLabel.isHidden = !plugin.isExternal
        enabledSwitch.state = plugin.enabled ? .on : .off
        descLabel.stringValue = plugin.desc ?? "No description"
        progressIndicator.isHidden = true
        progressIndicator.stopAnimation(nil)
      }
    }

    @objc func enabledSwitchAction(_ sender: NSSwitch) {
      plugin.enabled = sender.state == .on
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

    @objc func updateBtnAction(_ sender: NSButton) {
      self.versionLabel.stringValue = NSLocalizedString("plugin.updating", comment: "")
      self.updateBtn.isHidden = true
      self.progressIndicator.isHidden = false
      self.progressIndicator.startAnimation(nil)
      Task { @MainActor in
        let (res, newPlugin) = await self.pluginManager.update(self.plugin)

        if res == .noUpdate {
          PluginListView.pluginHasUpdate[plugin.identifier] = false
        } else if res == .installed, let newPlugin = newPlugin {
          self.plugin = newPlugin
          PluginListView.pluginHasUpdate[newPlugin.identifier] = false
        }
        // labels and buttons will be reset on reload
        reloadRow()
      }
    }

    private func reloadRow() {
      if let row = JavascriptPlugin.plugins.firstIndex(of: plugin) {
        self.listView.tableView.reloadData(forRowIndexes: IndexSet([row]), columnIndexes: IndexSet([0]))
      } else {
        Logger.log("New plugin not found in plugin list after update")
        self.listView.tableView.reloadData()
      }
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
  private unowned let l10n: SettingsLocalization.Context
  private unowned let plugin: JavascriptPlugin
  private let okButton: NSButton
  private var webView: WKWebView!
  private let segControl: NSSegmentedControl
  private let loadingIndicator: NSProgressIndicator
  private let loadingFailedView: NSTextField
  private var currentTab: Tab = .about

  unowned let window: NSWindow

  enum Tab: Int {
    case settings = 0, about, help
  }

  init(l10n: SettingsLocalization.Context, plugin: JavascriptPlugin, window: NSWindow) {
    self.l10n = l10n
    self.window = window
    self.plugin = plugin
    let style: NSWindow.StyleMask = [.titled, .resizable, .fullSizeContentView]

    self.okButton = NSButton(title: NSLocalizedString("general.done", comment: "Done"),
                             target: nil, action: nil)
    okButton.translatesAutoresizingMaskIntoConstraints = false

    self.loadingIndicator = NSProgressIndicator()
    loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

    self.segControl = NSSegmentedControl()
    segControl.translatesAutoresizingMaskIntoConstraints = false

    self.loadingFailedView = NSTextField(labelWithString: l10n.localized(.text_FailedToLoadThePage))
    loadingFailedView.translatesAutoresizingMaskIntoConstraints = false

    super.init(contentRect: NSRect(x: 0, y: 0, width: 600, height: 450),
               styleMask: style,
               backing: .buffered,
               defer: false)

    guard let contentView = contentView else {
      Logger.log("Content view is nil in plugin details window", level: .error)
      return
    }

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
    iconView.image = .sf("puzzlepiece.extension", "gearshape.2")
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.size(width: 24, height: 24)

    segControl.segmentCount = 3
    segControl.segmentStyle = .texturedSquare
    if #available(macOS 26.0, *) {
      segControl.controlSize = .extraLarge
    } else {
      segControl.size(width: 360)
    }
    segControl.target = self
    segControl.action = #selector(changeTab)

    let segments: [([String], SettingsLocalization.Key)] = [
      (["gearshape.circle", "gearshape.fill"], .text_Settings),
      (["info.circle"], .text_About),
      (["questionmark.circle"], .text_Help),
    ]
    for (i, seg) in segments.enumerated() {
      segControl.setImage(.sf(seg.0), forSegment: i)
      segControl.setLabel(l10n.localized(seg.1), forSegment: i)
    }

    contentView.addSubview(iconView)
    iconView.padding(.leading(16), .top(20))
    contentView.addSubview(nameLabel)
    nameLabel.padding(.top(16)).spacing(.leading(8), to: iconView)
    contentView.addSubview(versionLabel)
    versionLabel.spacing(.top(4), to: nameLabel).spacing(.leading(8), to: iconView)
    contentView.addSubview(segControl)
    segControl.padding(.top(16), .trailing(16))
    contentView.addSubview(okButton)
    okButton.padding(.bottom(16), .trailing(16))

    createWebView()
    contentView.addSubview(webView)
    webView.padding(.horizontal(16))
      .spacing(.top(12), to: segControl)
      .spacing(.bottom(16), to: okButton)

    loadingIndicator.style = .spinning
    loadingIndicator.isHidden = true
    contentView.addSubview(loadingIndicator)
    loadingIndicator.center(.x, with: contentView).padding(.top(80))

    loadingFailedView.textColor = .systemRed
    loadingFailedView.isHidden = true
    contentView.addSubview(loadingFailedView)
    loadingFailedView.center(.x, with: contentView).padding(.top(80))

    // select settings tab by default
    segControl.selectedSegment = 0
    changeTab(segControl)
  }

  @objc private func changeTab(_ sender: NSSegmentedControl) {
    guard sender.selectedSegment != currentTab.rawValue else { return }
    // save settings to disk on tab change; it's fast so no need to check current tab
    plugin.syncPreferences()

    currentTab = .init(rawValue: sender.selectedSegment)!

    switch segControl.selectedSegment {
    case 0: generateSettingsPage()
    case 1: generateAboutPage()
    case 2: generateHelpPage()
    default: return
    }
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

    self.webView = WKWebView(frame: .zero, configuration: config)
    if #available(macOS 13.3, *) {
      webView.isInspectable = true
    }
    webView.navigationDelegate = self
    webView.translatesAutoresizingMaskIntoConstraints = false
    webView.setValue(false, forKey: "drawsBackground")
  }

  private func generateSettingsPage() {
    guard let prefURL = plugin.preferencesPageURL else {
      webView.loadHTMLString(generateHTML(body: "This plugin does not have a settings page."), baseURL: nil)
      return
    }
    webView.loadFileURL(prefURL, allowingReadAccessTo: plugin.root)
  }

  private func generateAboutPage() {
    func entry(_ key: String, _ value: String) -> String {
      return """
      <div class="small secondary">\(key)</div>
      <div class="pd">\(value)</div>
      """
    }

    func a(_ url: String) -> String {
      return "<a href='\(url)'>\(url)</a></div>"
    }

    var body = entry(l10n.localized(.text_Identifier), plugin.identifier) +
    entry(l10n.localized(.text_Author), plugin.authorName)

    if let url = plugin.authorURL, !url.isEmpty {
      body += entry(l10n.localized(.text_Website), a(url))
    }
    if let url = plugin.githubURLString {
      body += entry(l10n.localized(.text_Source), a(url))
    } else {
      body += entry(l10n.localized(.text_Source), NSLocalizedString("plugin.local", comment: ""))
    }
    if let subProviders = plugin.subProviders {
      body += entry(
        "Registered Subtitle Providers",
        subProviders.map { $0["name"] ?? "?" }.joined(separator: "<br>")
      )
    }

    let permissions = plugin.localizedPermissions(newLine: "<br>")
    body += entry(
      "Permissions",
      permissions.isEmpty ? NSLocalizedString("quicksetting.item_none", comment: "") :
        permissions.map {
          "<div class='perm \($0.isDangerous ? "dangerous" : "")'><b>\($0.name)</b><br>\($0.desc)</div>"
        }.joined()
  )

    webView.loadHTMLString(generateHTML(body: body), baseURL: nil)
  }

  private func generateHelpPage() {
    if let helpURL = plugin.helpPageURL {
      if helpURL.isFileURL {
        webView.loadFileURL(helpURL, allowingReadAccessTo: plugin.root)
      } else {
        webView.load(URLRequest(url: helpURL))
      }
    } else {
      webView.loadHTMLString(generateHTML(body: "This plugin does not have a help page."), baseURL: nil)
    }
  }

  private func generateHTML(body: String) -> String {
    return """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>\(plugin.name)</title>
    </head>
    <body>\(body)</body>
    </html>
    """
  }

  @objc func dismissSheet() {
    plugin.syncPreferences()
    window.endSheet(self)
  }
}

extension PluginDetailsWindow: WKScriptMessageHandler, WKNavigationDelegate {
  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    // don't allow remote pages in settings or about tab
    if currentTab != .help {
      guard let url = navigationAction.request.url,
            url.absoluteString.starts(with: plugin.preferencesPageURL?.absoluteString ?? "000") || url.absoluteString == "about:blank"
      else {
        Logger.log("Loading page from \(navigationAction.request.url?.absoluteString ?? "?") is not allowed", level: .error)
        decisionHandler(.cancel)
        return
      }
    }
    decisionHandler(.allow)
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    webView.alphaValue = 0
    loadingFailedView.isHidden = true
    if let scheme = webView.url?.scheme, scheme.starts(with: "http") {
      loadingIndicator.isHidden = false
      loadingIndicator.startAnimation(self)
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    loadingIndicator.stopAnimation(self)
    loadingIndicator.isHidden = true
    webView.alphaValue = 1
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    failedLoadingWebViewPage()
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    failedLoadingWebViewPage()
  }

  private func failedLoadingWebViewPage() {
    loadingFailedView.isHidden = false
    loadingIndicator.stopAnimation(self)
    loadingIndicator.isHidden = true
  }

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
/// The Help view can be a custom webpage so we don't want to apply additional CSS.
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

.perm {
  font-size: 11px;
  padding: 8px;
  margin: 8px 0;
  color: rgba(0, 0, 0, 0.8);
  border: 1px solid rgba(0, 0, 0, 0.5);
  border-radius: 4px;
  background: rgba(0, 0, 0, 0.1);
}

.perm.dangerous {
  border: 1px solid rgba(200, 0, 0, 0.5);
  background: rgba(200, 0, 0, 0.1);
}

@media (prefers-color-scheme: dark) {
  body {
    color-scheme: dark;
    color: #fff;
  }

  .secondary {
    color: rgba(255, 255, 255, .5);
  }

  .perm {
    color: rgba(255, 255, 255, 0.8);
  }
}

"""
