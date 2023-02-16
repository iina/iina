//
//  InputConfTableController.swift
//  iina
//
//  Created by Matt Svoboda on 2022.07.03.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation
import AppKit
import Cocoa

fileprivate let COPY_COUNT_REGEX = try! NSRegularExpression(
  pattern: #"(.*)(?:\scopy(?: (\d+))?)"#, options: []
)

fileprivate let nameColumnIndex = 0
fileprivate let draggingFormation: NSDraggingFormation = .default
fileprivate let useSeparateColorForBuiltinConfs = false

fileprivate let blendFraction: CGFloat = 0.05
@available(macOS 10.14, *)
fileprivate var builtinConfTextColor: NSColor!

@available(macOS 10.14, *)
private func recomputeCustomColors() {
  builtinConfTextColor = .controlAccentColor.blended(withFraction: blendFraction, of: .textColor)!
}

class ConfTableViewController: NSObject {
  private unowned var tableView: EditableTableView!
  private var confTableState: ConfTableState {
    return ConfTableState.current
  }
  private unowned var bindingTableViewController: BindingTableViewController
  private var distObservers: [NSObjectProtocol] = []  // For DistributedNotificationCenter
  private var observers: [NSObjectProtocol] = []      // For regular NotificationCenter

  // Convenience var. Pref lookup is super fast; should be fine to check on each access. Try to reduce need for restart
  fileprivate var enableInlineCreate: Bool {
    Preference.bool(for: .useInlineEditorInsteadOfDialogForNewInputConf)
  }

  init(_ inputConfTableView: EditableTableView, _ bindingTableViewController: BindingTableViewController) {
    self.tableView = inputConfTableView
    self.bindingTableViewController = bindingTableViewController

    super.init()

    tableView.dataSource = self
    tableView.delegate = self
    tableView.editableDelegate = self

    tableView.menu = NSMenu()
    tableView.menu?.delegate = self

    tableView.editableTextColumnIndexes = [nameColumnIndex]
    tableView.registerTableUIChangeObserver(forName: .iinaPendingUIChangeForConfTable)

    if #available(macOS 10.14, *) {
      recomputeCustomColors()
      distObservers.append(DistributedNotificationCenter.default().addObserver(forName: .appleColorPreferencesChangedNotification, object: nil, queue: .main, using: self.uiSettingsDidChange))
    }

    if #available(macOS 10.13, *) {
      // Enable drag & drop for MacOS 10.13+
      var acceptableDraggedTypes: [NSPasteboard.PasteboardType] = [.fileURL, .iinaKeyMapping]
      if Preference.bool(for: .acceptRawTextAsKeyBindings) {
        acceptableDraggedTypes.append(.string)
      }
      tableView.registerForDraggedTypes(acceptableDraggedTypes)
      tableView.setDraggingSourceOperationMask([.copy], forLocal: false)
      tableView.draggingDestinationFeedbackStyle = .regular
    }

    tableView.scrollRowToVisible(0)
  }

  deinit {
    for observer in distObservers {
      DistributedNotificationCenter.default().removeObserver(observer)
    }
    distObservers = []
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []
  }

  @available(macOS 10.14, *)
  private func uiSettingsDidChange(notification: Notification) {
    Logger.log("Detected change system color prefs; reloading Conf table", level: .verbose)
    recomputeCustomColors()
    self.tableView.reloadExistingRows(reselectRowsAfter: true)
  }

  func selectCurrentConfRow() {
    let confName = self.confTableState.selectedConfName
    guard let index = confTableState.confTableRows.firstIndex(of: confName) else {
      Logger.log("selectCurrentConfRow(): Failed to find '\(confName)' in table; falling back to default", level: .error)
      confTableState.fallBackToDefaultConf()
      return
    }

    self.tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    let printedIndexesMsg = "Selected index list is now: \(self.tableView.selectedRowIndexes.map{$0})"
    Logger.log("Selected row: '\(confName)' (index \(index)). \(printedIndexesMsg)", level: .verbose)
  }
}

// MARK: NSTableViewDelegate

