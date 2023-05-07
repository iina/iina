//
//  EditableTextField.swift
//  iina
//
//  Created by Matt Svoboda on 2022.06.23.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/*
 Should only be used within cells of `EditableTableView`.
 */
class EditableTextField: NSTextField {
  var editTracker: CellEditTracker? = nil

  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 {
      guard let editTracker = self.editTracker else {
        Logger.log("Table textField \(self) received double-click event without validateProposedFirstResponder() being called first!", level: .error)
        super.mouseDown(with: event)
        return
      }

      Logger.log("EditableTextField: Got a double-cick", level: .verbose)
      let approved = editTracker.askUserToApproveDoubleClickEdit()
      Logger.log("Double-click approved: \(approved)", level: .verbose)
      if approved {
        self.window?.makeFirstResponder(self)
      }
      // These are the only cases where `super.mouseDown()` should not be called
      return
    }
    super.mouseDown(with: event)
  }

  override func becomeFirstResponder() -> Bool {
    if let editTracker = editTracker {
      editTracker.startEdit()
    } else {
      Logger.log("Table textField \(self) had becomeFirstResponder() called without editTracker being set first!", level: .error)
    }
    return true
  }

  override var textColor: NSColor? {
    didSet {
      if let cell = self.cell as? EditableTextFieldCell {
        cell.textColorOrig = textColor
      }
    }
  }
}

// This class (so far) exists only for one reason: to make sure that rows with custom colored text
// will change back to the regular control color when their row is highlighted.
//
// To use, just make sure this class name is specified for every text field cell in every column which
// can have colored text (also that its parent is an `EditableTextField' and the parent table is
// an `EditableTableView`), and to set the desired color for the text, set the `textColor` property of
// the parent `EditableTextField`.
class EditableTextFieldCell: NSTextFieldCell {
  var textColorOrig: NSColor? = nil

  // When the background changes (as a result of selection/deselection), change text color appropriately.
  // This is needed to account for custom text coloring.
  override var backgroundStyle: NSView.BackgroundStyle {
    didSet {
      switch backgroundStyle {
        case .normal, .lowered:      // Deselected
          textColor = textColorOrig
        case .emphasized, .raised:  // AKA selected
          textColor = nil  // Use standard color
        default:
          Logger.log("Unsupported background style: \(backgroundStyle)", level: .warning	)
      }
    }
  }
}
