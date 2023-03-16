//
//  BindingTableViewController.swift
//  iina
//
//  Created by Matt Svoboda on 2022.07.03.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

fileprivate let blendFraction: CGFloat = 0.05
@available(macOS 10.14, *)
fileprivate var nonConfTextColor: NSColor!
@available(macOS 10.14, *)
fileprivate var pluginIconColor: NSColor!
@available(macOS 10.14, *)
fileprivate var libmpvIconColor: NSColor!
@available(macOS 10.14, *)
fileprivate var filterIconColor: NSColor!

@available(macOS 10.14, *)
private func recomputeCustomColors() {
  nonConfTextColor = .controlAccentColor.blended(withFraction: blendFraction, of: .textColor)!
  pluginIconColor = .controlAccentColor.blended(withFraction: blendFraction, of: .textColor)!
  libmpvIconColor = .controlAccentColor.blended(withFraction: blendFraction, of: .textColor)!
  filterIconColor = .controlAccentColor.blended(withFraction: blendFraction, of: .textColor)!
}

fileprivate let keyColumnIndex = 0
fileprivate let actionColumnIndex = 2
fileprivate let draggingFormation: NSDraggingFormation = .default
fileprivate let defaultDragOperation = NSDragOperation.move

class BindingTableViewController: NSObject {

  private unowned var tableView: EditableTableView!

  private var bindingTableState: BindingTableState {
    return BindingTableState.current
  }

  private var selectionDidChangeHandler: () -> Void
  private var distObservers: [NSObjectProtocol] = []
  private var observers: [NSObjectProtocol] = []

  private var draggedRowInfo: (Int, IndexSet)? = nil

  init(_ bindingTableView: EditableTableView, selectionDidChangeHandler: @escaping () -> Void) {
    self.tableView = bindingTableView
    self.selectionDidChangeHandler = selectionDidChangeHandler

    super.init()
    tableView.dataSource = self
    tableView.delegate = self
    tableView.editableDelegate = self

    tableView.menu = NSMenu()
    tableView.menu?.delegate = self

    tableView.allowsMultipleSelection = true
    tableView.editableTextColumnIndexes = [keyColumnIndex, actionColumnIndex]
    tableView.registerTableUIChangeObserver(forName: .iinaPendingUIChangeForBindingTable)
    if #available(macOS 10.14, *) {
      recomputeCustomColors()
      distObservers.append(DistributedNotificationCenter.default().addObserver(forName: .appleColorPreferencesChangedNotification, object: nil, queue: .main, using: self.uiSettingsDidChange))
    }
    observers.append(NotificationCenter.default.addObserver(forName: .iinaKeyBindingErrorOccurred, object: nil, queue: .main, using: errorDidOccur))
    if #available(macOS 10.13, *) {
      var acceptableDraggedTypes: [NSPasteboard.PasteboardType] = [.iinaKeyMapping]
      if Preference.bool(for: .acceptRawTextAsKeyBindings) {
        acceptableDraggedTypes.append(.string)
      }
      tableView.registerForDraggedTypes(acceptableDraggedTypes)
      tableView.setDraggingSourceOperationMask([defaultDragOperation], forLocal: false)
      tableView.draggingDestinationFeedbackStyle = .regular
    }

    if bindingTableState.appInputConfig.version < AppInputConfig.current.version {
      Logger.log("Binding table is out of date. Requesting rebuild")
      AppInputConfig.rebuildCurrent()
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
    Logger.log("Detected change system color prefs; reloading Binding table", level: .verbose)
    recomputeCustomColors()
    self.tableView.reloadExistingRows(reselectRowsAfter: true)
  }

  // Display error alert for errors:
  private func errorDidOccur(_ notification: Notification) {
    guard let alertInfo = notification.object as? Utility.AlertInfo else {
      Logger.log("Notification \(notification.name.rawValue.quoted): cannot display error: invalid object: \(type(of: notification.object))", level: .error)
      return
    }
    Utility.showAlert(alertInfo.key, arguments: alertInfo.args, sheetWindow: self.tableView.window)
  }
}

// MARK: NSTableViewDelegate

extension BindingTableViewController: NSTableViewDelegate {

  @objc func tableViewSelectionDidChange(_ notification: Notification) {
    selectionDidChangeHandler()
  }

  // Disalllow certain row indexes to be selected when user tries to perform a selection
  @objc func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {
    var approvedSelectionIndexes = IndexSet()
    for index in proposedSelectionIndexes {
      if let row = bindingTableState.getDisplayedRow(at: index), row.canBeModified {
        approvedSelectionIndexes.insert(index)
      }
    }
    return approvedSelectionIndexes
  }

  /**
   Make cell view when asked
   */
  @objc func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let bindingRow = bindingTableState.getDisplayedRow(at: row) else {
      return nil
    }