extension ConfTableViewController: NSTableViewDelegate {

  // Selection Changed
  @objc func tableViewSelectionDidChange(_ notification: Notification) {
    guard tableView.selectedRow >= 0 else {
      Logger.log("ConfTableViewController: ignoring tableViewSelectionDidChange(); no row selected", level: .verbose)
      return
    }
    Logger.log("ConfTableViewController: tableViewSelectionDidChange() called. Kicking off state change to index \(tableView.selectedRow)", level: .verbose)
    confTableState.changeSelectedConf(tableView.selectedRow)
  }

  /**
   Make cell view when asked
   */
  @objc func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row rowIndex: Int) -> NSView? {
    guard let identifier = tableColumn?.identifier else { return nil }
    guard let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView else { return nil }
    let columnName = identifier.rawValue

    guard let confName = confTableState.getConfName(at: rowIndex) else { return nil }
    let isBuiltinConf = ConfTableState.isBuiltinConf(confName)

    // For built-in conf rows, make text italic and show lock icon (also add color to text & icon if configured)
    switch columnName {
      case "nameColumn":
        let textColor: NSColor?
        if #available(macOS 10.14, *), useSeparateColorForBuiltinConfs {
          textColor = isBuiltinConf ? builtinConfTextColor : .controlTextColor
        } else {
          textColor = nil
        }
        cell.textField?.setFormattedText(stringValue: confName, textColor: textColor, italic: isBuiltinConf)
        return cell
      case "isDefaultColumn":
        if #available(macOS 10.14, *), useSeparateColorForBuiltinConfs {
          cell.imageView?.contentTintColor = builtinConfTextColor
        }
        cell.imageView?.isHidden = !isBuiltinConf
        return cell
      default:
        Logger.log("Unrecognized column: '\(columnName)'", level: .error)
        return nil
    }
  }
}

// MARK: EditableTableViewDelegate

extension ConfTableViewController: EditableTableViewDelegate {

  func userDidDoubleClickOnCell(row rowIndex: Int, column columnIndex: Int) -> Bool {
    return confTableState.getUserConfName(at: rowIndex) != nil
  }

  func userDidPressEnterOnRow(_ rowIndex: Int) -> Bool {
    return confTableState.getUserConfName(at: rowIndex) != nil
  }

  func editDidEndWithNoChange(row rowIndex: Int, column columnIndex: Int) {
    if self.confTableState.isAddingNewConfInline {
      // If user didn't enter a name, just remove the row
      confTableState.cancelInlineAdd()
    }
  }

  // User finished editing (callback from EditableTextField).
  // Renames current conf & its file on disk
  func editDidEndWithNewText(newValue newName: String, row: Int, column: Int) -> Bool {
    if confTableState.isAddingNewConfInline { // New file
      let succeeded = self.completeInlineAdd(newName: newName)
      if !succeeded {
        confTableState.cancelInlineAdd()
      }
      return succeeded

    } else { // Renaming existing file
      return self.moveFileAndRenameCurrentConf(newName: newName)
    }
  }

  private func completeInlineAdd(newName: String) -> Bool {
    guard !self.confTableState.isRow(newName) else {
      // Disallow overwriting another entry in list
      Utility.showAlert("config.name_existing", sheetWindow: self.tableView.window)
      return false
    }

    let newFilePath =  Utility.buildConfFilePath(for: newName)

    // Overwrite of unrecognized file which is not in IINA's list is ok as long as we prompt the user first
    guard self.handlePossibleExistingFile(filePath: newFilePath) else {
      return false  // cancel
    }

    // Make new empty file
    if !FileManager.default.createFile(atPath: newFilePath, contents: nil, attributes: nil) {
      Utility.showAlert("config.cannot_create", sheetWindow: self.tableView.window)
      return false
    }
    confTableState.completeInlineAdd(confName: newName, filePath: newFilePath)
    return true
  }

