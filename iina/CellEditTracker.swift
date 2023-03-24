//
//  FocusedTableCell.swift
//  iina
//
//  Created by Matt Svoboda on 10/8/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

// Plays the role of mediator: coordinates between EditableTableView and its EditableTextFields, to manage
// in-line cell editing.
class CellEditTracker: NSObject, NSTextFieldDelegate {
  // Stores info for the currently focused cell, whether or not the cell is being edited
  private struct CurrentFocus {
    let textField: EditableTextField
    let stringValueOrig: String
    let row: Int
    let column: Int
    // If true, `current` has had `startEdit()` called but not `endEdit()`:
    let editInProgress: Bool
  }
  private var current: CurrentFocus? = nil

  private let parentTable: EditableTableView
  private let delegate: EditableTableViewDelegate

  init(parentTable: EditableTableView, delegate: EditableTableViewDelegate) {
    self.parentTable = parentTable
    self.delegate = delegate
  }

  private func getTextMovementName(from notification: Notification) -> String {
    guard let textMovementInt = notification.userInfo?["NSTextMovement"] as? Int else {
      return "nil"
    }

    let tm = NSTextMovement(rawValue: textMovementInt)
    switch tm {
    case .return:
      return "return"
    case .backtab:
      return "backtab"
    case .cancel:
      return "cancel"
    case .other:
      return "other"
    case .tab:
      return "tab"
    default:
      return "{\(textMovementInt)}"
    }
  }

  @objc func controlTextDidEndEditing(_ notification: Notification) {
    Logger.log("DidEndEditing (nextNav: \(getTextMovementName(from: notification)))", level: .verbose)

    guard let current = self.current else {
      return
    }

    // Tab / return navigation (if any) will show up in the notification
    if let textMovementInt = notification.userInfo?["NSTextMovement"] as? Int,
       let textMovement = NSTextMovement(rawValue: textMovementInt) {

      self.endEdit()

      DispatchQueue.main.async {
        // Start asynchronously so we can return
        self.editAnotherCellAfterEditEnd(oldRow: current.row, oldColumn: current.column, textMovement)
      }
    } else {
      self.endEdit(closeEditorExplicitly: false)
    }
  }

  func changeCurrentCell(to textField: EditableTextField, row: Int, column: Int) {
    // Close old editor, if any:
    if let prev = self.current {
      if row == prev.row && column == prev.column && textField == prev.textField {
        return
      } else {
        Logger.log("CellEditTracker: changing cell from (\(prev.row), \(prev.column)) to (\(row), \(column))", level: .verbose)
        // Make sure old editor is closed and saved if appropriate:
        endEdit()
      }
    } else {
      Logger.log("CellEditTracker: changing cell to (\(row), \(column))", level: .verbose)
    }
    // keep track of it all
    self.current = CurrentFocus(textField: textField, stringValueOrig: textField.stringValue, row: row, column: column, editInProgress: false)
    textField.delegate = self
    textField.editTracker = self
  }

  func startEdit() {
    guard let current = current else {
      return
    }

    let textField = current.textField
    Logger.log("START Edit [\(current.row), \(current.column)] \"\(textField.stringValue)\"", level: .verbose)
    self.current = CurrentFocus(textField: textField, stringValueOrig: textField.stringValue, row: current.row, column: current.column, editInProgress: true)
    textField.isEditable = true
    textField.isSelectable = true
    textField.selectText(nil)  // creates editor
    textField.needsDisplay = true
  }

  @discardableResult
  private func commitChanges(to current: CurrentFocus) -> Bool {
    if current.textField.stringValue != current.stringValueOrig {
      if self.delegate.editDidEndWithNewText(newValue: current.textField.stringValue, row: current.row, column: current.column) {
        Logger.log("editDidEndWithNewText() returned TRUE: assuming new value accepted", level: .verbose)
        return true
      } else {
        // a return value of false tells us to revert to the previous value
        Logger.log("editDidEndWithNewText() returned FALSE: reverting displayed value to \"\(current.stringValueOrig)\"", level: .verbose)
        current.textField.stringValue = current.stringValueOrig
        return false
      }
    } else {
      Logger.log("endEdit() calling editDidEndWithNoChange()", level: .verbose)
      self.delegate.editDidEndWithNoChange(row: current.row, column: current.column)
    }
    return true
  }

