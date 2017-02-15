//
//  DurationDisplayView.swift
//  iina
//
//  Created by Christophe Laprun on 26/01/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

class DurationDisplayTextField: NSTextField {
  
  enum DisplayMode {
    case duration // displays the duration of the movie
    case remaining // displays the remaining time in the movie
  }
  
  var mode: DisplayMode = .duration
  
  /** Switches the display mode for the right label */
  func switchMode() {
    switch mode {
    case .duration:
      mode = .remaining
    default:
      mode = .duration
    }
  }
  
  
  func updateText(with duration: VideoTime, given current: VideoTime) {
    
    let stringValue: String
    switch mode {
    case .duration:
      stringValue = duration.stringRepresentation
    case .remaining:
      let remaining = duration - current
      stringValue = "-\(remaining.stringRepresentation)"
    }
    self.stringValue = stringValue
  }
  
  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)
    
    self.switchMode()
  }
  
}