  private func moveFileAndRenameCurrentConf(newName: String) -> Bool {
    // Validate name change
    guard !self.confTableState.selectedConfName.equalsIgnoreCase(newName) else {
      // No change to current entry: ignore
      return false
    }

    Logger.log("User renamed current conf to \(newName.quoted) in editor", level: .verbose)

    guard !self.confTableState.isRow(newName) else {
      // Disallow overwriting another entry in list
      Utility.showAlert("config.name_existing", sheetWindow: self.tableView.window)
      return false
    }

    let oldFilePath = self.confTableState.selectedConfFilePath
    let newFilePath =  Utility.buildConfFilePath(for: newName)

    if newFilePath != oldFilePath { // allow this...it helps when user is trying to fix corrupted file list
      // Overwrite of unrecognized file which is not in IINA's list is ok as long as we prompt the user first
      guard self.handlePossibleExistingFile(filePath: newFilePath) else {
        return false  // cancel
      }
    }

    // Let confTableState rename the file, update conf lists and send UI update
    return confTableState.renameSelectedConf(newName: newName)
  }

  // MARK: Cut, copy, paste, delete support.

  // Only selected table items which have `canBeModified==true` can be included.
  // Each menu item should be disabled if it cannot operate on at least one item.

  func isCopyEnabled() -> Bool {
    return true // can always copy current file
  }

  func isCutEnabled() -> Bool {
    return false
  }

  func isDeleteEnabled() -> Bool {
    return !confTableState.isSelectedConfReadOnly
  }

  func isPasteEnabled() -> Bool {
    // can paste either conf files or key bindings
    return !readConfFilesFromClipboard().isEmpty || bindingTableViewController.isPasteEnabled()
  }

  func doEditMenuCopy() {
    return copyConfFileToClipboard(confName: confTableState.selectedConfName)
  }

  func doEditMenuPaste() {
    // Conf files?
    let confFilePathList = readConfFilesFromClipboard()
    if !confFilePathList.isEmpty {
      // Try not to block animation for I/O or user prompts
      DispatchQueue.main.async {
        self.importConfFiles(confFilePathList, renameDuplicates: true)
      }
      return
    }

    // Maybe key bindings. Paste bindings into current conf, if any:
    bindingTableViewController.doEditMenuPaste()
  }

  func doEditMenuDelete() {
    // Delete current user conf
    deleteConf(confTableState.selectedConfName)
  }

  private func readConfFilesFromClipboard() -> [String] {
    ConfTableViewController.extractConfFileList(from: NSPasteboard.general)
  }

  // Convert conf file path to URL and put it in clipboard
  private func copyConfFileToClipboard(confName: String) {
    let filePath = confTableState.getFilePath(forConfName: confName)
    let url = NSURL(fileURLWithPath: filePath)

    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([url])
    Logger.log("Copied to the clipboard: \(url.description.quoted)", level: .verbose)
  }

}

// MARK: NSTableViewDataSource

extension ConfTableViewController: NSTableViewDataSource {
  /*
   Tell NSTableView the number of rows when it asks
   */
  @objc func numberOfRows(in tableView: NSTableView) -> Int {
    return confTableState.confTableRows.count
  }

  // MARK: Drag & Drop

