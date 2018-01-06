//
//  MiniPlayerWindowMenuActions.swift
//  iina
//
//  Created by lhc on 13/8/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

extension MiniPlayerWindowController {

  @objc func menuAlwaysOnTop(_ sender: AnyObject) {
    isOntop = !isOntop
    setWindowFloatingOnTop(isOntop)
  }


  @objc func menuSwitchToMiniPlayer(_ sender: NSMenuItem) {
    window?.orderOut(nil)
    player.switchBackFromMiniPlayer(automatically: false)
  }

}
