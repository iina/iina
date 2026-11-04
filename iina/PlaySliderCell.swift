//
//  PlaySliderCell.swift
//  iina
//
//  Created by lhc on 25/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

/// The value a play slider seeks to, held apart from the slider while the mouse button is down on it.
///
/// The slider sends its action at each change while it is tracked and once more when the button is released. In between, the time
/// shown is synchronized with `mpv`, which sets the slider to the position `mpv` reports, and during a seek past the duration `mpv`
/// reports for a file whose full length is longer that position is not the one sought. The action sent at the release therefore seeks
/// to the last value the pointer set, not to the value the slider then holds.
struct PlaySliderTracking {
  private var isTracking = false
  private var pointerValue: Double?

  /// The mouse button went down on the slider.
  mutating func began() {
    isTracking = true
    pointerValue = nil
  }

  /// The mouse button was released.
  mutating func ended() {
    isTracking = false
  }

  /// The value to seek to when the slider sends its action.
  /// - Parameter sliderValue: The value the slider holds.
  /// - Returns: While the slider is tracked, `sliderValue`, which the pointer has just set. For the action sent at the release, the
  ///     last value the pointer set; without one, `sliderValue`.
  mutating func seekValue(sliderValue: Double) -> Double {
    if isTracking {
      pointerValue = sliderValue
      return sliderValue
    }
    defer { pointerValue = nil }
    return pointerValue ?? sliderValue
  }
}

class PlaySliderCell: NSSliderCell {
  unowned var _playerCore: PlayerCore!
  var playerCore: PlayerCore {
    if let player = _playerCore { return player }

    let windowController = self.controlView!.window!.windowController
    let player = (windowController as! PlayerWindowController).player
    _playerCore = player
    return player
  }

  override var knobThickness: CGFloat {
    return knobWidth
  }

  let knobWidth: CGFloat = 3
  let knobHeight: CGFloat = 15
  let knobRadius: CGFloat = 1
  let barRadius: CGFloat = 1.5

  private var knobColor = NSColor.mainSliderKnob
  private var knobActiveColor = NSColor.mainSliderKnobActive
  private var barColorLeft = NSColor.mainSliderBarLeft
  private var barColorRight = NSColor.mainSliderBarRight

  var drawChapters = Preference.bool(for: .showChapterPos)

  var isPausedBeforeSeeking = false

  override func awakeFromNib() {
    minValue = 0
    maxValue = 100
  }

  // MARK:- Displaying the Cell

  override func drawKnob(_ knobRect: NSRect) {
    let isLightTheme = !controlView!.window!.effectiveAppearance.isDark
    if isLightTheme {
      drawKnobWithShadow(knobRect: knobRect)
    } else {
      drawKnobOnly(knobRect: knobRect)
    }
  }

  @discardableResult
  private func drawKnobOnly(knobRect: NSRect) -> NSBezierPath {
    // Round the X position for cleaner drawing
    let rect = NSMakeRect(round(knobRect.origin.x),
                          knobRect.origin.y + 0.5 * (knobRect.height - knobHeight),
                          knobRect.width,
                          knobHeight)

    let path = NSBezierPath(roundedRect: rect, xRadius: knobRadius, yRadius: knobRadius)
    (isHighlighted ? knobActiveColor : knobColor).setFill()
    path.fill()
    return path
  }

