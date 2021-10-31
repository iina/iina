//
//  PreviousCommand.swift
//  iina
//
//  Created by Nate Weaver on 2021-10-30.
//  Copyright © 2021 lhc. All rights reserved.
//

import Foundation

class PreviousCommand: NSScriptCommand {

  override func performDefaultImplementation() -> Any? {
    if let controller = NSApp.orderedWindows.first(where: { $0.delegate is PlayerWindowController })?.delegate as? PlayerWindowController {
      controller.player.handlePreviousCommand(self)
    }

    return nil
  }

}
