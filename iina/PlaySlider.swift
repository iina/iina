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

  // MARK:- Private Properties

  private var abLoopAKnob: PlaySliderLoopKnob!

  private var abLoopBKnob: PlaySliderLoopKnob!

  // MARK:- Initialization

  required init?(coder: NSCoder) {
    super.init(coder: coder)
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

  // MARK:- Mouse Events

  override func mouseDown(with event: NSEvent) {
    let clickLocation = convert(event.locationInWindow, from: nil)
    // When the knobs are overlapping we assume the user is trying to move the play knob rather than
    // change the loop points. So we intentionally test first for the mouse clicking on the play
    // knob, then test the B knob and then test the A knob and lastly default to the slider itself,
    // which will move the play knob.
    if isMousePoint(clickLocation, in: customCell.knobRect(flipped: isFlipped)) {
      super.mouseDown(with: event)
      return
    }
    if !abLoopB.isHidden && isMousePoint(clickLocation, in: abLoopB.frame) {
      abLoopB.beginDragging(with: event)
      return
    }
    if !abLoopA.isHidden && isMousePoint(clickLocation, in: abLoopA.frame) {
      abLoopA.beginDragging(with: event)
      return
    }
    super.mouseDown(with: event)
  }

  override func viewDidUnhide() {
    super.viewDidUnhide()
    // When IINA is not the application being used and the onscreen controller is hidden if the
    // mouse is moved over an IINA window the IINA will unhide the controller. If the slider is
    // not marked as needing display the controller will show without the slider. I would of thought
    // the NSView method would do this. The current Apple documentation does not say what the NSView
    // method does or even if it needs to be called by subclasses.
    needsDisplay = true
  }
}
