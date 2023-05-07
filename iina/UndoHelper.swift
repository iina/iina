//
//  TableStateManager.swift
//  iina
//
//  Created by Matt Svoboda on 11/26/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

// Just a bunch of boilerplate code for actionName, logging
class UndoHelper {
  static let DO = "Do"
  static let UNDO = "Undo"
  static let REDO = "Redo"

  typealias ActionBody = () -> Void

  var undoManager: UndoManager? {
    nil  // Subclasses should override
  }

  // This can be called both for the "undo" of the original "do", and for the "redo" (AKA the undo of the undo).
  // `actionName` will only be used for the original "do" action, and will be cached for use in "undo" / "redo".
  // Note: the `redo` param exists to (hopefully) improve readability and better indicate intent. It does not need to
  // be used if `undoAction` calls `registerUndo()` itself.
  @discardableResult
  func register(_ actionName: String? = nil, undo undoAction: @escaping ActionBody, redo redoAction: ActionBody? = nil) -> Bool {
    guard let undoMan = self.undoManager else {
      Logger.log("Cannot register for undo: undoManager is nil", level: .verbose)
      return false
    }

    let origActionName: String? = UndoHelper.getOrSetOriginalActionName(actionName, undoMan)

    Logger.log("[\(UndoHelper.formatAction(origActionName, undoMan))] Registering for \(undoMan.isRedoing ? UndoHelper.REDO : UndoHelper.UNDO)")

    undoMan.registerUndo(withTarget: self, handler: { manager in
      // Undo starts here. Or: undo of the undo (redo)
      Logger.log("[\(UndoHelper.formatAction(origActionName, undoMan))] Starting \(UndoHelper.currentOp(undoMan)) (\(UndoHelper.extraDebug(undoMan)))")

      undoAction()

      if let redoAction = redoAction {
        self.register(actionName, undo: redoAction, redo: undoAction)
      }
    })

    return true
  }

  func isUndoing() -> Bool {
    return self.undoManager?.isUndoing ?? false
  }

  func isUndoingOrRedoing() -> Bool {
    if let undoManager = self.undoManager, undoManager.isUndoing || undoManager.isRedoing {
      return true
    }
    return false
  }

  static private func getOrSetOriginalActionName(_ actionName: String?, _ undoMan: UndoManager) -> String? {
    if undoMan.isUndoing {
      return undoMan.undoActionName
    }
    if undoMan.isRedoing {
      return undoMan.redoActionName
    }

    // Action name only needs to be set once per action, and it will displayed for both "Undo {}" and "Redo {}".
    // There's no need to change the name of it for the redo.
    if let origActionName = actionName {
      undoMan.setActionName(origActionName)
      return origActionName
    }
    return nil
  }

  static private func extraDebug(_ undoMan: UndoManager) -> String {
    "canUndo: \(undoMan.canUndo), canRedo: \(undoMan.canRedo)"
  }

  static private func currentOp(_ undoMan: UndoManager) -> String {
    undoMan.isUndoing ? UNDO : (undoMan.isRedoing ? REDO : DO)
  }

  static private func formatAction(_ actionName: String?, _ undoMan: UndoManager) -> String {
    let op = UndoHelper.currentOp(undoMan)
    if let action = actionName {
      return "\(op) \(action)"
    }
    return op
  }
}

class PrefsWindowUndoHelper: UndoHelper {
  override var undoManager: UndoManager? {
    PreferenceWindowController.undoManager
  }
}