    guard let identifier = tableColumn?.identifier else { return nil }

    guard let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView else {
      return nil
    }
    let columnName = identifier.rawValue

    switch columnName {
      case "keyColumn":
        let stringValue = bindingRow.getKeyColumnDisplay(raw: isRaw)
        setFormattedText(for: cell, to: stringValue, isEnabled: bindingRow.isEnabled, origin: bindingRow.origin)
        return cell

      case "actionColumn":
        let stringValue = bindingRow.getActionColumnDisplay(raw: isRaw)
        setFormattedText(for: cell, to: stringValue, isEnabled: bindingRow.isEnabled, origin: bindingRow.origin, italic: !bindingRow.canBeModified)
        return cell

      case "statusColumn":
        cell.toolTip = bindingRow.displayMessage

        if let imageView: NSImageView = cell.imageView {
          if #available(macOS 11.0, *) {
            imageView.isHidden = false

            if !bindingRow.isEnabled {
              imageView.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)!
              imageView.contentTintColor = NSColor.systemRed
              return cell
            }

            switch bindingRow.origin {
              case .iinaPlugin:
                imageView.image = NSImage(systemSymbolName: "powerplug.fill", accessibilityDescription: nil)!
                imageView.contentTintColor = pluginIconColor
              case .libmpv:
                imageView.image = NSImage(systemSymbolName: "applescript.fill", accessibilityDescription: nil)!
                imageView.contentTintColor = libmpvIconColor
              case .savedFilter:
                imageView.image = NSImage(systemSymbolName: "camera.filters", accessibilityDescription: nil)!
                imageView.contentTintColor = filterIconColor
              default:
                if bindingRow.menuItem != nil {
                  imageView.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: nil)!
                } else {
                  imageView.image = nil
                }
                imageView.contentTintColor = NSColor.controlTextColor
            }
          } else {
            // FIXME: find icons to use so that all versions are supported
            imageView.isHidden = true
          }
        }

        return cell

      default:
        Logger.log("Unrecognized column: '\(columnName)'", level: .error)
        return nil
    }
  }

  private func setFormattedText(for cell: NSTableCellView, to stringValue: String, isEnabled: Bool, origin: InputBindingOrigin, italic: Bool = false) {
    guard let textField = cell.textField else { return }

    if isEnabled {
      var textColor: NSColor
      if #available(macOS 10.14, *) {
        textColor = nonConfTextColor
      } else {
        textColor = .linkColor
      }

      textField.setFormattedText(stringValue: stringValue, textColor: origin == InputBindingOrigin.confFile ? nil : textColor, italic: italic)
    } else {
      textField.setFormattedText(stringValue: stringValue, textColor: NSColor.systemRed, strikethrough: true, italic: italic)
    }
  }

  private var isRaw: Bool {
    return Preference.bool(for: .displayKeyBindingRawValues)
  }

  private var selectedRows: [InputBinding] {
    Array(tableView.selectedRowIndexes.compactMap( { bindingTableState.getDisplayedRow(at: $0) }))
  }

  private var selectedCopiableRows: [InputBinding] {
    self.selectedRows.filter({ $0.canBeCopied })
  }

  private var selectedModifiableRows: [InputBinding] {
    self.selectedRows.filter({ $0.canBeModified })
  }
}

// MARK: NSTableViewDataSource

extension BindingTableViewController: NSTableViewDataSource {
  /*
   Tell AppKit the number of rows when it asks
   */
  @objc func numberOfRows(in tableView: NSTableView) -> Int {
    return bindingTableState.displayedRowCount
  }

  // MARK: Drag & Drop

  /*
   Drag start: define which operations are allowed, and in which contexts
   */
  @objc func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    session.draggingFormation = draggingFormation

