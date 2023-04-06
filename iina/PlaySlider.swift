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

  // MARK:- Initialization

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

  // MARK:- Drawing

  override func draw(_ dirtyRect: NSRect) {
    // With the onscreen controller hidden and a movie playing spindumps showed time being spent
    // drawing the slider even though it was not visible. Apparently NSSlider is missing the
    // following check.
    guard !isHiddenOrHasHiddenAncestor else { return }
    super.draw(dirtyRect)
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
}