  @discardableResult
  func endEdit(closeEditorExplicitly: Bool = true) -> Bool {
    guard let current = current, current.editInProgress else { return false }

    let textField = current.textField
    Logger.log("END Edit   [\(current.row), \(current.column)] \"\(textField.stringValue)\"", level: .verbose)

    let shouldContinue = commitChanges(to: current)

    self.current = CurrentFocus(textField: textField, stringValueOrig: textField.stringValue, row: current.row, column: current.column, editInProgress: false)

    if closeEditorExplicitly {
      textField.window?.endEditing(for: textField)
      // Resign first responder status and give focus back to table row selection:
      textField.window?.makeFirstResponder(self.parentTable)
      textField.isEditable = false
      textField.isSelectable = false
      textField.needsDisplay = true
    }

    return shouldContinue
  }

  // MARK: Intercellular edit navigation

  func askUserToApproveDoubleClickEdit() -> Bool {
    if let current = current {
      return self.delegate.userDidDoubleClickOnCell(row: current.row, column: current.column)
    }
    return false
  }

  private func getIndexOfEditableColumn(_ columnIndex: Int) -> Int? {
    let editColumns = self.parentTable.editableTextColumnIndexes
    for (indexIndex, index) in editColumns.enumerated() {
      if columnIndex == index {
        return indexIndex
      }
    }
    Logger.log("Failed to find index \(columnIndex) in editableTextColumnIndexes (\(editColumns))", level: .error)
    return nil
  }

  private func nextTabColumnIndex(_ columnIndex: Int) -> Int {
    let editColumns = self.parentTable.editableTextColumnIndexes
    if let indexIndex = getIndexOfEditableColumn(columnIndex) {
      return editColumns[(indexIndex+1) %% editColumns.count]
    }
    return editColumns[0]
  }

  private func prevTabColumnIndex(_ columnIndex: Int) -> Int {
    let editColumns = self.parentTable.editableTextColumnIndexes
    if let indexIndex = getIndexOfEditableColumn(columnIndex) {
      return editColumns[(indexIndex-1) %% editColumns.count]
    }
    return editColumns[0]
  }

  // Thanks to:
  // https://samwize.com/2018/11/13/how-to-tab-to-next-row-in-nstableview-view-based-solution/
  // Returns true if it resulted in another editor being opened [asychronously], false if not.
  @discardableResult
  func editAnotherCellAfterEditEnd(oldRow rowIndex: Int, oldColumn columnIndex: Int, _ textMovement: NSTextMovement) -> Bool {
    let isInterRowTabEditingEnabled = Preference.bool(for: .tableEditKeyNavContinuesBetweenRows)

    var newRowIndex: Int
    var newColIndex: Int
    switch textMovement {
    case .tab:
      // Snake down the grid, left to right, top down
      newColIndex = nextTabColumnIndex(columnIndex)
      if newColIndex < 0 {
        Logger.log("Invalid value for next column: \(newColIndex)", level: .error)
        return false
      }
      if newColIndex <= columnIndex {
        guard isInterRowTabEditingEnabled else {
          return false
        }
        newRowIndex = rowIndex + 1
        if newRowIndex >= self.parentTable.numberOfRows {
          // Always done after last row
          return false
        }
      } else {
        newRowIndex = rowIndex
      }
    case .backtab:
      // Snake up the grid, right to left, bottom up
      newColIndex = prevTabColumnIndex(columnIndex)
      if newColIndex < 0 {
        Logger.log("Invalid value for prev column: \(newColIndex)", level: .error)
        return false
      }
      if newColIndex >= columnIndex {
        guard isInterRowTabEditingEnabled else {
          return false
        }
        newRowIndex = rowIndex - 1
        if newRowIndex < 0 {
          return false
        }
      } else {
        newRowIndex = rowIndex
      }
    case .return:
      guard isInterRowTabEditingEnabled else {
        return false
      }
      // Go to cell directly below
      newRowIndex = rowIndex + 1
      if newRowIndex >= self.parentTable.numberOfRows {
        // Always done after last row
        return false
      }
      newColIndex = columnIndex
    default: return false
    }

    DispatchQueue.main.async {
      self.parentTable.editCell(row: newRowIndex, column: newColIndex)
    }
    // handled
    return true
  }

}
