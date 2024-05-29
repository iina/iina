//
//  PrefKeyBindingViewController.swift
//  iina
//
//  Created by lhc on 12/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

@objcMembers
class PrefKeyBindingViewController: NSViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefKeyBindingViewController")
  }

  var preferenceTabTitle: String {
    return NSLocalizedString("preference.keybindings", comment: "Keybindings")
  }

  var preferenceTabImage: NSImage {
    return NSImage(named: NSImage.Name("pref_kb"))!
  }

  var preferenceContentIsScrollable: Bool {
    return false
  }

  static let defaultConfigMap: KeyValuePairs<String, String> = [
    "IINA Default": "iina-default-input",
    "mpv Default": "input",
    "VLC Default": "vlc-default-input",
    "Movist Default": "movist-default-input",
  ]

  static var defaultConfigs: [String: String] = {
    var configs: [String: String] = [:]
    for (key, value) in defaultConfigMap {
      configs[key] = Bundle.main.path(forResource: value, ofType: "conf", inDirectory: "config")!
    }
    return configs
  }()

  var userConfigs: [String: Any] = [:]
  var userConfigNames: [String] {
    return PrefKeyBindingViewController.defaultConfigMap.map { $0.key } + Array(userConfigs.keys).sorted()
  }

  var currentConfName: String!
  var currentConfFilePath: String!

  var shouldEnableEdit: Bool = true
  
  let fm = FileManager.default

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

    kbTableView.delegate = self
    kbTableView.doubleAction = Preference.bool(for: .displayKeyBindingRawValues) ? nil : #selector(editRow)
    confTableView.dataSource = self
    confTableView.delegate = self

    removeKmBtn.isEnabled = false

    if #available(macOS 10.13, *) {
      useMediaKeysButton.title = NSLocalizedString("preference.system_media_control", comment: "Use system media control")
    }

    // config files
    guard let uc = Preference.dictionary(for: .inputConfigs) else {
      Logger.fatal("Cannot get config file list!")
    }
    userConfigs = uc

    // Fallback default input config
    var currentConf = "IINA Default"
    if let confFromUd = Preference.string(for: .currentInputConfigName) {
      if getFilePath(forConfig: confFromUd, showAlert: false) != nil {
        currentConf = confFromUd
      }
    }
    // load
    confTableSelectRow(withTitle: currentConf)
    currentConfName = currentConf
    guard let path = getFilePath(forConfig: currentConf) else { return }
    currentConfFilePath = path
    loadConfigFile()
    
    NotificationCenter.default.addObserver(forName: .iinaKeyBindingChanged, object: nil, queue: .main, using: saveToConfFile)
  }

  private func confTableSelectRow(withTitle title: String) {
    if let index = userConfigNames.firstIndex(of: title) {
      confTableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }
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
  
  // Check whether or not a new config file with provided filename should be created.
  // Returns the path of the new config if could be created; nil otherwise
  private func checkNewConfigFile(with filename: String) -> String? {
    
    // Check if the name is empty
    guard !filename.isEmpty else {
      Utility.showAlert("config.empty_name", sheetWindow: self.view.window)
      return nil
    }
    
    // Check if there already exists a config which has the same name
    guard self.userConfigs[filename] == nil && PrefKeyBindingViewController.defaultConfigs[filename] == nil else {
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
  
  private func enableNewConfigFile(_ filename: String, _ filePath: String) {
    userConfigs[filename] = filePath
    Preference.set(self.userConfigs, for: .inputConfigs)
    
    currentConfName = filename
    currentConfFilePath = filePath
    confTableView.reloadData()
    confTableSelectRow(withTitle: filename)
    loadConfigFile()
  }

  @IBAction func newConfFileAction(_ sender: AnyObject) {
    Utility.quickPromptPanel("config.new", sheetWindow: view.window) { newName in
      guard let newFilePath = self.checkNewConfigFile(with: newName) else { return }

      if !self.fm.createFile(atPath: newFilePath, contents: nil, attributes: nil) {
        Utility.showAlert("config.cannot_create", sheetWindow: self.view.window)
        return
      }
      self.enableNewConfigFile(newName, newFilePath)
    }
  }


  @IBAction func duplicateConfFileAction(_ sender: AnyObject) {
    Utility.quickPromptPanel("config.duplicate", sheetWindow: view.window) { newName in
      guard let newFilePath = self.checkNewConfigFile(with: newName) else { return }

      do {
        try self.fm.copyItem(atPath: self.currentConfFilePath!, toPath: newFilePath)
      } catch let error {
        Utility.showAlert("config.cannot_create", arguments: [error.localizedDescription], sheetWindow: self.view.window)
        return
      }
      self.enableNewConfigFile(newName, newFilePath)
    }
    
  }
  
  @IBAction func configFileListDoubleAction(_ sender: NSTableView) {
    guard shouldEnableEdit else { return }
    Utility.quickPromptPanel("config.rename", sheetWindow: view.window) { newName in
      guard let newFilePath = self.checkNewConfigFile(with: newName) else { return }
      let oldName = self.currentConfName!
      do {
        try self.fm.moveItem(atPath: self.currentConfFilePath!, toPath: newFilePath)
      } catch let error {
        Utility.showAlert("config.cannot_create", arguments: [error.localizedDescription], sheetWindow: self.view.window)
        return
      }
      self.userConfigs.removeValue(forKey: oldName)
      self.enableNewConfigFile(newName, newFilePath)
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
    userConfigs.removeValue(forKey: currentConfName)
    Preference.set(userConfigs, for: Preference.Key.inputConfigs)
    // load
    confTableView.reloadData()
    currentConfName = userConfigNames[0]
    currentConfFilePath = getFilePath(forConfig: currentConfName)
    confTableSelectRow(withTitle: currentConfName)
    loadConfigFile()
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
      self.enableNewConfigFile(newName, newFilePath)
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

  private func loadConfigFile() {
    if let mapping = KeyMapping.parseInputConf(at: currentConfFilePath) {
      mappingController.content = nil
      mappingController.add(contentsOf: mapping)
      mappingController.setSelectionIndexes(IndexSet())
    } else {
      // on error
      Utility.showAlert("keybinding_config.error", arguments: [currentConfName], sheetWindow: view.window)
      let title = "IINA Default"
      currentConfName = title
      currentConfFilePath = getFilePath(forConfig: title)!
      confTableSelectRow(withTitle: title)
      loadConfigFile()
      return
    }
    Preference.set(currentConfName, for: .currentInputConfigName)
    setKeybindingsForPlayerCore()
    changeButtonEnabledStatus()
  }

  private func getFilePath(forConfig conf: String, showAlert: Bool = true) -> String? {
    // if is default config
    if let dv = PrefKeyBindingViewController.defaultConfigs[conf] {
      return dv
    } else if let uv = userConfigs[conf] as? String {
      return uv
    } else {
      if showAlert {
        Utility.showAlert("error_finding_file", arguments: ["config"], sheetWindow: view.window)
      }
      return nil
    }
  }

  private func isDefaultConfig(_ conf: String) -> Bool {
    return PrefKeyBindingViewController.defaultConfigs[conf] != nil
  }

  private func setKeybindingsForPlayerCore() {
    PlayerCore.setKeyBindings(mappingController.arrangedObjects as! [KeyMapping])
  }

}

// MARK: -

extension PrefKeyBindingViewController: NSTableViewDelegate, NSTableViewDataSource {

  // NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    return userConfigNames.count
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    let name = userConfigNames[row]
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
    if let tableView = notification.object as? NSTableView, tableView == confTableView {
      guard let title = userConfigNames[at: confTableView.selectedRow] else { return }
      currentConfName = title
      currentConfFilePath = getFilePath(forConfig: title)!
      loadConfigFile()
    }
    removeKmBtn.isEnabled = shouldEnableEdit && kbTableView.selectedRow != -1
  }

}