  private func drawKnobWithShadow(knobRect: NSRect) {
    NSGraphicsContext.saveGraphicsState()

    let shadow = NSShadow()
    shadow.shadowBlurRadius = 1
    shadow.shadowOffset = NSSize(width: 0, height: -0.5)
    shadow.set()

    let path = drawKnobOnly(knobRect: knobRect)

    /// According to Apple's docs for `NSShadow`: `The default shadow color is black with an alpha of 1/3`
    if let shadowColor = shadow.shadowColor {
      path.lineWidth = 0.4
      shadowColor.setStroke()
      path.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
  }

  override func knobRect(flipped: Bool) -> NSRect {
    let slider = self.controlView as! NSSlider
    let barRect = barRect(flipped: flipped)
    let percentage = slider.doubleValue / (slider.maxValue - slider.minValue)
    // The usable width of the bar is reduced by the width of the knob.
    let effectiveBarWidth = barRect.width - knobWidth
    let pos = barRect.origin.x + CGFloat(percentage) * effectiveBarWidth
    let rect = super.knobRect(flipped: flipped)

    let height: CGFloat = (barRect.origin.y - rect.origin.y) * 2 + barRect.height
    return NSMakeRect(pos, rect.origin.y, knobWidth, height)
  }

  override func drawBar(inside rect: NSRect, flipped: Bool) {
    let info = playerCore.info

    let slider = self.controlView as! NSSlider

    /// The position of the knob, rounded for cleaner drawing
    let knobPos : CGFloat = round(knobRect(flipped: flipped).origin.x);

    /// How far progressed the current video is, used for drawing the bar background
    var progress : CGFloat = 0;

    if info.isNetworkResource,
      info.cacheTime != 0,
      let duration = info.videoDuration,
      duration.second != 0 {
      let pos = Double(info.cacheTime) / Double(duration.second) * 100
      progress = round(rect.width * CGFloat(pos / (slider.maxValue - slider.minValue))) + 2;
    } else {
      progress = knobPos;
    }

    NSGraphicsContext.saveGraphicsState()
    let barRect: NSRect = rect
    let path = NSBezierPath(roundedRect: barRect, xRadius: barRadius, yRadius: barRadius)

    // draw chapters
    // add a rect for each chapter indicator line
    let chapterClip = NSBezierPath()
    if drawChapters {
      // When streaming if the audio stream is changed mpv will momentarily reset the video duration
      // to zero. Not useful to draw the chapter marks when the duration is unknown.
      if let totalSec = info.videoDuration?.second, totalSec != 0 {
        let chapters = info.chapters
        if chapters.count > 1 {
          for chapt in chapters[1...] {
            let chapPos = CGFloat(chapt.time.second) / CGFloat(totalSec) * barRect.width
            let rect = NSRect(x: chapPos - 0.5, y: barRect.origin.y, width: 1, height: barRect.height)
            chapterClip.append(NSBezierPath(rect: rect))
          }
        }
      }
    }

    // draw left
    let pathLeftRect : NSRect = NSMakeRect(barRect.origin.x, barRect.origin.y, progress, barRect.height)
    let clipL = NSBezierPath(rect: pathLeftRect)
    clipL.append(chapterClip.reversed)
    clipL.addClip()

    if controlView!.window!.effectiveAppearance.isDark {
      // Clip 1px around the knob
      path.append(NSBezierPath(rect: NSRect(x: knobPos - 1, y: barRect.origin.y, width: knobWidth + 2, height: barRect.height)).reversed);
    }

    barColorLeft.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    // draw right
    NSGraphicsContext.saveGraphicsState()

    let pathRight = NSMakeRect(barRect.origin.x + progress, barRect.origin.y, barRect.width - progress, barRect.height)
    let clipR = NSBezierPath(rect: pathRight)
    clipR.append(chapterClip.reversed)
    clipR.addClip()

    barColorRight.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
  }

  // MARK:- Tracking the Mouse

  /// The value to seek to, held apart from the slider while the mouse button is down on it.
  var tracking = PlaySliderTracking()

  override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
    isPausedBeforeSeeking = playerCore.info.state == .paused
    tracking.began()
    let result = super.startTracking(at: startPoint, in: controlView)
    if result {
      playerCore.pause()
      playerCore.mainWindow.thumbnailPeekView.isHidden = true
    } else {
      tracking = PlaySliderTracking()
    }
    return result
  }

  override func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint, in controlView: NSView, mouseIsUp flag: Bool) {
    if !isPausedBeforeSeeking {
      playerCore.resume()
    }
    tracking.ended()
    super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
  }
}