    switch(context) {
      case .withinApplication:
        return .copy.union(.move)
      case .outsideApplication:
        return .copy
      default:
        return .copy
    }
  }

  /*
   Drag start: convert tableview rows to clipboard items
   */
  @objc func tableView(_ tableView: NSTableView, pasteboardWriterForRow rowIndex: Int) -> NSPasteboardWriting? {
    let row = bindingTableState.getDisplayedRow(at: rowIndex)
    if let row = row, row.canBeCopied {
      return row.keyMapping
    }
    return nil
  }

  /*
   Drag start: set session variables.
   */
  @objc func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                       willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
    self.draggedRowInfo = (session.draggingSequenceNumber, rowIndexes)
    self.tableView.setDraggingImageToAllColumns(session, screenPoint, rowIndexes)
  }

  /**
   This is implemented to support dropping items onto the Trash icon in the Dock.
   */
  @objc func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    guard !bindingTableState.inputConfFile.isReadOnly && operation == NSDragOperation.delete else {
      return
    }

    let mappings = KeyMapping.deserializeList(from: session.draggingPasteboard)

    guard !mappings.isEmpty else {
      return
    }

    guard let (sequenceNumber, draggedRowIndexes) = self.draggedRowInfo,
          session.draggingSequenceNumber == sequenceNumber
            && mappings.count == draggedRowIndexes.count else {
      Logger.log("Cancelling drop: dragged data does not match!", level: .error)
      return
    }

    Logger.log("User dragged to the trash: \(mappings)", level: .verbose)
    // TODO: this is the wrong animation
    NSAnimationEffect.disappearingItemDefault.show(centeredAt: screenPoint, size: NSSize(width: 50.0, height: 50.0), completionHandler: {
      self.bindingTableState.removeBindings(at: draggedRowIndexes)
    })
  }

  /*
   Validate drop while hovering.
   */
  @objc func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow rowIndex: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {

    guard !bindingTableState.inputConfFile.isReadOnly else {
      return []  // deny drop
    }

    let mappingList = KeyMapping.deserializeList(from: info.draggingPasteboard)

    guard !mappingList.isEmpty else {
      return []  // deny drop
    }

    // Update that little red number:
    info.numberOfValidItemsForDrop = mappingList.count

    // Do not animate the drop; we have the row animations already
    info.animatesToDestination = false

    // Cannot drop on/into existing rows. Change to below it:
    let isAfterNotAt = dropOperation == .on
    // Can only make changes to the "default" section. If the drop cursor is not already inside it,
    // then we'll change it to the nearest valid index in the "default" section.
    let dropTargetRow = bindingTableState.getClosestValidInsertIndex(from: rowIndex, isAfterNotAt: isAfterNotAt)

    tableView.setDropRow(dropTargetRow, dropOperation: .above)

    var dragMask = info.draggingSourceOperationMask
    if dragMask.contains(.every) || dragMask.contains(.generic) {
      dragMask = defaultDragOperation
    }

    if dragMask.contains(.copy) {
      // Explicit copy is ok
      return .copy
    }

    // Dragging table rows within same table?
    if let dragSource = info.draggingSource as? NSTableView, dragSource == self.tableView {
      guard let (sequenceNumber, draggedRowIndexes) = self.draggedRowInfo,
            sequenceNumber == info.draggingSequenceNumber,
            draggedRowIndexes.count == mappingList.count else {
        Logger.log("Denying move within table: dragged data does not match!", level: .error)
        return []
      }
      // Only allow "move" if all dragged rows are editable
      for rowIndex in draggedRowIndexes {
        if !self.bindingTableState.isRowModifiable(rowIndex) {
          return []
        }
      }
      return .move
    }
    // From outside of table -> only copy allowed
    return .copy
  }

  /*
   Accept the drop and execute changes, or reject drop.
   */
  @objc func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row rowIndex: Int, dropOperation: NSTableView.DropOperation) -> Bool {

    let rowList = KeyMapping.deserializeList(from: info.draggingPasteboard)
    Logger.log("User dropped \(rowList.count) binding rows into KeyBinding table \(dropOperation == .on ? "on" : "above") rowIndex \(rowIndex)")
    guard !rowList.isEmpty else {
      return false
    }

    guard dropOperation == .above else {
      Logger.log("KeyBindingTableView: expected dropOperaion==.above but got: \(dropOperation); aborting drop")
      return false
    }

    info.numberOfValidItemsForDrop = rowList.count
    info.draggingFormation = draggingFormation
    info.animatesToDestination = true

    var dragMask = info.draggingSourceOperationMask
    if dragMask.contains(.every) || dragMask.contains(.generic) {
      dragMask = defaultDragOperation
    }

    // Return immediately, and import (or fail to) asynchronously
    if dragMask.contains(.copy) {
      DispatchQueue.main.async {
        self.copyMappings(from: rowList, to: rowIndex, isAfterNotAt: false)
      }
      return true
    } else if dragMask.contains(.move) {
      // Only allow drags from the same table
      guard let dragSource = info.draggingSource as? NSTableView, dragSource == self.tableView else {
        return false
      }
      guard let (sequenceNumber, draggedRowIndexes) = self.draggedRowInfo,
            sequenceNumber == info.draggingSequenceNumber,
            draggedRowIndexes.count == rowList.count else {
        Logger.log("Something went wrong keeping track of moved row indexes! Rejecting drop!", level: .error)
        return false
      }
      // Only allow "move" if all dragged rows are editable
      for rowIndex in draggedRowIndexes {
        if !self.bindingTableState.isRowModifiable(rowIndex) {
          return false
        }
      }
      DispatchQueue.main.async {
        self.moveMappings(from: draggedRowIndexes, to: rowIndex, isAfterNotAt: false)
      }
      return true
    } else {
      Logger.log("Rejecting drop: got unexpected drag mask: \(dragMask)")
      return false
    }
  }
}

