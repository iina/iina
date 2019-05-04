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

  static let defaultConfigs: [String: String] = [
    "IINA Default": Bundle.main.path(forResource: "iina-default-input", ofType: "conf", inDirectory: "config")!,
    "mpv Default": Bundle.main.path(forResource: "input", ofType: "conf", inDirectory: "config")!,
    "VLC Default": Bundle.main.path(forResource: "vlc-default-input", ofType: "conf", inDirectory: "config")!,
    "Movist Default": Bundle.main.path(forResource: "movist-default-input", ofType: "conf", inDirectory: "config")!
  ]

  var userConfigs: [String: Any]!
  var userConfigNames: [String] = []

  var currentConfName: String!
  var currentConfFilePath: String!

  var shouldEnableEdit: Bool = true

  // MARK: - Outlets

  @IBOutlet weak var confTableView: NSTableView!
  @IBOutlet weak var kbTableView: NSTableView!
  @IBOutlet weak var configHintLabel: NSTextField!
  @IBOutlet weak var addKmBtn: NSButton!
  @IBOutlet weak var removeKmBtn: NSButton!
  @IBOutlet weak var revealConfFileBtn: NSButton!
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
    // - default
    PrefKeyBindingViewController.defaultConfigs.forEach {
      userConfigNames.append($0.key)
    }
    // - user
    guard let uc = Preference.dictionary(for: .inputConfigs)
    else  {
      Logger.fatal("Cannot get config file list!")
    }
    userConfigs = uc
    userConfigs.forEach {
      userConfigNames.append($0.key)
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
      currentConf = "IINA Default"
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
    if let index = userConfigNames.index(of: title) {
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
    panel.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
    panel.addButton(withTitle: NSLocalizedString("general.cancel", comment: "Cancel"))
    panel.beginSheetModal(for: view.window!) { respond in
      if respond == .alertFirstButtonReturn {
        ok(keyRecordViewController.keyCode, keyRecordViewController.action)
      }
    }
  }

  @IBAction func addKeyMappingBtnAction(_ sender: AnyObject) {
    showKeyBindingPanel { key, action in
      guard !key.isEmpty && !action.isEmpty else { return }
      if action.hasPrefix("@iina") {
        let trimmedAction = action[action.index(action.startIndex, offsetBy: "@iina".count)...].trimmingCharacters(in: .whitespaces)
        self.mappingController.addObject(KeyMapping(key: key,
                                        rawAction: trimmedAction,
                                        isIINACommand: true))
      } else {
        self.mappingController.addObject(KeyMapping(key: key, rawAction: action))
      }

      self.kbTableView.scrollRowToVisible((self.mappingController.arrangedObjects as! [AnyObject]).count - 1)
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingChanged))
    }
  }

  @IBAction func removeKeyMappingBtnAction(_ sender: AnyObject) {
    mappingController.remove(sender)
    NotificationCenter.default.post(Notification(name: .iinaKeyBindingChanged))
  }

  // FIXME: may combine with duplicate action?
  @IBAction func newConfFileAction(_ sender: AnyObject) {
    // prompt
    Utility.quickPromptPanel("config.new", sheetWindow: view.window) { newName in
      guard !newName.isEmpty else {
        Utility.showAlert("config.empty_name", sheetWindow: self.view.window)
        return
      }
      guard self.userConfigs[newName] == nil && PrefKeyBindingViewController.defaultConfigs[newName] == nil else {
        Utility.showAlert("config.name_existing", sheetWindow: self.view.window)
        return
      }
      // new file
      let newFileName = newName + ".conf"
      let newFilePath = Utility.userInputConfDirURL.appendingPathComponent(newFileName).path
      let fm = FileManager.default
      // - if exists
      if fm.fileExists(atPath: newFilePath) {
        if Utility.quickAskPanel("config.file_existing", sheetWindow: self.view.window) {
          // - delete file
          do {
            try fm.removeItem(atPath: newFilePath)
          } catch {
            Utility.showAlert("error_deleting_file", sheetWindow: self.view.window)
            return
          }
        } else {
          NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: newFilePath)])
          return
        }
      }
      // - new file
      if !fm.createFile(atPath: newFilePath, contents: nil, attributes: nil) {
        Utility.showAlert("config.cannot_create", sheetWindow: self.view.window)
        return
      }
      // save
      self.userConfigs[newName] = newFilePath
      Preference.set(self.userConfigs, for: .inputConfigs)
      // load
      self.currentConfName = newName
      self.currentConfFilePath = newFilePath
      self.userConfigNames.append(newName)
      self.confTableView.reloadData()
      self.confTableSelectRow(withTitle: newName)
      self.loadConfigFile()
    }
  }


  @IBAction func duplicateConfFileAction(_ sender: AnyObject) {
    // prompt
    Utility.quickPromptPanel("config.duplicate", sheetWindow: view.window) { newName in
      if self.userConfigs[newName] != nil || PrefKeyBindingViewController.defaultConfigs[newName] != nil {
        Utility.showAlert("config.name_existing", sheetWindow: self.view.window)
        return
      }
      // copy
      let currFilePath = self.currentConfFilePath!
      let newFileName = newName + ".conf"
      let newFilePath = Utility.userInputConfDirURL.appendingPathComponent(newFileName).path
      let fm = FileManager.default
      // - if exists
      if fm.fileExists(atPath: newFilePath) {
        if Utility.quickAskPanel("config.file_existing", sheetWindow: self.view.window) {
          // - delete file
          do {
            try fm.removeItem(atPath: newFilePath)
          } catch {
            Utility.showAlert("error_deleting_file", sheetWindow: self.view.window)
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
      } catch let error {
        Utility.showAlert("config.cannot_create", arguments: [error.localizedDescription], sheetWindow: self.view.window)
        return
      }
      // save
      self.userConfigs[newName] = newFilePath
      Preference.set(self.userConfigs, for: .inputConfigs)
      // load
      self.currentConfName = newName
      self.currentConfFilePath = newFilePath
      self.userConfigNames.append(newName)
      self.confTableView.reloadData()
      self.confTableSelectRow(withTitle: newName)
      self.loadConfigFile()
    }
  }

  @IBAction func revealConfFileAction(_ sender: AnyObject) {
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
    if let index = userConfigNames.index(of: currentConfName) {
      userConfigNames.remove(at: index)
    }
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
      // save
      self.userConfigs[newName] = newFilePath
      Preference.set(self.userConfigs, for: .inputConfigs)
      // load
      self.currentConfName = newName
      self.currentConfFilePath = newFilePath
      self.userConfigNames.append(newName)
      self.confTableView.reloadData()
      self.confTableSelectRow(withTitle: newName)
      self.loadConfigFile()
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
    [revealConfFileBtn, deleteConfFileBtn, addKmBtn].forEach { btn in
      btn.isEnabled = shouldEnableEdit
    }
    kbTableView.tableColumns.forEach { $0.isEditable = shouldEnableEdit }
    configHintLabel.stringValue = NSLocalizedString("preference.key_binding_hint_\(shouldEnableEdit ? "2" : "1")", comment: "preference.key_binding_hint")
  }

  func saveToConfFile(_ sender: Notification) {
    let predicate = mappingController.filterPredicate
    mappingController.filterPredicate = nil
    let keyMapping = mappingController.arrangedObjects as! [KeyMapping]
    setKeybindingsForPlayerCore()
    mappingController.filterPredicate = predicate
    do {
      try KeyMapping.generateConfData(from: keyMapping).write(toFile: currentConfFilePath, atomically: true, encoding: .utf8)
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

  private func tellUserToDuplicateConfig() {
    Utility.showAlert("duplicate_config", sheetWindow: view.window)
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
    ]
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
      tellUserToDuplicateConfig()
      return
    }
    guard kbTableView.selectedRow != -1 else { return }
    let selectedData = mappingController.selectedObjects[0] as! KeyMapping
    showKeyBindingPanel(key: selectedData.key, action: selectedData.readableAction) { key, action in
      guard !key.isEmpty && !action.isEmpty else { return }
      selectedData.key = key
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
