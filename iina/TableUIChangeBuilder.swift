//
//  TableUIChangeBuilder.swift
//  iina
//
//  Created by Matt Svoboda on 11/26/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class TableUIChangeBuilder {
  // Derives the inverse of the given `TableUIChange` (as suitable for an Undo) and returns it.
  static func inverted(from original: TableUIChange, andAdjustAllIndexesBy offset: Int = 0) -> TableUIChange {
    let inverted: TableUIChange

    switch original.changeType {

    case .removeRows:
      inverted = TableUIChange(.insertRows)

    case .insertRows:
      inverted = TableUIChange(.removeRows)

    case .moveRows:
      inverted = TableUIChange(.moveRows)

    case .updateRows:
      inverted = TableUIChange(.updateRows)

    case .none, .reloadAll, .wholeTableDiff:
      // Will not cause a failure. But can't think of a reason to ever invert these types
      Logger.log("Calling inverted() on content change type '\(original.changeType)': was this intentional?", level: .warning)
      inverted = TableUIChange(original.changeType)
    }

    if inverted.changeType != .none && inverted.changeType != .reloadAll {
      inverted.newSelectedRowIndexes = IndexSet()
    }

    if let removed = original.toRemove {
      inverted.toInsert = IndexSet(removed.map({ $0 + offset }))
      // Add inserted lines to selection
      for insertIndex in inverted.toInsert! {
        inverted.newSelectedRowIndexes?.insert(insertIndex)
      }
      Logger.log("Invert: changed removes=\(removed.map{$0}) into inserts=\(inverted.toInsert!.map{$0})", level: .verbose)
    }
    if let toInsert = original.toInsert {
      inverted.toRemove = IndexSet(toInsert.map({ $0 + offset }))
      Logger.log("Invert: changed inserts=\(toInsert.map{$0}) into removes=\(inverted.toRemove!.map{$0})", level: .verbose)
    }
    if let toUpdate = original.toUpdate {
      inverted.toUpdate = IndexSet(toUpdate.map({ $0 + offset }))
      Logger.log("Invert: changed updates=\(toUpdate.map{$0}) into updates=\(inverted.toUpdate!.map{$0})", level: .verbose)
      // Add updated lines to selection
      for updateIndex in inverted.toUpdate! {
        inverted.newSelectedRowIndexes?.insert(updateIndex)
      }
    }
    if let movePairsOrig = original.toMove {
      var movePairsInverted: [(Int, Int)] = []

      for (fromIndex, toIndex) in movePairsOrig {
        let fromIndexNew = toIndex + offset
        let toIndexNew = fromIndex + offset
        movePairsInverted.append((fromIndexNew, toIndexNew))
      }

      inverted.toMove = movePairsInverted.reversed()  // Need to reverse order for proper animation

      // Preserve selection if possible:
      if let origBeginningSelection = original.oldSelectedRowIndexes,
          let origEndingSelection = original.newSelectedRowIndexes, inverted.changeType == .moveRows {
        inverted.newSelectedRowIndexes = origBeginningSelection
        inverted.oldSelectedRowIndexes = origEndingSelection
        Logger.log("Invert: changed movePairs from \(movePairsOrig) to \(inverted.toMove!.map{$0}); changed selection from \(origEndingSelection.map{$0}) to \(origBeginningSelection.map{$0})", level: .verbose)
      }
    }

    // Select next row after delete event (maybe):
    applyExtraSelectionRules(to: inverted)

    return inverted
  }

  // MARK: Diff

  /*
   Creates a new `TableUIChange` and populates its `toRemove, `toInsert`, and `toMove` fields
   based on a diffing algorithm similar to Git's.

   Note for tables containing non-unique rows:
   If changes were made to row(s) which not unique in the table, the diffing algorithm can't reliably
   identify which of the duplicates changed and which didn't, and may pick the wrong ones.
   Assuming the positions of shared rows are fungible, this isn't exactly wrong but may be visually
   inconvenient for things like undo. Where possible, this should be avoided in favor of explicit information.

   Solution shared by Giles Hammond:
   https://stackoverflow.com/a/63281265/1347529S
   Further reference:
   https://swiftrocks.com/how-collection-diffing-works-internally-in-swift
   */
  static func buildDiff<R>(oldRows: Array<R>, newRows: Array<R>, completionHandler:
                           TableUIChange.CompletionHandler? = nil, overrideSingleRowMove: Bool = false) -> TableUIChange where R:Hashable {
    guard #available(macOS 10.15, *) else {
      Logger.log("Animated table diff not available in MacOS versions below 10.15. Falling back to ReloadAll")
      return TableUIChange(.reloadAll, completionHandler: completionHandler)
    }

    let diff = TableUIChange(.wholeTableDiff, completionHandler: completionHandler)
    diff.toRemove = IndexSet()
    diff.toInsert = IndexSet()
    diff.toUpdate = IndexSet()
    diff.toMove = []

    // Remember, AppKit expects the order of operations to be: 1. Delete, 2. Insert, 3. Move

    let steps = newRows.difference(from: oldRows).steps
    Logger.log("Computing TableUIChange from diff: found \(steps.count) differences between \(oldRows.count) old & \(newRows.count) new rows")

    // Override default behavior for single row: treat del + ins as move
    if overrideSingleRowMove && steps.count == 2 {
      switch steps[0] {
      case let .remove(_, indexToRemove):
        switch steps[1] {
        case let .insert(_, indexToInsert):
          if indexToRemove == indexToInsert {
            diff.toUpdate = IndexSet(integer: indexToInsert)
            Logger.log("Overrode TableUIChange from diff: changed 1 rm + 1 add into 1 update: \(indexToInsert)", level: .verbose)
            return diff
          }
          diff.toMove?.append((indexToRemove, indexToInsert))
          Logger.log("Overrode TableUIChange from diff: changed 1 rm + 1 add into 1 move: from \(indexToRemove) to \(indexToInsert)", level: .verbose)
          return diff
        default: break
        }
      default: break
      }
    }

    for step in steps {
      switch step {
      case let .remove(_, index):
        // If toOffset != nil, it signifies a MOVE from fromOffset -> toOffset. But the offset must be adjusted for removes!
        diff.toRemove?.insert(index)
      case let .insert(_, index):
        diff.toInsert?.insert(index)
      case let .move(_, from, to):
        diff.toMove?.append((from, to))
      }
    }

    return diff
  }

  static private func applyExtraSelectionRules(to tableUIChange: TableUIChange) {
    if TableUIChange.selectNextRowAfterDelete && !tableUIChange.hasMove && !tableUIChange.hasInsert && tableUIChange.hasRemove {
      // After selected rows are deleted, keep a selection on the table by selecting the next row
      if let toRemove = tableUIChange.toRemove, let lastRemoveIndex = toRemove.last {
        let newSelectionIndex: Int = lastRemoveIndex - toRemove.count + 1
        if newSelectionIndex < 0 {
          Logger.log("selectNextRowAfterDelete: new selection index is less than zero! Discarding", level: .error)
        } else {
          tableUIChange.newSelectedRowIndexes = IndexSet(integer: newSelectionIndex)
          Logger.log("TableUIChange: selecting next index after removed rows: \(newSelectionIndex)", level: .verbose)
        }
      }
    }
  }
}
