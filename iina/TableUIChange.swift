//
//  TableUIChange.swift
//  iina
//
//  Created by Matt Svoboda on 9/29/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/*
 Each instance of this class:
 * Represents an atomic state change to the UI of an associated `EditableTableView`
 * Contains all the metadata (though not the actual data) needed to transition it from {State_N} to {State_N+1}, where each state refers to a single user action or the response to some external update. All of thiis is needed in order to make AppKit animations work.

 In order to facilitate table animations, and to get around some AppKit limitations such as the tendency
 for it to lose track of the row selection, much additional boilerplate is needed to keep track of state.
 This objects attempts to provide as much of this as possible and provide future reusability.
 */
class TableUIChange {
  // MARK: Static definitions

  typealias CompletionHandler = (TableUIChange) -> Void
  typealias AnimationBlock = (NSAnimationContext) -> Void

  // After removal of rows, select the next single row after the last one removed:
  static let selectNextRowAfterDelete = true

  enum ContentChangeType {
    case removeRows

    case insertRows

    case moveRows

    case updateRows

    // No changes to content, but can specify changes to metadata (selection change, completionHandler, ...)
    case none

    // Due to AppKit limitations (removes selection, disables animations, seems to send extra events)
    // use this only when absolutely needed:
    case reloadAll

    // Can have any number of inserts, removes, moves, and updates:
    case wholeTableDiff
  }

  // MARK: Instance Vars

  // Required
  let changeType: ContentChangeType

  var toRemove: IndexSet? = nil
  var toInsert: IndexSet? = nil
  var toUpdate: IndexSet? = nil
  // Used by ContentChangeType.moveRows. Ordered list of pairs of (fromIndex, toIndex)
  var toMove: [(Int, Int)]? = nil

  // NSTableView already updates previous selection indexes if added/removed rows cause them to move.
  // To select added rows, or select next index after remove, etc, will need an explicit call to update selection afterwards.
  // Will not call to update selection if this is nil.
  var newSelectedRowIndexes: IndexSet? = nil

  // MARK: Optional vars

  // Provide this to restore old selection when calculating the inverse of this change (when doing an undo of "move").
  // TODO: (optimization) figure out how to calculate this from `toMove` instead of storing this
  var oldSelectedRowIndexes: IndexSet? = nil

  // Optional animations
  var flashBefore: IndexSet? = nil
  var flashAfter: IndexSet? = nil

  // Animation overrides. Leave nil to use the value from the table
  var rowInsertAnimation: NSTableView.AnimationOptions? = nil
  var rowRemoveAnimation: NSTableView.AnimationOptions? = nil

  // If true, reload all existing rows after executing the primary differences (to cover the case that one of them may have changed)
  var reloadAllExistingRows: Bool = false

  // If true, and only if there are selected row(s), scroll the table so that the first selected row is
  // visible to the user. Does this after `reloadAllExistingRows` but before `completionHandler`.
  var scrollToFirstSelectedRow: Bool = true

  // A method which, if supplied, is called at the end of execute()
  let completionHandler: TableUIChange.CompletionHandler?

  var hasRemove: Bool {
    if let toRemove = self.toRemove {
      return !toRemove.isEmpty
    }
    return false
  }

  var hasInsert: Bool {
    if let toInsert = self.toInsert {
      return !toInsert.isEmpty
    }
    return false
  }

  var hasMove: Bool {
    if let toMove = self.toMove {
      return !toMove.isEmpty
    }
    return false
  }

  init(_ changeType: ContentChangeType, completionHandler: TableUIChange.CompletionHandler? = nil) {
    self.changeType = changeType
    self.completionHandler = completionHandler
  }

  // MARK: Execute

