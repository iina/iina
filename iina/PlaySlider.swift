//
//  PlaySlider.swift
//  iina
//
//  Created by low-batt on 10/11/21.
//  Copyright © 2021 lhc. All rights reserved.
//

import Cocoa

extension NSSlider {
  func replaceCellPreservingConfiguration(with replacement: NSSliderCell) {
    let currentValue = doubleValue
    let currentMinValue = minValue
    let currentMaxValue = maxValue
    let currentAltIncrementValue = altIncrementValue
    let currentSliderType = sliderType
    let currentNumberOfTickMarks = numberOfTickMarks
    let currentTickMarkPosition = tickMarkPosition
    let currentAllowsTickMarkValuesOnly = allowsTickMarkValuesOnly
    let currentIsContinuous = isContinuous
    let currentIsEnabled = isEnabled
    let currentTarget = target
    let currentAction = action
    let currentTag = tag
    let currentNeutralValue: Double? = if #available(macOS 26.0, *) { neutralValue } else { nil }

    cell = replacement
    minValue = currentMinValue
    maxValue = currentMaxValue
    doubleValue = currentValue
    altIncrementValue = currentAltIncrementValue
    sliderType = currentSliderType
    numberOfTickMarks = currentNumberOfTickMarks
    tickMarkPosition = currentTickMarkPosition
    allowsTickMarkValuesOnly = currentAllowsTickMarkValuesOnly
    isContinuous = currentIsContinuous
    isEnabled = currentIsEnabled
    target = currentTarget
    action = currentAction
    tag = currentTag
    if #available(macOS 26.0, *), let currentNeutralValue {
      neutralValue = currentNeutralValue
    }
  }
}

/// A custom [slider](https://developer.apple.com/design/human-interface-guidelines/macos/selectors/sliders/)
/// for the onscreen controller.
///
/// This slider adds two thumbs (referred to as knobs in code) to the progress bar slider to show the A and B loop points of the
/// [mpv](https://mpv.io/manual/stable/) A-B loop feature and allow the loop points to be adjusted. When the feature is
/// disabled the additional thumbs are hidden.
/// - Note: Floating OSCs use a standard `NSSliderCell`; other layouts retain `PlaySliderCell`.
/// - Note: Unlike `NSSlider` the `draw` method of this class will do nothing if the view is hidden.
final class PlaySlider: NSSlider {

  private(set) var usesSystemAppearance = false
  private var originalTrackFillColor: NSColor?
  private var legacyCell: PlaySliderCell!
  private var systemCell: NSSliderCell!

  /// Knob representing the A loop point for the mpv A-B loop feature.
  var abLoopA: PlaySliderLoopKnob { abLoopAKnob }

  /// Knob representing the B loop point for the mpv A-B loop feature.
  var abLoopB: PlaySliderLoopKnob { abLoopBKnob }

  var sliderCell: NSSliderCell { cell as! NSSliderCell }
  var sliderKnobWidth: CGFloat { (cell as? PlaySliderCell)?.knobWidth ?? sliderCell.knobThickness }
  var sliderKnobHeight: CGFloat { (cell as? PlaySliderCell)?.knobHeight ?? sliderCell.knobThickness }
  var sliderKnobRadius: CGFloat { (cell as? PlaySliderCell)?.knobRadius ?? sliderCell.knobThickness / 2 }

  var drawChapters: Bool {
    get { legacyCell.drawChapters }
    set {
      legacyCell.drawChapters = newValue
      needsDisplay = true
    }
  }

  /// Range of values the slider is configured to return.
  var range: ClosedRange<Double> { minValue...maxValue }

  /// Span of the range of values the slider is configured to return.
  var span: Double { maxValue - minValue }

  // MARK:- Private Properties

  private var abLoopAKnob: PlaySliderLoopKnob!

  private var abLoopBKnob: PlaySliderLoopKnob!