// MARK: EditableTableViewDelegate

extension BindingTableViewController: EditableTableViewDelegate {

  func userDidDoubleClickOnCell(row rowIndex: Int, column columnIndex: Int) -> Bool {
    Logger.log("Double-click: Edit requested for row \(rowIndex), col \(columnIndex)")
    return edit(rowIndex: rowIndex, columnIndex: columnIndex, skipInlineEdit: true)
  }

  func userDidPressEnterOnRow(_ rowIndex: Int) -> Bool {
    Logger.log("Enter key: Edit requested for row \(rowIndex)")
    return edit(rowIndex: rowIndex, skipInlineEdit: true)
  }

  func editDidEndWithNewText(newValue: String, row rowIndex: Int, column columnIndex: Int) -> Bool {
    guard bindingTableState.isRowModifiable(rowIndex) else {
      // An error here would be really bad
      Logger.log("Cannot save binding row \(rowIndex): edit is not allowed for this row type! If you see this message please report it.", level: .error)
      return false
    }

    guard let editedRow = bindingTableState.getDisplayedRow(at: rowIndex) else {
      Logger.log("userDidEndEditing(): failed to get row \(rowIndex) (newValue='\(newValue)')")
      return false
    }

    Logger.log("User finished editing value for row \(rowIndex), col \(columnIndex): \(newValue.quoted)", level: .verbose)

    let rawKey, rawAction: String?
    var isIINA: Bool? = nil
    switch columnIndex {
      case keyColumnIndex:
        rawKey = KeyCodeHelper.escapeReservedMpvKeys(newValue)
        rawAction = nil
      case actionColumnIndex:
        rawKey = nil
        if let trimmedValue = KeyMapping.removeIINAPrefix(from: newValue) {
          isIINA = true
          rawAction = trimmedValue
        } else {
          isIINA = false
          rawAction = newValue
        }
      default:
        Logger.log("userDidEndEditing(): bad column index: \(columnIndex)")
        return false
    }

    let newVersion = editedRow.keyMapping.clone(rawKey: rawKey, rawAction: rawAction, isIINACommand: isIINA)
    bindingTableState.updateBinding(at: rowIndex, to: newVersion)
    return true
  }

  // MARK: Reusable actions

  // Edit either inline or with popup, depending on current mode
  @discardableResult
  private func edit(rowIndex: Int, columnIndex: Int = 0, skipInlineEdit: Bool = false) -> Bool {
    guard requireCurrentConfIsEditable(forAction: "edit row") else { return false }

    guard bindingTableState.isRowModifiable(rowIndex) else {
      // Should never see this message
      Logger.log("Cannot edit binding row \(rowIndex): row cannot be modified! Aborting", level: .error)
      return false
    }

    if isRaw {
      if !skipInlineEdit {
        // Use in-line editor
        self.tableView.editCell(row: rowIndex, column: columnIndex)
      }
      return true
    } else {
      editWithPopup(rowIndex: rowIndex)
      return false
    }
  }

  // Use this if isRaw==false (i.e., not inline editing)
  private func editWithPopup(rowIndex: Int) {
    Logger.log("Opening key binding pop-up for row #\(rowIndex)", level: .verbose)

    guard let row = bindingTableState.getDisplayedRow(at: rowIndex) else {
      return
    }

    showEditBindingPopup(key: row.keyMapping.rawKey, action: row.keyMapping.readableAction, ok: { rawKey, rawAction, isIINACommand in
      let newVersion = row.keyMapping.clone(rawKey: rawKey, rawAction: rawAction, isIINACommand: isIINACommand)
      self.bindingTableState.updateBinding(at: rowIndex, to: newVersion)
    })
  }

  // Adds a new binding after the current selection and then opens an editor for it. The editor with either be inline or using the popup,
  // depending on whether isRaw is true or false, respectively.
  func addNewBinding() {
    var rowIndex: Int
    // If there are selected rows, add the new row right below the last selection. Otherwise add to end of table.
    if let lastSelectionIndex = tableView.selectedRowIndexes.max() {
      rowIndex = lastSelectionIndex
    } else {
      rowIndex = self.tableView.numberOfRows - 1
    }
    editNewEmptyBinding(relativeTo: rowIndex, isAfterNotAt: true)
  }