  /*
   Drag start: define which operations are allowed
   */
  @objc func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    session.draggingFormation = draggingFormation
    return .copy
  }

  /*
   Drag start: convert tableview rows to clipboard items
   */
  @objc func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
    if let confName = confTableState.getConfName(at: row) {
      let filePath = confTableState.getFilePath(forConfName: confName)
      return NSURL(fileURLWithPath: filePath)
    }
    return nil
  }

  /*
   Drag start: set session variables.
   */
  @objc func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                       willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
    self.tableView.setDraggingImageToAllColumns(session, screenPoint, rowIndexes)
  }

  /**
   This is implemented to support dropping items onto the Trash icon in the Dock
   */
  @objc func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    guard operation == NSDragOperation.delete else {
      return
    }

    let userConfList = ConfTableViewController.extractConfFileList(from: session.draggingPasteboard).compactMap {
      confTableState.getUserConfName(forFilePath: $0) }

    guard userConfList.count == 1 else { return }
    let confName = userConfList[0]

    Logger.log("User dragged to the trash: \(confName)", level: .verbose)

    // TODO: this is the wrong animation
    NSAnimationEffect.disappearingItemDefault.show(centeredAt: screenPoint, size: NSSize(width: 50.0, height: 50.0), completionHandler: {
      self.deleteConf(confName)
    })
  }

  /*
   Validate drop while hovering.
   Override drag operation to "copy" always, and set drag target to whole table.
   */
  @objc func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {

    info.draggingFormation = draggingFormation
    info.animatesToDestination = true

    if let dragSource = info.draggingSource as? NSTableView, dragSource == self.tableView {
      // Don't allow drops onto self
      return []
    }

    // Bring this window to the front when things are dragged over it (in the case of drags from the Finder)
    info.draggingDestinationWindow?.orderFrontRegardless()

    // Check for conf files
    let confFileCount = ConfTableViewController.extractConfFileList(from: info.draggingPasteboard).count
    if confFileCount > 0 {
      // Update that little red number:
      info.numberOfValidItemsForDrop = confFileCount

      tableView.setDropRow(-1, dropOperation: .above)
      return NSDragOperation.copy
    }

    // Check for key bindings
    let bindingCount = KeyMapping.deserializeList(from: info.draggingPasteboard).count
    if bindingCount > 0 && dropOperation == .on, confTableState.getUserConfName(at: row) != nil {
      // Drop bindings into another user conf
      info.numberOfValidItemsForDrop = bindingCount
      return NSDragOperation.copy
    }

    // Either no bindings or no conf files
    return []
  }

  /*
   Accept the drop and execute it, or reject drop.
   */
  @objc func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
    let dragMask = info.draggingSourceOperationMask
    guard dragMask.contains(.copy) else {
      Logger.log("Rejecting drop: got unexpected drag mask: \(dragMask)")
      return false
    }

    info.animatesToDestination = true
    info.draggingFormation = draggingFormation

    // Option A: drop input conf file(s) into table
    let confFilePathList = ConfTableViewController.extractConfFileList(from: info.draggingPasteboard)
    if !confFilePathList.isEmpty {
      Logger.log("User dropped \(confFilePathList.count) conf files into table")
      info.numberOfValidItemsForDrop = confFilePathList.count
      // Try not to block animation for I/O or user prompts
      DispatchQueue.main.async {
        self.importConfFiles(confFilePathList, renameDuplicates: true)
      }
      return true
    }

    // Option B: drop bindings into user conf file
    let bindingList = KeyMapping.deserializeList(from: info.draggingPasteboard)
    if !bindingList.isEmpty, dropOperation == .on, let targetConfName = confTableState.getUserConfName(at: row) {
      Logger.log("User dropped \(bindingList.count) bindings into \(targetConfName.quoted) conf")
      info.numberOfValidItemsForDrop = bindingList.count
      // Try not to block UI. Failures should be rare here anyway
      DispatchQueue.main.async {
        self.confTableState.appendBindingsToUserConfFile(bindingList, targetConfName: targetConfName)
      }
      return true
    }

    return false
  }

  private static func extractConfFileList(from pasteboard: NSPasteboard) -> [String] {
    var fileList: [String] = []

    pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.forEach {
      if let url = $0 as? URL {
        let filePath = url.path
        if filePath.lowercasedPathExtension == AppData.confFileExtension {
          fileList.append(url.path)
        }
      }
    }
    return fileList
  }
}

// MARK: NSMenuDelegate

extension ConfTableViewController:  NSMenuDelegate {

