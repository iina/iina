//
//  SettingsPageAdvanced.swift
//  iina
//
//  Created by Hechen Li on 2026-02-02.
//  Copyright © 2026 lhc. All rights reserved.
//

fileprivate let ui = SettingsUIHelper.sharedUI

private final class MPVOptionFieldEditor: NSTextView {
  var pasteHandler: ((String) -> Bool)?

  override func paste(_ sender: Any?) {
    guard let string = NSPasteboard.general.string(forType: .string),
          pasteHandler?(string) == true else {
      super.paste(sender)
      return
    }
  }
}

private final class MPVOptionsTableView: NSTableView {
  let optionFieldEditor: MPVOptionFieldEditor = {
    let editor = MPVOptionFieldEditor()
    editor.isFieldEditor = true
    return editor
  }()
}

private final class MPVOptionTextFieldCell: NSTextFieldCell {
  override func fieldEditor(for controlView: NSView) -> NSTextView? {
    return (controlView as? MPVOptionsTableView)?.optionFieldEditor
  }
}

class SettingsPageAdvanced: SettingsPage {
  private var pageView: NSView?
  private var advancedSettingsView: NSView?
  private let prefObserver = Preference.Observer()

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

  override func pageLoaded() {
    if let renderedView = advancedSettingsSwitch.renderedView {
      advancedSettingsView = renderedView
      var pageView: NSView = renderedView
      while let superview = pageView.superview, !(superview is NSClipView) {
        pageView = superview
      }
      self.pageView = pageView
    }

    prefObserver.add(.enableAdvancedSettings, runNow: true) { [weak self] _ in
      self?.setAdvancedControlsEnabled(Preference.bool(for: .enableAdvancedSettings))
    }
  }

  private lazy var fileChooseView: SettingsAccessory.FileChooserView = .init(.userDefinedConfDir)
  private lazy var mpvOptionsEditor: MPVOptionsEditor = MPVOptionsEditor()
  private lazy var openLogFolderBtn: NSButton = {
    let btn = NSButton(title: ui.localized(.text_OpenLogDirectory), target: nil, action: nil)
    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.target = self
    btn.action = #selector(openLogFolder)
    return btn
  }()

  private lazy var advancedSettingsSwitch: SettingsItem.Switch = {
    let item = SettingsItem.Switch()
      .bindTo(.enableAdvancedSettings)
      .image(name: ["flask"])
      .hasDescription()
      .withHelpLink(AppData.wikiLink.appending("/MPV-Options-and-Properties"))
    item.stateChangeCallback = { [weak self] _ in
      DispatchQueue.main.async {
        self?.setAdvancedControlsEnabled(Preference.bool(for: .enableAdvancedSettings))
      }
    }
    return item
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
        advancedSettingsSwitch
      }
    }
  }

  private func setAdvancedControlsEnabled(_ enabled: Bool) {
    guard let pageView else { return }
    setControlsEnabled(in: pageView, enabled: enabled, skipping: advancedSettingsView)
  }

  private func setControlsEnabled(in view: NSView, enabled: Bool, skipping skippedView: NSView?) {
    guard view !== skippedView else { return }
    if let control = view as? NSControl {
      control.isEnabled = enabled
    }
    view.subviews.forEach { setControlsEnabled(in: $0, enabled: enabled, skipping: skippedView) }
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
          .hasDescription(content: .text_AdditionalMpvOptions_desc)
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

  let tableView: MPVOptionsTableView = MPVOptionsTableView()
  let scrollView: NSScrollView = NSScrollView()
  let addBtn: NSButton = NSButton()
  let delBtn: NSButton = NSButton()

  var options: [[String]] = []

  override init() {
    addBtn.bezelStyle = .push
    delBtn.bezelStyle = .push

    super.init()

    let monoFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    scrollView.documentView = tableView
    scrollView.drawsBackground = false
    tableView.backgroundColor = .clear
    tableView.focusRingType = .none
    tableView.registerForDraggedTypes([MPVOptionsEditor.dragType])
    tableView.delegate = self
    tableView.dataSource = self
    tableView.optionFieldEditor.pasteHandler = { [weak self] in self?.pasteOption($0) ?? false }
    let columnKey = NSTableColumn(identifier: .key)
    columnKey.title = "Key"
    columnKey.minWidth = 140
    let keyCell = MPVOptionTextFieldCell()
    keyCell.isEditable = true
    keyCell.isSelectable = true
    keyCell.lineBreakMode = .byTruncatingTail
    keyCell.font = monoFont
    columnKey.dataCell = keyCell
    tableView.addTableColumn(columnKey)
    let columnValue = NSTableColumn(identifier: .value)
    columnValue.title = "Value"
    let valueCell = MPVOptionTextFieldCell()
    valueCell.isEditable = true
    valueCell.isSelectable = true
    valueCell.lineBreakMode = .byTruncatingTail
    valueCell.font = monoFont
    columnValue.dataCell = valueCell
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

  private static func parsePastedOption(_ string: String) -> [String]? {
    guard let separator = string.firstIndex(of: "=") else { return nil }

    let whitespaceAndNewlines = CharacterSet.whitespacesAndNewlines
    let key = String(string[..<separator]).trimmingCharacters(in: whitespaceAndNewlines)
    let value = String(string[string.index(after: separator)...]).trimmingCharacters(in: whitespaceAndNewlines)
    guard !key.isEmpty, !value.isEmpty else { return nil }
    return [key, value]
  }

  private func pasteOption(_ string: String) -> Bool {
    guard let option = Self.parsePastedOption(string),
          options.indices.contains(tableView.editedRow) else { return false }

    let row = tableView.editedRow
    guard tableView.abortEditing() else { return false }
    options[row] = option
    tableView.reloadData(forRowIndexes: IndexSet(integer: row),
                         columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
    saveToUserDefaults()
    return true
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
