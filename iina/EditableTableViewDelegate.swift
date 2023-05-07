//
//  NSTableViewExtension.swift
//  iina
//
//  Created by Matt Svoboda on 10/6/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

// Adds optional methods for use in conjunction with `EditableTableView`
// (which will itself hopefully become an extension of `NSTableView` at some point).
protocol EditableTableViewDelegate {
  func editDidEndWithNewText(newValue: String, row rowIndex: Int, column columnIndex: Int) -> Bool

  func editDidEndWithNoChange(row rowIndex: Int, column columnIndex: Int)

  // The user double-clicked on the cell with the given row & coumn indexes.
  // If true is returned, an in-line editor will be opened for editing the cell text.
  // If false is returned, no action will be taken.
  func userDidDoubleClickOnCell(row rowIndex: Int, column columnIndex: Int) -> Bool

  // The user double-clicked on the cell with the given row & coumn indexes.
  // If true is returned, an in-line editor will be opened for the first editable cell in that row.
  // If false is returned, no action will be taken.
  func userDidPressEnterOnRow(_ rowIndex: Int) -> Bool

  /*
   OK, this is how standard cut, copy, paste, & delete work. Don't forget again!

   Each of these 4 actions are built into AppKit and will be called in various places: possibly the Edit menu, key equivalents, or toolbar items.
   No assuptions should be made about calling context - just use the state of the table to see what (if anything) should be copied/etc.

   The Edit menu (et al.) look for @objc functions named `cut`, `copy`, `paste`, and `delete` with signatures like:
   `@objc func copy(_ sender: AnyObject?)`
   It goes down the responder chain looking for them, so ideally they should be defined in the first responder's class.
   This means NSTableView or its subclasses, NOT its delegates! Each action will be called only if it exists and passes validation.

   Enablement:
   The responder chain is checked to to see if `validateUserInterfaceItem()` is enabled.
   Each action is disabled by default, and only enabled if this method is present, and returns `true` in response to the associated action.

   `EditableTableView` adds stubs for all the needed functions, and calls the associated action handlers in `NSTableViewDelegate`
   when appropriate (see `doEditMenu*` below). The delegate functions do not need to be annotated with @objc.
   */

  // Callbacks for Edit menu item enablement. Delegates should override these if they want to support the standard operations.

  func isCutEnabled() -> Bool

  func isCopyEnabled() -> Bool

  func isPasteEnabled() -> Bool

  func isDeleteEnabled() -> Bool

  func isSelectAllEnabled() -> Bool

  // Edit menu action handlers. Delegates should override these if they want to support the standard operations.

  func doEditMenuCut()

  func doEditMenuCopy()

  func doEditMenuPaste()

  func doEditMenuDelete()

  // No need for selectAll - it's trivial and NSTableView provides it
}

// Adds null defaults for all protocol methods
extension EditableTableViewDelegate {
  func editDidEndWithNewText(newValue: String, row rowIndex: Int, column columnIndex: Int) -> Bool {
    // If in-line editing is enabled, then this method should be overriden, so this message should never be seen.
    Logger.log("EditableTableViewDelegate.editDidEndWithNewText(): null default method was called!", level: .warning)
    return false
  }

  func editDidEndWithNoChange(row rowIndex: Int, column columnIndex: Int) {
  }

  func userDidDoubleClickOnCell(row rowIndex: Int, column columnIndex: Int) -> Bool {
    // If in-line editing is enabled, then this method should be overriden, so this message should never be seen.
    Logger.log("EditableTableViewDelegate.userDidDoubleClickOnCell(): null default method was called!", level: .warning)
    return false
  }

  func userDidPressEnterOnRow(_ rowIndex: Int) -> Bool {
    // If in-line editing is enabled, then this method should be overriden, so this message should never be seen.
    Logger.log("EditableTableViewDelegate.userDidPressEnterOnRow(): null default method was called!", level: .warning)
    return false
  }

  // Edit > Cut, Copy, Paste, Delete are disabled by default.

  func isCutEnabled() -> Bool {
    false
  }

  func isCopyEnabled() -> Bool {
    false
  }

  func isPasteEnabled() -> Bool {
    false
  }

  func isDeleteEnabled() -> Bool {
    false
  }

  func isSelectAllEnabled() -> Bool {
    true
  }

  func doEditMenuCut() {}

  func doEditMenuCopy() {}

  func doEditMenuPaste() {}

  func doEditMenuDelete() {}
}