  fileprivate class InputConfMenuItem: NSMenuItem {
    let confName: String

    public init(confName: String, title: String, action selector: Selector?, key: String) {
      self.confName = confName
      super.init(title: title, action: selector, keyEquivalent: key)
    }

    required init(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }

  fileprivate class ConfMenuItemProvider: MenuItemProvider {
    func buildItem(_ title: String, action: Selector?, targetRow: Any, key: String, _ cmb: CascadingMenuItemBuilder) throws -> NSMenuItem {
      return InputConfMenuItem(confName: targetRow as! String, title: title, action: action, key: key)
    }
  }

  // Builds context menu each time a row is right-clicked
  @objc func menuNeedsUpdate(_ contextMenu: NSMenu) {
    // This will prevent menu from showing if no items are added
    contextMenu.removeAllItems()

    guard let clickedConfName: String = confTableState.getConfName(at: tableView.clickedRow) else {
      let mib = CascadingMenuItemBuilder(.menu(contextMenu), .unit(Unit.config), .target(self))
      self.addPasteMenuItem(mib, didClickOnUserConf: false)
      return
    }
    let mib = CascadingMenuItemBuilder(mip: ConfMenuItemProvider(), .menu(contextMenu),
      .unit(Unit.config), .unitCount(1), .targetRow(clickedConfName), .target(self))

    let didClickOnUserConf = !ConfTableState.isBuiltinConf(clickedConfName)

    // Show in Finder
    mib.addItem("Show in Finder", #selector(self.showInFinderFromMenu(_:)), with: .enabled(didClickOnUserConf))

    // Rename Conf File
    mib.addItem("Rename", #selector(self.renameFromMenu(_:)), with: .enabled(didClickOnUserConf), .key(KeyCodeHelper.KeyEquivalents.RETURN))

    // Duplicate
    mib.addItem("Duplicate", #selector(self.duplicateConfFromMenu(_:)))

    // ---
    mib.addSeparator()

    mib.likeEditCopy().addItem(#selector(self.copyConfFromMenu(_:)))

    self.addPasteMenuItem(mib, didClickOnUserConf: didClickOnUserConf)

    mib.addSeparator()

    // Delete
    mib.likeEasyDelete().butWith(.enabled(didClickOnUserConf)).addItem(#selector(self.deleteConfFromMenu(_:)))
  }

  private func addPasteMenuItem(_ mib: CascadingMenuItemBuilder, didClickOnUserConf: Bool) {
    let pasteBuilder = mib.likeEditPaste().butWith(.action(#selector(self.pasteFromMenu(_:))))
    var didAdd = false
    let confCount = readConfFilesFromClipboard().count
    if confCount > 0 {
      pasteBuilder.butWith(.unitCount(confCount)).addItem()
      didAdd = true
    } else {
      let bindingCount = bindingTableViewController.readBindingsFromClipboard().count
      if bindingCount > 0 {
        pasteBuilder.butWith(.unit(.keyBinding), .unitCount(bindingCount), .enabled(didClickOnUserConf)).addItem()
        didAdd = true
      }
    }
    if !didAdd {  // disabled
      pasteBuilder.addItem(with: .enabled(false), .unitCount(0))
    }
  }

  @objc fileprivate func copyConfFromMenu(_ sender: InputConfMenuItem) {
    self.copyConfFileToClipboard(confName: sender.confName)
  }

  @objc fileprivate func pasteFromMenu(_ sender: InputConfMenuItem) {
    // Conf files?
    let confFilePathList = readConfFilesFromClipboard()
    if !confFilePathList.isEmpty {
      // Try not to block animation for I/O or user prompts
      DispatchQueue.main.async {
        self.importConfFiles(confFilePathList, renameDuplicates: true)
      }
      return
    }

    // Maybe key bindings
    let mappingsToInsert = bindingTableViewController.readBindingsFromClipboard()
    if !mappingsToInsert.isEmpty {
      let destConfName = sender.confName
      Logger.log("User chose to paste \(mappingsToInsert.count) bindings into \(destConfName.quoted)")
      if destConfName == confTableState.selectedConfName {
        // If currently open conf file, this will paste under the current selection
        bindingTableViewController.doEditMenuPaste()
      } else {
        // If other files, append at end
        confTableState.appendBindingsToUserConfFile(mappingsToInsert, targetConfName: destConfName)
      }
    }
  }

  @objc fileprivate func deleteConfFromMenu(_ sender: InputConfMenuItem) {
    self.deleteConf(sender.confName)
  }

  @objc fileprivate func showInFinderFromMenu(_ sender: InputConfMenuItem) {
    self.showInFinder(sender.confName)
  }

  @objc fileprivate func renameFromMenu(_ sender: InputConfMenuItem) {
    if let targetRowIndex = confTableState.confTableRows.firstIndex(of: sender.confName) {
      tableView.editCell(row: targetRowIndex, column: nameColumnIndex)
    }
  }

  @objc fileprivate func duplicateConfFromMenu(_ sender: InputConfMenuItem) {
    self.duplicateConf(sender.confName)
  }

  // MARK: Reusable UI actions

  // Action: Delete Conf
  @objc public func deleteConf(_ confName: String) {
    guard confTableState.isRow(confName) else {
      return
    }

    // Let confTableState delete the file, update prefs & refresh UI
    confTableState.removeConf(confName)
  }

  @objc func showInFinder(_ confName: String) {
    let confFilePath = confTableState.getFilePath(forConfName: confName)
    let url = URL(fileURLWithPath: confFilePath)
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  // Action: New Conf
  @objc func createNewConf() {
    if enableInlineCreate {
      // Add a new conf with no name, and immediately open an editor for it.
      // The table will update asynchronously, but we need to make sure it's done adding before we can edit it.
      let _ = confTableState.addNewUserConfInline(completionHandler: { tableUIChange in
        if let selectedRowIndex = tableUIChange.newSelectedRowIndexes?.first {
          self.tableView.editCell(row: selectedRowIndex, column: 0)  // open  an editor for the new row
        }
      })
    } else {
      // Open modal dialog and prompt user
      Utility.quickPromptPanel("config.new", sheetWindow: tableView.window) { newName in
        guard !newName.isEmpty else {
          Utility.showAlert("config.empty_name", sheetWindow: self.tableView.window)
          return
        }

        self.makeNewConfFile(newName, doAction: { (newFilePath: String) in
          // - new file
          if !FileManager.default.createFile(atPath: newFilePath, contents: nil, attributes: nil) {
            Utility.showAlert("config.cannot_create", sheetWindow: self.tableView.window)
            return false
          }
          return true
        })
      }
    }
  }

  // Action: Duplicate Conf
  @objc func duplicateConf(_ confName: String) {
    let currFilePath = confTableState.getFilePath(forConfName: confName)

    if enableInlineCreate {
      // Find a new name for the duplicate, and immediately open an editor for it to change the name.
      // The table will update asynchronously, but we need to make sure it's done adding before we can edit it.
      if let (newConfName, newFilePath) = self.duplicateConfFile(forConfName: confName) {
        self.confTableState.addUserConf(confName: newConfName, filePath: newFilePath, completionHandler: { tableUIChange in
          if let selectedRowIndex = tableUIChange.newSelectedRowIndexes?.first {
            self.tableView.editCell(row: selectedRowIndex, column: 0)  // open  an editor for the new row
          }
        })
      }
    } else {
      // prompt
      Utility.quickPromptPanel("config.duplicate", sheetWindow: tableView.window) { newName in
        guard !newName.isEmpty else {
          Utility.showAlert("config.empty_name", sheetWindow: self.tableView.window)
          return
        }
        guard !self.confTableState.isRow(newName) else {
          Utility.showAlert("config.name_existing", sheetWindow: self.tableView.window)
          return
        }

        self.makeNewConfFile(newName, doAction: { (newFilePath: String) in
          // - copy file
          do {
            try FileManager.default.copyItem(atPath: currFilePath, toPath: newFilePath)
            return true
          } catch let error {
            Utility.showAlert("config.cannot_create", arguments: [error.localizedDescription], sheetWindow: self.tableView.window)
            return false
          }
        })
      }
    }
  }

  private func duplicateConfFile(forConfName confName: String) -> (String, String)? {
    guard confTableState.isRow(confName) else { return nil }
    let origFilePath = confTableState.getFilePath(forConfName: confName)

    let (newConfName, newFilePath) = findNewNameForDuplicate(originalName: confName)

    do {
      Logger.log("Duplicating file: \(origFilePath.quoted) -> \(newFilePath.quoted)")
      try FileManager.default.copyItem(atPath: origFilePath, toPath: newFilePath)
      return (newConfName, newFilePath)
    } catch let error {
      DispatchQueue.main.async {
        Logger.log("Failed to create duplicate: \(origFilePath.quoted) -> \(newFilePath.quoted): \(error.localizedDescription)", level: .error)
        Utility.showAlert("config.cannot_create", arguments: [error.localizedDescription], sheetWindow: self.tableView.window)
      }
      return nil
    }
  }

  private func makeNewConfFile(_ newName: String, doAction: (String) -> Bool) {
    let newFilePath =  Utility.buildConfFilePath(for: newName)

    // - if exists with same name
    guard self.handlePossibleExistingFile(filePath: newFilePath) else {
      return
    }

    guard doAction(newFilePath) else {
      return
    }

    self.confTableState.addUserConf(confName: newName, filePath: newFilePath)
  }

  /*
   Action: Import conf file(s).
   Checks that each file can be opened and parsed and if any cannot, prints an error and does nothing.
   If any of the imported files would overwrite an existing one:
   - If `renameDuplicates` is true, a new name is chosen automatically for each.
   - If `renameDuplicates` is false, for each conflict, the user is asked whether to delete the existing.
     If the user declines any of them, the import is immediately cancelled before it changes any data.

   If successful, adds new rows to the UI, with the last added row being selected as the new current conf.
   */
  func importConfFiles(_ fileList: [String], renameDuplicates: Bool = false) {
    // Return immediately, and import (or fail to) asynchronously
    DispatchQueue.global(qos: .userInitiated).async {
      Logger.log("Importing input conf files: \(fileList)", level: .verbose)

      // confName -> (srcFilePath, dstFilePath)
      var createdConfDict: [String: (String, String)] = [:]

      for filePath in fileList {
        let url = URL(fileURLWithPath: filePath)
        // If conf is builtin, its name won't match its filename exactly, so need to look it up
        let confName = self.confTableState.getBuiltinConfName(forFilePath: filePath) ?? url.deletingPathExtension().lastPathComponent

        guard InputConfFile.tryLoadingFile(at: filePath) else {
          DispatchQueue.main.async {
            Logger.log("Error reading conf file \(filePath.quoted); aborting import", level: .error)
            Utility.showAlert("keybinding_config.error", arguments: [url.lastPathComponent], sheetWindow: self.tableView.window)
          }
          // Do not import any files if we can't parse one.
          // This probably means the user doesn't know what they are doing, or something is very wrong
          return
        }
        var newName = confName
        var newFilePath: String
        if let filePath = self.getFilePathIfValid(forConfName: newName) {
          newFilePath = filePath
        } else if renameDuplicates {
          (newName, newFilePath) = self.findNewNameForDuplicate(originalName: newName)
        } else {
          // Looks like file exists, but renameDuplicates is disabled
          newFilePath = Utility.buildConfFilePath(for: newName)

          if filePath.equalsIgnoreCase(newFilePath) {
            // Edge case
            Logger.log("File is already present in input_conf directory but was missing from conf list; adding it: \(filePath.quoted)")
          } else {
            DispatchQueue.main.sync {  // block because we need user input to proceed
              guard self.handlePossibleExistingFile(filePath: newFilePath) else {
                // Do not proceed if user does not want to delete.
                Logger.log("Aborting conf file import: user did not delete file: \(newFilePath.quoted)")
                return
              }
            }
          }
        }

        createdConfDict[newName] = (filePath, newFilePath)
      }

      // Copy files one by one. Allow copy errors but keep track of which failed
      var failedNameSet = Set<String>()
      for (newName, (filePath, newFilePath)) in createdConfDict {
        if filePath != newFilePath {
          do {
            Logger.log("Import: copying: \(filePath.quoted) -> \(newFilePath.quoted)")
            try FileManager.default.copyItem(atPath: filePath, toPath: newFilePath)
          } catch let error {
            DispatchQueue.main.async {
              Logger.log("Import: failed to copy: \(filePath.quoted) -> \(newFilePath.quoted): \(error.localizedDescription)", level: .error)
              Utility.showAlert("config.cannot_create", arguments: [error.localizedDescription], sheetWindow: self.tableView.window)
            }
            failedNameSet.insert(newName)
          }
        }
      }

      // Filter failed rows from being added to UI
      let confsToAdd: [String: String] = createdConfDict.filter{ !failedNameSet.contains($0.key) }.mapValues { $0.1 }
      guard !confsToAdd.isEmpty else {
        return
      }
      Logger.log("Successfully imported: \(confsToAdd.count) input conf files")

      // update prefs & refresh UI
      self.confTableState.addUserConfs(confsToAdd)
    }
  }

  // Check whether file already exists at `filePath`.
  // If it does, prompt the user to overwrite it or show it in Finder. Return true if user agrees, false otherwise
  private func handlePossibleExistingFile(filePath: String) -> Bool {
    let fm = FileManager.default
    if fm.fileExists(atPath: filePath) {
      Logger.log("Blocked by existing file: \(filePath.quoted)'", level: .verbose)
      let fileName = URL(fileURLWithPath: filePath).lastPathComponent
      // TODO: show the filename in the dialog
      if Utility.quickAskPanel("config.file_existing", messageComment: "\(fileName.quoted)") {
        // - delete file
        do {
          try fm.removeItem(atPath: filePath)
          Logger.log("Successfully removed file: \(filePath.quoted)'")
          return true
        } catch  {
          Utility.showAlert("error_deleting_file", sheetWindow: self.tableView.window)
          Logger.log("Failed to remove file: \(filePath.quoted)': \(error)")
          return false
        }
      } else {
        // - show file. cancel delete
        Logger.log("User chose to show file in Finder: \(filePath.quoted)'", level: .verbose)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: filePath)])
        return false
      }
    }
    return true
  }

  // MARK: Calculate name of duplicate file

  // Attempt to match Finder's algorithm for file name of copy
  private func findNewNameForDuplicate(originalName: String) -> (String, String) {
    // Strip any copy suffix off of it. Start with no copy suffix and check upwards to see if there's a gap
    var (newConfName, _) = parseBaseAndCopyCount(from: originalName)

    while true {
      let nextName = incrementCopyName(confName: newConfName)
      Logger.log("Checking potential new file name: \(nextName.quoted)", level: .verbose)
      newConfName = nextName

      if let newFilePath = getFilePathIfValid(forConfName: newConfName) {
        return (newConfName, newFilePath)
      }
    }
  }

  private func getFilePathIfValid(forConfName newConfName: String) -> String? {
    // Entry with same name already exists in conf list?
    guard !confTableState.isRow(newConfName) else {
      return nil
    }

    // File with same name already exists?
    let newFilePath =  Utility.buildConfFilePath(for: newConfName)
    guard !FileManager.default.fileExists(atPath: newFilePath) else {
      return nil
    }
    return newFilePath
  }

  private func matchRegex(_ regex: NSRegularExpression, _ msg: String) -> NSTextCheckingResult? {
    return regex.firstMatch(in: msg, options: [], range: NSRange(location: 0, length: msg.count))
  }

  private func parseBaseAndCopyCount(from name: String) -> (String, Int) {
    if let match = matchRegex(COPY_COUNT_REGEX, name) {
      if let baseNameRange = Range(match.range(at: 1), in: name) {
        // Found
        let copyCount: Int
        if let copyCountRange = Range(match.range(at: 2), in: name) {
          copyCount = Int(String(name[copyCountRange])) ?? 1
        } else {
          copyCount = 1   // first "copy" has implicit number
        }
        let baseName = String(name[baseNameRange])
        return (baseName, copyCount)
      }
      Logger.log("Failed to parse name: \(name.quoted)", level: .error)
    }
    // No match
    return (name, 0)
  }

  private func incrementCopyName(confName: String) -> String {
    // Check for copy count number first
    let (baseName, copyCount) = parseBaseAndCopyCount(from: confName)
    if copyCount == 0 {
      return "\(baseName) copy"
    }
    return "\(baseName) copy \(copyCount + 1)"
  }

}
