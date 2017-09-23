//
//  PrefKeyBindingViewController.swift
//  iina
//
//  Created by lhc on 12/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import MASPreferences

class PrefKeyBindingViewController: NSViewController, MASPreferencesViewController {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefKeyBindingViewController")
  }

  override var identifier: NSUserInterfaceItemIdentifier? {
    get {
      return NSUserInterfaceItemIdentifier("keybinding")
    }
    set {
      super.identifier = newValue
    }
  }

  var toolbarItemImage: NSImage? {
    return #imageLiteral(resourceName: "toolbar_key")
  }

  var toolbarItemLabel: String? {
    view.layoutSubtreeIfNeeded()
    return NSLocalizedString("preference.keybindings", comment: "Keybindings")
  }

  var hasResizableWidth: Bool = false

  static let defaultConfigs: [String: String] = [
    "IINA Default": Bundle.main.path(forResource: "iina-default-input", ofType: "conf", inDirectory: "config")!,
    "MPV Default": Bundle.main.path(forResource: "input", ofType: "conf", inDirectory: "config")!,
    "VLC Default": Bundle.main.path(forResource: "vlc-default-input", ofType: "conf", inDirectory: "config")!
  ]

  var userConfigs: [String: Any]!

  var currentMapping: [KeyMapping] = []
  var currentConfName: String!
  var currentConfFilePath: String!

  var shouldEnableEdit: Bool = true
  var displayRawValues: Bool = false

  // MARK: - Outlets

  @IBOutlet weak var configSelectPopUp: NSPopUpButton!
  @IBOutlet weak var kbTableView: NSTableView!
  @IBOutlet weak var addKmBtn: NSButton!
  @IBOutlet weak var removeKmBtn: NSButton!
  @IBOutlet weak var revealConfFileBtn: NSButton!
  @IBOutlet weak var deleteConfFileBtn: NSButton!
  @IBOutlet weak var newConfigBtn: NSButton!
  @IBOutlet weak var duplicateConfigBtn: NSButton!



  override func viewDidLoad() {
    super.viewDidLoad()

    // tableview
    kbTableView.dataSource = self
    kbTableView.delegate = self
    kbTableView.doubleAction = #selector(editRow)

    // config files
    // - default
    PrefKeyBindingViewController.defaultConfigs.forEach {
      configSelectPopUp.addItem(withTitle: $0.key)
    }
    // - user
    guard let uc = Preference.dictionary(for: .inputConfigs)
    else  {
      Utility.fatal("Cannot get config file list!")
    }
    userConfigs = uc
    userConfigs.forEach {
      configSelectPopUp.addItem(withTitle: $0.key)
    }

    var currentConf = ""
    var gotCurrentConf = false
    if let confFromUd = Preference.string(for: .currentInputConfigName) {
      if getFilePath(forConfig: confFromUd, showAlert: false) != nil {
        currentConf = confFromUd
        gotCurrentConf = true
      }
    }
    if !gotCurrentConf {
      currentConf = configSelectPopUp.titleOfSelectedItem ?? configSelectPopUp.itemTitles.first ?? "IINA Default"
    }
    // load
    configSelectPopUp.selectItem(withTitle: currentConf)
    currentConfName = currentConf
    shouldEnableEdit = !isDefaultConfig(currentConf)
    changeButtonEnabled()
    guard let path = getFilePath(forConfig: currentConf) else { return }
    currentConfFilePath = path
    loadConfigFile()
  }

  // MARK: - IBActions

  func showKeyBindingPanel(key: String = "", action: String = "", ok: (String, String) -> Void) {
    let panel = NSAlert()
    let keyRecordViewController = KeyRecordViewController()
    keyRecordViewController.keyCode = key
    keyRecordViewController.action = action
    panel.messageText = NSLocalizedString("keymapping.title", comment: "Key Mapping")
    panel.informativeText = NSLocalizedString("keymapping.message", comment: "Press any key to record.")
    panel.accessoryView = keyRecordViewController.view
    panel.window.initialFirstResponder = keyRecordViewController.keyRecordView
    panel.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
    panel.addButton(withTitle: NSLocalizedString("general.cancel", comment: "Cancel"))
    if panel.runModal() == .alertFirstButtonReturn {
      ok(keyRecordViewController.keyCode, keyRecordViewController.action)
    }
  }

  @IBAction func configSelectAction(_ sender: AnyObject) {
    guard let title = configSelectPopUp.selectedItem?.title else { return }
    currentConfName = title
    currentConfFilePath = getFilePath(forConfig: title)!
    loadConfigFile()
    changeButtonEnabled()
  }

  @IBAction func addKeyMappingBtnAction(_ sender: AnyObject) {
    showKeyBindingPanel { key, action in
      guard !key.isEmpty && !action.isEmpty else { return }
      if action.hasPrefix("@iina") {
        let trimmedAction = action[action.index(action.startIndex, offsetBy: "@iina".characters.count)...].trimmingCharacters(in: .whitespaces)
        currentMapping.append(KeyMapping(key: key,
                                         rawAction: trimmedAction,
                                         isIINACommand: true))
      } else {
        currentMapping.append(KeyMapping(key: key, rawAction: action))
      }

      kbTableView.reloadData()
      kbTableView.scrollRowToVisible(currentMapping.count - 1)
      saveToConfFile()
    }
  }

  @IBAction func removeKeyMappingBtnAction(_ sender: AnyObject) {
    if kbTableView.selectedRow >= 0 {
      currentMapping.remove(at: kbTableView.selectedRow)
      kbTableView.reloadData()
    }
    saveToConfFile()
  }

  // FIXME: may combine with duplicate action?
  @IBAction func newConfFileAction(_ sender: AnyObject) {
    // prompt
    var newName = ""
    let result = Utility.quickPromptPanel("config.new") { newName = $0 }
    if !result { return }
    guard !newName.isEmpty else {
      Utility.showAlert("config.empty_name")
      return
    }
    guard userConfigs[newName] == nil && PrefKeyBindingViewController.defaultConfigs[newName] == nil else {
      Utility.showAlert("config.name_existing")
      return
    }
    // new file
    let newFileName = newName + ".conf"
    let newFilePath = Utility.userInputConfDirURL.appendingPathComponent(newFileName).path
    let fm = FileManager.default
    // - if exists
    if fm.fileExists(atPath: newFilePath) {
      if Utility.quickAskPanel("config.file_existing") {
        // - delete file
        do {
          try fm.removeItem(atPath: newFilePath)
        } catch {
          Utility.showAlert("error_deleting_file")
          return
        }
      } else {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: newFilePath)])
        return
      }
    }
    // - new file
    if !fm.createFile(atPath: newFilePath, contents: nil, attributes: nil) {
      Utility.showAlert("config.cannot_create")
      return
    }
    // save
    userConfigs[newName] = newFilePath
    Preference.set(userConfigs, for: .inputConfigs)
    // load
    currentConfName = newName
    currentConfFilePath = newFilePath
    configSelectPopUp.addItem(withTitle: newName)
    configSelectPopUp.selectItem(withTitle: newName)
    loadConfigFile()
    changeButtonEnabled()
  }


  @IBAction func duplicateConfFileAction(_ sender: AnyObject) {
    // prompt
    var newName = ""
    let result = Utility.quickPromptPanel("config.duplicate") { newName = $0 }
    if !result { return }
    if userConfigs[newName] != nil || PrefKeyBindingViewController.defaultConfigs[newName] != nil {
      Utility.showAlert("config.name_existing")
      return
    }
    // copy
    let currFilePath = currentConfFilePath!
    let newFileName = newName + ".conf"
    let newFilePath = Utility.userInputConfDirURL.appendingPathComponent(newFileName).path
    let fm = FileManager.default
    // - if exists
    if fm.fileExists(atPath: newFilePath) {
      if Utility.quickAskPanel("config.file_existing") {
        // - delete file
        do {
          try fm.removeItem(atPath: newFilePath)
        } catch {
          Utility.showAlert("error_deleting_file")
          return
        }
      } else {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: newFilePath)])
        return
      }
    }
    // - copy file
    do {
      try fm.copyItem(atPath: currFilePath, toPath: newFilePath)
    } catch {
      Utility.showAlert("config.cannot_create")
      return
    }
    // save
    userConfigs[newName] = newFilePath
    Preference.set(userConfigs, for: .inputConfigs)
    // load
    currentConfName = newName
    currentConfFilePath = newFilePath
    configSelectPopUp.addItem(withTitle: newName)
    configSelectPopUp.selectItem(withTitle: newName)
    loadConfigFile()
    changeButtonEnabled()
  }

  @IBAction func revealConfFileAction(_ sender: AnyObject) {
    let url = URL(fileURLWithPath: currentConfFilePath)
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  @IBAction func deleteConfFileAction(_ sender: AnyObject) {
    do {
      try FileManager.default.removeItem(atPath: currentConfFilePath)
    } catch {
      Utility.showAlert("error_deleting_file")
    }
    userConfigs.removeValue(forKey: currentConfName)
    Preference.set(userConfigs, for: Preference.Key.inputConfigs)
    // load
    configSelectPopUp.removeItem(withTitle: currentConfName)
    currentConfName = configSelectPopUp.itemTitles[0]
    currentConfFilePath = getFilePath(forConfig: currentConfName)
    loadConfigFile()
    changeButtonEnabled()
  }

  @IBAction func displayRawValueAction(_ sender: NSButton) {
    displayRawValues = sender.state == .on
    kbTableView.doubleAction = displayRawValues ? nil : #selector(editRow)
    kbTableView.reloadData()
  }

  @IBAction func openKeyBindingsHelpAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.wikiLink.appending("/Manage-Key-Bindings"))!)
  }

  // MARK: - UI

  private func changeButtonEnabled() {
    shouldEnableEdit = !isDefaultConfig(currentConfName)
    [revealConfFileBtn, deleteConfFileBtn, addKmBtn, removeKmBtn].forEach { btn in
      btn.isEnabled = shouldEnableEdit
    }
    kbTableView.tableColumns.forEach { $0.isEditable = shouldEnableEdit }
  }

  func saveToConfFile() {
    setKeybindingsForPlayerCore()
    do {
      try KeyMapping.generateConfData(from: currentMapping).write(toFile: currentConfFilePath, atomically: true, encoding: .utf8)
    } catch {
      Utility.showAlert("config.cannot_write")
    }
  }


  // MARK: - Private

  private func loadConfigFile() {
    if let mapping = KeyMapping.parseInputConf(at: currentConfFilePath) {
      currentMapping = mapping
    } else {
      // on error
      Utility.showAlert("keybinding_config.error", arguments: [currentConfName])
      let title = "IINA Default"
      currentConfName = title
      currentConfFilePath = getFilePath(forConfig: title)!
      configSelectPopUp.selectItem(withTitle: title)
      loadConfigFile()
      changeButtonEnabled()
      return
    }
    Preference.set(currentConfName, for: .currentInputConfigName)
    setKeybindingsForPlayerCore()
    kbTableView.reloadData()
  }

  private func getFilePath(forConfig conf: String, showAlert: Bool = true) -> String? {
    // if is default config
    if let dv = PrefKeyBindingViewController.defaultConfigs[conf] {
      return dv
    } else if let uv = userConfigs[conf] as? String {
      return uv
    } else {
      if showAlert {
        Utility.showAlert("error_finding_file", arguments: ["config"])
      }
      return nil
    }
  }

  private func isDefaultConfig(_ conf: String) -> Bool {
    return PrefKeyBindingViewController.defaultConfigs[conf] != nil
  }

  private func setKeybindingsForPlayerCore() {
    var result: [String: KeyMapping] = [:]
    currentMapping.forEach { result[$0.key] = $0 }
    PlayerCore.keyBindings = result
  }

}

