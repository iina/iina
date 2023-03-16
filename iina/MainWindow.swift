//
//  MainWindow.swift
//  iina
//
//  Created by Collider LI on 10/1/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class MainWindow: NSWindow {
  var forceKeyAndMain = false

  override func keyDown(with event: NSEvent) {
    // Forward all key events which the window receives to controller. This fixes:
    // (a) ESC key not otherwise sent to window
    // (b) window was not getting a chance to respond before main menu
    if let controller = windowController as? MainWindowController {
      controller.keyDown(with: event)
    }
  }

  override var canBecomeKey: Bool {
    forceKeyAndMain ? true : super.canBecomeKey
  }
  
  override var canBecomeMain: Bool {
    forceKeyAndMain ? true : super.canBecomeMain
  }
}
