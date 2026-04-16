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

  override func awakeFromNib() {
    super.awakeFromNib()
    if #available(macOS 26, *), Preference.bool(for: .useLiquidGlass) {
      // Replace custom cell with standard NSSliderCell for full Liquid Glass animation
      let maxVol = Double(Preference.integer(for: .maxVolume))
      let standardCell = NSSliderCell()
      standardCell.minValue = 0
      standardCell.maxValue = maxVol
      standardCell.doubleValue = self.doubleValue
      standardCell.isContinuous = self.isContinuous
      standardCell.target = self.target
      standardCell.action = self.action
      standardCell.controlSize = (self.cell as? NSCell)?.controlSize ?? .regular
      self.cell = standardCell
    }
  }

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
