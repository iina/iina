//
//  AppDelegate+Scripting.swift
//  iina
//
//  Created by Nate Weaver on 2020-03-02.
//  Copyright © 2020 lhc. All rights reserved.
//

import AppKit

extension AppDelegate {

  func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool {
    return Set(["orderedPlayerWindows", "orderedPlayers"]).contains(key)
  }

  @objc var orderedPlayers: [PlayerCore] {
    let windows = NSApp.orderedWindows
    var players = [PlayerCore]()

    for window in windows {
      if window.isVisible, let controller = window.delegate as? PlayerWindowController {
        players.append(controller.player)
      }
    }

    return players
  }

  @objc(handlePlayCommand:) func handlePlayCommand(_ command: NSScriptCommand) {
    
  }

}
