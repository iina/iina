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

  override func cancelOperation(_ sender: Any?) {
    let controller = windowController as! MainWindowController
    if let kb = PlayerCore.keyBindings["ESC"] {
      controller.handleKeyBinding(kb)
    } else {
      super.cancelOperation(sender)
    }
  }

  override var canBecomeKey: Bool {
    forceKeyAndMain ? true : super.canBecomeKey
  }
  
  override var canBecomeMain: Bool {
    forceKeyAndMain ? true : super.canBecomeMain
  }
}
