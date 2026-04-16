//
//  VolumeSlider.swift
//  iina
//
//  Created by low-batt on 6/30/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Cocoa

/// A custom [slider](https://developer.apple.com/design/human-interface-guidelines/macos/selectors/sliders/)
/// for the volume slider in the on screen controller.
class VolumeSlider: NSSlider {

  // MARK: - Mouse / Trackpad events

  /// The user is scrolling while the cursor is within the slider.
  ///
  /// With certain kinds of input devices, such as a mouse with a scroll wheel that spins freely, it is easy to accidentally move the cursor
  /// over the slider and unintentionally change the volume. For users that dislike this behavior IINA provides a setting to disable
  /// scrolling the slider. When this setting is enabled the user must grab and drag the slider's thumb to change the volume or click on a
  /// position within the slider.
  /// - Parameter event: Event indicating the scroll wheel position changed.
  override func scrollWheel(with event: NSEvent) {
    guard !Preference.bool(for: .disableVolumeSliderScrolling) else { return }
    super.scrollWheel(with: event)
  }
}