  // Subclasses should override executeContentUpdates() instead of this
  func execute(on tableView: EditableTableView) {
    let animationGroups = LinkedList<AnimationBlock>()


    // 1. "Before" animations (if provided)
    if let flashBefore = self.flashBefore, !flashBefore.isEmpty {
      animationGroups.append { context in
        self.animateFlash(forIndexes: flashBefore, in: tableView, context)
      }
    }


    // 2. Perform row update animations
    animationGroups.append { context in
      // Encapsulate all animations in this function inside a transaction.
      tableView.beginUpdates()
      defer {
        tableView.endUpdates()
      }

      if AccessibilityPreferences.motionReductionEnabled {
        Logger.log("Motion reduction is enabled: nulling out animation", level: .verbose)
        context.duration = 0.0
        context.allowsImplicitAnimation = false
      }

      self.executeRowUpdates(on: tableView)
    }


    // 3. Change row selection.
    // MUST NOT DO THIS IN THE SAME ANIMATION GROUP AS ROW UPDATES or else weird selection "burn-in" can result
    animationGroups.append { context in
      // track this so we don't do it more than once (it fires the selectionChangedListener every time)
      let wantsReloadOfExistingRows: Bool
      if self.changeType == .reloadAll {
        // Don't reload twice
        wantsReloadOfExistingRows = false
      } else if self.reloadAllExistingRows || self.changeType == .updateRows || (!(self.toUpdate?.isEmpty ?? true)) {
        // Just schedule a reload for all of them. This is a very inexpensive operation, and much easier
        // than chasing down all the possible ways other rows could be updated.
        wantsReloadOfExistingRows = true
      } else {
        wantsReloadOfExistingRows = false
      }

      if wantsReloadOfExistingRows {
        Logger.log("TableUIChange: reloading existing rows", level: .verbose)
        // Also uses `newSelectedRowIndexes`, if it is not nil:
        tableView.reloadExistingRows(reselectRowsAfter: true, usingNewSelection: self.newSelectedRowIndexes)
      } else if let newSelectedRowIndexes = self.newSelectedRowIndexes {
        Logger.log("TableUIChange: selecting \(newSelectedRowIndexes.count) rows", level: .verbose)
        tableView.selectApprovedRowIndexes(newSelectedRowIndexes)
      } else {
        Logger.log("TableUIChange: no change to row selection", level: .verbose)
      }

      if self.scrollToFirstSelectedRow,
         let newSelectedRowIndexes = self.newSelectedRowIndexes,
         let firstSelectedRow = newSelectedRowIndexes.first {
        tableView.scrollRowToVisible(firstSelectedRow)
      }
    }

    // 4. "After" animations (if provided)
    if let flashAfter = self.flashAfter, !flashAfter.isEmpty {
      animationGroups.append { context in
        self.animateFlash(forIndexes: flashAfter, in: tableView, context)
      }
    }

    executeGroup(animationGroups.firstNode)
  }

  // Recursive function which executions code for a single group in the chain
  private func executeGroup(_ groupNode: LinkedList<AnimationBlock>.Node?) {
    guard let groupNode = groupNode else {
      if let lastCompletionHandler = self.completionHandler {
        Logger.log("Executing custom completion handler for TableUIChange", level: .verbose)
        lastCompletionHandler(self)
      }
      return
    }

    NSAnimationContext.runAnimationGroup(groupNode.value, completionHandler: {
      self.executeGroup(groupNode.next)
    })
  }

