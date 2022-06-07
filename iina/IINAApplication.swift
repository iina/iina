//
//  IINAApplication.swift
//  iina
//
//  Created by Matt Svoboda on 2022.06.06.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation
import AppKit

@objc(IINAApplication)
class IINAApplication: NSApplication {
  override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .keyDown:
        if handleKeyDown(event) {
            return
        }
      default:
        break
    }

    // process via the normal chain:
    super.sendEvent(event)
  }

  func handleKeyDown(_ keyDownEvent: NSEvent) -> Bool {
    let keyStroke: String = KeyCodeHelper.mpvKeyCode(from: keyDownEvent)
    Logger.log("GlobalKeyDown: \"\(keyStroke)\"", level: .verbose)

    // Let main menu handle it first:
    if let mainMenu = NSApplication.shared.mainMenu, mainMenu.performKeyEquivalent(with: keyDownEvent) {
      Logger.log("Menu processed keyDown!", level: .verbose)

      let activePlayer = PlayerCore.active
      if activePlayer.mainWindow.hasKeyboardFocus {
        // Notify player window that the main menu stole its keyboard event:
        activePlayer.keyInputController.keyWasHandled(keyDownEvent)
      }
      return true
    } else {
      Logger.log("Menu didn't process keyDown. Sending to other responders", level: .verbose)
      return false
    }
  }
}
