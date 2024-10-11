//
//  PrefKeyBindingViewController.swift
//  iina
//
//  Created by lhc on 12/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate let fm = FileManager.default
fileprivate typealias KC = PrefKeyBindingViewController

@objcMembers
class PrefKeyBindingViewController: PreferenceViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefKeyBindingViewController")
  }

  var preferenceTabTitle: String {
    return NSLocalizedString("preference.keybindings", comment: "Keybindings")
  }

  var preferenceTabImage: NSImage {
    return makeSymbol("keyboard.badge.ellipsis", fallbackImage: "pref_kb")
  }

  var preferenceContentIsScrollable: Bool {
    return false
  }

  static let defaultConfigMap: KeyValuePairs<String, String> = [
    "IINA Default": "iina-default-input",
    "mpv Default": "input",
    "VLC Default": "vlc-default-input",
    "Movist Default": "movist-default-input",
    "Movist v2 Default": "movist-v2-default-input",
  ]

  let fallbackDefault = "IINA Default"

  static var defaultConfigs: [String: String] = {
    var configs: [String: String] = [:]
    for (key, value) in defaultConfigMap {
      configs[key] = Bundle.main.path(forResource: value, ofType: "conf", inDirectory: "config")!
    }
    return configs
  }()

  static var userConfigs: [String: String] {
    do {
      let files = try fm.contentsOfDirectory(at: Utility.userInputConfDirURL, includingPropertiesForKeys: nil)
      let configFiles = files.filter { $0.pathExtension == "conf" }
      return Dictionary(uniqueKeysWithValues: configFiles.map { ($0.deletingPathExtension().lastPathComponent, $0.path) })
    } catch {
      Logger.fatal("Cannot get user config file!")
    }
  }

  private var cachedConfigNames: [String]!

  var configNames: [String] {
    return KC.defaultConfigMap.map { $0.key } + Array(KC.userConfigs.keys).sorted()
  }

  var currentConfName: String!
  var currentConfFilePath: String!
  
  // This variable is to prevent `NSTableView.reloadData()` in the `loadConfigFile` to trigger `loadConfigFile` again thus forming an infinite loop
  var isLoadingConfig = false

  var shouldEnableEdit: Bool = true

  // MARK: - Outlets

  @IBOutlet weak var confTableView: NSTableView!
  @IBOutlet weak var kbTableView: NSTableView!
  @IBOutlet weak var configHintLabel: NSTextField!
  @IBOutlet weak var addKmBtn: NSButton!
  @IBOutlet weak var removeKmBtn: NSButton!
  @IBOutlet weak var showConfFileBtn: NSButton!
  @IBOutlet weak var deleteConfFileBtn: NSButton!
  @IBOutlet weak var newConfigBtn: NSButton!
  @IBOutlet weak var duplicateConfigBtn: NSButton!
  @IBOutlet weak var useMediaKeysButton: NSButton!
  @IBOutlet weak var keyMappingSearchField: NSSearchField!
  @IBOutlet var mappingController: NSArrayController!

  override func viewDidLoad() {
    super.viewDidLoad()

    cachedConfigNames = configNames

    kbTableView.delegate = self
    kbTableView.doubleAction = Preference.bool(for: .displayKeyBindingRawValues) ? nil : #selector(editRow)
    confTableView.dataSource = self
    confTableView.delegate = self

    removeKmBtn.isEnabled = false

    useMediaKeysButton.title = NSLocalizedString("preference.system_media_control", comment: "Use system media control")

    // Load the config file saved in user default
    loadConfigFile(Preference.string(for: .currentInputConfigName), true)

    NotificationCenter.default.addObserver(forName: .iinaKeyBindingChanged, object: nil, queue: .main, using: saveToConfFile)
  }

  // MARK: - IBActions

  func showKeyBindingPanel(key: String = "", action: String = "", ok: @escaping (String, String) -> Void) {
    let panel = NSAlert()
    let keyRecordViewController = KeyRecordViewController()
    keyRecordViewController.keyCode = key
    keyRecordViewController.action = action
    panel.messageText = NSLocalizedString("keymapping.title", comment: "Key Mapping")
    panel.informativeText = NSLocalizedString("keymapping.message", comment: "Press any key to record.")
    panel.accessoryView = keyRecordViewController.view
    panel.window.initialFirstResponder = keyRecordViewController.keyRecordView
    let okButton = panel.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
    okButton.cell!.bind(.enabled, to: keyRecordViewController, withKeyPath: "ready", options: nil)
    panel.addButton(withTitle: NSLocalizedString("general.cancel", comment: "Cancel"))
    panel.beginSheetModal(for: view.window!) { respond in
      if respond == .alertFirstButtonReturn {
        let rawKey = KeyCodeHelper.escapeReservedMpvKeys(keyRecordViewController.keyCode)
        ok(rawKey, keyRecordViewController.action)
      }
    }
  }

  @IBAction func addKeyMappingBtnAction(_ sender: AnyObject) {
    showKeyBindingPanel { key, action in
      guard !key.isEmpty && !action.isEmpty else { return }
      if action.hasPrefix("@iina") {
        let trimmedAction = action[action.index(action.startIndex, offsetBy: "@iina".count)...].trimmingCharacters(in: .whitespaces)
        self.mappingController.addObject(KeyMapping(rawKey: key,
                                        rawAction: trimmedAction,
                                        isIINACommand: true))
      } else {
        self.mappingController.addObject(KeyMapping(rawKey: key, rawAction: action))
      }

      self.kbTableView.scrollRowToVisible((self.mappingController.arrangedObjects as! [AnyObject]).count - 1)
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingChanged))
    }
  }

  @IBAction func removeKeyMappingBtnAction(_ sender: AnyObject) {
    mappingController.remove(sender)
    NotificationCenter.default.post(Notification(name: .iinaKeyBindingChanged))
  }

  @IBAction func newConfFileAction(_ sender: AnyObject) {
    Utility.quickPromptPanel("config.new", sheetWindow: view.window) { newName in
      guard let newFilePath = self.newConfigFilePath(forName: newName) else { return }

      if !fm.createFile(atPath: newFilePath, contents: nil, attributes: nil) {
        Utility.showAlert("config.cannot_create", sheetWindow: self.view.window)
        return
      }
      self.loadConfigFile(newName)
    }
  }

  @IBAction func duplicateConfFileAction(_ sender: AnyObject) {
    Utility.quickPromptPanel("config.duplicate", sheetWindow: view.window) { newName in
      guard let newFilePath = self.newConfigFilePath(forName: newName) else { return }

      do {
        try fm.copyItem(atPath: self.currentConfFilePath!, toPath: newFilePath)
      } catch let error {
        Utility.showAlert("config.cannot_create", arguments: [error.localizedDescription], sheetWindow: self.view.window)
        return
      }
      self.loadConfigFile(newName)
    }
    
  }
  
  @IBAction func configFileListDoubleAction(_ sender: NSTableView) {
    guard shouldEnableEdit else { return }
    Utility.quickPromptPanel("config.rename", sheetWindow: view.window) { newName in
      guard let newFilePath = self.newConfigFilePath(forName: newName) else { return }

      do {
        try fm.moveItem(atPath: self.currentConfFilePath!, toPath: newFilePath)
      } catch let error {
        Utility.showAlert("config.cannot_create", arguments: [error.localizedDescription], sheetWindow: self.view.window)
        return
      }
      self.loadConfigFile(newName)
    }
  }

  @IBAction func showConfFileAction(_ sender: AnyObject) {
    let url = URL(fileURLWithPath: currentConfFilePath)
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  @IBAction func deleteConfFileAction(_ sender: AnyObject) {
    do {
      try FileManager.default.removeItem(atPath: currentConfFilePath)
    } catch {
      Utility.showAlert("error_deleting_file", sheetWindow: view.window)
    }
    // Fallback to default
    loadConfigFile(fallbackDefault)
  }

  @IBAction func importConfigBtnAction(_ sender: Any) {
    Utility.quickOpenPanel(title: "Select Config File to Import", chooseDir: false, sheetWindow: view.window, allowedFileTypes: ["conf"]) { url in
      guard url.isFileURL, url.lastPathComponent.hasSuffix(".conf") else { return }
      let newFilePath = Utility.userInputConfDirURL.appendingPathComponent(url.lastPathComponent).path
      let newName = url.deletingPathExtension().lastPathComponent
      // copy file
      do {
        try FileManager.default.copyItem(atPath: url.path, toPath: newFilePath)
      } catch let error {
        Utility.showAlert("config.cannot_create", arguments: [error.localizedDescription], sheetWindow: self.view.window)
        return
      }
      self.loadConfigFile(newName)
    }
  }

  @IBAction func displayRawValueAction(_ sender: NSButton) {
    kbTableView.doubleAction = Preference.bool(for: .displayKeyBindingRawValues) ? nil : #selector(editRow)
    kbTableView.reloadData()
  }

  @IBAction func openKeyBindingsHelpAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.wikiLink.appending("/Manage-Key-Bindings"))!)
  }

  // MARK: - UI

  private func changeButtonEnabledStatus() {
    shouldEnableEdit = !isDefaultConfig(currentConfName)
    [showConfFileBtn, deleteConfFileBtn, addKmBtn].forEach { btn in
      btn.isEnabled = shouldEnableEdit
    }
    kbTableView.tableColumns.forEach { $0.isEditable = shouldEnableEdit }
    configHintLabel.stringValue = NSLocalizedString("preference.key_binding_hint_\(shouldEnableEdit ? "2" : "1")", comment: "preference.key_binding_hint")
  }

  func saveToConfFile(_ sender: Notification) {
    let predicate = mappingController.filterPredicate
    mappingController.filterPredicate = nil
    let keyMappings = mappingController.arrangedObjects as! [KeyMapping]
    for mapping in keyMappings {
      mapping.rawKey = KeyCodeHelper.escapeReservedMpvKeys(mapping.rawKey)
    }
    setKeybindingsForPlayerCore()
    mappingController.filterPredicate = predicate
    do {
      try KeyMapping.generateInputConf(from: keyMappings).write(toFile: currentConfFilePath, atomically: true, encoding: .utf8)
    } catch {
      Utility.showAlert("config.cannot_write", sheetWindow: view.window)
    }
  }


  // MARK: - Private

  /// This function firstly reloads the table data, select the config file row, then load the config file.
  /// If the target config file cannot be found, or the file cannot be parsed correctly, it will fallback to the default config.
  /// - Parameter configName: the target config name
  private func loadConfigFile(_ configName: String?, _ initialSetup: Bool = false) {
    guard configName != Preference.string(for: .currentInputConfigName) || initialSetup else { return }
    isLoadingConfig = true
    
    func fallback() {
      isLoadingConfig = false
      Utility.showAlert("keybinding_config.error", arguments: [currentConfName], sheetWindow: view.window)
      loadConfigFile(fallbackDefault)
    }

    guard let configName = configName else { fallback(); return }
    
    cachedConfigNames = configNames
    confTableView.reloadData()
    if let index = cachedConfigNames.firstIndex(of: configName) {
      confTableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }
    currentConfName = configName
    currentConfFilePath = getFilePath(forConfig: configName)!
    
    guard let mapping = KeyMapping.parseInputConf(at: currentConfFilePath) else { fallback(); return }

    mappingController.content = nil
    mappingController.add(contentsOf: mapping)
    mappingController.setSelectionIndexes(IndexSet())

    changeButtonEnabledStatus()

    if !initialSetup {
      Preference.set(currentConfName, for: .currentInputConfigName)
      setKeybindingsForPlayerCore()
    }

    isLoadingConfig = false
  }

  /// Check whether or not a new config file with provided filename should be created.
  /// - Parameter filename: the filename of the new config file
  /// - Returns: the path of the new config if could be created; nil otherwise.
  private func newConfigFilePath(forName filename: String) -> String? {
    // Check if the name is empty
    guard !filename.isEmpty else {
      Utility.showAlert("config.empty_name", sheetWindow: self.view.window)
      return nil
    }

    // Check if there already exists a config which has the same name
    guard KC.userConfigs[filename] == nil && KC.defaultConfigs[filename] == nil else {
      Utility.showAlert("config.name_existing", sheetWindow: self.view.window)
      return nil
    }

    // Check if there exists a config file with the same filename
    let filePath = Utility.userInputConfDirURL.appendingPathComponent(filename + ".conf").path
    if fm.fileExists(atPath: filePath) {
      Utility.quickAskPanel("config.file_existing", sheetWindow: self.view.window) { result in
        if result == .alertFirstButtonReturn {
          NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: filePath)])
        }
      }
      return nil
    }
    return filePath
  }

  private func getFilePath(forConfig conf: String, showAlert: Bool = true) -> String? {
    let path = KC.defaultConfigs[conf] ?? KC.userConfigs[conf]
    if path == nil {
      if showAlert {
        Utility.showAlert("error_finding_file", arguments: ["config"], sheetWindow: view.window)
      }
    }
    return path
  }

  private func isDefaultConfig(_ conf: String) -> Bool {
    return KC.defaultConfigs[conf] != nil
  }

  private func setKeybindingsForPlayerCore() {
    PlayerCore.setKeyBindings(mappingController.arrangedObjects as! [KeyMapping])
  }

}

