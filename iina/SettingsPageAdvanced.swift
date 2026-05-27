//
//  SettingsPageAdvanced.swift
//  iina
//
//  Created by Hechen Li on 2026-02-02.
//  Copyright © 2026 lhc. All rights reserved.
//

class SettingsPageAdvanced: SettingsPage {
  override var identifier: String {
    "advanced"
  }
  
  override var title: String {
    return NSLocalizedString("preference.advanced", comment: "Advanced")
  }

  override var image: NSImage {
    return .sf("flask", "slider.horizontal.3", withConfiguration: symbolConfiguration)!
  }

  override var localizationTable: String {
    "SettingsAdvancedLocalizable"
  }

  private lazy var fileChooseView: SettingsAccessory.FileChooserView = .init(.userDefinedConfDir)
  private lazy var mpvOptionsEditor: MPVOptionsEditor = .init(l10n: localizationContext)
  private lazy var openLogFolderBtn: NSButton = {
    let btn = NSButton(title: localizationContext.localized(.text_OpenLogDirectory), target: nil, action: nil)
    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.target = self
    btn.action = #selector(openLogFolder)
    return btn
  }()

  override func content() -> [SettingsSection] {
    return sections {
      sectionEnableAdvanced()
      sectionLogging()
      sectionMPV()
    }
  }

  private func sectionEnableAdvanced() -> SettingsSection {
    return section {
      SettingsList() {
        SettingsItem.Switch()
          .bindTo(.enableAdvancedSettings)
          .image(name: ["flask"])
          .hasDescription()
          .withHelpLink(AppData.wikiLink.appending("/MPV-Options-and-Properties"))
      }
    }
  }

  private func sectionLogging() -> SettingsSection {
    return section {
      SettingsList(title: .text_Logging) {
        SettingsItem.PopupButton()
          .bindTo(.logLevel, ofType: Logger.Level.self)
          .image(name: "cylinder.split.1x2")
        SettingsItem.Switch()
          .bindTo(.enableLogging)
          .extraViews(openLogFolderBtn)
      }
      SettingsList {
        SettingsItem.General(title: .text_OpenLogWindow)
          .image(name: "macwindow")
          .extraViews(NSButton(image: .sf("arrow.right")!, target: AppDelegate.shared, action: #selector(AppDelegate.showLogWindow)))
      }
    }
  }

  private func sectionMPV() -> SettingsSection {
    return section {
      SettingsList(title: .text_MPVSettings) {
        SettingsItem.Switch()
          .bindTo(.useMpvOsd)
          .image(name: "ellipsis.bubble")
      }
      SettingsList {
        SettingsItem.Switch()
          .image(name: ["folder.badge.gearshape", "folder.badge.gear"])
          .bindTo(.useUserDefinedConfDir)
          .extraViews(fileChooseView.textField, fileChooseView.chooseButton)
      }
      SettingsList {
        SettingsItem.General(title: .text_AdditionalMpvOptions)
          .image(name: ["document.badge.gearshape", "doc.badge.gearshape"])
          .extraViews(mpvOptionsEditor.delBtn, mpvOptionsEditor.addBtn)
        SettingsItem.Custom()
          .view(mpvOptionsEditor.view)
      }
    }
  }

  @objc private func openLogFolder() {
    NSWorkspace.shared.open(Logger.logDirectory)
  }
}

fileprivate class MPVOptionsEditor: SettingsAccessory.Base, NSTableViewDelegate, NSTableViewDataSource {
  private static let dragType = NSPasteboard.PasteboardType("com.colliderli.iina.mpv-option-row")

  let tableView: NSTableView = NSTableView()
  let scrollView: NSScrollView = NSScrollView()
  let addBtn: NSButton = NSButton()
  let delBtn: NSButton = NSButton()

  var options: [[String]] = []

  override init(l10n: SettingsLocalization.Context) {
    addBtn.bezelStyle = .push
    delBtn.bezelStyle = .push

    super.init(l10n: l10n)

    let monoFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    scrollView.documentView = tableView
    scrollView.drawsBackground = false
    tableView.backgroundColor = .clear
    tableView.focusRingType = .none
    tableView.registerForDraggedTypes([MPVOptionsEditor.dragType])
    tableView.delegate = self
    tableView.dataSource = self
    let columnKey = NSTableColumn(identifier: .key)
    columnKey.title = "Key"
    columnKey.minWidth = 140
    (columnKey.dataCell as? NSCell)?.font = monoFont
    tableView.addTableColumn(columnKey)
    let columnValue = NSTableColumn(identifier: .value)
    columnValue.title = "Value"
    (columnValue.dataCell as? NSCell)?.font = monoFont
    tableView.addTableColumn(columnValue)
    tableView.columnAutoresizingStyle = .sequentialColumnAutoresizingStyle
    tableView.rowHeight = 18

    let stackView = ui.vStack(scrollView)
    view.addSubview(stackView)
    stackView.padding(.leading(SettingsSubList.indent + 8), .trailing(0), .bottom(8), .top(0))
    stackView.size(height: 120)

    addBtn.image = .sf("plus")
    addBtn.target = self
    addBtn.action = #selector(addOptionAction)
    delBtn.image = .sf("minus")
    delBtn.isEnabled = false
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

  func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
    let item = NSPasteboardItem()
    item.setString(String(row), forType: MPVOptionsEditor.dragType)
    return item
  }

  func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
    guard dropOperation == .above else { return [] }
    return .move
  }

  func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
    guard let str = info.draggingPasteboard.string(forType: MPVOptionsEditor.dragType),
          let srcRow = Int(str),
          srcRow != row, srcRow != row - 1 else { return false }
    let option = options.remove(at: srcRow)
    let destRow = srcRow < row ? row - 1 : row
    options.insert(option, at: destRow)
    tableView.beginUpdates()
    tableView.moveRow(at: srcRow, to: destRow)
    tableView.endUpdates()
    saveToUserDefaults()
    return true
  }
}