  // Adds a new binding at the given location then opens an editor for it. The editor with either be inline or using the popup,
  // depending on whether isRaw is true or false, respectively.
  // If isAfterNotAt==true, inserts after the row with given rowIndex. If isAfterNotAt==false, inserts before the row with given rowIndex.
  private func editNewEmptyBinding(relativeTo rowIndex: Int, isAfterNotAt: Bool = false) {
    guard requireCurrentConfIsEditable(forAction: "insert binding") else { return }

    Logger.log("Inserting new binding \(isAfterNotAt ? "after" : "at") current row index: \(rowIndex)", level: .verbose)

    if isRaw {
      // The table will execute asynchronously, but we need to wait for it to complete in order to guarantee we have something to edit
      let afterComplete: TableUIChange.CompletionHandler = { tableUIChange in
        // We don't know beforehand exactly which row it will end up at, but we can get this info from the TableUIChange object
        if let insertedRowIndex = tableUIChange.toInsert?.first {
          self.tableView.editCell(row: insertedRowIndex, column: 0)
        }
      }
      let newMapping = KeyMapping(rawKey: "", rawAction: "")
      let _ = bindingTableState.insertNewBinding(relativeTo: rowIndex, isAfterNotAt: isAfterNotAt, newMapping, afterComplete: afterComplete)

    } else {
      showEditBindingPopup(ok: { rawKey, rawAction, isIINACommand in
        let newMapping = KeyMapping(rawKey: rawKey, rawAction: rawAction, isIINACommand: isIINACommand)
        self.bindingTableState.insertNewBinding(relativeTo: rowIndex, isAfterNotAt: isAfterNotAt, newMapping,
                                                afterComplete: self.scrollToFirstInserted)
      })
    }
  }

  // Displays popup for editing a binding
  private func showEditBindingPopup(key: String = "", action: String = "", ok: @escaping (String, String, Bool) -> Void) {
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
    panel.beginSheetModal(for: tableView.window!) { respond in
      if respond == .alertFirstButtonReturn {
        let enteredKey = keyRecordViewController.keyCode
        let readableAction = keyRecordViewController.action
        let rawAction: String
        let isIINACommand: Bool

        // Do some processing on the entered values before returning:
        let rawKey = KeyCodeHelper.escapeReservedMpvKeys(enteredKey)
        if let trimmedAction = KeyMapping.removeIINAPrefix(from: readableAction) {
          rawAction = trimmedAction
          isIINACommand = true
        } else {
          rawAction = readableAction
          isIINACommand = false
        }
        ok(rawKey, rawAction, isIINACommand)
      }
    }
  }

  // e.g., drag & drop "copy" operation
  private func copyMappings(from mappingList: [KeyMapping], to rowIndex: Int, isAfterNotAt: Bool = false) {
    guard requireCurrentConfIsEditable(forAction: "move binding(s)") else { return }
    guard !mappingList.isEmpty else { return }

    // Make sure to use copy() to clone the object here
    let newMappings: [KeyMapping] = mappingList.map { $0.clone() }

    bindingTableState.insertNewBindings(relativeTo: rowIndex, isAfterNotAt: isAfterNotAt, newMappings,
                                                                    afterComplete: scrollToFirstInserted)
  }

  // e.g., drag & drop "move" operation
  private func moveMappings(from rowIndexes: IndexSet, to rowIndex: Int, isAfterNotAt: Bool = false) {
    guard requireCurrentConfIsEditable(forAction: "move binding(s)") else { return }
    guard !rowIndexes.isEmpty else { return }

    let firstInsertedRowIndex = bindingTableState.moveBindings(from: rowIndexes, to: rowIndex, isAfterNotAt: isAfterNotAt,
                                                               afterComplete: self.scrollToFirstInserted)
    self.tableView.scrollRowToVisible(firstInsertedRowIndex)
  }

  // Each TableUpdate executes asynchronously, but we need to wait for it to complete in order to do any further work on
  // inserted rows.
  private func scrollToFirstInserted(_ tableUIChange: TableUIChange) {
    if let firstInsertedRowIndex = tableUIChange.toInsert?.first {
      self.tableView.scrollRowToVisible(firstInsertedRowIndex)
    }
  }

  func removeSelectedBindings() {
    Logger.log("Removing selected bindings", level: .verbose)
    bindingTableState.removeBindings(at: tableView.selectedRowIndexes)
  }

  private func requireCurrentConfIsEditable(forAction action: String) -> Bool {
    if !bindingTableState.inputConfFile.isReadOnly {
      return true
    }

    // Should never see this ideally. If we do, something went wrong with UI enablement.
    Logger.log("Cannot \(action): cannot modify a default config. Telling user to duplicate the config instead", level: .verbose)
    Utility.showAlert("duplicate_config", sheetWindow: tableView.window)
    return false
  }

  // MARK: Cut, copy, paste, delete support.

  // Only selected table items which have `canBeModified==true` can be included.
  // Each menu item should be disabled if it cannot operate on at least one item.

  func isCopyEnabled() -> Bool {
    return !selectedCopiableRows.isEmpty
  }

  func isCutEnabled() -> Bool {
    return isDeleteEnabled()
  }

  func isDeleteEnabled() -> Bool {
    return !bindingTableState.inputConfFile.isReadOnly && !selectedModifiableRows.isEmpty
  }

