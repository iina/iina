//
//  AccessibilityPreference.swift
//  iina
//
//  Created by low-batt on 6/26/21.
//  Copyright © 2021 lhc. All rights reserved.
//

import Foundation

struct AccessibilityPreferences {

  /// Adjusts an animation to be instantaneous if the IINA setting `Enable animations` is disabled.
  /// - Parameter duration: Desired animation duration.
  /// - Returns: `0` if animations have been disabled; otherwise the given duration.
  static func adjustedDuration(_ duration: TimeInterval) -> TimeInterval {
    return Preference.bool(for: PK.enableAnimations) ? duration : 0
  }

  /// Reflects whether the macOS accessibility setting to reduce motion is in an enabled state.
  ///
  /// This property provides a wrapper around the `NSWorkspace` property so that code that needs to check this setting does not
  /// need to concern itself with this setting not being available until macOS Sierra.
  ///
  /// Proper handling of the Reduce motion setting is covered in the Apple [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) under
  /// [Accessibility - Motion](https://developer.apple.com/design/human-interface-guidelines/accessibility#Motion).
  ///
  /// To enable the
  /// [Reduced motion](https://support.apple.com/guide/mac-help/stop-or-reduce-onscreen-motion-mchlc03f57a1/mac)
  /// setting:
  /// - Click on `System Settings…` under the  menu
  /// - The `System Settings` window appears
  /// - On the left side of the window click on `Accessibility`
  /// - On the right side of the window click on `Display`
  /// - In the `Display` section look for the `Reduced motion` setting
  /// - Slide the toggle button to be on (blue)
  /// - Returns: `true` if reduce motion is enabled; otherwise `false`.
  static var motionReductionEnabled: Bool {
    if #available(macOS 10.12, *) {
      return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    } else {
      return false
    }
  }
}
