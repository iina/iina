import XCTest
@testable import IINALogic

final class KeyMappingActionButtonsTests: XCTestCase {
  func testEditButtonsShownOnlyWhenSelectedAndEditable() {
    XCTAssertTrue(
      KeyMappingActionButtons.shouldShowEditButtons(isSelected: true, isEditable: true)
    )
    XCTAssertFalse(
      KeyMappingActionButtons.shouldShowEditButtons(isSelected: true, isEditable: false)
    )
    XCTAssertFalse(
      KeyMappingActionButtons.shouldShowEditButtons(isSelected: false, isEditable: true)
    )
    XCTAssertFalse(
      KeyMappingActionButtons.shouldShowEditButtons(isSelected: false, isEditable: false)
    )
  }

  func testLockButtonShownOnlyWhenSelectedAndNotEditable() {
    XCTAssertTrue(
      KeyMappingActionButtons.shouldShowLockButton(isSelected: true, isEditable: false)
    )
    XCTAssertFalse(
      KeyMappingActionButtons.shouldShowLockButton(isSelected: true, isEditable: true)
    )
    XCTAssertFalse(
      KeyMappingActionButtons.shouldShowLockButton(isSelected: false, isEditable: false)
    )
    XCTAssertFalse(
      KeyMappingActionButtons.shouldShowLockButton(isSelected: false, isEditable: true)
    )
  }
}
