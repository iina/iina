//
//  MiniPlaySlider.swift
//  iina
//
//  Created by low-batt on 6/30/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Cocoa

class MiniPlaySlider: NSSlider {

  // MARK: - Mouse / Trackpad events

  /// The user is scrolling while the cursor is within the slider.
  ///
  /// With certain kinds of input devices, such as a mouse with a scroll wheel that spins freely, it is easy to accidentally move the cursor
  /// over the slider and unintentionally change the playback position. For users that dislike this behavior IINA provides a setting to
  /// disable scrolling the slider. When this setting is enabled the user must grab and drag the slider's thumb to change the playback
  /// position or click on a position within the slider.
  /// - Parameter event: Event indicating the scroll wheel position changed.
  override func scrollWheel(with event: NSEvent) {
    let verticalNone = (Preference.enum(for: .verticalScrollAction) as Preference.ScrollAction) == .none
    let horizontalNone = (Preference.enum(for: .horizontalScrollAction) as Preference.ScrollAction) == .none
    guard SliderScrollPolicy.shouldAllowScroll(
      disableSliderScrolling: Preference.bool(for: .disablePlaySliderScrolling),
      verticalActionNone: verticalNone,
      horizontalActionNone: horizontalNone,
      deltaX: event.scrollingDeltaX,
      deltaY: event.scrollingDeltaY
    ) else { return }
    super.scrollWheel(with: event)
  }
}
