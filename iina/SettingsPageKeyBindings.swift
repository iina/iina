//
//  SettingsKeyBindings.swift
//  iina
//
//  Created by Hechen Li on 2026-02-01.
//  Copyright © 2026 lhc. All rights reserved.
//

class SettingsPageKeyBindings: SettingsPage {
  override var identifier: String {
    "key.bindings"
  }
  
  override var title: String {
    return NSLocalizedString("preference.keybindings", comment: "Key Bindings")
  }

  override var image: NSImage {
    return .sf("keyboard", withConfiguration: symbolConfiguration)!
  }

  override var localizationTable: String {
    "SettingsKeyBindingLocalizable"
  }

  private lazy var configEditor: ConfigEditor = .init(l10n: localizationContext)

  override func content() -> [SettingsSection] {
    return sections {
      sectionMediaControl()
      sectionConfiguration()
    }
  }

  private func sectionMediaControl() -> SettingsSection {
    return section {
      SettingsList {
        SettingsItem.Switch()
          .bindTo(.useMediaKeys)
          .image(name: ["playpause.circle", "playpause"])
          .withHelpLink(AppData.wikiLink.appending("/Manage-Key-Bindings"))
      }
    }
  }

  private func sectionConfiguration() -> SettingsSection {
    return section {
      SettingsList {
        SettingsItem.General(title: .text_KeyBindingSet)
          .image(name: ["book.and.wrench", "wrench.adjustable", "wrench"])
          .withValueView(configEditor.chooserView)
        SettingsItem.Custom()
          .view(configEditor.editorView)
        SettingsItem.Switch()
          .bindTo(.displayKeyBindingRawValues)
      }
    }
  }
}


private extension NSUserInterfaceItemIdentifier {
  static let columnID = NSUserInterfaceItemIdentifier("MainColumn")
}


