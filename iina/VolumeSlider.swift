//
//  VolumeSlider.swift
//  iina
//
//  Created by low-batt on 6/30/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Cocoa

/// An NSSlider subclass used for the volume slider in the on-screen controller.
class VolumeSlider: NSSlider {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    maxValue = Double(Preference.integer(for: .maxVolume))
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    maxValue = Double(Preference.integer(for: .maxVolume))
  }

  func setQuickTimeStyle(_ enabled: Bool) {
    controlSize = enabled ? .small : .mini
    trackFillColor = enabled ? .white : nil
    if #available(macOS 26.0, *) {
      tintProminence = enabled ? .primary : .automatic
    }
    needsDisplay = true
  }

  // MARK: - Mouse / Trackpad events

  /// Keep AppKit's native slider tracking active on macOS versions affected by IINA issue #5768.
  ///
  /// This override intentionally does nothing beyond forwarding the event to AppKit. Without
  /// it, Tahoe can skip the tracking path for an NSSlider subclass.
  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)
  }

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