  func isPasteEnabled() -> Bool {
    return !bindingTableState.inputConfFile.isReadOnly && !readBindingsFromClipboard().isEmpty
  }

  func doEditMenuCut() {
    if copyToClipboard() {
      removeSelectedBindings()
    }
  }

  func doEditMenuCopy() {
    _ = copyToClipboard()
  }

  func doEditMenuPaste() {
    // default to *after* current selection
    if let desiredInsertIndex = self.tableView.selectedRowIndexes.last {
      pasteFromClipboard(relativeTo: desiredInsertIndex, isAfterNotAt: true)
    } else {
      pasteFromClipboard(relativeTo: self.tableView.numberOfRows, isAfterNotAt: true)
    }
  }

  func doEditMenuDelete() {
    removeSelectedBindings()
  }

  // If `rowsToCopy` is specified, copies it to the Clipboard.
  // If it is not specified, uses the currently selected rows
  // Returns `true` if it copied at least 1 row; `false` if not
  private func copyToClipboard(rowsToCopy: [InputBinding]? = nil) -> Bool {
    let rows: [InputBinding]
    if let rowsToCopy = rowsToCopy {
      rows = rowsToCopy.filter({ $0.canBeCopied })
    } else {
      rows = self.selectedCopiableRows
    }

    if rows.isEmpty {
      Logger.log("No bindings to copy: not touching clipboard", level: .verbose)
      return false
    }

    let mappings = rows.map { $0.keyMapping }

    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects(mappings)
    Logger.log("Copied \(rows.count) bindings to the clipboard", level: .verbose)
    return true
  }

  private func pasteFromClipboard(relativeTo rowIndex: Int, isAfterNotAt: Bool = false) {
    let mappingsToInsert = readBindingsFromClipboard()
    guard !mappingsToInsert.isEmpty else {
      Logger.log("Aborting Paste action because there is nothing to paste", level: .warning)
      return
    }
    Logger.log("Pasting \(mappingsToInsert.count) bindings \(isAfterNotAt ? "after" : "at") index \(rowIndex)")
    bindingTableState.insertNewBindings(relativeTo: rowIndex, isAfterNotAt: isAfterNotAt, mappingsToInsert,
                                        afterComplete: self.scrollToFirstInserted)
  }

  func readBindingsFromClipboard() -> [KeyMapping] {
    return KeyMapping.deserializeList(from: NSPasteboard.general)
  }
}

// MARK: NSMenuDelegate

extension BindingTableViewController: NSMenuDelegate {

