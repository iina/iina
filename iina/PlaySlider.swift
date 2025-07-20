//
//  PlaySlider.swift
//  iina
//
//  Created by low-batt on 10/11/21.
//  Copyright © 2021 lhc. All rights reserved.
//

import Cocoa

/// A custom [slider](https://developer.apple.com/design/human-interface-guidelines/macos/selectors/sliders/)
/// for the onscreen controller.
///
/// This slider adds two thumbs (referred to as knobs in code) to the progress bar slider to show the A and B loop points of the
/// [mpv](https://mpv.io/manual/stable/) A-B loop feature and allow the loop points to be adjusted. When the feature is
/// disabled the additional thumbs are hidden.
/// - Requires: The custom slider cell provided by `PlaySliderCell` **must** be used with this class.
/// - Note: Unlike `NSSlider` the `draw` method of this class will do nothing if the view is hidden.
final class PlaySlider: NSSlider {

  /// Knob representing the A loop point for the mpv A-B loop feature.
  var abLoopA: PlaySliderLoopKnob { abLoopAKnob }

  /// Knob representing the B loop point for the mpv A-B loop feature.
  var abLoopB: PlaySliderLoopKnob { abLoopBKnob }

  /// The slider's cell correctly typed for convenience.
  var customCell: PlaySliderCell { cell as! PlaySliderCell }

  /// Range of values the slider is configured to return.
  var range: ClosedRange<Double> { minValue...maxValue }

  /// Span of the range of values the slider is configured to return.
  var span: Double { maxValue - minValue }

  // MARK:- Private Properties

  private var abLoopAKnob: PlaySliderLoopKnob!

  private var abLoopBKnob: PlaySliderLoopKnob!

  // MARK: - Initialization

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    if #available(macOS 11, *) {
      // Apple increased the height of sliders in Big Sur. Until we have time to restructure the
      // on screen controller to accommodate a larger slider reduce the size of the slider from
      // regular to small. This makes the slider match the behavior seen under Catalina. This MUST
      // be set before creating the loop knobs as it changes the height of knobs which is referenced
      // during loop knob initialization.
      controlSize = .small
    }
    abLoopAKnob = PlaySliderLoopKnob(slider: self, toolTip: "A-B loop A")
    abLoopBKnob = PlaySliderLoopKnob(slider: self, toolTip: "A-B loop B")
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
}
