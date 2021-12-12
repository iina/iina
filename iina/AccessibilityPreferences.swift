//
//  AccessibilityPreference.swift
//  iina
//
//  Created by low-batt on 6/26/21.
//  Copyright © 2021 lhc. All rights reserved.
//

import Foundation

struct AccessibilityPreferences {

  /// Adjusts an animation to be instantaneous if the macOS System Preference Reduce motion is enabled.
  /// - Parameter duration: Desired animation duration.
  /// - Returns: `0` if reduce motion is enabled; otherwise the given duration.
  static func adjustedDuration(_ duration: TimeInterval) -> TimeInterval {
    return motionReductionEnabled ? 0 : duration
  }

  /// Reflects whether the macOS System Preference accessibility option to retuce motion is in an enabled state.
  ///
  /// This property provides a wrapper around the `NSWorkspace` property so that code that needs to check this preference setting
  /// does not need to concern itself with this preference not being available until macOS Sierra.
  ///
  /// Proper handling of the Reduce motion preference setting is covered in the
  /// [Apple Human Interface Guidelines under Appearance Effects and Motion](https://developer.apple.com/design/human-interface-guidelines/accessibility/overview/appearance-effects/).
  ///
  /// To change this preference, choose Apple menu > System Preferences, click Accessibility, click Display, then click Display and
  /// check or uncheck Reduce motion.
  ///
  /// - Returns: `true` if reduce motion is enabled; otherwise `false`.
  static var motionReductionEnabled: Bool {
    if #available(macOS 10.12, *) {
      return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    } else {
      return false
    }
  }
}