  private func executeRowUpdates(on tableView: EditableTableView) {
    let insertAnimation = AccessibilityPreferences.motionReductionEnabled ? [] : (self.rowInsertAnimation ?? tableView.rowInsertAnimation)
    let removeAnimation = AccessibilityPreferences.motionReductionEnabled ? [] : (self.rowRemoveAnimation ?? tableView.rowRemoveAnimation)

    Logger.log("Executing TableUIChange type \"\(self.changeType)\": \(self.toRemove?.count ?? 0) removes, \(self.toInsert?.count ?? 0) inserts, \(self.toMove?.count ?? 0), moves, \(self.toUpdate?.count ?? 0) updates; reloadExisting: \(self.reloadAllExistingRows), \(self.newSelectedRowIndexes?.count ?? -1) selectedRows", level: .verbose)

    switch changeType {

      case .removeRows:
        if let indexes = self.toRemove {
          tableView.removeRows(at: indexes, withAnimation: removeAnimation)
        }

      case .insertRows:
        if let indexes = self.toInsert {
          tableView.insertRows(at: indexes, withAnimation: insertAnimation)
        }

      case .moveRows:
        if let movePairs = self.toMove {
          for (oldIndex, newIndex) in movePairs {
            Logger.log("Moving row \(oldIndex) → \(newIndex)", level: .verbose)
            tableView.moveRow(at: oldIndex, to: newIndex)
          }
        }

      case .updateRows:
        // will reload rows in next step
        break

      case .none:
        break

      case .reloadAll:
        // Try not to use this much, if at all
        Logger.log("Executing TableUIChange: ReloadAll", level: .verbose)
        tableView.reloadData()

      case .wholeTableDiff:
        if let toRemove = self.toRemove,
           let toInsert = self.toInsert,
           let toUpdate = self.toUpdate,
           let movePairs = self.toMove {
          guard !toRemove.isEmpty || !toInsert.isEmpty || !toUpdate.isEmpty || !movePairs.isEmpty else {
            Logger.log("Executing changes from diff: no rows changed", level: .verbose)
            break
          }
          // Remember, AppKit expects the order of operations to be: 1. Delete, 2. Insert, 3. Move
          tableView.removeRows(at: toRemove, withAnimation: removeAnimation)
          tableView.insertRows(at: toInsert, withAnimation: insertAnimation)
          for (oldIndex, newIndex) in movePairs {
            Logger.log("Executing changes from diff: moving row: \(oldIndex) → \(newIndex)", level: .verbose)
            tableView.moveRow(at: oldIndex, to: newIndex)
          }
        }
    }
  }

  // Set up a flash animation to make it clear which rows were updated or removed.
  // Don't need to worry about moves & inserts, because those will be highlighted
  func setUpFlashForChangedRows() {
    flashBefore = IndexSet()
    if let toRemove = self.toRemove {
      for index in toRemove {
        flashBefore?.insert(index)
      }
    }
  }

  private func animateFlash(forIndexes indexes: IndexSet, in tableView: NSTableView, _ context: NSAnimationContext) {
    Logger.log("Flashing rows: \(indexes.map({$0}))", level: .verbose)

    context.duration = 0.2
    tableView.beginUpdates()
    defer {
      tableView.endUpdates()
    }

    for index in indexes {
      if let rowView = tableView.rowView(atRow: index, makeIfNecessary: false) {
        let animation = CAKeyframeAnimation()
        animation.keyPath = "backgroundColor"
        animation.values = [NSColor.textBackgroundColor.cgColor,
                            NSColor.controlTextColor.cgColor,
                            NSColor.textBackgroundColor.cgColor]
        animation.keyTimes = [0, 0.25, 1]
        animation.duration = context.duration
        rowView.layer?.add(animation, forKey: "bgFlash")
      }
    }
  }

  func shallowClone() -> TableUIChange {
    let clone = TableUIChange(self.changeType, completionHandler: self.completionHandler)
    clone.toRemove = self.toRemove
    clone.toInsert = self.toInsert
    clone.toMove = self.toMove
    clone.toUpdate = self.toUpdate
    clone.newSelectedRowIndexes = self.newSelectedRowIndexes
    clone.oldSelectedRowIndexes = self.oldSelectedRowIndexes
    clone.rowInsertAnimation = self.rowInsertAnimation
    clone.rowRemoveAnimation = self.rowRemoveAnimation
    clone.reloadAllExistingRows = self.reloadAllExistingRows
    clone.scrollToFirstSelectedRow = self.scrollToFirstSelectedRow

    return clone
  }
}
