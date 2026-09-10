//
//  KeyMappingActionButtons.swift
//  iina
//
//  Pure visibility rules for Key Bindings row action buttons (issue #6329).
//  Mirrored in other/LogicTests for unit tests.
//

enum KeyMappingActionButtons {
  /// Edit/delete appear only for a selected row in an editable config.
  static func shouldShowEditButtons(isSelected: Bool, isEditable: Bool) -> Bool {
    isSelected && isEditable
  }

  /// Lock help appears only for a selected row in a locked/built-in config.
  static func shouldShowLockButton(isSelected: Bool, isEditable: Bool) -> Bool {
    isSelected && !isEditable
  }
}
