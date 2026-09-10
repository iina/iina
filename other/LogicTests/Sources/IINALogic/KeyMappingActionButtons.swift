/// Pure visibility rules for Key Bindings row action buttons (issue #6329).
/// Mirrored in `iina/KeyMappingActionButtons.swift`.
public enum KeyMappingActionButtons {
  /// Edit/delete appear only for a selected row in an editable config.
  public static func shouldShowEditButtons(isSelected: Bool, isEditable: Bool) -> Bool {
    isSelected && isEditable
  }

  /// Lock help appears only for a selected row in a locked/built-in config.
  public static func shouldShowLockButton(isSelected: Bool, isEditable: Bool) -> Bool {
    isSelected && !isEditable
  }
}
