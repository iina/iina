//
//  SettingsPageAdvanced.swift
//  iina
//
//  Created by Hechen Li on 2026-02-02.
//  Copyright © 2026 lhc. All rights reserved.
//

class SettingsPageAdvanced: SettingsPage {
  override var title: String {
    return NSLocalizedString("preference.advanced", comment: "Advanced")
  }
  
  override var image: NSImage {
    return makeSymbol("flask", fallbackImage: "pref_advanced")
  }
  
  override var localizationTable: String {
    "SettingsAdvancedLocalizable"
  }
  
  private lazy var fileChooseView: SettingsAccessory.FileChooserView = .init(.userDefinedConfDir)
  private lazy var mpvOptionsEditor: MPVOptionsEditor = .init(l10n: localizationContext)
  private lazy var openLogFolderBtn: NSButton = {
    let btn = NSButton()
    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.title = localizationContext.localized(.text_OpenLogDirectory)
    return btn
  }()

  override func content() -> NSView {
    return sections {
      sectionEnableAdvanced()
      sectionLogging()
      sectionMPV()
    }
  }
  
  private func sectionEnableAdvanced() -> [NSView] {
    return section {
      SettingsListView() {
        SettingsItem.Switch()
          .bindTo(.enableAdvancedSettings)
          .image(name: ["flask"])
          .hasDescription()
          .withHelpLink(AppData.wikiLink.appending("/MPV-Options-and-Properties"))
      }
    }
  }

  private func sectionLogging() -> [NSView] {
    return section {
      SettingsListView(title: .text_Logging) {
        SettingsItem.PopupButton()
          .bindTo(.logLevel, ofType: Logger.Level.self)
          .image(name: "cylinder.split.1x2")
          .hasDescription()
        SettingsItem.Switch()
          .bindTo(.enableLogging)
          .extraViews(openLogFolderBtn)
      }
    }
  }
  
  private func sectionMPV() -> [NSView] {
    return section {
      SettingsListView(title: .text_MPVSettings) {
        SettingsItem.Switch()
          .bindTo(.useMpvOsd)
          .image(name: "ellipsis.bubble")
      }
      SettingsListView {
        SettingsItem.Switch()
          .image(name: ["folder.badge.gearshape", "folder.badge.gear"])
          .bindTo(.useUserDefinedConfDir)
          .extraViews(fileChooseView.textField, fileChooseView.chooseButton)
      }
      SettingsListView {
        SettingsItem.General(title: .text_AdditionalMpvOptions)
          .image(name: ["document.badge.gearshape", "doc.badge.gearshape"])
          .extraViews(mpvOptionsEditor.delBtn, mpvOptionsEditor.addBtn)
        SettingsItem.Custom()
          .view(mpvOptionsEditor.view)
      }
    }
  }
}


fileprivate class MPVOptionsEditor: SettingsAccessory.Base, NSTableViewDelegate, NSTableViewDataSource {
  let tableView: NSTableView
  let addBtn: NSButton
  let delBtn: NSButton

  var options: [[String]] = []

  override init(l10n: SettingsLocalization.Context) {
    self.tableView = NSTableView()
    self.addBtn = NSButton()
    self.delBtn = NSButton()
    
    super.init(l10n: l10n)
    
    let monoFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    
    tableView.delegate = self
    tableView.dataSource = self
    let columnKey = NSTableColumn(identifier: .key)
    columnKey.title = "Key"
    (columnKey.dataCell as? NSCell)?.font = monoFont
    tableView.addTableColumn(columnKey)
    let columnValue = NSTableColumn(identifier: .value)
    columnValue.title = "Value"
    (columnValue.dataCell as? NSCell)?.font = monoFont
    tableView.addTableColumn(columnValue)

    let stackView = makeStackView([tableView], orientation: .vertical)
    view.addSubview(stackView)
    stackView.padding(.leading(SettingsSubListView.padding), .trailing(0), .bottom(0), .top(0))
    
    addBtn.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
    addBtn.target = self
    addBtn.action = #selector(addOptionAction)
    delBtn.image = NSImage(systemSymbolName: "minus", accessibilityDescription: nil)
    delBtn.target = self
    delBtn.action = #selector(removeOptionAction)

    guard let op = Preference.value(for: .userOptions) as? [[String]] else {
      Utility.showAlert("extra_option.cannot_read", sheetWindow: view.window)
      return
    }
    options = op
  }
  
  private func saveToUserDefaults() {
    Preference.set(options, for: .userOptions)
    UserDefaults.standard.synchronize()
  }
  
  @objc func addOptionAction(_ sender: AnyObject) {
    options.append(["name", "value"])
    tableView.reloadData()
    tableView.selectRowIndexes(IndexSet(integer: options.count - 1), byExtendingSelection: false)
    saveToUserDefaults()
  }

  @objc func removeOptionAction(_ sender: AnyObject) {
    if tableView.selectedRow >= 0 {
      options.remove(at: tableView.selectedRow)
      tableView.reloadData()
      saveToUserDefaults()
    }
  }

  func controlTextDidEndEditing(_ obj: Notification) {
    saveToUserDefaults()
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    return options.count
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    guard options.count > row else { return nil }
    if tableColumn?.identifier == .key {
      return options[row][0]
    } else if tableColumn?.identifier == .value {
      return options[row][1]
    }
    return nil
  }

  func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
    guard let value = object as? String,
      let identifier = tableColumn?.identifier else { return }
    guard !value.isEmpty else {
      Utility.showAlert("extra_option.empty", sheetWindow: view.window)
      return
    }
    guard options.count > row else { return }
    if identifier == .key {
      options[row][0] = value
    } else if identifier == .value {
      options[row][1] = value
    }
    saveToUserDefaults()
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    if tableView.selectedRowIndexes.count == 0 {
      tableView.reloadData()
    }
    delBtn.isEnabled = tableView.selectedRow != -1
  }
}
