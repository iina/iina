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
  private(set) var usesSystemAppearance = false
  private var originalControlSize: NSControl.ControlSize = .mini
  private var originalTrackFillColor: NSColor?
  private var legacyCell: VolumeSliderCell!
  private lazy var systemCell: NSSliderCell = {
    let cell = NSSliderCell()
    cell.refusesFirstResponder = false
    return cell
  }()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    cell = VolumeSliderCell()
    legacyCell = cell as? VolumeSliderCell
    originalControlSize = controlSize
    originalTrackFillColor = trackFillColor
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    if !(cell is VolumeSliderCell) {
      cell = VolumeSliderCell()
    }
    legacyCell = cell as? VolumeSliderCell
    originalControlSize = controlSize
    originalTrackFillColor = trackFillColor
  }

  func setQuickTimeStyle(_ enabled: Bool) {
    let useSystemAppearance = if #available(macOS 26.0, *) { enabled } else { false }
    guard usesSystemAppearance != useSystemAppearance else { return }

    replaceCellPreservingConfiguration(with: useSystemAppearance ? systemCell : legacyCell)
    usesSystemAppearance = useSystemAppearance
    controlSize = useSystemAppearance ? .small : originalControlSize
    trackFillColor = useSystemAppearance ? .white : originalTrackFillColor
    if #available(macOS 26.0, *) {
      tintProminence = useSystemAppearance ? .none : .automatic
    }
    needsDisplay = true
  }

  // MARK: - Drawing

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard usesSystemAppearance, maxValue > 100 else { return }
    let sliderCell = cell as! NSSliderCell
    let rect = sliderCell.barRect(flipped: isFlipped)
    let x = round(rect.minX + rect.width * CGFloat(100 / maxValue))
    NSGraphicsContext.saveGraphicsState()
    let clip = NSBezierPath(rect: rect)
    clip.append(NSBezierPath(rect: sliderCell.knobRect(flipped: isFlipped)
      .insetBy(dx: -1, dy: -1)).reversed)
    clip.addClip()
    NSColor.separatorColor.withAlphaComponent(0.8).setFill()
    NSBezierPath(rect: NSRect(x: x - 0.5, y: rect.minY,
                              width: 1, height: rect.height)).fill()
    NSGraphicsContext.restoreGraphicsState()
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

fileprivate class VolumeSliderCell: NSSliderCell {
  override func awakeFromNib() {
    minValue = 0
    maxValue = Double(Preference.integer(for: .maxVolume))
  }

  override func drawBar(inside rect: NSRect, flipped: Bool) {
    let knobPos: CGFloat = round(knobRect(flipped: flipped).origin.x)
    let radius: CGFloat = 1.5
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let x100 = round(rect.minX + rect.width * CGFloat(100 / maxValue))

    let gapClip: NSBezierPath?
    if maxValue > 100 {
      let width: CGFloat = 2
      let gapRect = NSMakeRect(x100 - width / 2, rect.minY, width, rect.height)
      gapClip = NSBezierPath(rect: gapRect).reversed
    } else {
      gapClip = nil
    }

    NSGraphicsContext.saveGraphicsState()
    let clipLeft = NSBezierPath(rect: NSMakeRect(rect.minX, rect.minY, knobPos, rect.height))
    if let gapClip, x100 < knobPos {
      clipLeft.append(gapClip)
    }
    clipLeft.addClip()
    NSColor.volumeSliderBarLeft.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    let rightRect = NSMakeRect(rect.minX + knobPos, rect.minY, rect.width - knobPos, rect.height)
    let clipRight = NSBezierPath(rect: rightRect)
    if let gapClip, knobPos < x100 {
      clipRight.append(gapClip)
    }
    clipRight.addClip()
    NSColor.volumeSliderBarRight.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
  }

}
