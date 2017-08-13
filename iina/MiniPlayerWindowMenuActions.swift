//
//  MiniPlayerWindowMenuActions.swift
//  iina
//
//  Created by lhc on 13/8/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

extension MiniPlayerWindowController {

  func menuAlwaysOnTop(_ sender: AnyObject) {
    isOntop = !isOntop
    setWindowFloatingOnTop(isOntop)
  }


  func menuSwitchToMiniPlayer(_ sender: NSMenuItem) {
    window?.close()
    player.switchBackFromMiniPlayer()
  }
}
