//
//  EditableTableView.swift
//  iina
//
//  Created by Matt Svoboda on 2022.06.23.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class EditableTableView: NSTableView {

  // Can be overridden by each TableUIChange if set there
  var rowInsertAnimation: NSTableView.AnimationOptions = .slideUp
  var rowRemoveAnimation: NSTableView.AnimationOptions = .slideDown

  // Must provide this for editCell() to work
  var editableTextColumnIndexes: [Int] = []

  // Must provide this for EditableTableView extended functionality
  var editableDelegate: EditableTableViewDelegate? = nil {
    didSet {
      if let editableDelegate = editableDelegate {
        cellEditTracker = CellEditTracker(parentTable: self, delegate: editableDelegate)
      } else {
        cellEditTracker = nil
      }
    }
  }

  private var cellEditTracker: CellEditTracker? = nil
  private var lastEditedTextField: EditableTextField? = nil
  private var observers: [NSObjectProtocol] = []

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []
  }

  // MARK: Edit menu > Cut, Copy, Paste, Delete

  @objc func copy(_ sender: AnyObject?) {
    editableDelegate?.doEditMenuCopy()
  }

  @objc func cut(_ sender: AnyObject?) {
    editableDelegate?.doEditMenuCut()
  }

  @objc func paste(_ sender: AnyObject?) {
    editableDelegate?.doEditMenuPaste()
  }

  @objc func delete(_ sender: AnyObject?) {
    editableDelegate?.doEditMenuDelete()
  }

  // According to ancient Apple docs, the following is also called for toolbar items:
  override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
    let actionDescription = item.action == nil ? "nil" : "\(item.action!)"
    guard let delegate = self.editableDelegate else {
      Logger.log("EditableTableView.validateUserInterfaceItem(): no delegate! Disabling \"\(actionDescription)\"", level: .warning)
      return false
    }

    var isAllowed = false
    switch item.action {
      case #selector(copy(_:)):
        isAllowed = delegate.isCopyEnabled()
      case #selector(cut(_:)):
        isAllowed = delegate.isCutEnabled()
      case #selector(paste(_:)):
        isAllowed = delegate.isPasteEnabled()
      case #selector(delete(_:)):
        isAllowed = delegate.isDeleteEnabled()
      case #selector(selectAll(_:)):
        isAllowed = delegate.isSelectAllEnabled()
      default:
        Logger.log("EditableTableView.validateUserInterfaceItem(): defaulting isAllowed=false for \"\(actionDescription)\"", level: .verbose)
        return false
    }
    Logger.log("EditableTableView.validateUserInterfaceItem(): isAllowed=\(isAllowed) for \"\(actionDescription)\"", level: .verbose)
    return isAllowed
  }

  // MARK: In-line cell editing

  override func keyDown(with event: NSEvent) {
    if let keyChar = KeyCodeHelper.keyMap[event.keyCode]?.0 {
      switch keyChar {
        case "ENTER", "KP_ENTER":
          if selectedRow >= 0 && selectedRow < numberOfRows && !editableTextColumnIndexes.isEmpty {
            if let delegate = self.editableDelegate, delegate.userDidPressEnterOnRow(selectedRow) {
              Logger.log("TableView.KeyDown: \(keyChar) on row \(selectedRow)")
              editCell(row: selectedRow, column: editableTextColumnIndexes[0])
              return
            }
          }
        default:
          break
      }
    }
    super.keyDown(with: event)
  }

  override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
    if let event = event, event.type == .leftMouseDown, event.modifierFlags.isEmpty {
      if let editableTextField = responder as? EditableTextField, let cellEditTracker = cellEditTracker {
        // Unortunately, the event with event.clickCount==2 does not seem to present itself here.
        // Workaround: pass everything to the EditableTextField, which does see double-click.
        if let locationInTable = self.window?.contentView?.convert(event.locationInWindow, to: self) {
          let clickedRow = self.row(at: locationInTable)
          let clickedColumn = self.column(at: locationInTable)
          // qualifies!
          cellEditTracker.changeCurrentCell(to: editableTextField, row: clickedRow, column: clickedColumn)
          return true
        }
      }
    }

    return super.validateProposedFirstResponder(responder, for: event)
  }

  override func becomeFirstResponder() -> Bool {
    // If user types ESC key while is FieldEditor, it goes straight here instead of notifying its text field.
    if let cellEditTracker = cellEditTracker {
      cellEditTracker.endEdit()
    }
    return true
  }

  // Convenience method
  func editCell(row rowIndex: Int, column columnIndex: Int) {
    guard let cellEditTracker = cellEditTracker else {
      return
    }

    guard rowIndex >= 0 && columnIndex >= 0 else {
      Logger.log("Discarding request to edit cell: rowIndex (\(rowIndex)) or columnIndex (\(columnIndex)) is less than 0", level: .error)
      return
    }
    guard rowIndex < numberOfRows else {
      Logger.log("Discarding request to edit cell: rowIndex (\(rowIndex)) cannot be >= numberOfRows (\(numberOfRows))", level: .error)
      return
    }
    guard columnIndex < numberOfColumns else {
      Logger.log("Discarding request to edit cell: columnIndex (\(columnIndex)) cannot be >= numberOfColumns (\(numberOfColumns))", level: .error)
      return
    }

    guard let view = self.view(atColumn: columnIndex, row: rowIndex, makeIfNecessary: true),
          let cellView = view as? NSTableCellView,
          let editableTextField = cellView.textField as? EditableTextField else {
      return
    }

    Logger.log("EditableTableView: Opening inline editor for row \(rowIndex), col \(columnIndex)", level: .verbose)

    self.scrollRowToVisible(rowIndex)
    cellEditTracker.changeCurrentCell(to: editableTextField, row: rowIndex, column: columnIndex)

    if self.selectedRow != rowIndex {
      Logger.log("Selecting edit row: \(rowIndex)", level: .verbose)
      self.selectApprovedRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
    }

    self.window?.makeFirstResponder(editableTextField)
  }

  // Convenience function, for debugging
  private func eventTypeText(_ event: NSEvent?) -> String {
    if let event = event {
      switch event.type {
        case .leftMouseDown:
          return "leftMouseDown"
        case .leftMouseUp:
          return "leftMouseUp"
        case .cursorUpdate:
          return "cursorUpdate"
        default:
          return "\(event.type)"
      }
    }
    return "nil"
  }

  // MARK: Misc functions

  // All this garbage is needed just to show all the columns when dragging (instead of just the clicked one)
  func setDraggingImageToAllColumns(_ session: NSDraggingSession, _ dragStartScreenPoint: NSPoint, _ rowIndexes: IndexSet) {
    let rowIndexArray = Array(rowIndexes)

    // Need to convert to TableView's coord system
    guard let window = self.window else { return }
    let dragStartWindowPoint = window.convertPoint(fromScreen: dragStartScreenPoint)
    let dragStartPointInTable = self.convert(dragStartWindowPoint, from: nil)

    var dragStartPointInCell: CGPoint = .zero
    var dragStartColumnIndex = self.column(at: dragStartPointInTable)
    var dragStartRowIndex = self.row(at: dragStartPointInTable)
    if dragStartColumnIndex < 0 || dragStartRowIndex < 0 {
      Logger.log("Failed to get cellView from drag start coordinates! Cannot calculate drag image offset!", level: .error)
      dragStartColumnIndex = 0
      dragStartRowIndex = 0
    } else {
      if let clickedCell = view(atColumn: dragStartColumnIndex, row: dragStartRowIndex, makeIfNecessary: false) {
        dragStartPointInCell = clickedCell.convert(dragStartPointInTable, from: self)
        Logger.log("Drag cell: row \(dragStartRowIndex), col \(dragStartColumnIndex); dragPoint \(dragStartPointInCell)", level: .verbose)
      }
    }

    session.enumerateDraggingItems(options: .clearNonenumeratedImages, for: nil, classes: [NSPasteboardItem.self], searchOptions: [:]) {(draggingItem, rowNumber, stop) in

      draggingItem.imageComponentsProvider = {
        var componentArray: [NSDraggingImageComponent] = []

        guard rowNumber < rowIndexArray.count else { return componentArray }
        let rowIndex = rowIndexArray[rowNumber]

        // First pass: collect components and size information
        var maxRowHeight = self.rowHeight
        var columnOffsets: [CGFloat] = []
        var xOffsets: [CGFloat] = []
        for columnIndex in 0..<self.numberOfColumns {
          // note: keep `makeIfNecessary==false` to prevent drawing items which aren't on the screen
          // (a nice performance improvement, but could be improved visually)
          if let cellView = self.view(atColumn: columnIndex, row: rowIndex, makeIfNecessary: false) as? NSTableCellView {

            if columnIndex == 0 {
              columnOffsets.append(0.0)
            } else {
              let colWidth = self.tableColumns[columnIndex - 1].width + self.intercellSpacing.width
              columnOffsets.append(columnOffsets.last! + colWidth)
            }

            let dragImageComps = cellView.draggingImageComponents
            for (compIndex, comp) in dragImageComps.enumerated() {
              if comp.frame.height > maxRowHeight {
                maxRowHeight = comp.frame.height
              }
              if compIndex == 0 {
                xOffsets.append(columnOffsets.last!)
              } else {
                // Never tested with more than 1 component per column.
                // Probably will need adjusting. At least this shouldn't crash!
                xOffsets.append(xOffsets.last! + dragImageComps[compIndex-1].frame.width)
              }
              componentArray.append(comp)
            }
          }
        }

        // The `draggingFrame` of `draggingItem` uses the coordinate system of the clicked cell by default.
        // Need to convert this...
        let dragStartColumnOffset: CGFloat = columnOffsets[dragStartColumnIndex]

        // Second pass: set offsets and sizes
        for (compArrIndex, comp) in componentArray.enumerated() {
          let yAdjustToCenter = (maxRowHeight - comp.frame.height) / 2
          comp.frame = NSRect(x: xOffsets[compArrIndex] - dragStartColumnOffset, y: yAdjustToCenter, width: comp.frame.width, height: comp.frame.height)
        }

        let draggingFrameOrigin = CGPoint(x: 0.0,
                                          y: 0.0)
        let draggingFrameSize = CGSize(width: self.frame.width,
                                       height: self.rowHeight * CGFloat(rowIndexArray.count))
        draggingItem.draggingFrame = NSRect(origin: draggingFrameOrigin, size: draggingFrameSize)
        Logger.log("DraggingFrame: \(draggingItem.draggingFrame)", level: .verbose)

        Logger.log("Returning \(componentArray.count) draggingImageComponents", level: .verbose)
        return componentArray
      }
    }
  }

  // Use this instead of reloadData() if the table data needs to be reloaded but the row count is the same.
  // This will preserve the selection indexes (whereas reloadData() will not)
  func reloadExistingRows(reselectRowsAfter: Bool, usingNewSelection newRowIndexes: IndexSet? = nil) {
    let selectedRows = newRowIndexes ?? self.selectedRowIndexes
    Logger.log("Reloading existing rows\(reselectRowsAfter ? " (will re-select \(selectedRows) after)" : "")", level: .verbose)
    reloadData(forRowIndexes: IndexSet(0..<numberOfRows), columnIndexes: IndexSet(0..<numberOfColumns))
    if reselectRowsAfter {
      // Fires change listener...
      selectApprovedRowIndexes(selectedRows, byExtendingSelection: false)
    }
  }

  func selectApprovedRowIndexes(_ newSelectedRowIndexes: IndexSet, byExtendingSelection: Bool = false) {
    // It seems that `selectionIndexesForProposedSelection` needs to be called explicitly
    // in order to keep enforcing selection rules.
    if let approvedRows = self.delegate?.tableView?(self, selectionIndexesForProposedSelection: newSelectedRowIndexes) {
      Logger.log("Updating table selection to approved indexes: \(approvedRows.map{$0})", level: .verbose)
      self.selectRowIndexes(approvedRows, byExtendingSelection: byExtendingSelection)
    } else {
      Logger.log("Updating table selection (no approval) to indexes: \(newSelectedRowIndexes.map{$0})", level: .verbose)
      self.selectRowIndexes(newSelectedRowIndexes, byExtendingSelection: byExtendingSelection)
    }
  }

  // MARK: TableUIChange

  func registerTableUIChangeObserver(forName name: Notification.Name) {
    observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main, using: tableShouldChange))
  }

  // Row(s) changed in datasource. Could be insertions, deletions, selection change, etc (see: `ContentChangeType`).
  // This notification contains the information needed to make the updates to the table (see: `TableUIChange`).
  private func tableShouldChange(_ notification: Notification) {
    guard let tableUIChange = notification.object as? TableUIChange else {
      Logger.log("Received \"\(notification.name.rawValue)\" with invalid object: \(type(of: notification.object))", level: .error)
      return
    }

    Logger.log("Received \"\(notification.name.rawValue)\" notification with changeType \(tableUIChange.changeType)", level: .verbose)
    tableUIChange.execute(on: self)
  }
}
