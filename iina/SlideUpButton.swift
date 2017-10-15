//
//  SlideUpButton.swift
//  iina
//
//  Created by lhc on 13/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class SlideUpButton: NSButton {

  override func resetCursorRects() {
    addCursorRect(self.bounds, cursor: .pointingHand)
  }

}