// MARK: -

extension PrefKeyBindingViewController: NSTableViewDelegate, NSTableViewDataSource {

  func numberOfRows(in tableView: NSTableView) -> Int {
    return currentMapping.count
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    guard let identifier = tableColumn?.identifier else { return nil }

    guard let mapping = currentMapping.at(row) else { return nil }
    if identifier == Constants.Identifier.key {
      return displayRawValues ? mapping.key : mapping.prettyKey
    } else if identifier == Constants.Identifier.action {
      return displayRawValues ? mapping.readableAction : mapping.prettyCommand
    }
    return ""
  }

  func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
    guard let value = object as? String,
      let identifier = tableColumn?.identifier else { return }
    if identifier == Constants.Identifier.key {
      currentMapping[row].key = value
    } else if identifier == Constants.Identifier.action {
      currentMapping[row].rawAction = value
    }
    saveToConfFile()
  }

  func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
    return displayRawValues
  }

  @objc func editRow() {
    guard shouldEnableEdit else { return }
    let selectedData = currentMapping[kbTableView.selectedRow]
    showKeyBindingPanel(key: selectedData.key, action: selectedData.readableAction) { key, action in
      guard !key.isEmpty && !action.isEmpty else { return }
      selectedData.key = key
      selectedData.rawAction = action
      kbTableView.reloadData()
      saveToConfFile()
    }
  }

}
