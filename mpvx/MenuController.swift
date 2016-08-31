//
//  MenuController.swift
//  mpvx
//
//  Created by lhc on 31/8/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class MenuController: NSObject, NSMenuDelegate {
  
  @IBOutlet weak var file: NSMenuItem!
  @IBOutlet weak var open: NSMenuItem!

  @IBOutlet weak var cotrol: NSMenuItem!
  @IBOutlet weak var pause: NSMenuItem!
  @IBOutlet weak var stop: NSMenuItem!
  @IBOutlet weak var forward: NSMenuItem!
  @IBOutlet weak var nextFrame: NSMenuItem!
  @IBOutlet weak var backward: NSMenuItem!
  @IBOutlet weak var previousFrame: NSMenuItem!
  @IBOutlet weak var jumpTo: NSMenuItem!
  @IBOutlet weak var screenShot: NSMenuItem!
  @IBOutlet weak var gotoScreenshotFolder: NSMenuItem!
  @IBOutlet weak var advancedScreenShot: NSMenuItem!
  @IBOutlet weak var abLoop: NSMenuItem!
  @IBOutlet weak var playlist: NSMenuItem!
  @IBOutlet weak var playlistMenu: NSMenu!
  @IBOutlet weak var chapter: NSMenuItem!
  @IBOutlet weak var chapterMenu: NSMenu!
  
  func bindMenuItems() {
    // Control
    pause.action = #selector(MainWindowController.menuTogglePause(_:))
    stop.action = #selector(MainWindowController.menuStop(_:))
    forward.action = #selector(MainWindowController.menuStep(_:))
    nextFrame.action = #selector(MainWindowController.menuStepFrame(_:))
    backward.action = #selector(MainWindowController.menuStep(_:))
    previousFrame.action = #selector(MainWindowController.menuStepFrame(_:))
    jumpTo.action = #selector(MainWindowController.menuJumpTo(_:))
    screenShot.action = #selector(MainWindowController.menuSnapshot(_:))
    gotoScreenshotFolder.action = #selector(AppDelegate.menuOpenScreenshotFolder(_:))
//    advancedScreenShot
    abLoop.action = #selector(MainWindowController.menuABLoop(_:))
    playlistMenu.delegate = self
    updatePlaylist()
  }
  
  func updatePlaylist() {
    playlistMenu.removeAllItems()
    playlistMenu.addItem(withTitle: "Show/Hide Playlist Panel", action: #selector(MainWindowController.playlistButtonAction(_:)), keyEquivalent: "")
    playlistMenu.addItem(NSMenuItem.separator())
    for (index, item) in PlayerCore.shared.info.playlist.enumerated() {
      let menuItem = NSMenuItem(title: item.filenameForDisplay, action: #selector(MainWindowController.menuPlaylistItem(_:)), keyEquivalent: "")
      menuItem.tag = index
      playlistMenu.addItem(menuItem)
    }
  }
  
  // MARK: - Menu delegate
  
  func menuWillOpen(_ menu: NSMenu) {
    if menu == playlistMenu {
      updatePlaylist()
    } else if menu == chapterMenu {
      
    }
  }
  
}
