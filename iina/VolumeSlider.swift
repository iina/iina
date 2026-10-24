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
  private(set) var usesSystemAppearance = false
  private var originalControlSize: NSControl.ControlSize = .mini
  private var originalTrackFillColor: NSColor?
  private var legacyCell: VolumeSliderCell!
  private var systemCell: NSSliderCell!

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    systemCell = cell as? NSSliderCell
    legacyCell = VolumeSliderCell()
    cell = legacyCell
    originalControlSize = controlSize
    originalTrackFillColor = trackFillColor
    maxValue = Double(Preference.integer(for: .maxVolume))
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    systemCell = cell as? NSSliderCell
    legacyCell = VolumeSliderCell()
    cell = legacyCell
    originalControlSize = controlSize
    originalTrackFillColor = trackFillColor
    maxValue = Double(Preference.integer(for: .maxVolume))
  }

  func setQuickTimeStyle(_ enabled: Bool) {
    let useSystemAppearance = if #available(macOS 26.0, *) { enabled } else { false }
    let desiredCell = useSystemAppearance ? systemCell! : legacyCell!
    guard usesSystemAppearance != useSystemAppearance || cell !== desiredCell else { return }
    if cell !== desiredCell {
      replaceCellPreservingConfiguration(with: desiredCell)
    }
    usesSystemAppearance = useSystemAppearance
    controlSize = useSystemAppearance ? .small : originalControlSize
    trackFillColor = useSystemAppearance ? .white : originalTrackFillColor
    if #available(macOS 26.0, *) {
      tintProminence = useSystemAppearance ? .primary : .automatic
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

fileprivate final class VolumeSliderCell: NSSliderCell {
  override func drawBar(inside rect: NSRect, flipped: Bool) {
    let knobPos = round(knobRect(flipped: flipped).origin.x)
    let path = NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5)
    let x100 = round(rect.minX + rect.width * CGFloat(100 / maxValue))
    let gapClip: NSBezierPath?
    if maxValue > 100 {
      let gapRect = NSRect(x: x100 - 1, y: rect.minY, width: 2, height: rect.height)
      gapClip = NSBezierPath(rect: gapRect).reversed
    } else {
      gapClip = nil
    }

    NSGraphicsContext.saveGraphicsState()
    let clipLeft = NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY,
                                             width: knobPos, height: rect.height))
    if let gapClip, x100 < knobPos { clipLeft.append(gapClip) }
    clipLeft.addClip()
    NSColor.volumeSliderBarLeft.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    let rightRect = NSRect(x: rect.minX + knobPos, y: rect.minY,
                           width: rect.width - knobPos, height: rect.height)
    let clipRight = NSBezierPath(rect: rightRect)
    if let gapClip, knobPos < x100 { clipRight.append(gapClip) }
    clipRight.addClip()
    NSColor.volumeSliderBarRight.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
  }
}
