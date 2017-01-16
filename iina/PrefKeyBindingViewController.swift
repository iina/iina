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

  override var nibName: String? {
    return "PrefKeyBindingViewController"
  }

  override var identifier: String? {
    get {
      return "keybinding"
    }
    set {
      super.identifier = newValue
    }
  }

  var toolbarItemImage: NSImage {
    return NSImage(named: "toolbar_key")!
  }

  var toolbarItemLabel: String {
    return NSLocalizedString("preference.keybindings", comment: "Keybindings")
  }

  lazy var keyRecordViewController: KeyRecordViewController = KeyRecordViewController()

  static let defaultConfigs: [String: String] = [
    "IINA Default": Bundle.main.path(forResource: "iina-default-input", ofType: "conf", inDirectory: "config")!,
    "MPV Default": Bundle.main.path(forResource: "input", ofType: "conf", inDirectory: "config")!
  ]

  var userConfigs: [String: Any]!

  var currentMapping: [KeyMapping] = []
  var currentConfName: String!
  var currentConfFilePath: String!

  var shouldEnableEdit: Bool = true

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

    // config files
    // - default
    PrefKeyBindingViewController.defaultConfigs.forEach { (k, v) in
      configSelectPopUp.addItem(withTitle: k)
    }
    // - user
    guard let uc = UserDefaults.standard.dictionary(forKey: Preference.Key.inputConfigs)
    else  {
      Utility.fatal("Cannot get config file list!")
      return
    }
    userConfigs = uc
    userConfigs.forEach { (k, v) in
      configSelectPopUp.addItem(withTitle: k)
    }

    var currentConf = ""
    var gotCurrentConf = false
    if let confFromUd = UserDefaults.standard.string(forKey: Preference.Key.currentInputConfigName) {
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

  @IBAction func configSelectAction(_ sender: AnyObject) {
    guard let title = configSelectPopUp.selectedItem?.title else { return }
    currentConfName = title
    currentConfFilePath = getFilePath(forConfig: title)!
    loadConfigFile()
    changeButtonEnabled()
  }

  @IBAction func addKeyMappingBtnAction(_ sender: AnyObject) {
    let panel = NSAlert()
    panel.messageText = "Add Key Mapping"
    panel.informativeText = "Press any key to start."
    panel.accessoryView = keyRecordViewController.view
    panel.window.initialFirstResponder = keyRecordViewController.keyRecordView
    panel.addButton(withTitle: "OK")
    panel.addButton(withTitle: "Cancel")
    let response = panel.runModal()
    if response == NSAlertFirstButtonReturn {
      let key = keyRecordViewController.keyCode
      let action = keyRecordViewController.action
      guard !key.isEmpty && !action.isEmpty else { return }
      let splitted = action.characters.split(separator: " ").map { String($0) }
      currentMapping.append(KeyMapping(key: key, action: splitted))
      kbTableView.reloadData()
      kbTableView.scrollRowToVisible(currentMapping.count - 1)
    }
    saveToConfFile()
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
    let result = Utility.quickPromptPanel(messageText: "New Input Configuration", informativeText: "Please enter a name for the new configuration.") { newName = $0 }
    if !result { return }
    guard !newName.isEmpty else {
      Utility.showAlert(message: "The name cannot br empty.")
      return
    }
    guard userConfigs[newName] == nil && PrefKeyBindingViewController.defaultConfigs[newName] == nil else {
      Utility.showAlert(message: "The name already exists.")
      return
    }
    // new file
    let newFileName = newName + ".conf"
    let newFilePath = Utility.userInputConfDirURL.appendingPathComponent(newFileName).path
    let fm = FileManager.default
    // - if exists
    if fm.fileExists(atPath: newFilePath) {
      if Utility.quickAskPanel(title: "Config file already exists", infoText: "It should not happen. Choose OK to overwrite, Cancel to reveal the file in finder.") {
        // - delete file
        do {
          try fm.removeItem(atPath: newFilePath)
        } catch {
          Utility.showAlert(message: "Cannot delete the file.")
          return
        }
      } else {
        NSWorkspace.shared().activateFileViewerSelecting([URL(fileURLWithPath: newFilePath)])
        return
      }
    }
    // - new file
    if !fm.createFile(atPath: newFilePath, contents: nil, attributes: nil) {
      Utility.showAlert(message: "Cannot create config file.")
      return
    }
    // save
    userConfigs[newName] = newFilePath
    UserDefaults.standard.set(userConfigs, forKey: Preference.Key.inputConfigs)
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
    let result = Utility.quickPromptPanel(messageText: "New Input Configuration", informativeText: "Please enter a name for the duplicated configuration.") { newName = $0 }
    if !result { return }
    if userConfigs[newName] != nil || PrefKeyBindingViewController.defaultConfigs[newName] != nil {
      Utility.showAlert(message: "The name already exists.")
      return
    }
    // copy
    let currFilePath = currentConfFilePath!
    let newFileName = newName + ".conf"
    let newFilePath = Utility.userInputConfDirURL.appendingPathComponent(newFileName).path
    let fm = FileManager.default
    // - if exists
    if fm.fileExists(atPath: newFilePath) {
      if Utility.quickAskPanel(title: "Config file already exists", infoText: "It should not happen. Choose OK to overwrite, Cancel to reveal the file in finder.") {
        // - delete file
        do {
          try fm.removeItem(atPath: newFilePath)
        } catch {
          Utility.showAlert(message: "Cannot delete the file.")
          return
        }
      } else {
        NSWorkspace.shared().activateFileViewerSelecting([URL(fileURLWithPath: newFilePath)])
        return
      }
    }
    // - copy file
    do {
      try fm.copyItem(atPath: currFilePath, toPath: newFilePath)
    } catch {
      Utility.showAlert(message: "Cannot create config file.")
      return
    }
    // save
    userConfigs[newName] = newFilePath
    UserDefaults.standard.set(userConfigs, forKey: Preference.Key.inputConfigs)
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
    NSWorkspace.shared().activateFileViewerSelecting([url])
  }

  @IBAction func deleteConfFileAction(_ sender: AnyObject) {
    do {
      try FileManager.default.removeItem(atPath: currentConfFilePath)
    } catch {
      Utility.showAlert(message: "Cannot delete config file!")
      return
    }
    userConfigs.removeValue(forKey: currentConfName)
    UserDefaults.standard.set(userConfigs, forKey: Preference.Key.inputConfigs)
    // load
    configSelectPopUp.removeItem(withTitle: currentConfName)
    currentConfName = configSelectPopUp.itemTitles[0]
    currentConfFilePath = getFilePath(forConfig: currentConfName)
    loadConfigFile()
    changeButtonEnabled()
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
    do {
      try KeyMapping.generateConfData(from: currentMapping).write(toFile: currentConfFilePath, atomically: true, encoding: .utf8)
    } catch {
      Utility.showAlert(message: "Cannot write to config file!")
    }
  }


  // MARK: - Private

  private func loadConfigFile() {
    let reader = StreamReader(path: currentConfFilePath)
    currentMapping = []
    while var line: String = reader?.nextLine() {      // ignore empty lines
      if line.isEmpty { continue }
      // igore comment
      if line.hasPrefix("#") { continue }
      // remove inline comment
      if let sharpIndex = line.characters.index(of: "#") {
        line = line.substring(to: sharpIndex)
      }
      // split
      let splitted = line.characters.split(separator: " ", maxSplits: 1)
      let key = String(splitted[0])
      let action = splitted[1].split(separator: " ").map { seq in return String(seq) }

      currentMapping.append(KeyMapping(key: key, action: action, comment: nil))
    }
    UserDefaults.standard.set(currentConfName, forKey: Preference.Key.currentInputConfigName)
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
        Utility.showAlert(message: "Cannot find config file location!")
      }
      return nil
    }
  }

  private func isDefaultConfig(_ conf: String) -> Bool {
    return PrefKeyBindingViewController.defaultConfigs[conf] != nil
  }

}

extension PrefKeyBindingViewController: NSTableViewDelegate, NSTableViewDataSource {

  func numberOfRows(in tableView: NSTableView) -> Int {
    return currentMapping.count
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    guard let identifier = tableColumn?.identifier else { return nil }

    let mapping = currentMapping[row]
    if identifier == Constants.Identifier.key {
      return mapping.key
    } else if identifier == Constants.Identifier.action {
      return mapping.readableAction
    }
    return ""
  }

  func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
    guard let value = object as? String,
      let identifier = tableColumn?.identifier else { return }
    if identifier == Constants.Identifier.key {
      currentMapping[row].key = value
    } else if identifier == Constants.Identifier.action {
      currentMapping[row].action = value.characters.split(separator: " ").map { return String($0) }
    }
    saveToConfFile()
  }

}
