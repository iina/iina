//
//  PlaySliderCell.swift
//  iina
//
//  Created by lhc on 25/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

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

  private var knobColor = NSColor(named: .mainSliderKnob)!
  private var knobActiveColor = NSColor(named: .mainSliderKnobActive)!
  private var barColorLeft = NSColor(named: .mainSliderBarLeft)!
  private var barColorRight = NSColor(named: .mainSliderBarRight)!
  private var chapterStrokeColor = NSColor(named: .mainSliderBarChapterStroke)!

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

    let height: CGFloat
    if #available(macOS 11, *) {
      height = (barRect.origin.y - rect.origin.y) * 2 + barRect.height
    } else {
      height = rect.height
    }
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
    let barRect: NSRect
    if #available(macOS 11, *) {
      barRect = rect
    } else {
      barRect = NSMakeRect(rect.origin.x, rect.origin.y + 1, rect.width, rect.height - 2)
    }
    let path = NSBezierPath(roundedRect: barRect, xRadius: barRadius, yRadius: barRadius)

    // draw left
    let pathLeftRect : NSRect = NSMakeRect(barRect.origin.x, barRect.origin.y, progress, barRect.height)
    NSBezierPath(rect: pathLeftRect).addClip();

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
    NSBezierPath(rect: pathRight).setClip()
    barColorRight.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    // draw chapters
    NSGraphicsContext.saveGraphicsState()
    if drawChapters {
      if let totalSec = info.videoDuration?.second {
        chapterStrokeColor.setStroke()
        let chapters = info.chapters
        if chapters.count > 1 {
          for chapt in chapters[1...] {
            let chapPos = CGFloat(chapt.time.second) / CGFloat(totalSec) * barRect.width
            let linePath = NSBezierPath()
            linePath.move(to: NSPoint(x: chapPos, y: barRect.origin.y))
            linePath.line(to: NSPoint(x: chapPos, y: barRect.origin.y + barRect.height))
            linePath.stroke()
          }
        }
      }
    }
    NSGraphicsContext.restoreGraphicsState()
  }

  // MARK:- Tracking the Mouse

  override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
    isPausedBeforeSeeking = playerCore.info.state == .paused
    let result = super.startTracking(at: startPoint, in: controlView)
    if result {
      playerCore.pause()
      playerCore.mainWindow.thumbnailPeekView.isHidden = true
    }
    return result
  }

  override func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint, in controlView: NSView, mouseIsUp flag: Bool) {
    if !isPausedBeforeSeeking {
      playerCore.resume()
    }
    super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
  }
}