  // MARK: - Initialization

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    systemCell = cell as? NSSliderCell
    legacyCell = PlaySliderCell()
    legacyCell.refusesFirstResponder = true
    legacyCell.minValue = 0
    legacyCell.maxValue = 100
    originalTrackFillColor = trackFillColor
    commonInit()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    systemCell = cell as? NSSliderCell
    legacyCell = PlaySliderCell()
    legacyCell.refusesFirstResponder = true
    legacyCell.minValue = 0
    legacyCell.maxValue = 100
    originalTrackFillColor = trackFillColor
    commonInit()
  }

  private func commonInit() {
    // Apple increased the height of sliders in Big Sur. Until we have time to restructure the
    // on screen controller to accommodate a larger slider reduce the size of the slider from
    // regular to small. This makes the slider match the behavior seen under Catalina. This MUST
    // be set before creating the loop knobs as it changes the height of knobs which is referenced
    // during loop knob initialization.
    controlSize = .small

    abLoopAKnob = PlaySliderLoopKnob(slider: self, toolTip: "A-B loop A")
    abLoopBKnob = PlaySliderLoopKnob(slider: self, toolTip: "A-B loop B")
  }

  func setQuickTimeStyle(_ enabled: Bool) {
    let useSystemAppearance = if #available(macOS 26.0, *) { enabled } else { false }
    let desiredCell = useSystemAppearance ? systemCell! : legacyCell!
    guard usesSystemAppearance != useSystemAppearance || cell !== desiredCell else { return }
    if cell !== desiredCell {
      replaceCellPreservingConfiguration(with: desiredCell)
    }
    usesSystemAppearance = useSystemAppearance
    controlSize = .small
    trackFillColor = useSystemAppearance ? .white : originalTrackFillColor
    if #available(macOS 26.0, *) {
      tintProminence = useSystemAppearance ? .primary : .automatic
    }
    abLoopA.updateGeometry()
    abLoopB.updateGeometry()
    needsDisplay = true
  }

  override func viewDidUnhide() {
    super.viewDidUnhide()
    // When IINA is not the application being used and the onscreen controller is hidden if the
    // mouse is moved over an IINA window the IINA will unhide the controller. If the slider is
    // not marked as needing display the controller will show without the slider. I would have
    // thought the NSView method would do this. The current Apple documentation does not say what
    // the NSView method does or even if it needs to be called by subclasses.
    needsDisplay = true
  }

  // MARK: - Mouse / Trackpad events

  /// Informs the receiver that the user has pressed the left mouse button.
  ///
  /// This is a workaround for IINA issue #5768 where starting with macOS Tahoe AppKit is miss-handling mouse events in certain
  /// circumstances. Merely adding this function solved the problem. Maybe the presence of this function prevents the use of some sort
  /// of faulty optimization?
  /// - Important: _DO NOT REMOVE_ this function thinking it is not needed. Read issue #5768.
  /// - Parameter event: An object encapsulating information about the mouse-down event.
  override func mouseDown(with event: NSEvent) {
    let player = playerCore
    let shouldResume = player.info.state != .paused
    player.pause()
    player.mainWindow.thumbnailPeekView.isHidden = true
    super.mouseDown(with: event)
    if shouldResume {
      player.resume()
    }
  }

  /// The user is scrolling while the cursor is within the slider.
  ///
  /// With certain kinds of input devices, such as a mouse with a scroll wheel that spins freely, it is easy to accidentally move the cursor
  /// over the slider and unintentionally change the playback position. For users that dislike this behavior IINA provides a setting to
  /// disable scrolling the slider. When this setting is enabled the user must grab and drag the slider's thumb to change the playback
  /// position or click on a position within the slider.
  /// - Parameter event: Event indicating the scroll wheel position changed.
  override func scrollWheel(with event: NSEvent) {
    guard !Preference.bool(for: .disablePlaySliderScrolling) else { return }
    super.scrollWheel(with: event)
  }

  private var playerCore: PlayerCore {
    (window!.windowController as! PlayerWindowController).player
  }

}