// MARK: - NSTableViewDelegate, NSTableViewDataSource

extension PrefKeyBindingViewController: NSTableViewDelegate, NSTableViewDataSource {

  // NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    return cachedConfigNames.count
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    let name = cachedConfigNames[row]
    return [
      "name": name,
      "isHidden": !isDefaultConfig(name)
    ] as [String: Any]
  }

  // NSTableViewDelegate

  func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
    if tableView == kbTableView {
      return Preference.bool(for: .displayKeyBindingRawValues)
    } else {
      return false
    }
  }

  @objc func editRow() {
    guard shouldEnableEdit else {
      Utility.showAlert("duplicate_config", sheetWindow: view.window)
      return
    }
    guard kbTableView.selectedRow != -1 else { return }
    let selectedData = mappingController.selectedObjects[0] as! KeyMapping
    showKeyBindingPanel(key: selectedData.rawKey, action: selectedData.readableAction) { key, action in
      guard !key.isEmpty && !action.isEmpty else { return }
      selectedData.rawKey = key
      selectedData.rawAction = action
      self.kbTableView.reloadData()
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingChanged))
    }
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !isLoadingConfig else { return }
    if let tableView = notification.object as? NSTableView, tableView == confTableView {
      guard let title = cachedConfigNames[at: confTableView.selectedRow], title != currentConfName else { return }
      loadConfigFile(title)
    }
    removeKmBtn.isEnabled = shouldEnableEdit && kbTableView.selectedRow != -1
  }

}
