//
//  PlaylistPlaybackProgressView.swift
//  iina
//
//  Created by Collider LI on 13/5/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class PlaylistPlaybackProgressView: NSView {

  private static let fillColor = NSColor(calibratedWhite: 1, alpha: 0.6)

  /// The percentage from 0 to 1.
  var percentage: Double = 0


  override func draw(_ dirtyRect: NSRect) {
    let rect = NSRect(x: 0, y: 0, width: bounds.width * CGFloat(percentage), height: bounds.height)
    PlaylistPlaybackProgressView.fillColor.setFill()
    NSBezierPath(rect: rect).fill()
  }
    
}
