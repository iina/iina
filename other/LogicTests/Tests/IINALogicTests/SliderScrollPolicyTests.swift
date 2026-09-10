import XCTest
import CoreGraphics
@testable import IINALogic

final class SliderScrollPolicyTests: XCTestCase {
  func testDisableSliderScrollingBlocksAllAxes() {
    XCTAssertFalse(
      SliderScrollPolicy.shouldAllowScroll(
        disableSliderScrolling: true,
        verticalActionNone: false,
        horizontalActionNone: false,
        deltaX: 0,
        deltaY: 3
      )
    )
    XCTAssertFalse(
      SliderScrollPolicy.shouldAllowScroll(
        disableSliderScrolling: true,
        verticalActionNone: false,
        horizontalActionNone: false,
        deltaX: 3,
        deltaY: 0
      )
    )
  }

  func testVerticalNoneBlocksVerticalDominantScroll() {
    XCTAssertFalse(
      SliderScrollPolicy.shouldAllowScroll(
        disableSliderScrolling: false,
        verticalActionNone: true,
        horizontalActionNone: false,
        deltaX: 0,
        deltaY: 2
      )
    )
  }

  func testHorizontalNoneBlocksHorizontalDominantScroll() {
    XCTAssertFalse(
      SliderScrollPolicy.shouldAllowScroll(
        disableSliderScrolling: false,
        verticalActionNone: false,
        horizontalActionNone: true,
        deltaX: 2,
        deltaY: 0
      )
    )
  }

  func testEqualDeltasTreatedAsVertical() {
    XCTAssertFalse(
      SliderScrollPolicy.shouldAllowScroll(
        disableSliderScrolling: false,
        verticalActionNone: true,
        horizontalActionNone: false,
        deltaX: 2,
        deltaY: 2
      )
    )
    XCTAssertTrue(
      SliderScrollPolicy.shouldAllowScroll(
        disableSliderScrolling: false,
        verticalActionNone: false,
        horizontalActionNone: true,
        deltaX: 2,
        deltaY: 2
      )
    )
  }

  func testAllowsScrollWhenAxisActionIsNotNone() {
    XCTAssertTrue(
      SliderScrollPolicy.shouldAllowScroll(
        disableSliderScrolling: false,
        verticalActionNone: false,
        horizontalActionNone: true,
        deltaX: 0,
        deltaY: 3
      )
    )
    XCTAssertTrue(
      SliderScrollPolicy.shouldAllowScroll(
        disableSliderScrolling: false,
        verticalActionNone: true,
        horizontalActionNone: false,
        deltaX: 3,
        deltaY: 0
      )
    )
  }

  func testBothAxesNoneBlocksEverything() {
    XCTAssertFalse(
      SliderScrollPolicy.shouldAllowScroll(
        disableSliderScrolling: false,
        verticalActionNone: true,
        horizontalActionNone: true,
        deltaX: 0,
        deltaY: 1
      )
    )
    XCTAssertFalse(
      SliderScrollPolicy.shouldAllowScroll(
        disableSliderScrolling: false,
        verticalActionNone: true,
        horizontalActionNone: true,
        deltaX: 1,
        deltaY: 0
      )
    )
  }
}
