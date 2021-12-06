//
//  PreviousFrameCommand.swift
//  iina
//
//  Created by Nate Weaver on 2021-12-01.
//  Copyright © 2021 lhc. All rights reserved.
//

import Foundation

class PreviousFrameCommand: NSScriptCommand {

  override func performDefaultImplementation() -> Any? {
    if let controller = NSApp.orderedWindows.first(where: { $0.delegate is PlayerWindowController })?.delegate as? PlayerWindowController {
      controller.player.handlePreviousFrameCommand(self)
    }

    return nil
  }

}
