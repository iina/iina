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
  private lazy var systemCell: NSSliderCell = {
    let cell = NSSliderCell()
    cell.refusesFirstResponder = false
    return cell
  }()

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
    cell = PlaySliderCell()
    legacyCell = cell as? PlaySliderCell
    originalTrackFillColor = trackFillColor
    commonInit()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    legacyCell = cell as? PlaySliderCell
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
    guard usesSystemAppearance != useSystemAppearance else { return }

    replaceCellPreservingConfiguration(with: useSystemAppearance ? systemCell : legacyCell)
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

  // MARK: - Drawing

  /// Draw the slider.
  ///
  /// The [NSSlider](https://developer.apple.com/documentation/appkit/nsslider) method is being overridden
  /// for two reasons.
  ///
  /// With the onscreen controller hidden and a movie playing spindumps showed time being spent drawing the slider even though it
  /// was not visible. Apparently `NSSlider.draw` is not calling
  /// [hiddenOrHasHiddenAncestor](https://developer.apple.com/documentation/appkit/nsview/1483473-hiddenorhashiddenancestor)
  /// to see if drawing can be avoided.  This was noticed under macOS Monterey.  Unknown if Apple addressed this in later macOS
  /// releases.
  ///
  /// The loop knobs are added as subviews to the slider. That should have resulted in the `PlaySliderLoopKnob.draw` method
  /// being called when the slider was being drawn. Prior to macOS Sonoma that did not occur. The assumption is that the
  /// [NSSlider](https://developer.apple.com/documentation/appkit/nsslider) `draw` method was not calling
  /// `super.draw` and that has now been corrected. As a workaround on earlier versions of macOS the loop knob `draw` method
  /// is called directly.
  override func draw(_ dirtyRect: NSRect) {
    guard !isHiddenOrHasHiddenAncestor else { return }
    super.draw(dirtyRect)
    if usesSystemAppearance {
      drawSystemAppearanceIndicators()
    }
    abLoopA.needsDisplay = true
    abLoopB.needsDisplay = true
    guard #unavailable(macOS 14) else { return }
    abLoopA.draw(dirtyRect)
    abLoopB.draw(dirtyRect)
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
    guard usesSystemAppearance else {
      super.mouseDown(with: event)
      return
    }
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

  private func drawSystemAppearanceIndicators() {
    let rect = sliderCell.barRect(flipped: isFlipped)
    let knobRect = sliderCell.knobRect(flipped: isFlipped)
    let info = playerCore.info

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let clip = NSBezierPath(rect: rect)
    clip.append(NSBezierPath(rect: knobRect.insetBy(dx: -1, dy: -1)).reversed)
    clip.addClip()

    if info.isNetworkResource,
       info.cacheTime != 0,
       let duration = info.videoDuration,
       duration.second > 0 {
      let playedX = knobRect.midX
      let cachedRatio = CGFloat(Double(info.cacheTime) / Double(duration.second)).clamped(to: 0...1)
      let cachedX = rect.minX + rect.width * cachedRatio
      if cachedX > playedX {
        let cacheRect = NSRect(x: playedX, y: rect.midY - 1,
                               width: cachedX - playedX, height: 2)
        NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: cacheRect, xRadius: 1, yRadius: 1).fill()
      }
    }

    guard drawChapters,
          let totalSeconds = info.videoDuration?.second,
          totalSeconds > 0,
          info.chapters.count > 1 else { return }
    NSColor.separatorColor.withAlphaComponent(0.75).setFill()
    for chapter in info.chapters.dropFirst() {
      let ratio = CGFloat(chapter.time.second / totalSeconds).clamped(to: 0...1)
      let x = round(rect.minX + rect.width * ratio)
      NSBezierPath(rect: NSRect(x: x - 0.5, y: rect.minY,
                                width: 1, height: rect.height)).fill()
    }
  }
}
