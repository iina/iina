//
//  SliderScrollPolicy.swift
//  iina
//
//  Pure rules for whether NSSlider should handle scrollWheel (issue #6324).
//  Mirrored in other/LogicTests for unit tests.
//

import CoreGraphics

enum SliderScrollPolicy {
  /// Returns false when slider scrolling is disabled, or the dominant scroll axis
  /// maps to ScrollAction.none (equal deltas count as vertical).
  static func shouldAllowScroll(
    disableSliderScrolling: Bool,
    verticalActionNone: Bool,
    horizontalActionNone: Bool,
    deltaX: CGFloat,
    deltaY: CGFloat
  ) -> Bool {
    if disableSliderScrolling { return false }
    let verticalDominant = abs(deltaY) >= abs(deltaX)
    return verticalDominant ? !verticalActionNone : !horizontalActionNone
  }
}