fileprivate class ConfigEditor: SettingsAccessory.Base {
  fileprivate typealias KC = PrefKeyBindingViewController

  private let prefObserver = Preference.Observer()
  let chooserView: NSView
  let editorView: NSView

  let kbTableView: NSTableView
  let searchField: NSSearchField

  let chooserPopupButton: NSPopUpButton
  let addConfBtn: NSButton
  let delConfBtn: NSButton
  let addKeyMappingBtn: NSButton

  var mappingController: NSArrayController

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
      let files = try FileManager.default.contentsOfDirectory(at: Utility.userInputConfDirURL, includingPropertiesForKeys: nil)
      let configFiles = files.filter { $0.pathExtension == "conf" }
      return Dictionary(uniqueKeysWithValues: configFiles.map { ($0.deletingPathExtension().lastPathComponent, $0.path) })
    } catch {
      Logger.fatal("Cannot get user config file!")
    }
  }

  var configNames: [String] {
    return KC.defaultConfigMap.map { $0.key } + Array(KC.userConfigs.keys).sorted()
  }

  let configNameValidator: Utility.InputValidator<String> = { input in
    if input.isEmpty {
      return .valueIsEmpty
    }
    if KC.userConfigs[input] != nil || KC.defaultConfigs[input] != nil {
      return .valueAlreadyExists
    }
    return .ok
  }

  var currentConfName: String!
  var currentConfFilePath: String!

  // This variable is to prevent `NSTableView.reloadData()` in the `loadConfigFile` to trigger `loadConfigFile` again thus forming an infinite loop
  var isLoadingConfig = false

  override init(l10n: SettingsLocalization.Context) {
    self.mappingController = NSArrayController()
    self.kbTableView = NSTableView()
    self.searchField = NSSearchField()
    searchField.translatesAutoresizingMaskIntoConstraints = false

    self.chooserPopupButton = NSPopUpButton()
    chooserPopupButton.translatesAutoresizingMaskIntoConstraints = false
    chooserPopupButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)

    self.chooserView = NSView()
    chooserView.translatesAutoresizingMaskIntoConstraints = false
    self.editorView = NSView()
    editorView.translatesAutoresizingMaskIntoConstraints = false

    self.addConfBtn = NSButton()
    self.delConfBtn = NSButton()
    addConfBtn.bezelStyle = .push
    delConfBtn.bezelStyle = .push

    self.addKeyMappingBtn = NSButton()

    super.init(l10n: l10n)

    kbTableView.bind(.content, to: mappingController, withKeyPath: "arrangedObjects", options: nil)
    kbTableView.bind(.selectionIndexes, to: mappingController, withKeyPath: "selectionIndexes", options: nil)
    kbTableView.delegate = self
    kbTableView.headerView = nil
    kbTableView.target = self

    let column = NSTableColumn(identifier: .columnID)
    column.title = "Items"
    kbTableView.addTableColumn(column)

    addConfBtn.translatesAutoresizingMaskIntoConstraints = false
    addConfBtn.image = .init(systemSymbolName: "square.grid.3x1.folder.badge.plus", accessibilityDescription: "Add Configuration")
    addConfBtn.target = self
    addConfBtn.action = #selector(addConfBtnAction)
    delConfBtn.translatesAutoresizingMaskIntoConstraints = false
    delConfBtn.image = .init(systemSymbolName: "trash", accessibilityDescription: "Delete Configuration")
    delConfBtn.target = self
    delConfBtn.action = #selector(deleteConfFileAction)

    let chooserStackView = ui.hStack(chooserPopupButton, delConfBtn, addConfBtn)
    chooserView.addSubview(chooserStackView)
    chooserStackView.padding(.all(8))

    addKeyMappingBtn.translatesAutoresizingMaskIntoConstraints = false
    addKeyMappingBtn.imagePosition = .imageOnly
    addKeyMappingBtn.bezelStyle = .circular
    addKeyMappingBtn.image = .sf("plus")
    addKeyMappingBtn.target = self
    addKeyMappingBtn.action = #selector(addKeyMappingAction)
    addKeyMappingBtn.size(width: 26, height: 26)

    let headerViewContainer = NSView()
    headerViewContainer.translatesAutoresizingMaskIntoConstraints = false
    headerViewContainer.size(height: 32)
    let headerView = ui.hStack(searchField, addKeyMappingBtn)
    headerViewContainer.addSubview(headerView)
    headerView.padding(.top(8), .leading(16), .trailing(16))

    let editorStackView = ui.vStack(align: .leading, spacing: 0, headerViewContainer, kbTableView)

    searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
    searchField.bind(
      .predicate, to: mappingController, withKeyPath: "filterPredicate",
      options: [
        .predicateFormat: "(readableAction contains[cd] $value) OR (prettyCommand contains[cd] $value)",
      ]
    )

    editorView.addSubview(editorStackView)
    editorStackView.padding(.leading(16), .trailing, .vertical)

    NotificationCenter.default.addObserver(forName: .iinaKeyBindingChanged, object: nil, queue: .main, using: saveToConfFile)

    prefObserver.add(.displayKeyBindingRawValues) { [unowned self] _ in
      kbTableView.reloadData()
    }
    loadConfigFile(Preference.string(for: .currentInputConfigName), true)
  }

  /// This function firstly reloads the table data, select the config file row, then load the config file.
  /// If the target config file cannot be found, or the file cannot be parsed correctly, it will fallback to the default config.
  /// - Parameter configName: the target config name
  private func loadConfigFile(_ configName: String?, _ initialSetup: Bool = false) {
    guard configName != Preference.string(for: .currentInputConfigName) || initialSetup else { return }
    isLoadingConfig = true

    func fallback() {
      isLoadingConfig = false
      DispatchQueue.main.async {
        Utility.showAlert("keybinding_config.error", arguments: [configName ?? "Unknown"], sheetWindow: self.view.window)
      }
      loadConfigFile(fallbackDefault)
    }

    guard let configName = configName,
          let confFilePath = getFilePath(forConfig: configName, showAlert: false) else { fallback(); return }

    populateChooser(select: configName)
    currentConfName = configName
    currentConfFilePath = confFilePath

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

  private func populateChooser(select currentConfName: String? = nil) {
    guard let menu = chooserPopupButton.menu else { return }

    menu.removeAllItems()
    for name in configNames {
      let isDefaultConfig = KC.defaultConfigs[name] != nil
      menu.addItem(withTitle: name, image: isDefaultConfig ? ["lock"] : nil,
                   action: #selector(configSelected), target: self, obj: name)
    }

    if let currentConfName = currentConfName {
      chooserPopupButton.selectItem(withTitle: currentConfName)
    }
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

  @objc private func configSelected() {
    guard !isLoadingConfig else { return }
    guard let item = chooserPopupButton.selectedItem, item.title != currentConfName else { return }
    loadConfigFile(item.title)
    changeButtonEnabledStatus()
  }

  @objc private func addConfBtnAction() {
    let menu = NSMenu()
    if #available(macOS 14.0, *) {
      menu.addItem(.sectionHeader(title: l10n.localized(.text_NewKeyBindingSet)))
    } else {
      menu.addItem(withTitle: l10n.localized(.text_NewKeyBindingSet))
      menu.addItem(.separator())
    }
    menu.addItem(withTitle: l10n.localized(.text_CreateAnEmptySet),
                 action: #selector(newConfFileAction), target: self)
    menu.addItem(withTitle: l10n.localized(.text_DuplicateCurrentSet),
                 action: #selector(duplicateConfFileAction), target: self)
    menu.addItem(withTitle: l10n.localized(.text_ImportAnExistingConfigFile),
                 action: #selector(importConfigAction), target: self)
    menu.addItem(.separator())
    menu.addItem(withTitle: l10n.localized(.text_ShowTheConfigFileIn),
                 action: #selector(showConfFileAction), target: self)
    NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent!, for: addConfBtn)
  }

  @objc func newConfFileAction(_ sender: AnyObject) {
    Utility.quickPromptPanel("config.new", validator: configNameValidator, sheetWindow: addConfBtn.window) { newName in
      guard let newFilePath = self.newConfigFilePath(forName: newName) else { return }

      if !FileManager.default.createFile(atPath: newFilePath, contents: nil, attributes: nil) {
        Utility.showAlert("config.cannot_create", sheetWindow: self.addConfBtn.window)
        return
      }
      self.loadConfigFile(newName)
    }
  }

  @objc func duplicateConfFileAction(_ sender: AnyObject) {
    Utility.quickPromptPanel("config.duplicate", validator: configNameValidator, sheetWindow: addConfBtn.window) { newName in
      guard let newFilePath = self.newConfigFilePath(forName: newName) else { return }

      do {
        try FileManager.default.copyItem(atPath: self.currentConfFilePath!, toPath: newFilePath)
      } catch let error {
        Utility.showAlert("config.cannot_create", arguments: [error.localizedDescription], sheetWindow: self.view.window)
        return
      }
      self.loadConfigFile(newName)
    }
  }

  @objc func importConfigAction(_ sender: Any) {
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

  @objc func showConfFileAction(_ sender: AnyObject) {
    let url = URL(fileURLWithPath: currentConfFilePath)
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  @objc func deleteConfFileAction(_ sender: AnyObject) {
    guard isCurrentConfigEditable() else { return }
    Task { @MainActor in
      guard await Dialogs.ask("delete_keybindingset").show(in: kbTableView.window!) else { return }
      do {
        try FileManager.default.removeItem(atPath: currentConfFilePath)
      } catch {
        await Dialogs.alert("error_deleting_file").show(in: view.window!)
      }
      // Fallback to default
      loadConfigFile(fallbackDefault)
    }
  }

  @objc func addKeyMappingAction(_ sender: AnyObject) {
    Task { @MainActor in
      guard isCurrentConfigEditable() else {
        await Dialogs.alert("duplicate_config").show(in: kbTableView.window!)
        return
      }
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
  }

  @objc func removeKeyMappingAction(_ sender: ButtonWithObject) {
    guard let km = sender.object else { return }
    mappingController.remove(km)
    NotificationCenter.default.post(Notification(name: .iinaKeyBindingChanged))
  }

  @objc func editKeyMappingAction(_ sender: ButtonWithObject) {
    Task { @MainActor in
      guard isCurrentConfigEditable() else {
        await Dialogs.alert("duplicate_config").show(in: kbTableView.window!)
        return
      }
      guard let km = sender.object else { return }
      showKeyBindingPanel(key: km.rawKey, action: km.readableAction) { key, action in
        guard !key.isEmpty && !action.isEmpty else { return }
        km.rawKey = key
        km.rawAction = action
        self.kbTableView.reloadData()
        NotificationCenter.default.post(Notification(name: .iinaKeyBindingChanged))
      }
    }
  }

  @objc func showHelpForLockedSetAction(_ sender: ButtonWithObject) {
    Task {
      await Dialogs.alert("duplicate_config").show(in: kbTableView.window!)
    }
  }

  private func showKeyBindingPanel(key: String = "", action: String = "", ok: @escaping (String, String) -> Void) {
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
    panel.beginSheetModal(for: kbTableView.window!) { respond in
      if respond == .alertFirstButtonReturn {
        let rawKey = KeyCodeHelper.escapeReservedMpvKeys(keyRecordViewController.keyCode)
        ok(rawKey, keyRecordViewController.action)
      }
    }
  }

  private func changeButtonEnabledStatus() {
    let shouldEnableEdit = isCurrentConfigEditable()
    delConfBtn.isEnabled = shouldEnableEdit
    addKeyMappingBtn.image = shouldEnableEdit ? .sf("plus") : .customLockBadgeQuestionmark
  }

  /// Check whether or not a new config file with provided filename should be created.
  /// - Parameter filename: the filename of the new config file
  /// - Returns: the path of the new config if could be created; nil otherwise.
  private func newConfigFilePath(forName filename: String) -> String? {
    // Check if there exists a config file with the same filename
    let filePath = Utility.userInputConfDirURL.appendingPathComponent(filename + ".conf").path
    if FileManager.default.fileExists(atPath: filePath) {
      Utility.quickAskPanel("config.file_existing", sheetWindow: self.view.window) { result in
        if result == .alertFirstButtonReturn {
          NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: filePath)])
        }
      }
      return nil
    }
    return filePath
  }

  func isCurrentConfigEditable() -> Bool {
    return KC.defaultConfigs[currentConfName] == nil
  }

  private func setKeybindingsForPlayerCore() {
    PlayerCore.setKeyBindings(mappingController.arrangedObjects as! [KeyMapping])
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
}

extension ConfigEditor: NSTableViewDelegate, NSMenuDelegate {
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let km = (mappingController.arrangedObjects as? [KeyMapping])?[at: row] else { return nil }
    let cell = (tableView.makeView(withIdentifier: .columnID, owner: self) as? KeyMappingCell) ?? KeyMappingCell()

    cell.setup(keyMapping: km, self)
    return cell
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    return RowView()
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    return 32
  }
}


fileprivate class KeyMappingCell: NSTableCellView {
  var keyLabel: NSTextField!
  var actionLabel: NSTextField!
  var editButton: ButtonWithObject!
  var removeButton: ButtonWithObject!
  var lockHelpButton: ButtonWithObject!
  weak var editor: ConfigEditor!

  func setup(keyMapping km: KeyMapping, _ editor: ConfigEditor) {
    self.editor = editor

    if keyLabel == nil || actionLabel == nil {
      self.identifier = .columnID

      let actionLabel = NSTextField(labelWithString: "")
      actionLabel.translatesAutoresizingMaskIntoConstraints = false

      let spacer = NSView()
      spacer.translatesAutoresizingMaskIntoConstraints = false
      spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

      func createActionButton(symbol: String, action: Selector) -> ButtonWithObject {
        let image = NSImage.sf(symbol)!
        let button = ButtonWithObject(
          title: "", image: image, target: editor, action: action)
        button.bezelStyle = .circular
        button.size(width: 20, height: 20)
        button.isHidden = true
        return button
      }

      self.editButton = createActionButton(
        symbol: "gearshape.fill", action: #selector(editor.editKeyMappingAction))
      self.removeButton = createActionButton(
        symbol: "trash.fill", action: #selector(editor.removeKeyMappingAction))
      self.lockHelpButton = createActionButton(
        symbol: "custom.lock.badge.questionmark", action: #selector(editor.showHelpForLockedSetAction))

      let keyBox = NSBox()
      keyBox.translatesAutoresizingMaskIntoConstraints = false
      keyBox.titlePosition = .noTitle
      keyBox.boxType = .custom
      keyBox.borderWidth = 1
      keyBox.borderColor = .separatorColor
      keyBox.fillColor = .controlBackgroundColor
      keyBox.cornerRadius = 4
      keyBox.contentViewMargins = .zero
      let keyLabel = NSTextField(labelWithAttributedString: NSAttributedString(string: ""))
      keyLabel.translatesAutoresizingMaskIntoConstraints = false
      keyBox.contentView?.addSubview(keyLabel)
      keyBox.size(height: 28)
      keyLabel.padding(.horizontal(4)).center(.y, with: keyBox.contentView)

      self.keyLabel = keyLabel
      self.actionLabel = actionLabel

      let stackView = NSStackView(views: [actionLabel, spacer, lockHelpButton, removeButton, editButton, keyBox])
      stackView.translatesAutoresizingMaskIntoConstraints = false
      stackView.orientation = .horizontal
      stackView.alignment = .centerY

      self.addSubview(stackView)
      stackView.padding(.vertical, .horizontal(4))
    }

    editButton.isHidden = true
    removeButton.isHidden = true
    lockHelpButton.isHidden = true

    if Preference.bool(for: .displayKeyBindingRawValues) {
      keyLabel.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
      actionLabel.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    } else {
      keyLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
      actionLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    keyLabel.attributedStringValue = km.attributedKeyForDisplay
    actionLabel.stringValue = km.actionForDisplay
    removeButton.object = km
    editButton.object = km
  }

  func selectionChanged(_ selected: Bool) {
    if editor.isCurrentConfigEditable() {
      editButton.isHidden = !selected
      removeButton.isHidden = !selected
      lockHelpButton.isHidden = true
    } else {
      lockHelpButton.isHidden = !selected
    }
  }
}


fileprivate class ButtonWithObject : NSButton {
  weak var object: KeyMapping?
}


class RowView: NSTableRowView {
  override var isSelected: Bool {
    didSet {
      // Push selection state to the cell view
      for subview in subviews {
        (subview as? KeyMappingCell)?.selectionChanged(isSelected)
      }
    }
  }
}
