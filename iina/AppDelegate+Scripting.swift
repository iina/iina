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
    return key == "orderedPlayers"
  }

  @objc var orderedPlayers: [PlayerCore] {
    return NSApp.orderedWindows.lazy.filter(\.isVisible).compactMap { ($0.delegate as? PlayerWindowController)?.player }
  }

  @objc(handlePlayCommand:) func handlePlayCommand(_ command: NSScriptCommand) {
    
  }

}