  fileprivate class BindingMenuItem: NSMenuItem {
    let row: InputBinding
    let rowIndex: Int

    public init(_ row: InputBinding, rowIndex: Int, title: String, action selector: Selector?, key: String = "") {
      self.row = row
      self.rowIndex = rowIndex
      super.init(title: title, action: selector, keyEquivalent: key)
    }

    required init(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }

  fileprivate class BindingMenuItemProvider: MenuItemProvider {
    func buildItem(_ title: String, action: Selector?, targetRow: Any, key: String, _ cmb: CascadingMenuItemBuilder) throws -> NSMenuItem {
      let targetRowIndex: Int = try cmb.requireAttr(.targetRowIndex)
      return BindingMenuItem(targetRow as! InputBinding, rowIndex: targetRowIndex, title: title, action: action, key: key)
    }
  }

  private func addReadOnlyConfMenuItem(_ mib: CascadingMenuItemBuilder) {
    mib.addItalicDisabledItem("Cannot make changes: \(bindingTableState.inputConfFile.confName.quoted) is a built-in config")
  }

  func menuNeedsUpdate(_ contextMenu: NSMenu) {
    // This will prevent menu from showing if no items are added
    contextMenu.removeAllItems()

    let clickedRowIndex = tableView.clickedRow
    guard let clickedRow = bindingTableState.getDisplayedRow(at: tableView.clickedRow) else { return }
    let mib = CascadingMenuItemBuilder(mip: BindingMenuItemProvider(), .menu(contextMenu), .unit(Unit.keyBinding),
                                .targetRow(clickedRow), .targetRowIndex(tableView.clickedRow), .target(self))

    if tableView.selectedRowIndexes.count > 1 && tableView.selectedRowIndexes.contains(clickedRowIndex) {
      buildMenu(mib.butWith(.unitCount(tableView.selectedRowIndexes.count)), for: tableView.selectedRowIndexes)
    } else {
      buildMenuForSingleRow(mib.butWith(.unitCount(1)), clickedRow, clickedRowIndex)
    }
  }

  // SINGLE: For right-click on a single row. This may be selected, if it is the only row in the selection.
  private func buildMenuForSingleRow(_ mib: CascadingMenuItemBuilder, _ clickedRow: InputBinding, _ clickedRowIndex: Int) {
    let isSelectedConfReadOnly = bindingTableState.inputConfFile.isReadOnly
    let isRowEditable = !isSelectedConfReadOnly && clickedRow.canBeModified

    if isSelectedConfReadOnly {
      addReadOnlyConfMenuItem(mib)
    } else if !isRowEditable {
      let culprit: String
      switch clickedRow.origin {
        case .iinaPlugin:
          let sourceName = (clickedRow.keyMapping as? MenuItemMapping)?.sourceName ?? "<ERROR>"
          culprit = "the IINA plugin \(sourceName.quoted)"
        case .savedFilter:
          let sourceName = (clickedRow.keyMapping as? MenuItemMapping)?.sourceName ?? "<ERROR>"
          culprit = "the saved filter \(sourceName.quoted)"
        case .libmpv:
          culprit = "a Lua script or other mpv interface"
        default:
          Logger.log("Unrecognized binding origin for rowIndex \(clickedRowIndex): \(clickedRow.origin)", level: .error)
          culprit = "<unknown>"
      }
      mib.addItalicDisabledItem("Cannot modify binding: it is owned by \(culprit)")
    } else {
      // Edit options
      if isRaw {
        mib.addItem("Edit Key", #selector(self.editKeyColumn(_:)), with: .key(KeyCodeHelper.KeyEquivalents.RETURN), .keyMods([]))
        mib.addItem("Edit Action", #selector(self.editActionColumn(_:)))
      } else {
        mib.addItem("Edit Row...", #selector(self.editRow(_:)), with: .key(KeyCodeHelper.KeyEquivalents.RETURN), .keyMods([]))
      }
    }

    // ---
    mib.addSeparator()

    // Cut, Copy, Paste, Delete
    mib.likeEditCut().butWith(.action(#selector(self.cutRow(_:))), .enabled(isRowEditable)).addItem()
    mib.likeEditCopy().butWith(.action(#selector(self.copyRow(_:))), .enabled(clickedRow.canBeCopied)).addItem()

    let clipboardCount = readBindingsFromClipboard().count
    let isPasteEnabled = !isSelectedConfReadOnly && clipboardCount > 0
    let pb = mib.butWith(.unitCount(clipboardCount), .enabled(isPasteEnabled))
    if !isPasteEnabled {
      pb.likeEditPaste().addItem()
    } else if isRowEditable {
      pb.likePasteAbove().butWith(.action(#selector(self.pasteAbove(_:))), .key("")).addItem()  // let the row below use the key equivalent
      pb.likePasteBelow().butWith(.action(#selector(self.pasteBelow(_:)))).addItem()
    } else {
      // If current row is not editable, a new row can only be added in the direction of the editable rows ("default" section).
      let isAfterNotAt = bindingTableState.getClosestValidInsertIndex(from: clickedRowIndex) > clickedRowIndex
      if isAfterNotAt {
        pb.likePasteBelow().butWith(.action(#selector(self.pasteBelow(_:)))).addItem()
      } else {
        pb.likePasteAbove().butWith(.action(#selector(self.pasteAbove(_:)))).addItem()
      }
    }

    // ---
    mib.addSeparator()

    mib.likeEasyDelete().butWith(.action(#selector(self.removeRow(_:))), .enabled(isRowEditable)).addItem()

    // ---
    mib.addSeparator()

    // Insert New: follow same logic as Paste, except don't show at all if disabled
    if !isSelectedConfReadOnly {
      if isRowEditable {
        mib.addItem(with: .unitActionFormat(UnitActionFormat.insertNewAbove), .action(#selector(self.addNewRowAbove(_:))))
        mib.addItem(with: .unitActionFormat(UnitActionFormat.insertNewBelow), .action(#selector(self.addNewRowBelow(_:))))
      } else {
        // If current row is not editable, a new row can only be added in the direction of the editable rows ("default" section).
        let isAfterNotAt = bindingTableState.getClosestValidInsertIndex(from: clickedRowIndex) > clickedRowIndex
        if isAfterNotAt {
          mib.addItem(with: .unitActionFormat(UnitActionFormat.insertNewBelow), .action(#selector(self.addNewRowBelow(_:))))
        } else {
          mib.addItem(with: .unitActionFormat(UnitActionFormat.insertNewAbove), .action(#selector(self.addNewRowAbove(_:))))
        }
      }
    }
  }

  // MULTIPLE: For right-click on selected rows
  private func buildMenu(_ mib: CascadingMenuItemBuilder, for selectedRowIndexes: IndexSet) {
    let selectedRowsCount = tableView.selectedRowIndexes.count

    var modifiableCount = 0
    var copyableCount = 0
    for rowIndex in tableView.selectedRowIndexes {
      if let bindingRow = bindingTableState.getDisplayedRow(at: rowIndex) {
        if bindingRow.canBeCopied {
          copyableCount += 1
        }
        if bindingRow.canBeModified {
          modifiableCount += 1
        }
      }
    }

    // Add disabled italicized message if not all can be operated on
    if bindingTableState.inputConfFile.isReadOnly {
      modifiableCount = 0
      addReadOnlyConfMenuItem(mib)
    } else {
      let readOnlyCount = tableView.selectedRowIndexes.count - modifiableCount
      if readOnlyCount > 0 {
        let readOnlyDisclaimer: String
        if readOnlyCount == selectedRowsCount {
          readOnlyDisclaimer = "\(readOnlyCount) bindings are read-only"
        } else {
          readOnlyDisclaimer = "\(readOnlyCount) of \(selectedRowsCount) bindings are read-only"
        }
        mib.addItalicDisabledItem(readOnlyDisclaimer)
      }
    }

    // ---
    mib.addSeparator()

    // Cut, Copy, Paste, Delete

    // By setting target:`tableView`, AppKit, will call `tableView.validateUserInterfaceItem()` to enable/disable each action appropriately
    let mibEditOps = mib.butWith(.target(self.tableView))
    mibEditOps.likeEditCut().addItem(#selector(self.tableView.cut(_:)))
    mibEditOps.likeEditCopy().addItem(#selector(self.tableView.copy(_:)))

    // Paste is enabled if file is editable & there are bindings in the clipboard; doesn't matter if selected rows are editable
    let mibPaste = mib.butWith(.unitCount(readBindingsFromClipboard().count), .enabled(true))
    if isPasteEnabled() {
      var shouldAddAbove = false
      var shouldAddBelow = true

      let firstSelectedIndex = (tableView.selectedRowIndexes.first ?? 0)
      if bindingTableState.getClosestValidInsertIndex(from: firstSelectedIndex) <= firstSelectedIndex {
        shouldAddAbove = true
      }

      let lastSelectedIndex = tableView.selectedRowIndexes.last ?? tableView.numberOfRows
      if bindingTableState.getClosestValidInsertIndex(from: lastSelectedIndex, isAfterNotAt: true) >= lastSelectedIndex {
        shouldAddBelow = true
      }

      if shouldAddAbove {
        // Can't have two items with the same key equiv. When in doubt give it to "Below" item because that's what Paste defaults to.
        let mib = shouldAddBelow ? mibPaste.butWith(.key("")) : mibPaste
        mib.likePasteAbove().butWith(.targetRowIndex(firstSelectedIndex)).addItem(#selector(self.pasteAbove(_:)))
      }

      if shouldAddBelow {
        mibPaste.likePasteBelow().butWith(.targetRowIndex(lastSelectedIndex)).addItem(#selector(self.pasteBelow(_:)))
      }
    } else {
      mibPaste.likeEditPaste().butWith(.action(nil), .enabled(false)).addItem()
    }

    // ---
    mib.addSeparator()

    mibEditOps.likeEasyDelete().addItem(#selector(self.tableView.delete(_:)))
  }

  @objc fileprivate func editKeyColumn(_ sender: BindingMenuItem) {
    edit(rowIndex: sender.rowIndex, columnIndex: keyColumnIndex)
  }

  @objc fileprivate func editActionColumn(_ sender: BindingMenuItem) {
    edit(rowIndex: sender.rowIndex, columnIndex: actionColumnIndex)
  }

  @objc fileprivate func editRow(_ sender: BindingMenuItem) {
    edit(rowIndex: sender.rowIndex)
  }

  @objc fileprivate func addNewRowAbove(_ sender: BindingMenuItem) {
    editNewEmptyBinding(relativeTo: sender.rowIndex, isAfterNotAt: false)
  }

  @objc fileprivate func addNewRowBelow(_ sender: BindingMenuItem) {
    editNewEmptyBinding(relativeTo: sender.rowIndex, isAfterNotAt: true)
  }

  // Similar to Edit menu operations, but operating on a single non-selected row:
  @objc fileprivate func cutRow(_ sender: BindingMenuItem) {
    if copyToClipboard(rowsToCopy: [sender.row]) {
      bindingTableState.removeBindings(at: IndexSet(integer: sender.rowIndex))
    }
  }

  @objc fileprivate func copyRow(_ sender: BindingMenuItem) {
    _ = copyToClipboard(rowsToCopy: [sender.row])
  }

  @objc fileprivate func pasteAbove(_ sender: BindingMenuItem) {
    pasteFromClipboard(relativeTo: sender.rowIndex, isAfterNotAt: false)
  }

  @objc fileprivate func pasteBelow(_ sender: BindingMenuItem) {
    pasteFromClipboard(relativeTo: sender.rowIndex, isAfterNotAt: true)
  }

  @objc fileprivate func removeRow(_ sender: BindingMenuItem) {
    bindingTableState.removeBindings(at: IndexSet(integer: sender.rowIndex))
  }
}
