//
//  FixedProgressBar.swift
//  iina
//
//  Created by Hechen Li on 2025-09-18.
//  Copyright © 2025 lhc. All rights reserved.
//

/// A class to draw progress bars in the OSD manually since macOS 26 added animation to NSProgressIndicator
/// that can't be disabled.
class FixedProgressBar: NSView {
  private let paddingY: CGFloat = 4
  
  var doubleValue: Double = 0.5 {
    didSet {
      setNeedsDisplay(bounds)
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    NSGraphicsContext.saveGraphicsState()

    NSColor.controlAccentColor.setFill()

    let boundRect = NSMakeRect(0, paddingY, bounds.width, bounds.height - 2 * paddingY)
    let progressRect = NSMakeRect(0, paddingY, bounds.width * doubleValue, bounds.height - 2 * paddingY)
    NSBezierPath(roundedRect: boundRect, xRadius: 3, yRadius: 3).addClip()
    NSBezierPath(rect: progressRect).fill()

    NSGraphicsContext.restoreGraphicsState()
  }
}
