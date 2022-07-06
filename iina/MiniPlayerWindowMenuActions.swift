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
    setWindowFloatingOnTop(!isOntop)
  }


  @objc func menuSwitchToMiniPlayer(_ sender: NSMenuItem) {
    player.switchBackFromMiniPlayer(automatically: false)
  }
  
  @objc func menuSearchPlaylist(_ sender: NSMenuItem) {
    player.mainWindow.playlistView.playlistSearchViewController.openSearchWindow()
  }

}
