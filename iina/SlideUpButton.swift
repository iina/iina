//
//  SlideUpButton.swift
//  mpvx
//
//  Created by lhc on 13/8/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class SlideUpButton: NSButton {

  override func resetCursorRects() {
    addCursorRect(self.bounds, cursor: NSCursor.pointingHand())
  }
  
}
